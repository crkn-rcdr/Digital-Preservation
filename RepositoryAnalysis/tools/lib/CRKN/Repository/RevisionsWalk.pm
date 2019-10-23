package CRKN::Repository::RevisionsWalk;

use strict;
use Config::General;
use CRKN::REST::repoanalysis;
use CRKN::REST::repoanalysisf;
use CIHM::Swift::Client;
use JSON;
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
    }
    else {
        warn "_view/walkq GET return code: ".$res->code."\n";
    }
}


# These are AIP specific variables used by the rest of this module.
sub aip {
    my $self = shift;
    return $self->{aip};
}
sub manifestdate {
    my $self = shift;
    return $self->{manifestdate};
}
sub rad {
    my $self = shift;
    return $self->{rad};
}
sub sipfiles {
    my $self = shift;
    return $self->rad->{sipfiles};
}
sub raf {
    my $self = shift;
    return $self->{raf};
}
sub aipdata {
    my $self = shift;
    return $self->{aipdata};
}
sub repoanalysisdata {
    my $self = shift;
    return $self->{repoanalysisdata};
}

sub filemetadata {
    my $self = shift;
    return $self->{filemetadata};
}


sub processaip {
    my ($self,$aip,$manifestdate) = @_;

    # Set for other functions
    $self->{aip}=$aip;
    $self->{manifestdate}=$manifestdate;

    # Load list of files within AIP from repository container
    $self->load_aipdata();

    # Load list of files within AIP from repoanalysis container
    $self->load_repoanalysisdata();

    # Load manifest, and do some analysis based on that
    $self->load_manifest();

    # Load file data for this AIP
    $self->load_repoanalysisf();

    # Manipulates data from repoanalysisf for files in SIP
    $self->process_sipfiles();

    # Save file data for this AIP
    $self->save_repoanalysisf();

    # Store repoanalysis record
    my $res = $self->repoanalysis->create_or_update($self->aip,$self->rad);
    if ($res) {
	# This function returns string as result
	print "$res\n";
    }
}


