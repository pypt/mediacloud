package MediaWords::Controller::Admin::CM;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;
use warnings;
use parent 'Catalyst::Controller';

use List::Compare;

use MediaWords::CM::Dump;

sub index : Path : Args(0)
{

    return list( @_ );
}

# list all controversies
sub list : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $controversies = $db->query( <<END )->hashes;
select * from controversies_with_search_info order by controversies_id desc
END

    $c->stash->{ controversies } = $controversies;
    $c->stash->{ template }      = 'cm/list.tt2';
}

# add a periods field to the controversy dump
sub _add_periods_to_controversy_dump
{
    my ( $db, $controversy_dump ) = @_;

    my $periods = $db->query( <<END, $controversy_dump->{ controversy_dumps_id } )->hashes;
select distinct period from controversy_dump_time_slices
    where controversy_dumps_id = ?
    order by period;
END

    if ( @{ $periods } == 4 )
    {
        $controversy_dump->{ periods } = 'all';
    }
    else
    {
        $controversy_dump->{ periods } = join( ", ", map { $_->{ period } } @{ $periods } );
    }
}

sub _get_latest_full_dump_with_time_slices
{
    my ( $db, $controversy_dumps ) = @_;

    my $latest_full_dump;
    for my $cd ( @{ $controversy_dumps } )
    {
        if ( $cd->{ periods } eq 'all' )
        {
            $latest_full_dump = $cd;
            last;
        }
    }

    return unless ( $latest_full_dump );

    my $controversy_dump_time_slices = $db->query( <<END, $latest_full_dump->{ controversy_dumps_id } )->hashes;
select * from controversy_dump_time_slices 
    where controversy_dumps_id = ? 
    order by period, start_date, end_date
END

    map { _add_media_and_story_counts_to_cdts( $db, $_ ) } @{ $controversy_dump_time_slices };

    $latest_full_dump->{ controversy_dump_time_slices } = $controversy_dump_time_slices;

    return $latest_full_dump;
}

# view the details of a single controversy
sub view : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $db = $c->dbis;

    my $controversy = $db->query( <<END, $controversies_id )->hash;
select * from controversies_with_search_info where controversies_id = ?
END

    my $query = MediaWords::DBI::Queries::find_query_by_id( $db, $controversy->{ queries_id } );
    $query->{ media_set_names } = MediaWords::DBI::Queries::get_media_set_names( $db, $query ) if ( $query );

    my $controversy_dumps = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select * from controversy_dumps where controversies_id = ?
    order by controversy_dumps_id desc
END

    map { _add_periods_to_controversy_dump( $db, $_ ) } @{ $controversy_dumps };

    my $latest_full_dump = _get_latest_full_dump_with_time_slices( $db, $controversy_dumps );

    $c->stash->{ controversy }       = $controversy;
    $c->stash->{ query }             = $query;
    $c->stash->{ controversy_dumps } = $controversy_dumps;
    $c->stash->{ latest_full_dump }  = $latest_full_dump;
    $c->stash->{ template }          = 'cm/view.tt2';
}

# add num_stories, num_story_links, num_media, and num_media_links
# fields to the controversy_dump_time_slice
sub _add_media_and_story_counts_to_cdts
{
    my ( $db, $cdts ) = @_;

    ( $cdts->{ num_stories } ) = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->flat;
select count(*) from cd.story_link_counts where controversy_dump_time_slices_id = ?
END

    ( $cdts->{ num_story_links } ) = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->flat;
select count(*) from cd.story_links where controversy_dump_time_slices_id = ?
END

    ( $cdts->{ num_media } ) = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->flat;
select count(*) from cd.medium_link_counts where controversy_dump_time_slices_id = ?
END

    ( $cdts->{ num_medium_links } ) = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->flat;
select count(*) from cd.medium_links where controversy_dump_time_slices_id = ?
END
}

