package CRKN::Repository::walkmetadata::Worker;

use strict;
use Carp;
use AnyEvent;
use Try::Tiny;
use JSON;
use Config::General;
use Log::Log4perl;

use CIHM::Swift::Client;
use CRKN::REST::repoanalysis;
use CRKN::Repository::walkmetadata::Process;

use Data::Dumper;

our $self;

sub initworker {
    my $argjson = shift;

    our $self;
    $self = bless {};

    $self->{args} = decode_json $argjson;
    my $configpath = $self->args->{configpath};

    AE::log debug => "Initworker ($$): $configpath";

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    my %confighash = new Config::General( -ConfigFile => $configpath, )->getall;

    # Undefined if no <repoanalysis> config block
    if ( exists $confighash{repoanalysis} ) {
        $self->{repoanalysis} = new CRKN::REST::repoanalysis(
            server      => $confighash{repoanalysis}{server},
            database    => $confighash{repoanalysis}{database},
            type        => 'application/json',
            conf        => $configpath,
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        die "Missing <repoanalysis> configuration block in $configpath\n";
    }

    # Undefined if no <swift> config block
    if ( exists $confighash{swift} ) {
        my %swiftopt = ( furl_options => { timeout => 120 } );
        foreach ( "server", "user", "password", "account", "furl_options" ) {
            if ( exists $confighash{swift}{$_} ) {
                $swiftopt{$_} = $confighash{swift}{$_};
            }
        }
        $self->{swift}       = CIHM::Swift::Client->new(%swiftopt);
        $self->{swiftconfig} = $confighash{swift};
    }
    else {
        die "No <swift> configuration block in $configpath\n";
    }

}

# Simple accessors
sub args {
    my $self = shift;
    return $self->{args};
}

sub log {
    my $self = shift;
    return $self->{logger};
}

sub repoanalysis {
    my $self = shift;
    return $self->{repoanalysis};
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

sub warnings {
    my $warning = shift;
    our $self;
    my $aip = "unknown";

    # Strip wide characters before  trying to log
    ( my $stripped = $warning ) =~ s/[^\x00-\x7f]//g;

    if ($self) {
        $self->{message} .= $warning;
        $aip = $self->{aip};
        $self->log->warn( $aip . ": $stripped" );
    }
    else {
        say STDERR "$warning\n";
    }
}

sub job {
    my ( $aip, $argjson ) = @_;
    our $self;

    # Capture warnings
    local $SIG{__WARN__} = sub { &warnings };

    if ( !$self ) {
        initworker($argjson);
    }

    # Debugging: http://lists.schmorp.de/pipermail/anyevent/2017q2/000870.html
    #  $SIG{CHLD} = 'IGNORE';

    $self->{aip}             = $aip;
    $self->{message}         = '';
    $self->{metadatasummary} = {};

    $self->log->info("Processing $aip");

    AE::log debug => "$aip Before ($$)";

    my $status;

    # Handle and record any errors
    try {
        $status = 1;
        new CRKN::Repository::walkmetadata::Process(
            {
                aip            => $aip,
                args           => $self->args,
                worker         => $self,
                log            => $self->log,
                swift          => $self->swift,
                swiftcontainer => $self->container,
                repoanalysis   => $self->repoanalysis,
            }
        )->process;
    }
    catch {
        $status = 0;
        $self->log->error("$aip: $_");
        $self->{message} .= "Caught: " . $_;
    };
    $self->setResult( "status",  $status );
    $self->setResult( "message", $self->{message} );
    $self->postResults($aip);

    AE::log debug => "$aip After ($$)";

    return ($aip);
}

sub setResult {
    my ( $self, $var, $value ) = @_;

    $self->{metadatasummary}->{$var} = $value;
}

sub postResults {
    my ( $self, $aip ) = @_;

    $self->repoanalysis->create_or_update(
        $aip,
        {
            "metadatasummary" => $self->{metadatasummary}
        }
    );
}

1;
