package App::CSE::Command::Index;

use Moose;
extends qw/App::CSE::Command/;

use File::Find;
use Path::Class::Dir;
use Lucy::Plan::Schema;

use Log::Log4perl;
my $LOGGER = Log::Log4perl->get_logger();

has 'dir_index' => ( is => 'ro' , isa => 'Path::Class::Dir' , lazy_build => 1 );

sub _build_dir_index{
  my ($self) = @_;
  my $dir_index = Path::Class::Dir->new($self->cse->args()->[0] || '')->absolute();
  return $dir_index;
}

sub execute{
  my ($self) = @_;

  my $index_dir = $self->cse()->index_dir();

  my $schema = Lucy::Plan::Schema->new();
  my $sstring_type = Lucy::Plan::StringType->new( sortable => 1 );

  $schema->spec_field( name => 'path' , type => $sstring_type );
  $schema->spec_field( name => 'mime' , type => $sstring_type );

  ## Ok Schema has been built
  $LOGGER->info("Building index ".$index_dir);
  my $indexer = Lucy::Index::Indexer->new(schema => $schema,
                                          index => $index_dir,
                                          create => 1,
                                         );

  $LOGGER->info("Indexing files from ".$self->dir_index());


  my $wanted = sub{
    my $file_name = $File::Find::name;
    $LOGGER->info("Indexing $file_name");
    $indexer->add_doc({
                       path => $file_name,
                       mime => 'text/plain'
                      });
  };

  my $dir_index = $self->dir_index();
  ( $dir_index ) = ( $dir_index =~ /(.+)/ );

  File::Find::find({ wanted => $wanted,
                     no_chdir => 1
                   }, $dir_index );


  $indexer->commit();

  return 0;
}

__PACKAGE__->meta->make_immutable();

=head1 NAME

App::CSE::Command::Help - Help about the cse utility

=cut