sub load_manifest {
    my $self = shift;

    $self->{rad}={};

    my $file = $self->aip."/manifest-md5.txt";
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
	print STDERR "Mismatch on data file counts for ".$self->aip." !!\n";
	print STDERR Dumper(\@datafiles,\@revdatafiles,\@sipdatafiles)."\n";
    }

    foreach my $line (@datafiles) {
	my ($md5,$file) = split /\s+/, $line;

	if (! exists $self->aipdata->{$file}) {
	    die "$file didn't exist in Swift\n";
	}
	if ($md5 ne $self->aipdata->{$file}->{'hash'}) {
	    die "$file $md5 didn't match Swift hash ".$self->aipdata->{$file}->{'hash'}."\n";
	}
	if (! defined $self->aipdata->{$file}->{'bytes'}) {
	    die("Can't get length of /".$self->aip."/$file\n");
	}
	my $length=$self->aipdata->{$file}->{'bytes'};

	push @manifest, [$file,$md5,$length];

	if (substr($file,0,20) eq 'data/sip/data/files/') {
	    $self->rad->{sipfiles}->{$file}=[$md5,$length];
	    if(defined $sipdfmd5{"$md5:$length"}) {
		print STDERR ($self->aip.": $md5 with length $length is duplicate between $file and ".$sipdfmd5{"$md5:$length"}."\n");
	    } else {
		$sipdfmd5{"$md5:$length"}=$file;
	    }
	} else {
	    $self->rad->{revfiles}{$file}=[$md5,$length];
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

    # Hash of information to be posted to CouchDB
    $self->rad->{summary} = {
	manifestdate => $self->manifestdate,
	sipfiles => $sipfiles,
	revfiles => $revfiles,
	unique => $unique,
	duplicate => $duplicate
    };

    if ($revfiles != 0) {
	print $self->aip." SIP:$sipfiles , Revision:$revfiles , Unique:$unique , Duplicate:$duplicate\n";
    }
}

sub load_aipdata {
    my $self = shift;

    # Get a listing of files from Swift within this AIP
    my %containeropt = (
	"prefix" => $self->aip."/"
	);
    my %aipdata;
    # Need to loop possibly multiple times as Swift has a maximum of
    # 10,000 names.
    my $more=1;
    while ($more) {
	my $aipdataresp = $self->swift->container_get($self->container,
						      \%containeropt);
	if ($aipdataresp->code != 200) {
	    die "container_get(".$self->container.") for ".$self->aip." returned ". $aipdataresp->code . " - " . $aipdataresp->message. "\n";
	};
	$more=scalar(@{$aipdataresp->content});
	if ($more) {
	    $containeropt{'marker'}=$aipdataresp->content->[$more-1]->{name};

	    foreach my $object (@{$aipdataresp->content}) {
		my $file=substr $object->{name},(length $self->aip)+1;
		$aipdata{$file}=$object;
	    }
	}
    }

    $self->{aipdata}=\%aipdata;
}

sub load_repoanalysisdata {
    my $self = shift;

    # Get a listing of files from Swift within this AIP, this time from other container
    my %containeropt = (
	"prefix" => $self->aip."/"
	);

    my %repoanalysisdata;
    # Need to loop possibly multiple times as Swift has a maximum of
    # 10,000 names.
    my $more=1;
    while ($more) {
	my $aipdataresp = $self->swift->container_get($self->swiftrepoanalysis,
						      \%containeropt);
	if ($aipdataresp->code != 200) {
	    die "container_get(".$self->swiftrepoanalysis.") for ".$self->aip." returned ". $aipdataresp->code . " - " . $aipdataresp->message. "\n";
	};
	$more=scalar(@{$aipdataresp->content});
	if ($more) {
	    $containeropt{'marker'}=$aipdataresp->content->[$more-1]->{name};

	    foreach my $object (@{$aipdataresp->content}) {
		my $file=substr $object->{name},(length $self->aip)+1;
		$repoanalysisdata{$file}=$object;
	    }
	}
    }

    $self->{repoanalysisdata}=\%repoanalysisdata;
}


sub load_repoanalysisf {
    my $self=shift;

    $self->{raf}={};

    $self->repoanalysisf->type("application/json");
    my $res = $self->repoanalysisf->get("/".$self->repoanalysisf->database."/_all_docs",{
	include_docs => 'true',
	startkey => '"'.$self->aip.'/"',
	endkey => '"'.$self->aip.'/'.chr(0xfff0).'"'
					}, {deserializer => 'application/json'});
    if ($res->code == 200) {
	foreach my $row (@{$res->data->{rows}}) {
	    $self->{raf}->{$row->{key}}=$row->{doc};
	}
    }
    else {
	die "load_repoanalysisf return code: ".$res->code."\n";
    }
}

sub save_repoanalysisf {
    my $self=shift;

    if ($self->raf) {
        my @files=sort keys %{$self->raf};
        my @update;

        foreach my $file (@files) {
            my $thisfile=$self->raf->{$file};
            if ($thisfile->{changed}) {
                delete $thisfile->{changed};
                push @update, $thisfile;
            }
        }

        if (@update) {
            my $res = $self->repoanalysisf->post("/".$self->repoanalysisf->database."/_bulk_docs",
						 {docs => \@update },
						 {deserializer => 'application/json'});
            if ($res->code != 201) {
                die "save_repoanalysisf _bulk_docs returned: ".$res->code."\n";
            }
        }
    }
}

sub set_fmetadata {
    my ($self,$fmetadata,$key,$value) = @_;

    if (! exists $fmetadata->{$key} ||
        $fmetadata->{$key} ne $value) {
        $fmetadata->{$key}=$value;
        $fmetadata->{'changed'}=1;
    }
}

sub delete_fmetadata {
    my ($self,$fmetadata,$key) = @_;

    if (exists $fmetadata->{$key}) {
        delete $fmetadata->{$key};
        $fmetadata->{'changed'}=1;
    }
}


sub process_sipfiles {
    my $self=shift;

    # Nothing to do if there are no files...
    return if (! $self->sipfiles);

    foreach my $sipfile (keys %{$self->sipfiles}) {
	my $pathname = $self->aip."/".$sipfile;
	my ($md5,$length)=@{$self->sipfiles->{$sipfile}};

	my $fmetadata=$self->raf->{$pathname};

	# If record doesn't already exist, create one.
	if (! $fmetadata) {
	    $fmetadata={
		'_id' => $pathname,
		    changed => 1
	    };
	    $self->raf->{$pathname}=$fmetadata;
	}
	# Set that this file exists, to be used later
	$fmetadata->{finuse}=1;

	# Set what we already know from Swift
	$self->set_fmetadata($fmetadata,'md5',$md5);
	$self->set_fmetadata($fmetadata,'length',$length);

	my $container;
	my $jhovefile;
	my $jhovepath = $sipfile."/jhove.xml";
	if (exists $self->repoanalysisdata->{$jhovepath}) {
	    $container=$self->swiftrepoanalysis;
	    $jhovefile=$self->repoanalysisdata->{$jhovepath}
	} else {
	    $jhovepath=$sipfile;
	    $jhovepath =~ s|data/sip/data/files|data/sip/data/metadata|;
	    $jhovepath = $jhovepath.".jhove.xml";
	    if (exists $self->aipdata->{$jhovepath}) {
		$container=$self->container;
		$jhovefile=$self->aipdata->{$jhovepath};
	    }
	}
	if ($container) {
	    # A JHOVE file was found!
	    $self->set_fmetadata($fmetadata,'jhove_container',$container);
	    $self->set_fmetadata($fmetadata,'jhove_name',$jhovefile->{name});
	    $self->set_fmetadata($fmetadata,'jhove_hash',$jhovefile->{hash});
	    $self->set_fmetadata($fmetadata,'jhove_last_modified',$jhovefile->{last_modified});
	} else {
	    # Ensure these keys are empty, as might have been set by revision
	    $self->delete_fmetadata($fmetadata,'jhove_container');
	    $self->delete_fmetadata($fmetadata,'jhove_name');
	    $self->delete_fmetadata($fmetadata,'jhove_hash');
	    $self->delete_fmetadata($fmetadata,'jhove_last_modified');
	}
    }

    # Check for any files that are no longer in SIP, and
    # mark these couch documents to be deleted
    foreach my $sipfile (keys %{$self->raf}) {
	if (exists $self->raf->{$sipfile}->{finuse}) {
	    delete $self->raf->{$sipfile}->{finuse};
	} else {
	    # Mark CouchDB document as changed and deleted
	    $self->raf->{$sipfile}->{"_deleted"}=JSON::true;
	    $self->raf->{$sipfile}->{'changed'}=1;
	}
    }
}

1;
