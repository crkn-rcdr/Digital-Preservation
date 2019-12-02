package CRKN::Repository::walkmetadata::Process;

use strict;
use Data::Dumper;
use XML::LibXML;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Basename;
use File::Temp qw/ tempfile tempdir /;

sub new {
    my($class, $args) = @_;
    my $self = bless {}, $class;

    if (ref($args) ne "HASH") {
        die "Argument to CRKN::Repository::walkmetadata::Process->new() not a hash\n";
    };
    $self->{args} = $args;

    if (!$self->log) {
        die "Log::Log4perl object parameter is mandatory\n";
    }
    if (!$self->worker) {
        die "worker object parameter is mandatory\n";
    }
    if (!$self->swift) {
        die "swift object parameter is mandatory\n";
    }
    if (!$self->swiftcontainer) {
        die "swiftcontainer parameter is mandatory\n";
    }
    if (!$self->repoanalysis) {
        die "repoanalysis object parameter is mandatory\n";
    }
    if (!$self->aip) {
        die "Parameter 'aip' is mandatory\n";
    }
    $self->{updatedoc} = {};

    return $self;
}

sub args {
    my $self = shift;
    return $self->{args};
}
sub cmdargs {
    my $self = shift;
    return $self->args->{args};
}
sub aip {
    my $self = shift;
    return $self->args->{aip};
}
sub worker {
    my $self = shift;
    return $self->args->{worker};
}
sub log {
    my $self = shift;
    return $self->args->{log};
}
sub swift {
    my $self = shift;
    return $self->args->{swift};
}
sub swiftcontainer {
    my $self = shift;
    return $self->args->{swiftcontainer};
}
sub repoanalysis {
    my $self = shift;
    return $self->args->{repoanalysis};
}
sub repodoc {
    my $self = shift;
    return $self->{repodoc};
}

sub process {
    my ($self)= @_;

    my $aip=$self->aip;

    my $tempdir= File::Temp->newdir();

    $self->loadRepoDoc();
    $self->worker->setResult("manifestdate",$self->repodoc->{reposManifestDate});

    my @metspath;
    foreach my $mets (@{$self->repodoc->{METS}}) {
	push @metspath, $mets->{path};
    }
    @metspath = sort @metspath;

    my $changelogfile = $self->aip."/data/changelog.txt";
    my $r = $self->swift->object_get($self->swiftcontainer,$changelogfile);
    if ($r->code != 200) {
	die "object_get container: '".$self->swiftcontainer."' , object: '$changelogfile'  returned ". $r->code . " - " . $r->message. "\n";
    }
    my @changelog=split /\n/, $r->content;

    my @changes;
    CHANGELOGLINE: foreach my $logline (@changelog) {
	if ($logline =~ /^(\d\d\d\d\-\d\d-\d\dT\d\d:\d\d:\d\dZ)\s+(.*)$/) {
	    my %change;
	    $change{'date'}=$1;
	    my $line=$2;
	    for ($line) {
		if (/^Created new AIP$/) {
		    $change{'operation'}='new';
		}
		elsif (/^Built CMR record$/) {
		    next CHANGELOGLINE;
		}
		elsif (/^Created new SIP in existing AIP$/) {
		    $change{'operation'}='updatesip';
		}
		elsif (/^Updated SIP; old SIP stored as revision\s+(\w+)\s*$/) {
		    $change{'operation'}='updatesip';
		    $change{'revision'}=$1;
		}
		elsif (/^Updated metadata record; old record stored in revision\s+(\S+)\s*$/) {
		    $change{'operation'}='mdupdate';
		    $change{'revision'}=$1;
		}
		elsif (/^Updated metadata record. Reason:\s+(.+)\s*$/) {
		    $change{'operation'}='mdupdate';
		    $change{'reason'}=$1;
		}
		elsif (/^Deleted SIP and all revisions from archive. Reason:\s+(.+)\s*$/) {
		    $change{'operation'}='delsip';
		    $change{'reason'}=$1;
		}
		else {
		    if (scalar @changes) {
			my $lastchange = $changes[$#changes];
			if (($lastchange->{operation} eq 'mdupdate') ||
			    ($lastchange->{operation} eq 'updatesip') ||
			    ($lastchange->{operation} eq 'new')) {
			    $lastchange->{changelog}=$line;
			    $lastchange->{changelogdate}=$lastchange->{changelog};
			    next CHANGELOGLINE;
			}
		    }
		    $change{'line'}=$line;
		}
	    }
	    push @changes, \%change;
	} else {
	    warn "Log line didn't start with date: $logline\n";
	}
    }


    if (scalar(@metspath) == scalar(@changes)) {
	for (0..$#metspath) {
	    $changes[$_]{'metspath'}=$metspath[$_];
	}
    } else {
	warn "Number of changelog entries didn't match number of METS records\n";
    }
    $self->worker->setResult("changes",\@changes);
}

# Load document from 'repoanalysis' for this AIP
sub loadRepoDoc {
    my $self = shift;

    $self->repoanalysis->type("application/json");
    
    my $res = $self->repoanalysis->get("/".$self->repoanalysis->database."/".$self->aip,{}, {deserializer => 'application/json'});
    if ($res->code == 200) {
	$self->{repodoc}=$res->data;
    } else {
        die "Can't get repoanalysis document. GET return code: ".$res->code."\n";
    }
}


1;
