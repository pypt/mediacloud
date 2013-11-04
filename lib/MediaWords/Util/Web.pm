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
use MediaWords::Util::Config;

use constant MAX_DOWNLOAD_SIZE => 1024 * 1024;
use constant TIMEOUT           => 20;
use constant MAX_REDIRECT      => 15;

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

    my $config = MediaWords::Util::Config::get_config;

    $ua->from( $config->{ mediawords }->{ owner } );
    $ua->agent( $config->{ mediawords }->{ user_agent } );

    $ua->timeout( TIMEOUT );
    $ua->max_size( MAX_DOWNLOAD_SIZE );
    $ua->max_redirect( MAX_REDIRECT );
    $ua->env_proxy;

    return $ua;
}

# simple get for a url using the UserAgent above. return the decoded content
# if the response is successful and undef if not.
sub get_decoded_content
{
    my ( $url ) = @_;

    my $ua = UserAgent();

    my $res = $ua->get( $url );

    return $res->is_success ? $res->decoded_content : undef;
}

# get urls in parallel by using an external, forking script.
# we use this approach because LWP is not thread safe and
# LWP::Parallel::User is not fully parallel and no longer
# works with modern LWP in any case.
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
    for my $link ( @{ $links } )
    {
        $link->{ _link_num } = $i++;
        $link->{ _fetch_url } = $link->{ redirect_url } || $link->{ url };
    }
}

# if the url has been precached, return it, otherwise download the current links and the next ten links
sub get_cached_link_download
{
    my ( $link ) = @_;

    die( "no { _link_num } field in $link->{ url }: did you call cache_link_downloads? " )
      unless ( defined( $link->{ _link_num } ) );

    my $link_num = $link->{ _link_num };

    if ( my $response = $_link_downloads_cache->{ $link_num } )
    {
        return ( ref( $response ) ? $response->decoded_content : $response );
    }

    my $links      = $_link_downloads_list;
    my $urls       = [];
    my $url_lookup = {};
    for ( my $i = 0 ; $links->[ $link_num + $i ] && $i < LINK_CACHE_SIZE ; $i++ )
    {
        my $link = $links->[ $link_num + $i ];
        my $u    = URI->new( $link->{ _fetch_url } )->as_string;

        # handle duplicate urls within the same set of urls
        push( @{ $urls }, $u ) unless ( $url_lookup->{ $u } );
        push( @{ $url_lookup->{ $u } }, $link );

        $link->{ _cached_link_downloads }++;
    }

    my $responses = ParallelGet( $urls );

    $_link_downloads_cache = {};
    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;
        my $response_link_nums = [ map { $_->{ _link_num } } @{ $url_lookup->{ $original_url } } ];

        for my $response_link_num ( @{ $response_link_nums } )
        {
            if ( $response->is_success )
            {
                $_link_downloads_cache->{ $response_link_num } = $response;
            }
            else
            {
                my $msg = "error retrieving content for $original_url: " . $response->status_line;
                warn( $msg );
                $_link_downloads_cache->{ $response_link_num } = $msg;
            }
        }
    }

    warn( "Unable to find cached download for '$link->{ url }'" ) if ( !defined( $_link_downloads_cache->{ $link_num } ) );

    my $response = $_link_downloads_cache->{ $link_num };
    return ( ref( $response ) ? $response->decoded_content : ( $response || '' ) );
}

# get the redirected url from the cached download for the url.
# if no redirected url is found, just return the given url.
sub get_cached_link_download_redirect_url
{
    my ( $link ) = @_;

    my $url      = URI->new( $link->{ url } )->as_string;
    my $link_num = $link->{ _link_num };

    # make sure the $_link_downloads_cache is setup correctly
    get_cached_link_download( $link );

    if ( my $response = $_link_downloads_cache->{ $link_num } )
    {
        if ( $response && ref( $response ) )
        {
            return $response->request->uri->as_string;
        }
    }

    return $url;
}

1;