# view a controversy dump, with a list of its time slices
sub view_dump : Local
{
    my ( $self, $c, $controversy_dumps_id ) = @_;

    my $db = $c->dbis;

    my $controversy_dump = $db->query( <<END, $controversy_dumps_id )->hash;
select * from controversy_dumps where controversy_dumps_id = ?
END
    my $controversy = $db->find_by_id( 'controversies', $controversy_dump->{ controversies_id } );

    my $controversy_dump_time_slices = $db->query( <<END, $controversy_dumps_id )->hashes;
select * from controversy_dump_time_slices 
    where controversy_dumps_id = ? 
    order by period, start_date, end_date
END

    map { _add_media_and_story_counts_to_cdts( $db, $_ ) } @{ $controversy_dump_time_slices };

    $c->stash->{ controversy_dump }             = $controversy_dump;
    $c->stash->{ controversy }                  = $controversy;
    $c->stash->{ controversy_dump_time_slices } = $controversy_dump_time_slices;
    $c->stash->{ template }                     = 'cm/view_dump.tt2';
}

# get the media marked as the most influential media for the current time slice
sub _get_top_media_for_time_slice
{
    my ( $db, $cdts ) = @_;

    my $num_media = $cdts->{ model_num_media };

    return unless ( $num_media );

    my $top_media = $db->query( <<END, $num_media )->hashes;
select m.*, mlc.inlink_count, mlc.outlink_count, mlc.story_count
    from dump_media m, dump_medium_link_counts mlc
    where m.media_id = mlc.media_id
    order by mlc.inlink_count desc
    limit ?
END

    return $top_media;
}

# get the top 20 stories for the current time slice
sub _get_top_stories_for_time_slice
{
    my ( $db ) = @_;

    my $top_stories = $db->query( <<END, 20 )->hashes;
select s.*, slc.inlink_count, slc.outlink_count, m.name as medium_name
    from dump_stories s, dump_story_link_counts slc, dump_media m
    where s.stories_id = slc.stories_id and
        s.media_id = m.media_id
    order by slc.inlink_count desc
    limit ?
END

    return $top_stories;
}

# get the controversy_dump_time_slice, controversy_dump, and controversy
# for the current request
sub _get_controversy_objects
{
    my ( $db, $cdts_id ) = @_;

    die( "cdts param is required" ) unless ( $cdts_id );
    
    my $cdts        = $db->find_by_id( 'controversy_dump_time_slices', $cdts_id );
    my $cd          = $db->find_by_id( 'controversy_dumps', $cdts->{ controversy_dumps_id } );
    my $controversy = $db->find_by_id( 'controversies', $cd->{ controversies_id } );
    
    return ( $cdts, $cd, $controversy );
}

# view timelices, with links to csv and gexf files
sub view_time_slice : Local
{
    my ( $self, $c, $cdts_id ) = @_;

    my $db = $c->dbis;

    my $live = $c->req->param( 'l' );

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    _add_media_and_story_counts_to_cdts( $db, $cdts );

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $live );

    my $top_media = _get_top_media_for_time_slice( $db, $cdts );
    my $top_stories = _get_top_stories_for_time_slice( $db, $cdts );

    MediaWords::CM::Dump::discard_temp_tables( $db );

    $c->stash->{ cdts }             = $cdts;
    $c->stash->{ controversy_dump } = $cd;
    $c->stash->{ controversy }      = $controversy;
    $c->stash->{ top_media }        = $top_media;
    $c->stash->{ top_stories }      = $top_stories;
    $c->stash->{ live }             = $live;
    $c->stash->{ template }         = 'cm/view_time_slice.tt2';
}

# download a csv field from controversy_dump_time_slices_id
sub _download_cdts_csv
{
    my ( $c, $controversy_dump_time_slices_id, $csv ) = @_;

    my $field = $csv . '_csv';

    my $db = $c->dbis;

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $controversy_dump_time_slices_id );

    my $file = "${ csv }_$cdts->{ controversy_dump_time_slices_id }.csv";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/csv; charset=UTF-8' );
    $c->response->content_length( bytes::length( $cdts->{ $field } ) );
    $c->response->body( $cdts->{ $field } );
}

# download the stories_csv for the given time slice
sub dump_stories : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'stories' );
}

# download the story_links_csv for the given time slice
sub dump_story_links : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'story_links' );
}

# download the media_csv for the given time slice
sub dump_media : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'media' );
}

