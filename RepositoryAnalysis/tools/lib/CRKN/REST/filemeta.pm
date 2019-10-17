package CRKN::REST::filemeta;

use strict;
use Carp;
use DateTime;
use JSON;

use Moo;
with 'Role::REST::Client';
use Types::Standard qw(HashRef Str Int Enum HasMethods);


=head1 NAME
CRKN::REST::filemeta - Subclass of Role::REST::Client used to
interact with "filemeta" CouchDB databases
=head1 SYNOPSIS
    my $fmeta = CRKN::REST::filemeta->new($args);
      where $args is a hash of arguments.  In addition to arguments
      processed by Role::REST::Client we have the following 
      $args->{database} is the Couch database name.
=cut

sub BUILD {
    my $self = shift;
    my $args = shift;

    $self->{LocalTZ} = DateTime::TimeZone->new( name => 'local' );
    $self->database($args->{database});
    $self->set_persistent_header('Accept' => 'application/json');
}

has 'database' => (
    isa => Str,
    is  => 'rw',
    default => ''
);

=head1 METHODS
=head2 update_basic
    sub update_basic ( string UID, hash updatedoc )
    updatedoc - a hash that is passed to the _update function of the
        design document to update data for the given UID.
        Meaning of fields in updatedoc is defined by that function.
  returns null, or a string representing the return from the _update
  design document.  Return values include "update", "no update", "no create".
=cut

sub update_basic {
  my ($self, $uid, $updatedoc) = @_;
  my ($res, $code, $data);

  # This encoding makes $updatedoc variables available as form data
  $self->type("application/x-www-form-urlencoded");
  $res = $self->post("/".$self->{database}."/_design/tdr/_update/basic/".$uid, $updatedoc, {deserializer => 'application/json'});

  if ($res->code != 201 && $res->code != 200) {
      warn "_update/basic/$uid POST return code: " . $res->code . "\n";
  }
  if ($res->data) {
      return $res->data->{return};
  }
}

sub get_file {
    my ($self, $file) = @_;

    $self->type("application/json");
    my $res = $self->get("/".$self->{database}."/$file",{}, {deserializer => 'application/json'});
    if ($res->code == 200) {
        return $res->data;
    }
    else {
        warn "get_aip return code: ".$res->code."\n"; 
        return;
    }
}

sub get_attachment {
    my ($self, $uid, $filename) = @_;

    my $res = $self->get("/".$self->{database}."/$uid/$filename");
    if ($res->code == 200) {
        # Return the content without deserialization
        return $res->response->content;
    }
    else {
        warn "get_attachment($uid . $filename) return code: ".$res->code."\n"; 
        return;
    }
}

1;
