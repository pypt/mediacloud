package MediaWords::ImportStories::Feedly;

=head1 NAME

MediaWords::ImportStories::Feedly - import stories form feedly api

=head2 DESCRIPTION

Import stories from a feedly feed.

In addition to ImportStories options, new accepts the following options:

=over

=item *

feed_url - the url of a feed archived by feedly

=back

This module grabs historical stories from the feedly api.

=cut

use strict;
use warnings;

use Moose;
with 'MediaWords::ImportStories';

use Data::Dumper;
use Encode;
use LWP::Simple;
use Modern::Perl "2015";
use MediaWords::CommonLibs;
use URI::Escape;

use MediaWords::Util::JSON;
use MediaWords::Util::SQL;
use MediaWords::Util::Web;

# number of stories to return in each feedly request
Readonly my $FEEDLY_COUNT => 10_000;

has 'feed_url'          => ( is => 'rw' );
has 'feeds_id'          => ( is => 'rw' );
has 'scraped_feeds_ids' => ( is => 'rw' );

=head1 METHODS

=cut

# accept a hash generated from the feedly json response and return the list of story candidates.
# return only stories within the date range.  push any stories found onto the array ref $stories.
# create a new array ref for $stories if $stories is undef.
sub _push_stories_from_json_data($$$)
{
    my ( $self, $stories, $json_data ) = @_;

    my $latest_publish_date = 0;

    $stories ||= [];

    for my $item ( @{ $json_data->{ items } } )
    {
        next unless ( defined( $item->{ title } ) );

        next unless ( $item->{ originId } );

        my $publish_date = MediaWords::Util::SQL::get_sql_date_from_epoch( $item->{ published } / 1000 );

        $latest_publish_date = $publish_date if ( $publish_date gt $latest_publish_date );

        next unless ( $self->story_is_in_date_range( $publish_date ) );

        my $guid = "feedly:$item->{ originId }";
        my $url =
          ( $item->{ alternate } && $item->{ alternate }->[ 0 ]->{ href } ) ? $item->{ alternate }->[ 0 ]->{ href } : $guid;

        # each of summary.content and content.content may or may not be set
        my $content = ( $item->{ summary }->{ content } || '' ) . "\n" . ( $item->{ content }->{ content } || '' );

        my $story = {
            url          => $url,
            guid         => $guid,
            media_id     => $self->media_id,
            collect_date => MediaWords::Util::SQL::sql_now(),
            publish_date => $publish_date,
            title        => $item->{ title },
            description  => $content
        };

        push( @{ $stories }, $story );
    }

    say STDERR "latest_publish_date: $latest_publish_date";

    return $stories;
}

# get one chunk of stories from the feedly api.  if a continuation id is included in the chunk, recursively  call again
# with the continuation id.  accumulate stories from all recursive calls in $all_stories and return $all_stories.
sub _get_stories_from_feedly($$;$$)
{
    my ( $self, $feed_url, $continuation_id, $all_stories ) = @_;

    say STDERR "get_stories_from_feedly " . ( $continuation_id || 'START' );

    my $ua = MediaWords::Util::Web::UserAgentDetermined;
    $ua->max_size( undef );
    $ua->timing( '1,15,60,300,300,600,900' );

    my $esc_feed_url = uri_escape( $feed_url );
    my $api_url      = "http://cloud.feedly.com/v3/streams/contents?streamId=feed/$esc_feed_url&count=$FEEDLY_COUNT";

    if ( $continuation_id )
    {
        $api_url .= "&continuation=" . uri_escape( $continuation_id );
    }

    my $res = $ua->get( $api_url );

    die( "error calling feedly api with url '$api_url': " . $res->as_string ) unless ( $res->is_success );

    # for some reason, $res->decoded_content does not decode
    my $json = decode( 'utf8', $res->content );

    my $json_data = MediaWords::Util::JSON::decode_json( $json );

    if ( !$json_data->{ title } )
    {
        say STDERR "No feedly feed found for feed_url '" . $feed_url . "'";
        return [];
    }

    $all_stories = $self->_push_stories_from_json_data( $all_stories, $json_data );

    say STDERR "_get_new_stories_from_feedly chunk: " . scalar( @{ $all_stories } ) . " total stories found";

    if ( my $continuation_id = $json_data->{ continuation } )
    {
        return $self->_get_stories_from_feedly( $feed_url, $continuation_id, $all_stories );
    }
    else
    {
        return $all_stories;
    }
}

=head2 get_new_stories( $self )

Get stories from feedly for the feedly_url specified at object creation.  If feedly_url is a list of urls, return
the list of stories for the whole list.

=cut

sub get_new_stories($)
{
    my ( $self ) = @_;

    my $all_stories = [];

    my $feed_urls;
    my $feeds;
    if ( $self->feed_url )
    {
        $feed_urls = ref( $self->feed_url ) ? $self->feed_url : [ $self->feed_url ];
        DEBUG( sub { "get_new_stories: feed_url " . join( ",", @{ $feed_urls } ) } );
    }
    elsif ( my $feeds_id = $self->feeds_id )
    {
        DEBUG( sub { "get_new_stories feeds_id: $feeds_id" } );
        $feeds = $self->db->query( <<SQL, $feeds_id )->hashes;
select * from feedly_unscraped_feeds where feeds_id = ?
SQL
    }
    elsif ( my $media_id = $self->media_id )
    {
        DEBUG( sub { "get_new_stories media_id: $media_id" } );
        $feeds = $self->db->query( <<SQL, $media_id )->hashes;
select * from feedly_unscraped_feeds where media_id = ?
SQL
    }
    else
    {
        LOGDIE( "must specify either feed_url, media_id, or feeds_id" );
    }

    if ( $feeds )
    {
        $self->scraped_feeds_ids( [ map { $_->{ feeds_id } } @{ $feeds } ] );
        $feed_urls = [ map { $_->{ url } } @{ $feeds } ];
    }

    DEBUG( "no unscraped feeds found" ) unless ( @{ $feed_urls } );

    for my $feed_url ( @{ $feed_urls } )
    {
        say STDERR "get feedly stories for feed '$feed_url'";
        my $stories = $self->_get_stories_from_feedly( $feed_url );
        push( @{ $all_stories }, @{ $stories } );
    }

    return $all_stories;
}

1;