# download the medium_links_csv for the given time slice
sub dump_medium_links : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'medium_links' );
}

# download the gexf file for the time slice
sub gexf : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id, $csv ) = @_;

    my $db = $c->dbis;

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $controversy_dump_time_slices_id );

    my $gexf = $cdts->{ gexf };

    my $base_url = $c->uri_for( '/' );

    $gexf =~ s/\[_mc_base_url_\]/$base_url/g;

    my $file = "media_$cdts->{ controversy_dump_time_slices_id }.gexf";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/gexf; charset=UTF-8' );
    $c->response->content_length( bytes::length( $gexf ) );
    $c->response->body( $gexf );
}

# download a csv field from controversy_dumps
sub _download_cd_csv
{
    my ( $c, $controversy_dumps_id, $csv ) = @_;

    my $field = $csv . '_csv';

    my $db = $c->dbis;

    my $cd = $db->find_by_id( 'controversy_dumps', $controversy_dumps_id );

    my $file = "${ csv }_$cd->{ controversy_dumps_id }.csv";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/csv; charset=UTF-8' );
    $c->response->content_length( bytes::length( $cd->{ $field } ) );
    $c->response->body( $cd->{ $field } );
}

# download the daily_counts_csv for the given dump
sub dump_daily_counts : Local
{
    my ( $self, $c, $controversy_dumps_id ) = @_;

    _download_cd_csv( $c, $controversy_dumps_id, 'daily_counts' );
}

# download the weekly_counts_csv for the given dump
sub dump_weekly_counts : Local
{
    my ( $self, $c, $controversy_dumps_id ) = @_;

    _download_cd_csv( $c, $controversy_dumps_id, 'weekly_counts' );
}

# return the latest dump if it is not the dump to which the cdts belongs.  otherwise return undef.
sub _get_latest_controversy_dump
{
    my ( $db, $cdts ) = @_;

    my $latest_dump = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->hash;
select latest.* from controversy_dumps latest, controversy_dumps current, controversy_dump_time_slices cdts
    where cdts.controversy_dump_time_slices_id = ? and
        current.controversy_dumps_id = cdts.controversy_dumps_id and
        latest.controversy_dumps_id > current.controversy_dumps_id and
        latest.controversies_id = current.controversies_id
    order by latest.controversy_dumps_id desc 
    limit 1
END

    return $latest_dump;
}

# get the medium with the medium_stories, inlink_stories, and outlink_stories and associated
# counts. assumes the existence of dump_* stories as created by
# MediaWords::CM::Dump::setup_temporary_dump_tables
sub _get_medium_and_stories_from_dump_tables
{
    my ( $db, $media_id ) = @_;

    my $medium = $db->query( "select * from dump_media where media_id = ?", $media_id )->hash;

    return unless ( $medium );

    $medium->{ stories } = $db->query( <<'END', $media_id )->hashes;
select s.*, m.name medium_name, slc.inlink_count, slc.outlink_count
    from dump_stories s, dump_media m, dump_story_link_counts slc
    where 
        s.stories_id = slc.stories_id and
        s.media_id = m.media_id and
        s.media_id = ?
    order by slc.inlink_count desc
END

    $medium->{ inlink_stories } = $db->query( <<'END', $media_id )->hashes;
select distinct s.*, sm.name medium_name, sslc.inlink_count, sslc.outlink_count
    from dump_stories s, dump_story_link_counts sslc, dump_media sm, 
        dump_stories r, dump_story_link_counts rslc,
        dump_controversy_links_cross_media cl
    where 
        s.stories_id = sslc.stories_id and
        r.stories_id = rslc.stories_id and
        s.media_id = sm.media_id and
        s.stories_id = cl.stories_id and
        r.stories_id = cl.ref_stories_id and
        r.media_id = ?        
    order by sslc.inlink_count desc
END

    $medium->{ outlink_stories } = $db->query( <<'END', $media_id )->hashes;
select distinct r.*, rm.name medium_name, rslc.inlink_count, rslc.outlink_count
    from dump_stories s, dump_story_link_counts sslc, 
        dump_stories r, dump_story_link_counts rslc, dump_media rm, 
        dump_controversy_links_cross_media cl
    where 
        s.stories_id = sslc.stories_id and
        r.stories_id = rslc.stories_id and
        r.media_id = rm.media_id and
        s.stories_id = cl.stories_id and
        r.stories_id = cl.ref_stories_id and
        s.media_id = ?
    order by rslc.inlink_count desc
END

    $medium->{ story_count }   = scalar( @{ $medium->{ stories } } );
    $medium->{ inlink_count }  = scalar( @{ $medium->{ inlink_stories } } );
    $medium->{ outlink_count } = scalar( @{ $medium->{ outlink_stories } } );

    return $medium;
}

