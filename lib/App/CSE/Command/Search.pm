package App::CSE::Command::Search;

use Moose;
extends qw/App::CSE::Command/;

use App::CSE::Command::Check;
use App::CSE::Command::Index;
use App::CSE::Lucy::Highlight::Highlighter;
use App::CSE::Lucy::Search::QueryPrefix;
use DateTime;
use File::Find;
use File::MimeInfo::Magic;
use Log::Log4perl;
use Lucy::Search::Hits;
use Lucy::Search::IndexSearcher;
use Lucy::Search::QueryParser;
use Path::Class::Dir;
use Term::ANSIColor; # For colored

my $LOGGER = Log::Log4perl->get_logger();

has 'query_str' => ( is => 'ro' , isa => 'Str' , lazy_build => 1);
has 'query' => ( is => 'ro', isa => 'Lucy::Search::Query' , lazy_build => 1);

has 'hits' => ( is => 'ro', isa => 'Lucy::Search::Hits', lazy_build => 1);
has 'searcher' => ( is => 'ro' , isa => 'Lucy::Search::IndexSearcher' , lazy_build => 1);
has 'highlighter' => ( is => 'ro' , isa => 'App::CSE::Lucy::Highlight::Highlighter' , lazy_build => 1);

has 'num' => ( is => 'ro' , isa => 'Int', lazy_build => 1);
has 'offset' => ( is => 'ro' , isa => 'Int' , lazy_build => 1);

sub _build_highlighter{
  my ($self) = @_;
  return App::CSE::Lucy::Highlight::Highlighter->new(
                                                     searcher => $self->searcher(),
                                                     query    => $self->highlight_query(),
                                                     field    => 'content',
                                                     excerpt_length => 100,
                                                    );
}

sub highlight_query{
  my ($self) = @_;
  my $query = $self->query();
  if( $query->isa('App::CSE::Lucy::Search::QueryPrefix') ){
    return $query->highlight_query();
  }
  return $query;
}

sub _build_searcher{
  my ($self) = @_;
  my $searcher = Lucy::Search::IndexSearcher->new( index => $self->cse->index_dir().'' );
  return $searcher;
}

sub options_specs{
  return [ 'offset=i', 'num=i' ];
}

sub _build_offset{
  my ($self) = @_;
  return $self->cse()->options->{offset} || 0;
}

sub _build_num{
  my ($self) = @_;
  my $num = $self->cse->options()->{num};
  return defined($num) ? $num : 5;
}

sub _build_hits{
  my ($self) = @_;

  $LOGGER->info("Searching for '".$self->query()->to_string()."'");

  my $hits = $self->searcher->hits( query => $self->query(),
                                    offset => $self->offset(),
                                    num_wanted => $self->num()
                                  );
  return $hits;
}

sub _build_query_str{
  my ($self) = @_;
  return  shift @{$self->cse->args()} || '';
}

sub _build_query{
  my ($self) = @_;

  if( $self->query_str() =~ /\*$/ ){
    return App::CSE::Lucy::Search::QueryPrefix->new(
                                                    field        => 'content',
                                                    query_string => $self->query_str(),
                                                   );
  }

  my $qp = Lucy::Search::QueryParser->new( schema => $self->searcher->get_schema,
                                           default_boolop => 'AND',
                                           fields => [ 'content' ] );
  $qp->set_heed_colons(1);

  return $qp->parse($self->query_str());
}

sub execute{
  my ($self) = @_;

  unless( $self->query_str() ){
    $LOGGER->warn(colored("Missing query. Do cse help" , 'red'));
    return 1;
  }

  # Check the index.
  my $check = App::CSE::Command::Check->new({ cse => $self->cse() });
  if( $check->execute() ){
    $LOGGER->info(colored("Rebuilding the index..", 'green bold'));
    my $index_cmd = App::CSE::Command::Index->new( { cse => $self->cse() });
    if( $index_cmd->execute() ){
      $LOGGER->error(colored("Building index failed", 'red'));
      return 1;
    }
  }

  my $hits = $self->hits();
  my $highlighter = $self->highlighter();

  $LOGGER->info(colored('Hits: '. $self->offset().' - '.( $self->offset() + $self->num() - 1).' of '.$hits->total_hits(), 'green bold')."\n\n");

  while ( my $hit = $hits->next ) {

    my $excerpt = $highlighter->create_excerpt($hit);

    my $star = '';
    if( my $stat = File::stat::stat( $hit->{path} ) ){
      if( $hit->{mtime} lt DateTime->from_epoch(epoch => $stat->mtime())->iso8601() ){
        $star = colored('*' , 'red bold');
      }
    }

    my $hit_str = colored($hit->{path}.'', 'magenta bold').' ('.$hit->{mime}.') ['.$hit->{mtime}.$star.']'.colored(':', 'cyan bold').q|
|.$excerpt.q|

|;

    $LOGGER->info($hit_str);
  }

  return 0;
}

__PACKAGE__->meta->make_immutable();

=head1 NAME

App::CSE::Command::Index - Indexes a directory

=cut
