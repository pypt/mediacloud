#!/usr/bin/env perl

# dedup topic spidered media

# the basic method of this script is to:
# * group media sources by identical domains (eg. www.nytimes.com, nytimes.com, and articles.nytimes.com);
# * for each domain group, aggressively try to identify cases for which we should just automatically
#   merge all media within the given group (as in the above example);
# * otherwise, prompt the user to choose whether and how to dedup the media within the domain.
#
# currently this script just marks media as dups by setting the dup_media_id field in the media source.
# in the future, we are moving to actually removing the duplicate media source.

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;
use URI;

use MediaWords::DB;
use MediaWords::DBI::Media;
use MediaWords::Util::Tags;
use MediaWords::Util::URL;

sub mark_medium_as_dup
{
    my ( $db, $source_medium, $target_medium ) = @_;

    return if ( $source_medium->{ media_id } == $target_medium->{ media_id } );

    if ( $target_medium->{ dup_media_id } )
    {
        print( "target medium has dup_media_id set. skipping ...\n" );
        return;
    }

    if ( $target_medium->{ foreign_rss_links } )
    {
        print( "target medium has foreign_rss_links = true. skipping ...\n" );
        return;
    }

    print "$source_medium->{ name } -> $target_medium->{ name }\n";

    $source_medium->{ dup_media_id } = $target_medium->{ media_id };
    $source_medium->{ hide }         = 1;

    $db->query( <<END, $target_medium->{ media_id }, $source_medium->{ media_id } );
update media set dup_media_id = ? where media_id = ?
END
}

# mark the medium as not dup
sub mark_medium_is_not_dup
{
    my ( $db, $medium ) = @_;

    $medium->{ is_not_dup } = 1;

    $db->query( "update media set is_not_dup = true where media_id = ?", $medium->{ media_id } );
}