# get data about the medium as it existed in the given time slice.  include medium_stories,
# inlink_stories, and outlink_stories from the time slice as well.
sub _get_cdts_medium_and_stories
{
    my ( $db, $cdts, $media_id ) = @_;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts );

    my $medium = _get_medium_and_stories_from_dump_tables( $db, $media_id );

    MediaWords::CM::Dump::discard_temp_tables( $db );

    return $medium;
}

# get live data about the medium within the given controversy.  Include medium_stories,
# inlink_stories, and outlink_stories.
sub _get_live_medium_and_stories
{
    my ( $db, $controversy, $cdts, $media_id ) = @_;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, 1 );

    my $medium = _get_medium_and_stories_from_dump_tables( $db, $media_id );

    MediaWords::CM::Dump::discard_temp_tables( $db );

    return $medium;
}

# return undef if given fields in the given objects are the same and the
# list_field in the given lists are the same.   Otherwise return a string list
# of the fields and lists for which there are differences.
sub _get_object_diffs
{
    my ( $a, $b, $fields, $lists, $list_field ) = @_;

    my $diffs = [];

    for my $field ( @{ $fields } )
    {
        push( @{ $diffs }, $field ) if ( $a->{ $field } ne $b->{ $field } );
    }

    for my $list ( @{ $lists } )
    {
        my $a_ids = [ map { $_->{ $list_field } } @{ $a->{ $list } } ];
        my $b_ids = [ map { $_->{ $list_field } } @{ $b->{ $list } } ];

        my $lc = List::Compare->new( $a_ids, $b_ids );
        if ( !$lc->is_LequivalentR() )
        {
            my $list_name = $list;
            $list_name =~ s/_/ /g;
            push( @{ $diffs }, $list_name );
        }
    }

    return ( @{ $diffs } ) ? join( ", ", @{ $diffs } ) : undef;
}

# check each of the following for differences between the live and dump medium:
# * name
# * url
# * ids of stories
# * ids of inlink_stories
# * ids of outlink_stories
#
# return undef if there are no diffs and otherwise a string list of the
# attributes (above) for which there are differences
sub _get_live_medium_diffs
{
    my ( $dump_medium, $live_medium ) = @_;

    if ( !$live_medium )
    {
        return 'medium is no longer in controversy';
    }

    return _get_object_diffs(
        $dump_medium, $live_medium,
        [ qw(name url) ],
        [ qw(stories inlink_stories outlink_stories) ], 'stories_id'
    );
}

# view medium:
# * live if l=1 is specified, otherwise as a snapshot
# * within the context of a time slice if a time slice is specific
#   via cdts=<id>, otherwise within a whole controversy if 'c=<id>'
sub medium : Local
{
    my ( $self, $c, $media_id ) = @_;

    my $db = $c->dbis;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $c->req->param( 'cdts' ) );

    my $live = $c->req->param( 'l' );
    my $live_medium = _get_live_medium_and_stories( $db, $controversy, $cdts, $media_id );

    my ( $medium, $live_medium_diffs, $latest_controversy_dump );
    if ( $live )
    {
        $medium = $live_medium;
    }
    else
    {
        $medium = _get_cdts_medium_and_stories( $db, $cdts, $media_id );
        $live_medium_diffs = _get_live_medium_diffs( $medium, $live_medium );
        $latest_controversy_dump = _get_latest_controversy_dump( $db, $cdts );
    }

    $c->stash->{ cdts }                     = $cdts;
    $c->stash->{ controversy_dump }         = $cd;
    $c->stash->{ controversy }              = $controversy;
    $c->stash->{ medium }                   = $medium;
    $c->stash->{ latest_controversy_dump }  = $latest_controversy_dump;
    $c->stash->{ live_medium_diffs }        = $live_medium_diffs;
    $c->stash->{ live }                     = $live;
    $c->stash->{ live_medium }              = $live_medium;
    $c->stash->{ template }                 = 'cm/medium.tt2';
}

