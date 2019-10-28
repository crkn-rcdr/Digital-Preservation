package CRKN::Repository::walkfiles;

use strict;
use CRKN::REST::repoanalysisf;
use CIHM::Swift::Client;
use Config::General;
use Data::Dumper;
use XML::LibXML;

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

    my $lastid='';
    while (my $fileinfo = $self->getnext) {
	my $id=$fileinfo->{"_id"};
	if($id eq $lastid) {
	    warn "$id found - sleeping and trying again\n";
	    sleep(5); # Do nothing, and try again
	} else {
	    $lastid=$id;
	    $self->{id}=$id;
	    $self->{fileinfo}=$fileinfo;
	    eval { $self->process() };
	    if ($@) {
		$fileinfo->{jhove_error}=$@;
	    } else {
		delete $fileinfo->{jhove_error};
	    }
	    $fileinfo->{jhove_processed}=$fileinfo->{jhove_last_modified};
	    my $res = $self->repoanalysisf->post("/".$self->repoanalysisf->database."/_bulk_docs",{ docs => [$fileinfo]},{deserializer => 'application/json'});
	    if ($res->code != 201 && $res->code != 200) {
		warn "$id PUT return code: " . $res->code . "\n";
	    }
#	    exit 0; # TESTING
	}
    }
}

sub getnext {
    my $self = shift;

    $self->repoanalysisf->type("application/json");
    my $res = $self->repoanalysisf->get("/".$self->repoanalysisf->database."/_design/ra/_view/processjhoveq?reduce=false&limit=1&include_docs=true",{}, {deserializer => 'application/json'});
    if ($res->code == 200) {
	if (exists $res->data->{rows}) {
	    return $res->data->{rows}[0]{doc};
	} else {
	    warn "_view/processjhoveq GET returned no rows\n"; 
	}
    }
    else {
        warn "_view/processjhoveq GET return code: ".$res->code."\n"; 
    }
}

sub process {
    my ($self)= @_;

    my $id=$self->id;
    my $fileinfo=$self->fileinfo;
    
    my $jhove=$self->loadJhove;
    die "XML empty" if !$jhove;

    my $xpc = XML::LibXML::XPathContext->new($jhove);
    $xpc->registerNs('jhove', "http://hul.harvard.edu/ois/xml/ns/jhove");
    $xpc->registerNs('mix', "http://www.loc.gov/mix/v20");

    my $size=$xpc->findvalue("descendant::jhove:size",$jhove);
    if ($size > 0) {
	$fileinfo->{'Size'}=$size;
    }

    my $md5=$xpc->findvalue('descendant::jhove:checksum[@type="MD5"]',$jhove);
    if ($md5) {
	$fileinfo->{'MD5'}=$md5;
    }

    my $mimetype=$xpc->findvalue("descendant::jhove:mimeType",$jhove);
    if (index($mimetype,"image/")==0) {
	my @mix=$xpc->findnodes("descendant::mix:mix",$jhove);
	if (scalar(@mix)>0) {
	    $fileinfo->{'Width'}= $xpc->findvalue("descendant::mix:imageWidth",$mix[0]);
	    $fileinfo->{'Height'}= $xpc->findvalue("descendant::mix:imageHeight",$mix[0]);
	}
    }

    # Updating Filemeta database with potentially new information
    my $format=$xpc->findvalue("descendant::jhove:format",$jhove);
    if ($format) {
	$fileinfo->{'format'}=$format;
    }
    my $version=$xpc->findvalue("descendant::jhove:version",$jhove);
    if ($version) {
	$fileinfo->{'version'}=$version;
    }
    my $status=$xpc->findvalue("descendant::jhove:status",$jhove);
    if ($status) {
	$fileinfo->{'status'}=$status;
    }
    my $mimetype=$xpc->findvalue("descendant::jhove:mimeType",$jhove);
    if ($mimetype) {
	$fileinfo->{'mimetype'}=$mimetype;
    }
    my @errormsgs;
    foreach my $errormsg ($xpc->findnodes('descendant::jhove:message[@severity="error"]',$jhove)) {
	my $txtmsg=$errormsg->to_literal;
	if (! ($txtmsg =~ /^\d+$/)) {
	    push @errormsgs,$txtmsg;
	}
    }
    if (@errormsgs) {
	$fileinfo->{'errormsg'}=join(',',@errormsgs);
    }
}
sub id {
    my $self = shift;
    return $self->{id};
}
sub fileinfo {
    my $self = shift;
    return $self->{fileinfo};
}



sub loadJhove {
    my $self = shift;


    my $pathname=$self->fileinfo->{jhove_container}." / ". $self->fileinfo->{jhove_name};

    my $r=$self->swift->object_get($self->fileinfo->{jhove_container},
				   $self->fileinfo->{jhove_name});
    if ($r->code != 200) {
        die "Accessing $pathname returned code: " . $r->code."\n";
    }
    my $jhove = eval { XML::LibXML->new->parse_string($r->content) };
    if ($@) {
	die "XML::LibXM::parse_string for $pathname: $@\n";
    }
    return $jhove;
}

1;
