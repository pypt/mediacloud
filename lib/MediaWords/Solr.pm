package MediaWords::Solr;

use strict;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

# functions for searching the solr server

use JSON;

use MediaWords::Languages::Language;
use MediaWords::Util::Web;

# execute a query on the solr server using the given params.
# return a hash generated from the json results
sub query
{
    my ( $params ) = @_;

    $params->{ wt } = 'json';
    $params->{ rows } //= 1000000;
    $params->{ df }   //= 'sentence';

    my $url = MediaWords::Util::Config::get_config->{ mediawords }->{ solr_select_url };

    my $ua = MediaWords::Util::Web::UserAgent;

    $ua->timeout( 300 );
    $ua->max_size( undef );

    # print STDERR "executing solr query ...\n";
    # print STDERR Dumper( $params );
    my $res = $ua->post( $url, $params );

    # print STDERR "solr query response received.\n";

    if ( !$res->is_success )
    {
        die( "Error fetching solr response: " . $res->as_string );
    }

    my $json = $res->content;

    my $data;
    eval { $data = decode_json( $json ) };
    if ( $@ )
    {
        die( "Error parsing solr json: $@\n$json" );
    }

    if ( $data->{ error } )
    {
        die( "Error received from solr: '$json'" );
    }

    return $data;
}

# return all of the story ids that match the solr query
sub search_for_stories_ids
{
    my ( $params ) = @_;

    $params = { %{ $params } };

    $params->{ fl } = 'stories_id';

    my $response = query( $params );

    my $stories_id_lookup = {};
    map { $stories_id_lookup->{ $_->{ stories_id } } = 1 } @{ $response->{ response }->{ docs } };

    return [ keys( %{ $stories_id_lookup } ) ];
}

# execute the query and return only the number of documents found
sub get_num_found
{
    my ( $params ) = @_;

    $params = { %{ $params } };
    $params->{ rows } = 0;

    my $res = query( $params );

    return $res->{ response }->{ numFound };
}

# get sorted list of most common words in sentences matching a solr query.  exclude stop words from the
# long_stop_word list.  assumes english stemming and stopwording for now.
sub count_words
{
    my ( $params ) = @_;

    my $ua = MediaWords::Util::Web::UserAgent();

    $ua->timeout( 300 );
    $ua->max_size( undef );

    my $url = MediaWords::Util::Config::get_config->{ mediawords }->{ solr_wc_url };

    my $res = $ua->post( $url, $params );

    die( "error retrieving words from solr: " . $res->as_string ) unless ( $res->is_success );

    my $words = from_json( $res->content, { utf8 => 1 } );

    die( "Unable to parse json" ) unless ( ( ref( $words ) eq 'HASH' ) && ( $words->{ words } ) );

    $words = $words->{ words };

    # only support english for now
    my $language  = MediaWords::Languages::Language::language_for_code( 'en' );
    my $stopstems = $language->get_long_stop_word_stems();

    my $stopworded_words = [];
    for my $word ( @{ $words } )
    {
        next if ( length( $word->{ stem } ) < 3 );

        # we have restem the word because solr uses a different stemming implementation
        my $stem = $language->stem( $word->{ term } )->[ 0 ];

        push( @{ $stopworded_words }, $word ) unless ( $stopstems->{ $stem } );
    }

    return $stopworded_words;
}

1;
