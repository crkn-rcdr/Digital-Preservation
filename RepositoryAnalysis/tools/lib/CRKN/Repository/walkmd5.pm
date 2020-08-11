package CRKN::Repository::walkmd5;

use strict;
use Carp;
use Config::General;
use CRKN::REST::repoanalysis;
use CRKN::REST::repoanalysisf;
use Data::Dumper;

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::TDR::Replication->new() not a hash\n";
    }
    $self->{args} = $args;

    my %confighash =
      new Config::General( -ConfigFile => $args->{configpath}, )->getall;

    # Undefined if no <repoanalysis> config block
    if ( exists $confighash{repoanalysis} ) {
        $self->{repoanalysis} = new CRKN::REST::repoanalysis(
            server      => $confighash{repoanalysis}{server},
            database    => $confighash{repoanalysis}{database},
            type        => 'application/json',
            conf        => $args->{configpath},
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <repoanalysis> configuration block in config\n";
    }

    # Undefined if no <repoanalysis> config block
    if ( exists $confighash{repoanalysisf} ) {
        $self->{repoanalysisf} = new CRKN::REST::repoanalysisf(
            server      => $confighash{repoanalysisf}{server},
            database    => $confighash{repoanalysisf}{database},
            type        => 'application/json',
            conf        => $args->{configpath},
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <repoanalysisf> configuration block in config\n";
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

sub walk {
    my ($self) = @_;

    my $lastid = '';
    while ( my $aipinfo = $self->getnext ) {
        my $id = $aipinfo->{"_id"};
        if ( $id eq $lastid ) {
            warn "$id found - sleeping and trying again\n";
            sleep(5);    # Do nothing, and try again
        }
        else {
            $lastid = $id;
            $self->process( $id, $aipinfo );
        }
    }
}

sub getnext {
    my $self = shift;

    $self->repoanalysis->type("application/json");
    my $res = $self->repoanalysis->get(
        "/"
          . $self->repoanalysis->{database}
          . "/_design/ra/_view/walkmd5q?reduce=false&limit=1&include_docs=true",
        {},
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        if ( exists $res->data->{rows} ) {
            return $res->data->{rows}[0]{doc};
        }
        else {
            warn "_view/walkmd5q GET returned no rows\n";
        }
    }
    else {
        warn "_view/walkmd5q GET return code: " . $res->code . "\n";
    }
}

sub process {
    my ( $self, $aip, $aipinfo ) = @_;

    print "Processing $aip\n";
    my $manifestdate = $aipinfo->{summary}->{manifestdate};

    # Hash of information to be posted to CouchDB
    my %repoanalysis = (
        md5summary => {
            manifestdate  => $manifestdate,
            globaluniq    => [],
            revduplicates => {},
            sipduplicates => {}
        }
    );

    my %revdupinaip;
    my %sipdupinaip;

    if ( exists $aipinfo->{revfiles} ) {
        foreach my $file ( keys %{ $aipinfo->{revfiles} } ) {
            my ( $md5, $size ) = @{ $aipinfo->{revfiles}->{$file} };

            if (   exists $repoanalysis{md5summary}{revduplicates}{$md5}
                && exists $repoanalysis{md5summary}{revduplicates}{$md5}{$size}
              )
            {
                # An existing file already caused this lookup
                next;
            }

            my $res = $self->repoanalysisf->get(
                "/"
                  . $self->repoanalysisf->{database}
                  . "/_design/ra/_view/md5size?reduce=false&key=\[\"$md5\",\"$size\"\]",
                {},
                { deserializer => 'application/json' }
            );
            if ( $res->code == 200 ) {
                if ( scalar @{ $res->data->{rows} } ) {

                    # We only want the ones not in our SIP
                    my $inmysip = 0;
                    foreach my $found ( @{ $res->data->{rows} } ) {
                        if ( $found->{'id'} eq $aip ) {
                            $inmysip = 1;
                            last;
                        }
                    }
                    if ( !$inmysip ) {
                        foreach my $found ( @{ $res->data->{rows} } ) {
                            if ( !exists $repoanalysis{md5summary}
                                {revduplicates}{$md5}{$size} )
                            {
                                $repoanalysis{md5summary}{revduplicates}{$md5}
                                  {$size} = [];
                            }
                            push
                              @{ $repoanalysis{md5summary}{revduplicates}{$md5}
                                  {$size} },
                              $found->{'id'} . "/" . $found->{'value'};
                            $revdupinaip{ $found->{'id'} } = 1;
                        }
                    }
                }
                else {
                    push @{ $repoanalysis{md5summary}{globaluniq} }, $file;
                }
            }
            else {
                warn "_view/md5size GET return code: " . $res->code . "\n";
            }
        }
    }

    if ( exists $aipinfo->{sipfiles} ) {
        foreach my $file ( keys %{ $aipinfo->{sipfiles} } ) {
            my ( $md5, $size ) = @{ $aipinfo->{sipfiles}->{$file} };

            if (   exists $repoanalysis{md5summary}{sipduplicates}{$md5}
                && exists $repoanalysis{md5summary}{sipduplicates}{$md5}{$size}
              )
            {
                # An existing file already caused this lookup
                next;
            }

            my $res = $self->repoanalysisf->get(
                "/"
                  . $self->repoanalysisf->{database}
                  . "/_design/ra/_view/md5size?reduce=false&key=\[\"$md5\",\"$size\"\]",
                {},
                { deserializer => 'application/json' }
            );
            if ( $res->code == 200 ) {

                # Files unique to this SIP will exist 1 time.
                if ( ( scalar @{ $res->data->{rows} } ) > 1 ) {
                    foreach my $found ( @{ $res->data->{rows} } ) {
                        if ( !exists $repoanalysis{md5summary}{sipduplicates}
                            {$md5}{$size} )
                        {
                            $repoanalysis{md5summary}{sipduplicates}{$md5}
                              {$size} = [];
                        }
                        push @{ $repoanalysis{md5summary}{sipduplicates}{$md5}
                              {$size} },
                          $found->{'id'} . "/" . $found->{'value'};
                        $sipdupinaip{ $found->{'id'} } = 1;
                    }
                }
            }
            else {
                warn "_view/md5sizesip GET return code: " . $res->code . "\n";
            }
        }
    }
    my $sipduplicates =
      scalar( keys %{ $repoanalysis{md5summary}{sipduplicates} } );
    my $revduplicates =
      scalar( keys %{ $repoanalysis{md5summary}{revduplicates} } );
    if ($sipduplicates) {
        print "$aip SIP has $sipduplicates duplicates\n";
    }
    if ($revduplicates) {
        print "$aip revisions have $revduplicates duplicates\n";
    }

    # Array of AIPs that duplicates were found in, excluding this one.
    delete $revdupinaip{$aip};
    my @revdupfromaip = keys %revdupinaip;
    $repoanalysis{md5summary}{revdupfromaip} = \@revdupfromaip;

    delete $sipdupinaip{$aip};
    my @sipdupfromaip = keys %sipdupinaip;
    $repoanalysis{md5summary}{sipdupfromaip} = \@sipdupfromaip;

    my $res = $self->repoanalysis->create_or_update( $aip, \%repoanalysis );
}

1;
