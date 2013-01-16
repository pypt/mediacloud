package MediaWords::DBI::Media;
use Modern::Perl "2012";
use MediaWords::CommonLibs;
use MediaWords::Util::HTML;
use Text::Trim;

use strict;
use warnings;

use Encode;

use Regexp::Common qw /URI/;

use Data::Dumper;

# for each url in $urls, either find the medium associated with that
# url or the medium assocaited with the title from the given url or,
# if no medium is found, a newly created medium.  Return the list of
# all found or created media along with a list of error messages for the process.
sub find_or_create_media_from_urls
{
    my ( $dbis, $urls_string, $tags_string ) = @_;

    my $url_media = MediaWords::DBI::Media::find_media_from_urls( $dbis, $urls_string );

    _add_missing_media_from_urls( $dbis, $url_media );

    _add_media_tags_from_strings( $dbis, $url_media, $tags_string );

    return [ grep { $_ } map { $_->{ message } } @{ $url_media } ];
}

# given a set of url media (as returned by _find_media_from_urls) and a url
# return the index of the media source in the list whose url is the same as the url fetched the response.
# note that the url should be the original url and not any redirected urls (such as might be stored in
# response->request->url).
sub _get_url_medium_index_from_url
{
    my ( $url_media, $url ) = @_;

    for ( my $i = 0 ; $i < @{ $url_media } ; $i++ )
    {

        #print STDERR "'$url_media->[ $i ]->{ url }' eq '$url'\n";
        if ( URI->new( $url_media->[ $i ]->{ url } ) eq URI->new( $url ) )
        {
            return $i;
        }
    }

    warn( "Unable to find url '" . $url . "' in url_media list" );
    return undef;
}

# given an lwp response, grab the title of the media source as the <title> content or missing that the response url
sub _get_medium_title_from_response
{
    my ( $response ) = @_;

    my $content = $response->decoded_content;

    my ( $title ) = ( $content =~ /<title>(.*?)<\/title>/is );
    $title = html_strip( $title );
    $title = trim( $title );
    $title ||= trim( decode( 'utf8', $response->request->url ) );
    $title =~ s/\s+/ /g;

    $title =~ s/^\W*home\W*//i;

    $title = substr( $title, 0, 128 );

    return $title;
}

# find the media source by the reseponse.  recurse back along the response to all of the chained redirects
# to see if we can find the media source by any of those urls.
sub _find_medium_by_response
{
    my ( $dbis, $response ) = @_;

    my $r = $response;

    my $medium;
    while ( $r && !( $medium = MediaWords::DBI::Media::find_medium_by_url( $dbis, decode( 'utf8', $r->request->url ) ) ) )
    {
        $r = $r->previous;
    }

    return $medium;
}

# fetch the url of all missing media and add those media with the titles from the fetched urls
sub _add_missing_media_from_urls
{
    my ( $dbis, $url_media ) = @_;

    my $fetch_urls = [ map { URI->new( $_->{ url } ) } grep { !( $_->{ medium } ) } @{ $url_media } ];

    my $responses = MediaWords::Util::Web::ParallelGet( $fetch_urls );

    for my $response ( @{ $responses } )
    {
        my $original_request = MediaWords::Util::Web->get_original_request( $response );
        my $url              = $original_request->url;

        my $url_media_index = _get_url_medium_index_from_url( $url_media, $url );
        if ( !defined( $url_media_index ) )
        {
            next;
        }

        if ( !$response->is_success )
        {
            $url_media->[ $url_media_index ]->{ message } = "Unable to fetch medium url '$url': " . $response->status_line;
            next;
        }

        my $title = _get_medium_title_from_response( $response );

        my $medium = _find_medium_by_response( $dbis, $response );

        if ( !$medium )
        {
            if ( $medium = $dbis->query( "select * from media where name = ?", encode( 'UTF-8', $title ) )->hash )
            {
                $url_media->[ $url_media_index ]->{ message } =
                  "using existing medium with duplicate title '$title' already in database for '$url'";
            }
            else
            {
                $medium = $dbis->create(
                    'media',
                    {
                        name        => encode( 'UTF-8', $title ),
                        url         => encode( 'UTF-8', $url ),
                        moderated   => 'f',
                        feeds_added => 'f'
                    }
                );
            }
        }

        $url_media->[ $url_media_index ]->{ medium } = $medium;
    }

    # add error message for any url_media that were not found
    # if there's just one missing
    for my $url_medium ( @{ $url_media } )
    {
        if ( !$url_medium->{ medium } )
        {
            $url_medium->{ message } ||= "Unable to find medium for url '$url_medium->{ url }'";
        }
    }
}