# if one medium has the root domain as the url, mark everything as the dup of that medium
sub mark_dups_of_root_domain
{
    my ( $db, $domain, $media ) = @_;

    return if ( @{ $media } > 5 );

    for my $a ( @{ $media } )
    {
        if ( !$a->{ dup_media_id } && ( $a->{ url_c } =~ m~^https?://(www\.)?$domain/?~ ) )
        {
            for my $b ( @{ $media } )
            {
                next if ( $a->{ media_id } == $b->{ media_id } || $b->{ dup_media_id } );

                mark_medium_as_dup( $db, $b, $a );
            }
        }
    }
}

# if one medium already has other media pointing to it as the dup, use that medium
# as the dup for all other media in the domain
sub mark_dups_of_existing_dup
{
    my ( $db, $domain, $media ) = @_;

    return if ( @{ $media } > 5 );

    for my $m ( @{ $media } )
    {
        if ( $m->{ dup_media_id } )
        {
            my $a = $db->find_by_id( 'media', $m->{ dup_media_id } );

            for my $b ( @{ $media } )
            {
                next if ( $a->{ media_id } == $b->{ media_id } || $b->{ dup_media_id } );

                mark_medium_as_dup( $db, $b, $a );
            }
        }
    }
}

# check for media that are canonical url duplicates and mark one of each pair as a duplicate
sub mark_canonical_url_duplicates
{
    my ( $db, $domain, $media ) = @_;

    map { $_->{ url_c } = MediaWords::Util::URL::normalize_url_lossy( $_->{ url } ) } @{ $media };

    $media = [ sort { length( $a->{ url } ) <=> length( $b->{ url } ) } @{ $media } ];

    for my $a ( @{ $media } )
    {
        next if ( $a->{ dup_media_id } );

        for my $b ( @{ $media } )
        {
            next if ( $a->{ media_id } == $b->{ media_id } || $b->{ dup_media_id } );

            if ( $a->{ url_c } eq $b->{ url_c } )
            {
                mark_medium_as_dup( $db, $b, $a );
            }
        }
    }
}

# prompt user for media merge command and return the command
sub prompt_for_dup_media
{
    my ( $db, $domain, $media ) = @_;

    my $original_media = [ grep { !$_->{ is_spidered } } @{ $media } ];
    my $spidered_media = [ grep { $_->{ is_spidered } } @{ $media } ];

    my $ordered_media = [ @{ $original_media }, @{ $spidered_media } ];

    for my $medium ( @{ $media } )
    {
        $medium->{ not_dup_label }     = $medium->{ is_not_dup }        ? 'NOT_DUP '     : '';
        $medium->{ spidered_label }    = $medium->{ is_spidered }       ? 'SPIDERED '    : '';
        $medium->{ foreign_rss_links } = $medium->{ foreign_rss_links } ? 'FOREIGN_RSS ' : '';
    }

    while ( 1 )
    {
        print "\nDOMAIN: $domain\n";
        for ( my $i = 0 ; $i < @{ $ordered_media } ; $i++ )
        {
            my $m = $ordered_media->[ $i ];
            if ( !$m->{ hide } )
            {
                print( <<END );
$i: $m->{ name } [ id-$m->{ media_id } links-$m->{ inlink_count } $m->{ url } $m->{ foreign_rss_links }$m->{ spidered_label}$m->{ not_dup_label }]
END
            }
        }
        print "\n";

        print "Action (h for help):\n";

        my $line = <STDIN>;
        chomp( $line );
        my $command = [ split( / /, $line ) ];

        my $help = <<END;
<n>
to mark all remaining media as not dups

or

<source media num> <target media num>
to mark source media num as dup of target media num
where source media num can be 'a' for all or a specific number
END

        if ( $command->[ 0 ] eq 'h' )
        {
            print( $help );
        }
        elsif ( $command->[ 0 ] eq 'n' )
        {
            return undef;
        }
        elsif ( @{ $command } eq 2 )
        {
            my ( $s, $t ) = @{ $command };
            if (   ( $s =~ /^(a|\d+)$/ )
                && ( $t =~ /^\d+$/ )
                && ( $s eq 'a' || $ordered_media->[ $s ] )
                && $ordered_media->[ $t ] )
            {
                my $target_medium = $ordered_media->[ $t ];
                my $source_media = ( $s eq 'a' ) ? [ grep { !$_->{ hide } } @{ $media } ] : [ $ordered_media->[ $s ] ];

                return ( $source_media, $target_medium );
            }
        }

        print( "Invalid command.\n" );
        print( $help );
    }
}

# return list of all media that are not hidden and have not been marked is_not_dup
sub get_unprocessed_media
{
    my ( $media ) = @_;

    return [ grep { !( $_->{ hide } || $_->{ is_not_dup } || $_->{ dup_media_id } ) } @{ $media } ];
}

# prompt the user to decide whether domain-equivalent media sources are duplicates of one another
sub dedup_media
{
    my ( $db, $domain, $media ) = @_;

    while ( 1 )
    {
        my ( $source_media, $target_medium ) = prompt_for_dup_media( $db, $domain, $media );

        if ( !$source_media )
        {
            map { mark_medium_is_not_dup( $db, $_ ) } @{ $media };
            return;
        }

        for my $source_medium ( @{ $source_media } )
        {
            mark_medium_as_dup( $db, $source_medium, $target_medium );
        }

        my $unprocessed_media = get_unprocessed_media( $media );
        last unless ( @{ $unprocessed_media } > 1 );
    }
}

# return true if we should ignore this domain.  ignore the domain if
# the domain is blank, the number media is less than 2, the domain matches
# one of a few patterns, there are more than 5 not_dup media already in the domain,
# or no media in the domain have more at least 10 cross media links
sub ignore_domain
{
    my ( $domain, $domain_media ) = @_;

    return 1 if ( !$domain );

    return 1 if ( $domain =~ /(\.edu|\.us|\.blogspot\..*)$/ );

    my $min_link_count = 0;
    map { $min_link_count = 1 if ( $_->{ inlink_count } >= 10 ) } @{ $domain_media };
    return 1 unless ( $min_link_count );

    my $unprocessed_media = get_unprocessed_media( $domain_media );
    return 1 if ( scalar( @{ $unprocessed_media } ) < 2 );

    my $not_dup_media = [ grep { $_->{ is_not_dup } } @{ $domain_media } ];
    return 1 if ( scalar( @{ $not_dup_media } ) >= 5 );

    return 0;
}

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    my $spidered_tag = MediaWords::Util::Tags::lookup_tag( $db, 'spidered:spidered' )
      || die( "Unable to find spidered:spidered tag" );

    # only dedup media that are either not spidered or are associated with topic stories
    # (this eliminates spidered media not actually associated with any topic story)
    my $media = $db->query( <<END, $spidered_tag->{ tags_id } )->hashes;
with media_link_counts as (
    select r.media_id, count(*) inlink_count
        from cd.live_stories s
        join topic_links cl
            on ( s.stories_id = cl.stories_id and s.topics_id = cl.topics_id )
        join cd.live_stories r
            on ( r.stories_id = cl.ref_stories_id and s.topics_id = cl.topics_id )
        where r.media_id <> s.media_id
        group by r.media_id
)

select m.*,
        coalesce( mtm.tags_id, 0 ) is_spidered,
        coalesce( mlc.inlink_count, 0 ) inlink_count
    from
        media m
        left join media_tags_map mtm on ( m.media_id = mtm.media_id and mtm.tags_id = ? )
        left join media_link_counts mlc on ( m.media_id = mlc.media_id )
    where
        m.dup_media_id is null and
        ( ( mtm.tags_id is null ) or
            m.media_id in ( select distinct( cs.media_id ) from cd.live_stories cs ) )
  order by m.media_id
END

    my $media_domain_lookup = {};
    map { push( @{ $media_domain_lookup->{ MediaWords::DBI::Media::get_medium_domain( $_ ) } }, $_ ) } @{ $media };

    # find just the domains that have more than one unprocessed media source
    while ( my ( $domain, $domain_media ) = each( %{ $media_domain_lookup } ) )
    {
        delete( $media_domain_lookup->{ $domain } ) if ( ignore_domain( $domain, $domain_media ) );
    }

    my $num_domains = scalar( values( %{ $media_domain_lookup } ) );

    my $i = 1;
    while ( my ( $domain, $domain_media ) = each( %{ $media_domain_lookup } ) )
    {
        print( "\n" . $i++ . "/ $num_domains\n" );

        # try to auto-dedup via various methods
        mark_dups_of_existing_dup( $db, $domain, $domain_media );
        mark_canonical_url_duplicates( $db, $domain, $domain_media );
        mark_dups_of_root_domain( $db, $domain, $domain_media );

        # only do the manual deduping if the auto-deduping fails to mark all dups
        my $unprocessed_media = get_unprocessed_media( $domain_media );

        dedup_media( $db, $domain, $domain_media ) if ( @{ $unprocessed_media } > 1 );
    }
}

main();
