package CRKN::Repository::walkmetadata;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;

use CRKN::REST::repoanalysis;
use CRKN::Repository::walkmetadata::Worker;

use Coro::Semaphore;
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;

use Try::Tiny;
use JSON;
use Data::Dumper;

=head1 NAME
CRKN::Repository::walkmetadata - Process changelog.txt and METS records
=head1 SYNOPSIS
    my $wj = CRKN::Repository::walkmetadata->new($args);
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

sub walk {
    my ($self) = @_;


    $self->log->info("WalkMetadata: conf=".$self->configpath." skip=".$self->skip. " limit=".$self->limit. " maxprocs=" . $self->maxprocs . " timelimit=".$self->{timelimit});

    my $pool = AnyEvent::Fork
        ->new
        ->require ("CRKN::Repository::walkmetadata::Worker")
        ->AnyEvent::Fork::Pool::run 
        (
         "CRKN::Repository::walkmetadata::Worker::job",
         max        => $self->maxprocs,
         load       => 2,
         on_destroy => ( my $cv_finish = AE::cv ),
        );



    # Semaphore keeps us from filling the queue with too many AIPs before
    # some are processed.
    my $sem = new Coro::Semaphore ($self->maxprocs*2);
    my $somework;

    my $argstring = encode_json $self->args;
    while (my $aip = $self->getNextAIP) {
        $somework=1;
        $self->{inprogress}->{$aip}=1;
        $sem->down;
        $pool->($aip,$argstring,sub {
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

    my $aip;
    return if $self->endtime && time() > $self->endtime;

    if ($self->args->{aip} && ! (defined $self->{cmdaips})) {
	return if $self->{processedaip};
	$self->{processedaip}=1;
	my @cmdaips = split(',',$self->args->{aip});
	$self->{cmdaips}=\@cmdaips;
	print Data::Dumper->Dump([$self->{cmdaips}], [qw(AIPlist)]);
    }
    $aip = shift @{$self->{cmdaips}};
    return $aip if $aip;
    return if ($self->args->{aip});

    if (! defined $self->{walkmetadataq}) {
	$self->{walkmetadataq}=[];

	$self->repoanalysis->type("application/json");	
	my $res = $self->repoanalysis->get("/".$self->repoanalysis->database."/_design/ra/_view/walkmetadataq?reduce=false",{}, {deserializer => 'application/json'});
	if ($res->code == 200) {
	    if (exists $res->data->{rows}) {
		foreach my $njr (@{$res->data->{rows}}) {
		    push @{$self->{walkmetadataq}}, $njr->{id};
		}
	    } else {
		warn "_view/walkmetadataq GET returned no rows\n";
	    }
	} else {
	    warn "_view/walkmetadataq GET return code: ".$res->code."\n";
	}
	$self->{walkmetadataqcount}=scalar @{$self->{walkmetadataq}};
	if ($self->{walkmetadataqcount}) {
	    $self->log->info("There are ".$self->{walkmetadataqcount}." AIPs needing metadata processed");
	}
    }
    $aip = shift @{$self->{walkmetadataq}};
    return $aip if $aip;

    $self->log->info("Lists empty");

    return;
}

1;
