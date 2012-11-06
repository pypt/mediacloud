#!/usr/bin/env perl

# search through a the stories associated with a controversy and tag
# the stories matching any of a set of regexes with a tag for each regex

# usage: mediawords_search_tagged_stories.pl <controversy name>

# takes an input file on stdin with one regex per line

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Util::Tags;

sub get_patterns_from_input
{
    my ( $db, $controversy ) = @_;

    my $patterns = [];

    my $tag_set_name = "controversy_$controversy->{ name }";
    $tag_set_name =~ s/:/-/g;

    while ( my $line = <STDIN> )
    {
        chomp( $line );

        my $regex = $line;

        my $tag_name = $regex;
        $tag_name =~ s/[^\w]/_/g;

        next unless ( $regex && ( $regex =~ /\S/ ) );

        my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "${ tag_set_name }:${ tag_name }" );

        push( @{ $patterns }, { tag => $tag, regex => $regex } );
    }

    return $patterns;
}

# construct the regex, run it against the db, and return a list of which patterns each
# story matches
sub search_and_tag_stories
{
    my ( $db, $controversy, $patterns ) = @_;

    my $match_columns = [];
    for ( my $i = 0 ; $i < @{ $patterns } ; $i++ )
    {
        my $pattern = $patterns->[ $i ];

        # gotta do this weird sub-sub-query to get the planner not to seq scan story_sentences
        my $clause =
          "( s.url ~* '$pattern->{ regex }' or s.title ~* '$pattern->{ regex }' or " .
          "  s.description ~* '$pattern->{ regex }' or " . "  exists ( select 1 " .
          "             from ( select * from story_sentences ssa_$i where s.stories_id = ssa_$i.stories_id ) as ss_$i " .
          "             where ss_$i.sentence ~* '$pattern->{ regex }' ) ) match_$i";
        push( @{ $match_columns }, $clause );
    }

    my $match_columns_list = join( ", ", @{ $match_columns } );

    my $query =
      "select s.stories_id, s.title, $match_columns_list from stories s, controversy_stories cs " .
      "  where s.stories_id = cs.stories_id and cs.controversies_id = ?";
    print STDERR "query: $query\n";
    my $story_matches = $db->query( $query, $controversy->{ controversies_id } )->hashes;

    print @{ $story_matches } . " stories\n";
    for ( my $i = 0 ; $i < @{ $patterns } ; $i++ )
    {
        print "$patterns->[ $i ]->{ tag }->{ tag }: " . scalar( grep { $_->{ "match_$i" } } @{ $story_matches } ) . "\n";
    }

    $db->{ dbh }->{ AutoCommit } = 0;
    my $c = 0;
    for my $story_match ( @{ $story_matches } )
    {

        # print STDERR "update story $story_match->{ title }\n";
        for ( my $i = 0 ; $i < @{ $patterns } ; $i++ )
        {
            my $pattern = $patterns->[ $i ];
            $db->query(
                "delete from stories_tags_map where stories_id = ? and tags_id = ?",
                $story_match->{ stories_id },
                $pattern->{ tag }->{ tags_id }
            );
            if ( $story_match->{ "match_$i" } )
            {

                # print STDERR "$pattern->{ tag }->{ tag }\n";
                $db->query(
                    "insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )",
                    $story_match->{ stories_id },
                    $pattern->{ tag }->{ tags_id }
                );
            }
        }

        $db->commit if ( !( $c % 100 ) );
    }
}

sub main
{
    my ( $controversy_name ) = @ARGV;

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    die( "usage: $0 <controversy name>" ) if ( !$controversy_name );

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->query( "select * from controversies where name = ?", $controversy_name )->hash
      || die( "Unable to find controversy '$controversy_name'" );

    my $patterns = get_patterns_from_input( $db, $controversy );

    die( "no patterns found in input" ) if ( !@{ $patterns } );

    search_and_tag_stories( $db, $controversy, $patterns );
}

main();
