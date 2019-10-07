package CRKN::Repository::clearmd5;

use strict;
use Carp;
use Config::General;
use CRKN::REST::repoanalysis;
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
sub repoanalysis {
    my $self = shift;
    return $self->{repoanalysis};
}


sub walk {
    my ($self) = @_;

    # An empty summary
    my %repoanalysis = ( md5summary => {});
    
    my $lastid='';
    while (my $aipinfo = $self->getnext) {
	my $id=$aipinfo->{"id"};
	if($id eq $lastid) {
	    warn "$id found - sleeping and trying again\n";
	    sleep(5); # Do nothing, and try again
	} else {
	    $lastid=$id;
	    my $res = $self->repoanalysis->create_or_update($id,\%repoanalysis);
	}
    }
}


sub getnext {
    my $self = shift;

    $self->repoanalysis->type("application/json");

    my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/ra/_view/walkmd5r?reduce=false&limit=1&include_docs=false",{}, {deserializer => 'application/json'});

#    my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/ra/_view/sipdupinother?reduce=false&limit=1&include_docs=false",{}, {deserializer => 'application/json'});

    if ($res->code == 200) {
	if (exists $res->data->{rows}) {
	    return $res->data->{rows}[0];
	} else {
	    warn "_view/walkmd5r GET returned no rows\n"; 
	}
    }
    else {
        warn "_view/walkmd5r GET return code: ".$res->code."\n"; 
    }
}

1;
