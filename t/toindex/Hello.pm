package Hello;

use Moose;

sub some_method{
  print "Doing stuff\n";
}

__PACKAGE__->meta->make_immutable();

=head1 NAME

Hello - Some Hello class

=cut