# is the given date guess method reliable?
sub _story_date_is_reliable
{
    my ( $method ) = @_;

    return ( !$method || ( grep { $_ eq $method } qw(guess_by_url guess_by_url_and_date_text merged_story_rss manual) ) );
}

# get the story along with inlink_stories and outlink_stories and the associated
# counts.  assumes the existence of dump_* stories as created by
# MediaWords::CM::Dump::setup_temporary_dump_tables
sub _get_story_and_links_from_dump_tables
{
    my ( $db, $stories_id ) = @_;

    # if the below query returns nothing, the return type of the server prepared statement
    # may differ from the first call, which throws a postgres error, so we need to
    # disable server side prepares
    $db->dbh->{ pg_server_prepare } = 0;

    my $story = $db->query( "select * from dump_stories where stories_id = ?", $stories_id )->hash;

    return unless ( $story );

    $story->{ medium } = $db->query( "select * from dump_media where media_id = ?", $story->{ media_id } )->hash;
    ( $story->{ date_guess_method } ) = $db->query( <<END, $stories_id )->flat;
select tag from dump_tags t, dump_stories_tags_map stm, dump_tag_sets ts
    where ts.name = 'date_guess_method' and
        ts.tag_sets_id = t.tag_sets_id and
        t.tags_id = stm.tags_id and
        stm.stories_id = ?
END
    $story->{ date_is_reliable } = _story_date_is_reliable( $story->{ date_guess_method } );

    $story->{ inlink_stories } = $db->query( <<'END', $stories_id )->hashes;
select distinct s.*, sm.name medium_name, sslc.inlink_count, sslc.outlink_count
    from dump_stories s, dump_story_link_counts sslc, dump_media sm, 
        dump_stories r, dump_story_link_counts rslc,
        dump_controversy_links_cross_media cl
    where 
        s.stories_id = sslc.stories_id and
        r.stories_id = rslc.stories_id and
        s.media_id = sm.media_id and
        s.stories_id = cl.stories_id and
        r.stories_id = cl.ref_stories_id and
        cl.ref_stories_id = ?       
    order by sslc.inlink_count desc
END

    $story->{ outlink_stories } = $db->query( <<'END', $stories_id )->hashes;
select distinct r.*, rm.name medium_name, rslc.inlink_count, rslc.outlink_count
    from dump_stories s, dump_story_link_counts sslc, 
        dump_stories r, dump_story_link_counts rslc, dump_media rm, 
        dump_controversy_links_cross_media cl
    where 
        s.stories_id = sslc.stories_id and
        r.stories_id = rslc.stories_id and
        r.media_id = rm.media_id and
        s.stories_id = cl.stories_id and
        r.stories_id = cl.ref_stories_id and
        cl.stories_id = ?
    order by rslc.inlink_count desc
END

    $story->{ inlink_count }  = scalar( @{ $story->{ inlink_stories } } );
    $story->{ outlink_count } = scalar( @{ $story->{ outlink_stories } } );

    return $story;
}

# get data about the story as it existed in the given time slice.  include
# outlinks and inlinks, as well as the date guess method.
sub _get_cdts_story_and_links
{
    my ( $db, $cdts, $stories_id ) = @_;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts );

    my $story = _get_story_and_links_from_dump_tables( $db, $stories_id );

    MediaWords::CM::Dump::discard_temp_tables( $db );

    return $story;
}

# get data about the story as it exists now in the database, optionally
# in the date range of the if specified
sub _get_live_story_and_links
{
    my ( $db, $controversy, $cdts, $stories_id ) = @_;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, 1 );

    my $story = _get_story_and_links_from_dump_tables( $db, $stories_id );

    MediaWords::CM::Dump::discard_temp_tables( $db );

    return $story;
}

