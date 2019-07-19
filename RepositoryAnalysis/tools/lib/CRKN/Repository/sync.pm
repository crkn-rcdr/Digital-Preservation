package CRKN::Repository::sync;

use strict;
use Carp;
use CIHM::TDR::TDRConfig;
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


sub sync {
    my ($self) = @_;

    $self->internalmeta->type("application/json");
    my $res = $self->internalmeta->get("/".$self->internalmeta->{database}."/_design/tdr/_view/metscount?reduce=false&startkey=2&endkey=7",{}, {deserializer => 'application/json'});
    if ($res->code == 200) {
        if (exists $res->data->{rows}) {
            foreach my $hr (@{$res->data->{rows}}) {
                $self->getmanifestdate($hr->{id},$hr->{key});
            }
        }
    }
    else {
        warn "_view/metscount GET return code: ".$res->code."\n"; 
    }
}

sub getmanifestdate {
    my ($self,$aip,$metscount) = @_;

    my $res =  $self->internalmeta->get("/".$self->internalmeta->{database}."/$aip",{}, {deserializer => 'application/json'});

    if ($res->code == 200) {
	$res = 
	    $self->repoanalysis->create_or_update(
		$aip,
		{
		    metscount => $metscount,
		    manifestdate => $res->data->{reposManifestDate},
		});
	if ($res) {
	    print "$res\n";
	}
    }
    else {
        warn "_view/getmanifestdate GET return code: ".$res->code."\n"; 
    }
}

1;
