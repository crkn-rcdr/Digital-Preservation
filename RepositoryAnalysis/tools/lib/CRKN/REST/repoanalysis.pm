package CRKN::REST::repoanalysis;

use strict;
use Carp;
use Data::Dumper;
use DateTime;
use JSON;

use Moo;
with 'Role::REST::Client';
use Types::Standard qw(HashRef Str Int Enum HasMethods);

sub BUILD {
    my $self = shift;
    my $args = shift;

    $self->{LocalTZ} = DateTime::TimeZone->new( name => 'local' );
    $self->{conf} = $args->{conf}; 
    $self->{database} = $args->{database};
    $self->set_persistent_header('Accept' => 'application/json');
}

# Simple accessors for now -- Do I want to Moo?
sub database {
    my $self = shift;
    return $self->{database};
}

sub create_or_update {
  my ($self, $uid, $body) = @_;
  my ($res, $code, $data);

  # This encoding makes $updatedoc variables available as form data
  $self->type("application/json");
  $res = $self->post("/".$self->{database}."/_design/ra/_update/create_or_update/".$uid, $body, {});

  if ($res->code != 201 && $res->code != 200) {
      warn "_update/create_or_update/$uid POST return code: " . $res->code . "\n";
  }
  return $res->data;
}

1;
