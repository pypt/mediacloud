package MediaWords::Util::Web;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# various functions to make downloading web pages easier and faster, including parallel
# and cached fetching.

use strict;

use File::Temp;
use FindBin;
use LWP::UserAgent;
use Storable;

use MediaWords::Util::Paths;

use constant MAX_DOWNLOAD_SIZE => 1024 * 1024;
use constant TIMEOUT           => 20;
use constant MAX_REDIRECT      => 15;
use constant BOT_FROM          => 'mediacloud@cyber.law.harvard.edu';
use constant BOT_AGENT         => 'mediacloud bot (http://mediacloud.org)';

# number of links to prefetch at a time for the cached downloads
use constant LINK_CACHE_SIZE => 100;

# list of downloads to precache downloads for
my $_link_downloads_list;

# precached link downloads
my $_link_downloads_cache;

# return a user agent with media cloud default settings (
sub UserAgent
{
    my $ua = LWP::UserAgent->new();

    $ua->from( BOT_FROM );
    $ua->agent( BOT_AGENT );

    $ua->timeout( TIMEOUT );
    $ua->max_size( MAX_DOWNLOAD_SIZE );
    $ua->max_redirect( MAX_REDIRECT );

    return $ua;
}

# get urls in parallel
sub ParallelGet
{
    my ( $urls ) = @_;

    return [] unless ( $urls && @{ $urls } );

    my $web_store_input;
    my $results;
    for my $url ( @{ $urls } )
    {
        my $result = { url => $url, file => File::Temp::mktemp( '/tmp/MediaWordsUtilWebXXXXXXXX' ) };

        $web_store_input .= "$result->{ file }:$result->{ url }\n";

        push( @{ $results }, $result );
    }

    my $mc_script_path = MediaWords::Util::Paths::mc_script_path();
    my $cmd            = "'$mc_script_path'/../script/mediawords_web_store.pl";

    #say STDERR "opening cmd:'$cmd' ";

    if ( !open( CMD, '|-', $cmd ) )
    {
        warn( "Unable to start $cmd: $!" );
        return;
    }

    binmode( CMD, 'utf8' );

    print CMD $web_store_input;
    close( CMD );

    my $responses;
    for my $result ( @{ $results } )
    {
        my $response;
        if ( -f $result->{ file } )
        {
            $response = Storable::retrieve( $result->{ file } );
            push( @{ $responses }, $response );
            unlink( $result->{ file } );
        }
        else
        {
            $response = HTTP::Response->new( '500', "web store timeout for $result->{ url }" );
            $response->request( HTTP::Request->new( GET => $result->{ url } ) );

            push( @{ $responses }, $response );
        }
    }

    return $responses;
}

# walk back from the given response to get the original request that generated the response.
sub get_original_request
{
    my ( $class, $response ) = @_;

    my $original_response = $response;
    while ( $original_response->previous )
    {
        $original_response = $original_response->previous;
    }

    return $original_response->request;
}

# cache link downloads LINK_CACHE_SIZE at a time so that we can do them in parallel.
# this doesn't actually do any caching -- it just sets the list of
# links so that they can be done LINK_CACHE_SIZE at a time by get_cached_link_download.
sub cache_link_downloads
{
    my ( $links ) = @_;

    $_link_downloads_list = $links;

    my $i = 0;
    map { $_->{ _link_num } = $i++ } @{ $links };
}

# if the url has been precached, return it, otherwise download the current links and the next ten links
sub get_cached_link_download
{
    my ( $link ) = @_;

    die( "no { _link_num } field in $link } " ) if ( !defined( $link->{ _link_num } ) );

    my $link_num = $link->{ _link_num };

    # the url gets transformed like this in the ParallelGet below, so we have
    # to transform it here so that we can go back and find the request by the url
    # in the ParalleGet
    my $url = URI->new( $link->{ url } )->as_string;

    if ( my $response = $_link_downloads_cache->{ $url } )
    {
        return ( ref( $response ) ? $response->decoded_content : $response );
    }

    my $links = $_link_downloads_list;
    my $urls  = [];
    for ( my $i = 0 ; $links->[ $link_num + $i ] && $i < LINK_CACHE_SIZE ; $i++ )
    {
        my $link = $links->[ $link_num + $i ];
        push( @{ $urls }, URI->new( $link->{ url } )->as_string );
    }

    my $responses = ParallelGet( $urls );

    $_link_downloads_cache = {};
    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;
        if ( $response->is_success )
        {

            # print STDERR "original_url: $original_url " . length( $response->decoded_content ) . "\n";
            $_link_downloads_cache->{ $original_url } = $response;
        }
        else
        {
            my $msg = "error retrieving content for $original_url: " . $response->status_line;
            warn( $msg );
            $_link_downloads_cache->{ $original_url } = $msg;
        }
    }

    warn( "Unable to find cached download for '$url'" ) if ( !defined( $_link_downloads_cache->{ $url } ) );

    my $response = $_link_downloads_cache->{ $url };
    return ( ref( $response ) ? $response->decoded_content : ( $response || '' ) );
}

# get the redirected url from the cached download for the url.
# if no redirected url is found, just return the given url.
sub get_cached_link_download_redirect_url
{
    my ( $link ) = @_;

    my $url      = URI->new( $link->{ url } )->as_string;
    my $link_num = $link->{ link_num };

    # make sure the $_link_downloads_cache is setup correctly
    get_cached_link_download( $link );

    if ( my $response = $_link_downloads_cache->{ $url } )
    {
        if ( ref( $response ) )
        {
            return $response->request->uri->as_string;
        }
    }

    return $url;
}


1;
