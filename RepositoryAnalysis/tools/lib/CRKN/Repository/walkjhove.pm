package CRKN::Repository::walkjhove;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;

use CRKN::REST::repoanalysis;
use CRKN::REST::repoanalysisf;

use CRKN::Repository::walkjhove::Worker;

use Coro::Semaphore;
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;

use Try::Tiny;
use JSON;
use Data::Dumper;

=head1 NAME
CRKN::Repository::walkjhove - Generate and/or process JHOVE reports for files within a SIP of an AIP
=head1 SYNOPSIS
    my $wj = CRKN::Repository::walkjhove->new($args);
      where $args is a hash of arguments.
      $args->{configpath} is as used by Config::General
      $args->{aip} is a single AIP to process, rather than using queue.

=cut

sub new {
    my($class, $args) = @_;
    my $self = bless {}, $class;

    if (ref($args) ne "HASH") {
        die "Argument to CIHM::Meta::Hammer->new() not a hash\n";
    };
    $self->{args} = $args;

    $self->{skip}=delete $args->{skip};

    $self->{maxprocs}=delete $args->{maxprocs};
    if (! $self->{maxprocs}) {
        $self->{maxprocs}=3;
    }

    # Set up for time limit
    $self->{timelimit} = delete $args->{timelimit};
    if($self->{timelimit}) {
        $self->{endtime} = time() + $self->{timelimit};
    }


    # Set up in-progress hash (Used to determine which AIPs which are being
    # processed by a slave so we don't try to do the same AIP twice.
    $self->{inprogress}={};

    $self->{limit}=delete $args->{limit};
    if (! $self->{limit}) {
        $self->{limit} = ($self->{maxprocs})*2+1
    }

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");


    my %confighash = new Config::General(
	-ConfigFile => $args->{configpath},
	)->getall;


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
        croak "Missing <repoanalysisf> configuration block in config\n";
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
        croak "Missing <repoanalysisf> configuration block in config\n";
    }

    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}
sub configpath {
    my $self = shift;
    return $self->{args}->{configpath};
}
sub skip {
    my $self = shift;
    return $self->{skip};
}
sub maxprocs {
    my $self = shift;
    return $self->{maxprocs};
}
sub limit {
    my $self = shift;
    return $self->{limit};
}
sub endtime {
    my $self = shift;
    return $self->{endtime};
}
sub log {
    my $self = shift;
    return $self->{logger};
}
sub repoanalysis {
    my $self = shift;
    return $self->{repoanalysis};
}
sub repoanalysisf {
    my $self = shift;
    return $self->{repoanalysisf};
}


sub walk {
    my ($self) = @_;


    $self->log->info("WalkJhove: conf=".$self->configpath." skip=".$self->skip. " limit=".$self->limit. " maxprocs=" . $self->maxprocs . " timelimit=".$self->{timelimit});

    my $pool = AnyEvent::Fork
        ->new
        ->require ("CRKN::Repository::walkjhove::Worker")
        ->AnyEvent::Fork::Pool::run 
        (
         "CRKN::Repository::walkjhove::Worker::job",
         max        => $self->maxprocs,
         load       => 2,
         on_destroy => ( my $cv_finish = AE::cv ),
        );



    # Semaphore keeps us from filling the queue with too many AIPs before
    # some are processed.
    my $sem = new Coro::Semaphore ($self->maxprocs*2);
    my $somework;

    while (my $aip = $self->getNextAIP) {
        $somework=1;
        $self->{inprogress}->{$aip}=1;
        $sem->down;
        $pool->($aip,$self->configpath,sub {
            my $aip=shift;
            $sem->up;
            delete $self->{inprogress}->{$aip};
                });
    }
    undef $pool;
    if ($somework) {
        $self->log->info("Waiting for child processes to finish");
    }
    $cv_finish->recv;
    if ($somework) {
        $self->log->info("Finished.");
    }
}

sub getNextAIP {
    my $self = shift;

    return if $self->endtime && time() > $self->endtime;

    if ($self->args->{aip}) {
	return if $self->{processedaip};
	$self->{processedaip}=1;
	return $self->args->{aip};
    }

    if (! defined $self->{nojhove}) {
	$self->{nojhove}=[];

	$self->repoanalysisf->type("application/json");	
	my $res = $self->repoanalysisf->get("/".$self->repoanalysisf->database."/_design/ra/_view/nojhove?reduce=true&group=true&include_docs=false",{}, {deserializer => 'application/json'});
	if ($res->code == 200) {
	    if (exists $res->data->{rows}) {
		foreach my $njr (@{$res->data->{rows}}) {
		    push @{$self->{nojhove}}, $njr->{key};
		}
	    } else {
		warn "_view/nojhove GET returned no rows\n";
	    }
	} else {
	    warn "_view/nojhove GET return code: ".$res->code."\n";
	}
	$self->{nojhovecount}=scalar @{$self->{nojhove}};
	if ($self->{nojhovecount}) {
	    $self->log->info("There are ".$self->{nojhovecount}." AIPs with missing JHOVE reports");
	}
    }
    my $aip = shift @{$self->{nojhove}};
    return $aip if $aip;

    if (! defined $self->{walkjhoveq}) {
	$self->{walkjhoveq}=[];

	$self->repoanalysis->type("application/json");	
	my $res = $self->repoanalysis->get("/".$self->repoanalysis->database."/_design/ra/_view/walkjhoveq?reduce=false",{}, {deserializer => 'application/json'});
	if ($res->code == 200) {
	    if (exists $res->data->{rows}) {
		foreach my $njr (@{$res->data->{rows}}) {
		    push @{$self->{walkjhoveq}}, $njr->{id};
		}
	    } else {
		warn "_view/walkjhoveq GET returned no rows\n";
	    }
	} else {
	    warn "_view/walkjhoveq GET return code: ".$res->code."\n";
	}
	$self->{walkjhoveqcount}=scalar @{$self->{walkjhoveq}};
	if ($self->{walkjhoveqcount}) {
	    $self->log->info("There are ".$self->{walkjhoveqcount}." AIPs needing jhove reports processed");
	}
    }

    my $aip = shift @{$self->{walkjhoveq}};
    return $aip if $aip;

    $self->log->info("Lists empty");

    return;
}

1;