# check each of the following for differences between the live and dump story:
# * title
# * url
# * publish_date
# * ids of inlink_stories
# * ids of outlink_stories
#
# return undef if there are no diffs and otherwise a string list of the
# attributes (above) for which there are differences
sub _get_live_story_diffs
{
    my ( $dump_story, $live_story ) = @_;

    if ( !$live_story )
    {
        return 'story is no longer in controversy';
    }

    return _get_object_diffs(
        $dump_story, $live_story,
        [ qw(title url publish_date date_is_reliable) ],
        [ qw(inlink_stories outlink_stories) ], 'stories_id'
    );
}

# view story as it existed in a dump time slice
sub story : Local
{
    my ( $self, $c, $stories_id ) = @_;

    my $db = $c->dbis;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $c->req->param( 'cdts' ) );

    my $live = $c->req->param( 'l' );
    my $live_story = _get_live_story_and_links( $db, $controversy, $cdts, $stories_id );

    my ( $story, $live_story_diffs, $latest_controversy_dump );
    if ( $live )
    {
        $story = $live_story;
    }
    else
    {
        $story = _get_cdts_story_and_links( $db, $cdts, $stories_id );
        $live_story_diffs = _get_live_story_diffs( $story, $live_story );
        $latest_controversy_dump = _get_latest_controversy_dump( $db, $cdts );
    }

    $c->stash->{ cdts }                    = $cdts;
    $c->stash->{ cd }                      = $cd;
    $c->stash->{ controversy }             = $controversy;
    $c->stash->{ story }                   = $story;
    $c->stash->{ latest_controversy_dump } = $latest_controversy_dump;
    $c->stash->{ live_story_diffs }        = $live_story_diffs;
    $c->stash->{ live }                    = $live;
    $c->stash->{ live_story }              = $live_story;
    $c->stash->{ template }                = 'cm/story.tt2';
}

# get the text for a sql query that returns all of the story ids that
# match the given search query.  the search query uses a simplistic
# plan of removing quote characters, splitting the line on spaces,
# and finding all stories that include sentences that match all
# of the given terms
sub _get_stories_id_search_query
{
    my ( $db, $q ) = @_;
    
    $q =~ s/['"%]//g;
    
    my $terms = [ split( /\s/, $q ) ];

    return 'select stories_id from dump_story_link_counts' unless ( @{ $terms } );
    
    my $queries = [];
    for my $term ( @{ $terms } )
    {
        my $qterm = $db->dbh->quote( lc( "%${ term }%" ) );
        my $query = <<END;
select slc.stories_id 
    from dump_story_link_counts slc
        join dump_stories s on ( s.stories_id = slc.stories_id )
        left join story_sentences ss on ( slc.stories_id = s.stories_id )
    where ( ss.sentence like $qterm or 
            lower( s.title ) like $qterm or
            lower( s.url ) like $qterm )
END
        push( @{ $queries }, $query );
    }
    
    return join( ' intersect ', map { "( $_ )" } @{ $queries } );
}

# do a basic story search based on the 
sub search_stories : Local
{
    my ( $self, $c ) = @_;
    
    my $db = $c->dbis;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $c->req->param( 'cdts' ) );

    my $live = $c->req->param( 'l' );
    
    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $live );
    
    my $query = $c->req->param( 'q' );
    my $search_query = _get_stories_id_search_query( $db, $query );
    
    my $stories = $db->query( <<END )->hashes;
select s.*, m.name medium_name, slc.inlink_count, slc.outlink_count
    from dump_stories s, dump_media m, dump_story_link_counts slc
    where
        s.stories_id = slc.stories_id and
        s.media_id = m.media_id and
        s.stories_id in ( $search_query )
    order by slc.inlink_count desc
END
    
    MediaWords::CM::Dump::discard_temp_tables( $db );

    $c->stash->{ cdts }             = $cdts;
    $c->stash->{ controversy_dump } = $cd;
    $c->stash->{ controversy }      = $controversy;
    $c->stash->{ stories }          = $stories;
    $c->stash->{ query }            = $query;
    $c->stash->{ template }         = 'cm/stories.tt2';
}

1;
