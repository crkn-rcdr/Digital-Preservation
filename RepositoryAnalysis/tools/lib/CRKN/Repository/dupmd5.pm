package CRKN::Repository::dupmd5;

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

    my @dupmd5;
    
    $self->repoanalysis->type("application/json");

    my $skip=0;
    my $limit=100;
    my $rows=-1;
    until($rows == 0) {
	my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/filemap/_view/md5sizesip?group=true&group_level=1&limit=$limit&skip=$skip",{}, {deserializer => 'application/json'});
	if ($res->code == 200) {
	    if (exists $res->data->{rows}) {
		$rows=scalar(@{$res->data->{rows}});
		foreach my $hr (@{$res->data->{rows}}) {
		    if ($hr->{value} > 1) {
			push @dupmd5,$hr->{key}[0];
			print "Found ".$hr->{key}[0] . " has " .$hr->{value}."\n";
		    }
		}
		$skip = $skip+$rows;
	    } else {
		warn "No {rows}\n";
		$rows=0;
	    }
	}
	else {
	    warn "_view/hammerq GET return code: ".$res->code."\n";
	    $rows=0;
	}
    }

    print Dumper(\@dupmd5);
}

1;
