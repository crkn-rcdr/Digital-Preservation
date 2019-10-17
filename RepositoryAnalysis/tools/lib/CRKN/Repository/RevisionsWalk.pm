package CRKN::Repository::RevisionsWalk;

use strict;
use Config::General;
use CRKN::REST::repoanalysis;
use CRKN::REST::repoanalysisf;
use CIHM::Swift::Client;
use Data::Dumper;

sub new {
    my($class, $args) = @_;
    my $self = bless {}, $class;

    if (ref($args) ne "HASH") {
        die "Argument to CIHM::TDR::Replication->new() not a hash\n";
    };
    $self->{args} = $args;

    my %confighash = new Config::General(
	-ConfigFile => $args->{configpath},
	)->getall;

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
        die "Missing <repoanalysis> configuration block in config\n";
    }

    # Undefined if no <repoanalysisf> config block
    if (exists $confighash{repoanalysisf}) {
        $self->{repoanalysisf} = new CRKN::REST::repoanalysisf (
            server => $confighash{repoanalysisf}{server},
            database => $confighash{repoanalysisf}{database},
            type   => 'application/json',
            conf   => $args->{configpath},
            clientattrs => {timeout => 3600},
            );
    } else {
        die "Missing <repoanalysisf> configuration block in config\n";
    }

    # Undefined if no <swift> config block
    if(exists $confighash{swift}) {
	my %swiftopt = (
	    furl_options => { timeout => 120 }
	    );
	foreach ("server","user","password","account", "furl_options") {
	    if (exists  $confighash{swift}{$_}) {
		$swiftopt{$_}=$confighash{swift}{$_};
	    }
	}
        $self->{swift}=CIHM::Swift::Client->new(%swiftopt);
	$self->{swiftconfig}=$confighash{swift};
    } else {
	die "No <swift> configuration block in ".$self->configpath."\n";
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
sub repoanalysis {
    my $self = shift;
    return $self->{repoanalysis};
}
sub repoanalysisf {
    my $self = shift;
    return $self->{repoanalysisf};
}
sub swift {
    my $self = shift;
    return $self->{swift};
}
sub swiftconfig {
    my $self = shift;
    return $self->{swiftconfig};
}
sub repository {
    my $self = shift;
    return $self->swiftconfig->{repository};
}
sub container {
    my $self = shift;
    return $self->swiftconfig->{container};
}
sub swiftrepoanalysis {
    my $self = shift;
    return $self->swiftconfig->{repoanalysis};
}


sub walk {
    my ($self) = @_;


    $self->repoanalysis->type("application/json");
    my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/ra/_view/walkq?reduce=false",{}, {deserializer => 'application/json'});
    if ($res->code == 200) {
        if (exists $res->data->{rows}) {
            foreach my $hr (@{$res->data->{rows}}) {
                $self->processaip($hr->{id},$hr->{key});
            }
        }
	print STDERR "Only metadata updates: ".$self->{mdonly}."\n";
    }
    else {
        warn "_view/hammerq GET return code: ".$res->code."\n"; 
    }
}

sub processaip {
    my ($self,$aip,$manifestdate) = @_;


    my $file = $aip."/manifest-md5.txt";
    my $r = $self->swift->object_get($self->container,"$file");

    if ($r->code == 404 ) {
        print STDERR "Not yet found: $file"."\n";
        return;
    } elsif ($r->code != 200) {
        print STDERR "Accessing $file returned code: " . $r->code."\n";
        return;
    }


    # Now process the manifest in $r->content
    my @manifest;
    my %sipdfmd5;



    # Array of data files
    my @datafiles    = grep { /\/data\/files\// } 
                            (split /\n/, $r->content);

    # No longer need manifest.
    undef $r;

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
	manifestdate => $manifestdate,
	sipfiles => $sipfiles,
	revfiles => $revfiles
			 }
	);

    # Get a listing of files from Swift within this AIP
    my %containeropt = (
	"prefix" => $aip."/"
	);
    my %aipdata;
    # Need to loop possibly multiple times as Swift has a maximum of
    # 10,000 names.
    my $more=1;
    while ($more) {
	my $aipdataresp = $self->swift->container_get($self->container,
						      \%containeropt);
	if ($aipdataresp->code != 200) {
	    die "container_get(".$self->container.") for $aip returned ". $aipdataresp->code . " - " . $aipdataresp->message. "\n";
	};
	$more=scalar(@{$aipdataresp->content});
	if ($more) {
	    $containeropt{'marker'}=$aipdataresp->content->[$more-1]->{name};

	    foreach my $object (@{$aipdataresp->content}) {
		my $file=substr $object->{name},(length $aip)+1;
		$aipdata{$file}=$object;
	    }
	}
    }

    # Same get, but from the 'repoanalysis' container
    my %repoanalysisdata;
    # Need to loop possibly multiple times as Swift has a maximum of
    # 10,000 names.
    my $more=1;
    while ($more) {
	my $aipdataresp = $self->swift->container_get($self->swiftrepoanalysis,
						      \%containeropt);
	if ($aipdataresp->code != 200) {
	    die "container_get(".$self->swiftrepoanalysis.") for $aip returned ". $aipdataresp->code . " - " . $aipdataresp->message. "\n";
	};
	$more=scalar(@{$aipdataresp->content});
	if ($more) {
	    $containeropt{'marker'}=$aipdataresp->content->[$more-1]->{name};

	    foreach my $object (@{$aipdataresp->content}) {
		my $file=substr $object->{name},(length $aip)+1;
		$repoanalysisdata{$file}=$object;
	    }
	}
    }

    foreach my $line (@datafiles) {
	my ($md5,$file) = split /\s+/, $line;
	my $length;

	if (! exists $aipdata{$file}) {
	    die "$file didn't exist in Swift\n";
	}
	if ($md5 ne $aipdata{$file}{'hash'}) {
	    die "$file $md5 didn't match Swift hash ".$aipdata{$file}{'hash'}."\n";
	}
	if (! defined $aipdata{$file}{'bytes'}) {
	    die("Can't get length of /$aip/$file\n");
	}
	my $length=$aipdata{$file}{'bytes'};
	
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


    # Get JHove file metadata
    # TODO


    my $res = $self->repoanalysis->create_or_update($aip,\%repoanalysis);
    if ($res) {
	print "$res\n";
    }

}


1;
