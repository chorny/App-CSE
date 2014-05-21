package App::CSE::Command::Index;

use Moose;
extends qw/App::CSE::Command/;

use DateTime;

use File::Find;
use File::Path;
use File::stat;
use File::MimeInfo::Magic;

use Path::Class::Dir;
use Lucy::Plan::Schema;

use String::CamelCase;
use Term::ANSIColor;

## Note that using File::Slurp is done at the CSE level,
## avoiding undefined warnings,

use Log::Log4perl;
my $LOGGER = Log::Log4perl->get_logger();

my $BLACK_LIST = {
                  'application/x-trash' => 1
                 };


has 'dir_index' => ( is => 'ro' , isa => 'Path::Class::Dir' , lazy_build => 1 );

sub _build_dir_index{
  my ($self) = @_;

  if( my $to_index = $self->cse->args()->[0] ){
    return Path::Class::Dir->new($self->cse->args()->[0])->absolute();
  }

  ## Default to the current directory
  return Path::Class::Dir->new();
}

sub execute{
  my ($self) = @_;

  ## We will index as a new dir.
  my $index_dir = $self->cse()->index_dir().'-new';


  my $schema = Lucy::Plan::Schema->new();
  my $sstring_type = Lucy::Plan::StringType->new( sortable => 1 );

  my $case_folder = Lucy::Analysis::CaseFolder->new();
  my $tokenizer = Lucy::Analysis::StandardTokenizer->new();

  my $ft_anal = Lucy::Analysis::PolyAnalyzer->new(analyzers => [ $case_folder, $tokenizer ]);
  my $ft_type = Lucy::Plan::FullTextType->new(analyzer => $ft_anal,
                                              highlightable => 1
                                             );


  $schema->spec_field( name => 'path' , type => $sstring_type );
  $schema->spec_field( name => 'mtime' , type => $sstring_type );
  $schema->spec_field( name => 'mime' , type => $sstring_type );
  $schema->spec_field( name => 'content' , type => $ft_type );


  ## Ok Schema has been built
  $LOGGER->info("Building index ".$index_dir);
  my $indexer = Lucy::Index::Indexer->new(schema => $schema,
                                          index => $index_dir,
                                          create => 1,
                                         );

  $LOGGER->info("Indexing files from ".$self->dir_index());


  my $wanted = sub{
    my $file_name = $File::Find::name;

    if( $file_name =~ /\/\.[^\/]+$/ ){
      $LOGGER->info("File $file_name is hidden. Skipping");
      $File::Find::prune = 1;
      return;
    }

    my $content;

    unless( -r $file_name ){
      $LOGGER->warn("Cannot read $file_name. Skipping");
      return;
    }


    my $mime_type = File::MimeInfo::Magic::mimetype($file_name.'') || 'application/octect-stream';
    my $half_camel = $mime_type; $half_camel =~ s/\W/_/g;
    my $file_class_name = 'App::CSE::File::'.String::CamelCase::camelize($half_camel);
    my $file_class = eval{ Class::Load::load_class($file_class_name); };
    unless( $file_class ){
      warn "WHOT ABOUT $file_class_name for ".$mime_type." ?";
      $LOGGER->debug("No class for mimetype $mime_type");
      return;
    }

    unless( -d $file_name ){
      ## Slurp the content. Assume utf8 as we are being modern.
      $content = File::Slurp::read_file($file_name, binmode => ':utf8');
    }

    if( $BLACK_LIST->{$mime_type} ){
      return;
    }

    my $stat = File::stat::stat($file_name);
    my $mtime = DateTime->from_epoch( epoch =>  $stat->mtime());

    $LOGGER->debug("Indexing $file_name as $mime_type");
    $indexer->add_doc({
                       path => $file_name,
                       mime => $mime_type,
                       mtime => $mtime->iso8601(),
                       $content ? ( content => $content ) : ()
                      });
  };
  my $dir_index = $self->dir_index();

  File::Find::find({ wanted => $wanted,
                     no_chdir => 1,
                     follow => 0,
                   }, $dir_index );

  $indexer->commit();

  rmtree $self->cse->index_dir()->stringify();
  rename $index_dir , $self->cse->index_dir()->stringify();

  $LOGGER->info(colored("Index is ".$self->cse()->index_dir()->stringify(), 'green bold'));

  return 0;
}

__PACKAGE__->meta->make_immutable();

=head1 NAME

App::CSE::Command::Index - Indexes a directory

=cut
