package CRKN::Repository::walkmd5;

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

    my $lastid='';
    while (my $aipinfo = $self->getnext) {
	my $id=$aipinfo->{"_id"};
	if($id eq $lastid) {
	    warn "$id found - sleeping and trying again\n";
	    sleep(5); # Do nothing, and try again
	} else {
	    $lastid=$id;
	    $self->process($id,$aipinfo)
	}
    }
}


sub getnext {
    my $self = shift;

    $self->repoanalysis->type("application/json");
    my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/ra/_view/walkmd5q?reduce=false&limit=1&include_docs=true",{}, {deserializer => 'application/json'});
    if ($res->code == 200) {
	if (exists $res->data->{rows}) {
	    return $res->data->{rows}[0]{doc};
	} else {
	    warn "_view/walkmd5q GET returned no rows\n"; 
	}
    }
    else {
        warn "_view/walkmd5q GET return code: ".$res->code."\n"; 
    }
}

sub process {
    my ($self,$aip,$aipinfo)= @_;

    print "Processing $aip\n";
    my $manifestdate = $aipinfo->{summary}->{manifestdate};
    
    # Hash of information to be posted to CouchDB
    my %repoanalysis = ( md5summary => {
        manifestdate => $manifestdate,
	globaluniq => [],
	duplicates => {}
                         }
        );

    if (exists $aipinfo->{revfiles}) {
	foreach my $file (keys %{$aipinfo->{revfiles}}) {
	    my ($md5,$size) = @{$aipinfo->{revfiles}->{$file}};

	    if (exists $repoanalysis{md5summary}{duplicates}{$md5} &&
		exists $repoanalysis{md5summary}{duplicates}{$md5}{$size}) {
		# An existing file already caused this lookup
		next;
	    }

	    my $res = $self->repoanalysis->get("/".$self->repoanalysis->{database}."/_design/filemap/_view/md5sizesip?reduce=false&key=\[\"$md5\",\"$size\"\]",{}, {deserializer => 'application/json'});
	    if ($res->code == 200) {
		if (scalar @{$res->data->{rows}}) {

		    # We only want the ones not in our SIP
		    my $inmysip=0;
		    foreach my $found (@{$res->data->{rows}}) {
			if ($found->{'id'} eq $aip) {
			    $inmysip=1;
			    last;
			}
		    }
		    if (! $inmysip ) {
			foreach my $found (@{$res->data->{rows}}) {
			    if (! exists $repoanalysis{md5summary}{duplicates}{$md5}{$size}) {
				$repoanalysis{md5summary}{duplicates}{$md5}{$size} = [];
			    } 
			    push $repoanalysis{md5summary}{duplicates}{$md5}{$size},
				$found->{'id'}."/".$found->{'value'};
			    print "$aip has external duplicates\n";
			}
		    }
		}
		else {
		    push $repoanalysis{md5summary}{globaluniq},
			$file;
		} 
	    }
	    else {
		warn "_view/md5sizesip GET return code: ".$res->code."\n"; 
	    }
	}
    }
    my $res = $self->repoanalysis->create_or_update($aip,\%repoanalysis);
}


1;
