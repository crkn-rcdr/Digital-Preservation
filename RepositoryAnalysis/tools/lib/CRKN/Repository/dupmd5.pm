package CRKN::Repository::dupmd5;

use strict;
use Carp;
use Config::General;
use CRKN::REST::repoanalysis;
use Data::Dumper;


=head1 NAME

CRKN::Repository::dupmd5 - detect duplicate MD5's and determine if they have different file sizes.

=cut


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


    my @md5s;

    $self->repoanalysis->type("application/json");

    my $skip=0;
    my $limit=50000;
    my $rows=-1;
    until($rows == 0) {
	my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/filemap/_view/md5sizesip?group=true&group_level=1&limit=$limit&skip=$skip",{}, {deserializer => 'application/json'});
	if ($res->code == 200) {
	    if (exists $res->data->{rows}) {
		$rows=scalar(@{$res->data->{rows}});
		foreach my $hr (@{$res->data->{rows}}) {
		    if ($hr->{value} > 1) {
			push @md5s,$hr->{key}[0];
		    }
		}
		$skip = $skip+$rows;
		print "Skip=$skip md5s=".scalar(@md5s)." First was=".$res->data->{rows}->[0]->{key}[0]."\n";
	    } else {
		warn "No {rows}\n";
		$rows=0;
	    }
	}
	else {
	    warn "_view/md5sizesip GET return code: ".$res->code."\n";
	    $rows=0;
	}
    }
    print "There are ".scalar(@md5s)." md5's with more than 1 file\n";
    print "Checking for duplidates....\n";
    foreach my $md5 (@md5s) {
	$self->process_md5($md5);
    };
}



sub process_md5 {
    my ($self,$md5) = @_;

    my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/filemap/_view/md5sizesip?reduce=false&startkey=\[\"$md5\"\]&endkey=\[\"$md5\",{}\]",{}, {deserializer => 'application/json'});
    if ($res->code == 200) {
	if (exists $res->data->{rows}) {
	    my $size;
	    foreach my $mss (@{$res->data->{rows}}) {
		if (! defined $size) {
		    $size = $mss->{key}[1]
		} else {
		    if ($size != $mss->{key}[1]) {
			print "\nFound multiple sizes for $md5" . Dumper($res->data->{rows})."\n";
			last;
		    }
		}
	    }
	} else {
	    warn "No {rows} for $md5\n";
	}
    }
    else {
	warn "process_md5() view/md5sizesip return code: ".$res->code."\n";
    }
}


1;
