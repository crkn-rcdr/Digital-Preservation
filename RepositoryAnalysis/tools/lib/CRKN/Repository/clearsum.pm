package CRKN::Repository::clearsum;

use strict;
use Carp;
use Config::General;
use CRKN::REST::repoanalysis;
use CRKN::REST::repoanalysisf;
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

    if ($self->args->{md5} ) {
	print "Clearing md5summary\n";

	# An empty summary
	my %repoanalysis = ( md5summary => {});

	my $lastid='';
	while (my $aipinfo = $self->getnextmd5) {
	    my $id=$aipinfo->{"id"};
	    if($id eq $lastid) {
		warn "$id found - sleeping and trying again\n";
		sleep(5); # Do nothing, and try again
	    } else {
		$lastid=$id;
		print $self->repoanalysis->create_or_update($id,\%repoanalysis)."\n";
	    }
	}
    }
    if ($self->args->{revisions} ) {
	print "Clearing revision summaries\n";

	# An empty summary
	my %repoanalysis = ( summary => {});

	my $lastid='';
	while (my $aipinfo = $self->getnextwalkr) {
	    my $id=$aipinfo->{"id"};
	    if($id eq $lastid) {
		warn "$id found - sleeping and trying again\n";
		sleep(5); # Do nothing, and try again
	    } else {
		$lastid=$id;
		print $self->repoanalysis->create_or_update($id,\%repoanalysis)."\n";
	    }
	}
    }

    if ($self->args->{metadata} ) {
	print "Clearing metadata summaries\n";

	# An empty summary
	my %repoanalysis = ( metadatasummary => {});

	my $lastid='';
	while (my $aipinfo = $self->getnextwalkmetadatar) {
	    my $id=$aipinfo->{"id"};
	    if($id eq $lastid) {
		warn "$id found - sleeping and trying again\n";
		sleep(5); # Do nothing, and try again
	    } else {
		$lastid=$id;
		print $self->repoanalysis->create_or_update($id,\%repoanalysis)."\n";
	    }
	}
    }

    if ($self->args->{nojhove} ) {
	print "Clearing revision summaries where there are no JHOVE reports\n";

	# An empty summary
	my %repoanalysis = ( summary => {});

	$self->repoanalysisf->type("application/json");
	my $res = $self->repoanalysisf->get("/".$self->repoanalysisf->{database}."/_design/ra/_view/nojhove?reduce=true&group=true&include_docs=false",{}, {deserializer => 'application/json'});

	if ($res->code == 200) {
	    if (exists $res->data->{rows}) {
		foreach my $row (@{$res->data->{rows}}) {
		    my $id=$row->{key};
		    print $self->repoanalysis->create_or_update($id,\%repoanalysis)."\n";
		}
	    } else {
		warn "_view/nojhove GET returned no rows\n";
	    }
	}
	else {
	    warn "_view/nojhove GET return code: ".$res->code."\n";
	}
    }
}


sub getnextmd5 {
    my $self = shift;

    $self->repoanalysis->type("application/json");

#    my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/ra/_view/walkmd5r?reduce=false&limit=1&include_docs=false",{}, {deserializer => 'application/json'});

#    my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/ra/_view/sipdupinother?reduce=false&limit=1&include_docs=false",{}, {deserializer => 'application/json'});
    my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/ra/_view/dupinother?reduce=false&limit=1&include_docs=false",{}, {deserializer => 'application/json'});

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

sub getnextwalkr {
    my $self = shift;

    $self->repoanalysis->type("application/json");

    my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/ra/_view/walkr?reduce=false&limit=1&include_docs=false",{}, {deserializer => 'application/json'});

    if ($res->code == 200) {
	if (exists $res->data->{rows}) {
	    return $res->data->{rows}[0];
	} else {
	    warn "_view/walkr GET returned no rows\n";
	}
    }
    else {
        warn "_view/walkr GET return code: ".$res->code."\n";
    }
}

sub getnextwalkmetadatar {
    my $self = shift;

    $self->repoanalysis->type("application/json");

    my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/ra/_view/walkmetadatar?reduce=false&limit=1&include_docs=false",{}, {deserializer => 'application/json'});

    if ($res->code == 200) {
	if (exists $res->data->{rows}) {
	    return $res->data->{rows}[0];
	} else {
	    warn "_view/walkmetadatar GET returned no rows\n";
	}
    }
    else {
        warn "_view/walkmetadatar GET return code: ".$res->code."\n";
    }
}

1;