# given a list of media sources as returned by _find_media_from_urls, add the tags
# in the tags_string of each medium to that medium
sub _add_media_tags_from_strings
{
    my ( $dbis, $url_media, $global_tags_string ) = @_;

    for my $url_medium ( grep { $_->{ medium } } @{ $url_media } )
    {
        if ( $global_tags_string )
        {
            if ( $url_medium->{ tags_string } )
            {
                $url_medium->{ tags_string } .= ";$global_tags_string";
            }
            else
            {
                $url_medium->{ tags_string } = $global_tags_string;
            }
        }

        for my $tag_string ( split( /;/, $url_medium->{ tags_string } ) )
        {
            my ( $tag_set_name, $tag_name ) = split( ':', lc( $tag_string ) );

            my $tag_sets_id = $dbis->query( "select tag_sets_id from tag_sets where name = ?", lc( $tag_set_name ) )->list;
            if ( !$tag_sets_id )
            {
                $url_medium->{ message } .= " Unable to find tag set '$tag_set_name'";
                next;
            }

            my $tags_id = $dbis->find_or_create( 'tags', { tag => $tag_name, tag_sets_id => $tag_sets_id } )->{ tags_id };
            my $media_id = $url_medium->{ medium }->{ media_id };

            $dbis->find_or_create( 'media_tags_map', { tags_id => $tags_id, media_id => $media_id } );
        }
    }
}

# find the media source by the url or the url with/without the trailing slash
sub find_medium_by_url
{
    my ( $dbis, $url ) = @_;

    my $base_url = $url;

    $base_url =~ m~^([a-z]*)://~;
    my $protocol = $1 || 'http';

    $base_url =~ s~^([a-z]+://)?(www\.)?~~;
    $base_url =~ s~/$~~;

    my $url_permutations =
      [ "$protocol://$base_url", "$protocol://www.$base_url", "$protocol://$base_url/", "$protocol://www.$base_url/" ];

    my $medium =
      $dbis->query( "select * from media where url in (?, ?, ?, ?) order by length(url) desc", @{ $url_permutations } )
      ->hash;

    return $medium;
}

# given a newline separated list of media urls, return a list of hashes in the form of
# { medium => $medium_hash, url => $url, tags_string => $tags_string, message => $error_message }
# the $medium_hash is the existing media source with the given url, or undef if no existing media source is found.
# the tags_string is everything after a space on a line, to be used to add tags to the media source later.
sub find_media_from_urls
{
    my ( $dbis, $urls_string ) = @_;

    my $url_media = [];

    my $urls = [ split( "\n", $urls_string ) ];

    for my $tagged_url ( @{ $urls } )
    {
        my $medium;

        my ( $url, $tags_string ) = ( $tagged_url =~ /^\r*\s*([^\s]*)(?:\s+(.*))?/ );

        if ( $url !~ m~^[a-z]+://~ )
        {
            $url = "http://$url";
        }

        $medium->{ url }         = $url;
        $medium->{ tags_string } = $tags_string;

        if ( $url !~ /$RE{URI}/ )
        {
            $medium->{ message } = "'$url' is not a valid url";
        }

        $medium->{ medium } = MediaWords::DBI::Media::find_medium_by_url( $dbis, $url );

        push( @{ $url_media }, $medium );
    }

    return $url_media;
}

1;
