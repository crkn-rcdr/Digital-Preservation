package CRKN::Repository::walkjhove::Process;

use strict;
use Data::Dumper;
use XML::LibXML;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use Switch;


sub new {
    my($class, $args) = @_;
    my $self = bless {}, $class;

    if (ref($args) ne "HASH") {
        die "Argument to CRKN::Repository::walkjhove::Process->new() not a hash\n";
    };
    $self->{args} = $args;

    if (!$self->log) {
        die "Log::Log4perl object parameter is mandatory\n";
    }
    if (!$self->swift) {
        die "swift object parameter is mandatory\n";
    }
    if (!$self->worker) {
        die "worker object parameter is mandatory\n";
    }
    if (!$self->swiftcontainer) {
        die "swiftcontainer parameter is mandatory\n";
    }
    if (!$self->swiftrepoanalysis) {
        die "swiftrepoanalysis parameter is mandatory\n";
    }

    if (!$self->repoanalysis) {
        die "repoanalysis object parameter is mandatory\n";
    }
    if (!$self->repoanalysisf) {
        die "repoanalysisf object parameter is mandatory\n";
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
sub swiftrepoanalysis {
    my $self = shift;
    return $self->args->{swiftrepoanalysis};
}
sub repoanalysis {
    my $self = shift;
    return $self->args->{repoanalysis};
}
sub repoanalysisf {
    my $self = shift;
    return $self->args->{repoanalysisf};
}
sub repodoc {
    my $self = shift;
    return $self->{repodoc};
}
sub raf {
    my $self = shift;
    return $self->{raf};
}


sub process {
    my ($self)= @_;

    my $aip=$self->aip;

    my $tempdir= File::Temp->newdir();

    $self->loadRepoDoc();
    $self->worker->setResult("manifestdate",$self->repodoc->{reposManifestDate});
    # Load file data for this AIP
    $self->load_repoanalysisf();

    my $zipfile=$aip.".zip";
    my $tempzipfile = $tempdir."/".$zipfile;

    # Managing a ZIP of all reports
    my $zip = Archive::Zip->new();
    my $zipmodified;
    
    if (!($self->cmdargs->{regenerate})) {
	# Try to load existing ZIP if we aren't regenerating JHOVE reports
	my $r = $self->swift->object_get($self->swiftrepoanalysis,"$zipfile");
	if ($r->code == 200) {
	    open(my $fh, '>:raw', $tempzipfile)
		or die "Could not open file $tempzipfile: $!";
	    print $fh $r->content;
	    close $fh;
	    unless ( $zip->read( $tempzipfile ) == AZ_OK ) {
		die "Error with ZIP reading $tempzipfile\n";
	    }
	} elsif ($r->code != 404) {
	    die "object_get container: '".$self->swiftrepoanalysis."' , object: '/$zipfile'  returned ". $r->code . " - " . $r->message. "\n";
	}
    }

    my @zipmembers = $zip->members();

    # Some statistics
    my $reportfound=0;
    my $reportnotfound=0;
    
    foreach my $sipfile (keys %{$self->repodoc->{sipfiles}}) {
	my $sipfilebase = basename($sipfile);

	my $fileinfo=$self->raf->{$aip."/".$sipfile};
	die "SIP file list mismatch for $sipfile\n" if (!$fileinfo);


	if ($self->cmdargs->{regenerate}) {
	    # Clear references to old reports if we are regenerating
	    delete $fileinfo->{jhove_container};
	    delete $fileinfo->{jhove_name};
	}

	my $jhovetxt;
	my $xmlfilename="$sipfilebase.xml";

	my $zipfile;
	# memberNamed noisy when file name exist...
	foreach my $thisfile (@zipmembers) {
	    if ($thisfile->fileName() eq $xmlfilename) {
		$zipfile = $thisfile;
		last;
	    }
	}
	if ($zipfile) {
	    $jhovetxt = $zip->contents($zipfile);
	    $self->set_fmetadata($fileinfo,'jhove_container','zip');
	} elsif ($fileinfo->{jhove_container} && $fileinfo->{jhove_name}) {
	    my $pathname=$fileinfo->{jhove_container}." / ". $fileinfo->{jhove_name};
	    my $r=$self->swift->object_get($fileinfo->{jhove_container},
				   $fileinfo->{jhove_name});
	    if ($r->code != 200) {
		die "Accessing $pathname returned code: " . $r->code."\n";
	    }
	    $jhovetxt = $r->content;
	    $zip->addString($jhovetxt,$xmlfilename);
	    $zipmodified=1;
	} else {
	    $jhovetxt=$self->generate_jhove($sipfile,$tempdir);
	    if ($jhovetxt) {
		$zip->addString($jhovetxt,$xmlfilename);
		$self->set_fmetadata($fileinfo,'jhove_container','generate');
		$zipmodified=1;
	    }
	}
	my $jhove;
	if ($jhovetxt) {
	    $jhove=eval { XML::LibXML->new->parse_string($jhovetxt) };
	    if ($@) {
		die "XML::LibXM::parse_string on $sipfile: $@\n";
	    }
	}
	if ($jhove) {
	    $reportfound++;
	    $self->processjhove($fileinfo,$jhove);
	} else {
	    $reportnotfound++;
	}
    }

    # Save file data for this AIP
    $self->save_repoanalysisf();

    $self->worker->setResult("reportfound",$reportfound);
    $self->worker->setResult("reportnotfound",$reportnotfound);
    if ($zipmodified) {
	my $zipname = "$tempdir/$zipfile";
	unless ( $zip->overwriteAs($zipname) == AZ_OK ) {
	    die "Error writing $zipname\n";
	}
	open(my $fh, '<:raw', $zipname);
	$self->swift->object_put($self->swiftrepoanalysis, $zipfile, $fh);
	close $fh;
	$self->log->info("Stored ".$self->swiftrepoanalysis." : $zipfile");
    }
}

sub processjhove {
    my ($self,$fileinfo,$jhove)= @_;

    my $xpc = XML::LibXML::XPathContext->new($jhove);
    $xpc->registerNs('jhove', "http://hul.harvard.edu/ois/xml/ns/jhove");
    my $status=$xpc->findvalue("descendant::jhove:status",$jhove);
    if ($status) {
	$self->set_fmetadata($fileinfo,'status',$status);
    } else {
	$xpc->registerNs('jhove', "http://schema.openpreservation.org/ois/xml/ns/jhove");
	my $status=$xpc->findvalue("descendant::jhove:status",$jhove);
	if ($status) {
	    $self->set_fmetadata($fileinfo,'status',$status);
	} else {
	    die "Can't determine namespace for ".$fileinfo->{'_id'}."\n";
	}
    }
    $xpc->registerNs('mix', "http://www.loc.gov/mix/v20");

    
    my $jhoverelease=$xpc->findvalue('/*/@release',$jhove);
    $self->set_fmetadata($fileinfo,'jhoverelease',$jhoverelease) if ($jhoverelease);


    my $size=$xpc->findvalue("descendant::jhove:size",$jhove);
    $self->set_fmetadata($fileinfo,'Size',$size) if ($size > 0);

    my $md5=$xpc->findvalue('descendant::jhove:checksum[@type="MD5"]',$jhove);
    $self->set_fmetadata($fileinfo,'MD5',$md5) if ($md5);


    my $mimetype=$xpc->findvalue("descendant::jhove:mimeType",$jhove);
    if ($mimetype) {
	$self->set_fmetadata($fileinfo,'mimetype',$mimetype);
	if (index($mimetype,"image/")==0) {
	    my @mix=$xpc->findnodes("descendant::mix:mix",$jhove);
	    if (scalar(@mix)>0) {
		$self->set_fmetadata($fileinfo,'Width', 
				     $xpc->findvalue("descendant::mix:imageWidth",$mix[0]));
		$self->set_fmetadata($fileinfo,'Height',
				     $xpc->findvalue("descendant::mix:imageHeight",$mix[0]));
	    }
	}
    }

    # Updating Filemeta database with potentially new information
    my $format=$xpc->findvalue("descendant::jhove:format",$jhove);
    $self->set_fmetadata($fileinfo,'format',$format) if ($format);

    my $version=$xpc->findvalue("descendant::jhove:version",$jhove);
    $self->set_fmetadata($fileinfo,'version',$version) if ($version);

    my $date=$xpc->findvalue("descendant::jhove:date",$jhove);
    $self->set_fmetadata($fileinfo,'date',$date) if ($date);

    my @errormsgs;
    foreach my $errormsg ($xpc->findnodes('descendant::jhove:message[@severity="error"]',$jhove)) {
	my $txtmsg=$errormsg->to_literal;
	if (! ($txtmsg =~ /^\d+$/)) {
	    push @errormsgs,$txtmsg;
	}
    }
    if (@errormsgs) {
	$self->set_fmetadata($fileinfo,'errormsg',join(',',@errormsgs));
    }
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

sub load_repoanalysisf {
    my $self=shift;

    $self->{raf}={};

    $self->repoanalysisf->type("application/json");
    my $res = $self->repoanalysisf->get("/".$self->repoanalysisf->database."/_all_docs",{
	include_docs => 'true',
	startkey => '"'.$self->aip.'/"',
	endkey => '"'.$self->aip.'/'.chr(0xfff0).'"'
					}, {deserializer => 'application/json'});
    if ($res->code == 200) {
	foreach my $row (@{$res->data->{rows}}) {
	    $self->{raf}->{$row->{key}}=$row->{doc};
	}
    }
    else {
	die "load_repoanalysisf return code: ".$res->code."\n";
    }
}

sub save_repoanalysisf {
    my $self=shift;

    if ($self->raf) {
        my @files=sort keys %{$self->raf};
        my @update;

        foreach my $file (@files) {
            my $thisfile=$self->raf->{$file};
            if ($thisfile->{changed}) {
                delete $thisfile->{changed};
                push @update, $thisfile;
            }
        }

        if (@update) {
            my $res = $self->repoanalysisf->post("/".$self->repoanalysisf->database."/_bulk_docs",
						 {docs => \@update },
						 {deserializer => 'application/json'});
            if ($res->code != 201) {
                die "save_repoanalysisf _bulk_docs returned: ".$res->code."\n";
            }
        }
    }
}

sub set_fmetadata {
    my ($self,$fmetadata,$key,$value) = @_;

    if (! exists $fmetadata->{$key} ||
        $fmetadata->{$key} ne $value) {
        $fmetadata->{$key}=$value;
        $fmetadata->{'changed'}=1;
    }
}

sub delete_fmetadata {
    my ($self,$fmetadata,$key) = @_;

    if (exists $fmetadata->{$key}) {
        delete $fmetadata->{$key};
        $fmetadata->{'changed'}=1;
    }
}




sub generate_jhove {
    my ($self,$sipfile,$tempdir) = @_;

    my $sipfilebase = basename($sipfile);
    my $sipfiletemp = $tempdir."/".$sipfilebase;
    my $sipfilereport = $sipfiletemp.'.xml';
    my $sipfileget = $self->aip."/".$sipfile;

    my @fileparts=split(/\./,$sipfile);
    my $ext = pop @fileparts;

    my $r = $self->swift->object_get($self->swiftcontainer,$sipfileget);
    if ($r->code == 200) {
        open(my $fh, '>:raw', $sipfiletemp)
            or die "Could not open file $sipfiletemp: $!";
        print $fh $r->content;
        close $fh;
    } else {
        die "object_get container: '".$self->swiftcontainer."' , object: '$sipfileget'  returned ". $r->code . " - " . $r->message. "\n";
    }
    
    my $module;
    switch ($ext) {
        case 'jpg' {$module='JPEG-hul';}
        case 'jp2' {$module='JPEG2000-hul';}
        case 'tif' {$module='TIFF-hul';}
        case 'pdf' {$module='PDF-hul';}
        case 'xml' {$module='XML-hul';}
        else {die "unknown extension $ext for $sipfile\n";}
    }
    my @command=("/opt/jhove/jhove", # TODO: in config file?
                 "-k","-m",$module,"-h","xml","-o",$sipfilereport,$sipfiletemp);

    system(@command) == 0 
	or die "shell command @command failed: $?";

    open(my $fh, '<:raw', $sipfilereport);
    my $jhovetxt = do { local $/; <$fh> };
    close $fh;

    return $jhovetxt;
}

1;
