#! perl -T
use Test::More;

use App::CSE;


use File::Temp;
use Path::Class::Dir;

{
  #local @ARGV = ( 'help' );

  my $idx_dir = File::Temp->newdir( CLEANUP => 1 );
  my $content_dir = Path::Class::Dir->new('t/toindex');

  local @ARGV = ( 'index' , '--idx='.$idx_dir , $content_dir.'' );

  my $cse = App::CSE->new();

  is_deeply( $cse->args() , [ $content_dir ], "Ok good args");

  ok( $cse->index_dir() , "Ok index dir");
  is( $cse->index_dir()->absolute() , $idx_dir.'' , "Ok good option taken into account");

  ok( $cse->command()->isa('App::CSE::Command::Index') , "Ok good command instance");
  is( $cse->command()->dir_index() , $content_dir->absolute() , "Ok good index dir");
  is( $cse->main() , 0 ,  "Ok can execute the magic command just fine");
}

ok(1);
done_testing();
