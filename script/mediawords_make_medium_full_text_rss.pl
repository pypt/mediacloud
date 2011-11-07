#!/usr/bin/perl -w

# set the given medium to have full_text_rss == true.  reprocess all of the
# stories for the given medium to use the story->{ description } for the 
# story_sentence_words entries. 

# note that this script does not reprocess any of the aggregation --
# that has to be done separately.

use strict;

use encoding "utf8";

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::StoryVectors;

sub main
{
    my ( $medium_id ) = @ARGV;
    
    die ( "usage: $0 < medium id >" ) if ( !$medium_id );
    
    my $db = MediaWords::DB::connect_to_db;
    $db->dbh->{ AutoCommit } = 0;
    
    my $medium = $db->find_by_id( 'media', $medium_id );
    
    $medium->{ full_text_rss } = 1;
    $db->update_by_id( 'media', $medium_id, { full_text_rss => 1 } );
    
    my $stories = $db->query( "select * from stories where media_id = ? and full_text_rss = 'f'", $medium_id )->hashes;
    
    my $i = 0;
    for my $story ( @{ $stories } )
    {
        $story->{ full_text_rss } = 1;
        $db->update_by_id( 'stories', $story->{ stories_id }, { full_text_rss => 1 } );
        
        MediaWords::StoryVectors::update_story_sentence_words( $db, $story );
        
        print STDERR ++$i . " / " . scalar( @{ $stories } ) . "\n";
        
        $db->commit if ( !( $i % 100 ) );
    }
    
    $db->commit;
}

main();
