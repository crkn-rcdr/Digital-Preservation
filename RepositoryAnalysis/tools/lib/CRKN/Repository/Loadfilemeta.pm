package CRKN::Repository::Loadfilemeta;

use strict;
use Config::General;
use CRKN::REST::filemeta;
use CIHM::Swift::Client;
use Data::Dumper;
use URI::Escape;

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
    if (exists $confighash{filemeta}) {
        $self->{filemeta} = new CRKN::REST::filemeta (
            server => $confighash{filemeta}{server},
            database => $confighash{filemeta}{database},
            type   => 'application/json',
            conf   => $args->{configpath},
            clientattrs => {timeout => 3600},
            );
    } else {
        die "Missing <filemeta> configuration block in config\n";
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
sub filemeta {
    my $self = shift;
    return $self->{filemeta};
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


sub load {
    my ($self) = @_;

    my $jhovefiles=0;
    my $skip=0;
    my $limit=10000;
    my $rows=-1;
    my $descending="true";
    my $lastpath="none";
    until($rows == 0) {
	$self->filemeta->type("application/json");
	print "Limit=$limit Skip=$skip Lastpath=$lastpath LastRows=$rows JhoveFiles=$jhovefiles\n";
	my $res = $self->filemeta->get("/".$self->filemeta->database."/_all_docs?limit=$limit&skip=$skip&include_docs=true&descending=$descending",{}, {deserializer => 'application/json'});
        if ($res->code == 200) {
	    $rows = scalar(@{$res->data->{rows}});
	    foreach my $row (@{$res->data->{rows}}) {
		if (exists $row->{doc} &&
		    exists $row->{doc}->{'_attachments'} &&
		    exists $row->{doc}->{'_attachments'}->{'jhove.xml'}) {

		    $jhovefiles++;
		    # Copy attachment to Swift
		    my $pathname = $row->{id};
		    $lastpath=$pathname;
		    my $jhovexml = $self->filemeta->get_attachment(uri_escape($pathname),"jhove.xml");

		    my $putresp = $self->swift->object_put($self->swiftrepoanalysis,$pathname."/jhove.xml", $jhovexml);
		    if ($putresp->code != 201) {
			die("object_put of $pathname/jhove.xml returned ".$putresp->code . " - " . $putresp->message."\n");
		    }
		}
            }
	    $skip = $skip+$rows;
	} else {
	    die "load from filemeta return code: ".$res->code."\n"; 
        }
    }
}

1;
