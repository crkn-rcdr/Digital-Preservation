package CRKN::Repository::RevisionsWalk;

use strict;
use Carp;
use CIHM::TDR::TDRConfig;
use CIHM::TDR::ContentServer;
use CIHM::TDR::REST::internalmeta;
use CRKN::REST::repoanalysis;
use Data::Dumper;

sub new {
    my($class, $args) = @_;
    my $self = bless {}, $class;

    if (ref($args) ne "HASH") {
        die "Argument to CIHM::TDR::Replication->new() not a hash\n";
    };
    $self->{args} = $args;

    $self->{config} = CIHM::TDR::TDRConfig->instance($self->configpath);
    $self->{logger} = $self->{config}->logger;

    my %confighash = %{$self->{config}->get_conf};

    # Undefined if no <internalmeta> config block
    if (exists $confighash{internalmeta}) {
        $self->{internalmeta} = new CIHM::TDR::REST::internalmeta (
            server => $confighash{internalmeta}{server},
            database => $confighash{internalmeta}{database},
            type   => 'application/json',
            conf   => $args->{configpath},
            clientattrs => {timeout => 3600},
            );
    } else {
        croak "Missing <internalmeta> configuration block in config\n";
    }

    # Undefined if no <repoanalysis> config block
    if (exists $confighash{repoanalysis}) {
        $self->{repoanalysis} = new CRKN::REST::repoanalysis (
            server => $confighash{repoanalysis}{server},
            database => $confighash{repoanalysis}{database},
            type   => 'application/json',
            conf   => $args->{configpath},
            clientattrs => {timeout => 3600},
            );
    } else {
        croak "Missing <repoanalysis> configuration block in config\n";
    }

    my %cosargs = (
        jwt_payload => '{"uids":[".*"]}',
        conf => $self->configpath
        );
    $self->{cos} = new CIHM::TDR::REST::ContentServer (\%cosargs);
    if (!$self->cos) {
        croak "Missing ContentServer configuration\n";
    }

    $self->{mdonly}=0;
    
    return $self;
}
sub args {
    my $self = shift;
    return $self->{args};
}
sub configpath {
    my $self = shift;
    return $self->{args}->{configpath};
}
sub config {
    my $self = shift;
    return $self->{config};
}
sub log {
    my $self = shift;
    return $self->{logger};
}
sub internalmeta {
    my $self = shift;
    return $self->{internalmeta};
}
sub repoanalysis {
    my $self = shift;
    return $self->{repoanalysis};
}
sub cos {
    my $self = shift;
    return $self->{cos};
}


sub walk {
    my ($self) = @_;


    $self->internalmeta->type("application/json");
    my $res = $self->internalmeta->get("/".$self->internalmeta->{database}."/_design/tdr/_view/metscount?reduce=false&startkey=2&endkey=7",{}, {deserializer => 'application/json'});
    if ($res->code == 200) {
        if (exists $res->data->{rows}) {
            foreach my $hr (@{$res->data->{rows}}) {
                $self->getmanifest($hr->{id},$hr->{key});
            }
        }
	print STDERR "Only metadata updates: ".$self->{mdonly}."\n";
    }
    else {
        warn "_view/hammerq GET return code: ".$res->code."\n"; 
    }
}

sub getmanifest {
    my ($self,$aip,$metscount) = @_;


    my $file = $aip."/manifest-md5.txt";
    my $r = $self->cos->get("/$file");

    if ($r->code == 200) {
	$self->processmanifest($aip,$metscount,$r->response->content);
    } elsif ($r->code == 404 ) {
        print STDERR "Not yet found: $file"."\n";
        return;
    } else {
        print STDERR "Accessing $file returned code: " . $r->code."\n";
        return;
    }
}

sub processmanifest {
    my ($self,$aip,$metscount,$manifest) = @_;


    my @manifest;
    my %sipdfmd5;



    # Array of data files
    my @datafiles    = grep { /\/data\/files\// } 
                            (split /\n/, $manifest);

    my @revdatafiles = grep { /\s+data\/revisions\/([^\/]+)\/data\/files\// }
                            @datafiles;
    my @sipdatafiles = grep { /\s+data\/sip\/data\/files\// }
                            @datafiles;


    my $revfiles = scalar(@revdatafiles);
    my $sipfiles = scalar(@sipdatafiles);
    if (scalar(@datafiles) != ($revfiles+$sipfiles)) {
	print STDERR "Mismatch on data file counts for $aip !!\n";
	print STDERR Dumper(\@datafiles,\@revdatafiles,\@sipdatafiles)."\n";
    }


    # Hash of information to be posted to CouchDB
    my %repoanalysis = ( summary => {
	metscount => $metscount,
	sipfiles => $sipfiles,
	revfiles => $revfiles
			 }
	);

    foreach my $line (@datafiles) {
	my ($md5,$file) = split /\s+/, $line;
	my $length;

	# Retry 3 times
	for (my $count = 1; $count < 3 ; $count++) {
	    # Get the length of the file
	    my $r = $self->cos->head("/$aip/$file");
	    if ($r->code == 200) {
		$length=$r->response->header('Content-Length');
		last;
	    } else {
		print STDERR ("HEAD of $file returned code: ". $r->code."\n");
	    }
	}
	if (! defined $length) {
	    croak ("Can't get length of $file\n");
	}
	
	push @manifest, [$file,$md5,$length];

	if (substr($file,0,20) eq 'data/sip/data/files/') {
	    $repoanalysis{sipfiles}{$file}=[$md5,$length];
	    if(defined $sipdfmd5{"$md5:$length"}) {
		print STDERR ("$aip: $md5 with length $length is duplicate between $file and ".$sipdfmd5{"$md5:$length"}."\n");
	    } else {
		$sipdfmd5{"$md5:$length"}=$file;
	    }
	} else {
	    $repoanalysis{revfiles}{$file}=[$md5,$length];
	}
    }

    # Walk through manifest looking up revision files
    my ($unique,$duplicate)=(0,0);
    foreach my $filemd5 (@manifest) {
	my ($file,$md5,$length) = @{$filemd5};

	if ($file =~ /^data\/revisions\/([^\/]+)\/data\/files\//) {
	    if (defined $sipdfmd5{"$md5:$length"}) {
		$duplicate++;
	    } else {
		$unique++;
	    }
	}	
    }
    
    $repoanalysis{summary}{unique}=$unique;
    $repoanalysis{summary}{duplicate}=$duplicate;

    
    if ($revfiles == 0) {
	$self->{mdonly}++;
    } else {
	print "$aip SIP:$sipfiles , Revision:$revfiles , Unique:$unique , Duplicate:$duplicate\n";
    }

    my $res = $self->repoanalysis->create_or_update($aip,\%repoanalysis);
    if ($res) {
	print "$res\n";
    }

}


1;