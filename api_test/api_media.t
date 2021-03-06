use strict;
use warnings;
use utf8;

BEGIN { $ENV{ DIFF_OUTPUT_UNICODE } = 1 }

use Test::More tests => 26;
use Test::Differences;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;

    use Catalyst::Test ( 'MediaWords' );
    use MediaWords;
}

$ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;

use Test::Differences;
use Test::Deep;

require Test::NoWarnings;

use Data::Dumper;

use MediaWords::Crawler::Engine;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::Test::DB;
use MediaWords::Test::Data;
use MediaWords::Test::LocalServer;
use DBIx::Simple::MediaWords;
use MediaWords::StoryVectors;
use LWP::UserAgent;
use JSON;
use URI;
use URI::QueryParam;

use Data::Sorting qw( :basics :arrays :extras );
use Readonly;

Readonly my $TEST_API_KEY => 'f66a50230d54afaf18822808aed649f1d6ca72b08fb06d5efb6247afe9fbae52';

sub _api_request_url($;$)
{
    my ( $path, $params ) = @_;

    my $uri = URI->new( $path );
    $uri->query_param( 'key' => $TEST_API_KEY );

    if ( $params )
    {
        foreach my $key ( keys %{ $params } )
        {
            $uri->query_param( $key => $params->{ $key } );
        }
    }

    return $uri->as_string;
}

sub test_media
{
    my ( $db ) = @_;

    my $urls = [ { path => '/api/v2/media/single/1' }, { path => '/api/v2/media/list/', params => { 'rows' => 1 } }, ];

    foreach my $base_url ( @{ $urls } )
    {
        my $url = _api_request_url( $base_url->{ path }, $base_url->{ params } );

        my $response = request( $url );

        ok( $response->is_success, 'Request should succeed' );

        my $actual_response = decode_json( $response->decoded_content() );

        my $expected_response = [
            {
                'media_id'          => 1,
                'media_source_tags' => [
                    {
                        'tag_sets_id'     => 1,
                        'show_on_stories' => undef,
                        'tags_id'         => 17,
                        'description'     => undef,
                        'show_on_media'   => undef,
                        'tag_set'         => 'collection',
                        'tag'             => 'cc',
                        'label'           => undef
                    },
                    {
                        'tag_sets_id'     => 1,
                        'show_on_stories' => undef,
                        'tags_id'         => 18,
                        'description'     => undef,
                        'show_on_media'   => undef,
                        'tag_set'         => 'collection',
                        'tag'             => 'news',
                        'label'           => undef
                    }
                ],
                'name' => 'Wikinews, the free news source',
                'url'  => 'http://en.wikinews.org/wiki/Main_Page',
            }
        ];

        cmp_deeply( $actual_response, $expected_response, "response format mismatch for $url" );

        foreach my $medium ( @{ $expected_response } )
        {
            my $media_id = $medium->{ media_id };

            $response = request( _api_request_url( '/api/v2/feeds/list', { media_id => $media_id } ) );
            ok( $response->is_success, 'Request should succeed' );

            if ( !$response->is_success )
            {
                say STDERR Dumper( $response->decoded_content() );
            }

            my $expected_feed = [
                {
                    'media_id'  => 1,
                    'feed_type' => 'syndicated',
                    'name'      => 'English Wikinews Atom feed.',
                    'url' =>
'http://en.wikinews.org/w/index.php?title=Special:NewsFeed&feed=atom&categories=Published&notcategories=No%20publish%7CArchived%7CAutoArchived%7Cdisputed&namespace=0&count=30&hourcount=124&ordermethod=categoryadd&stablepages=only',
                    'feeds_id' => 1
                }
            ];

            my $feed_actual_response = decode_json( $response->decoded_content() );

            cmp_deeply( $feed_actual_response, $expected_feed, 'response format mismatch for feed' );
        }
    }

}

sub test_tags
{
    my ( $db ) = @_;

    my $urls = [
        { path => '/api/v2/tags/single/4' },
        { path => '/api/v2/tags/list', params => { 'last_tags_id' => 3, 'rows' => 1 } },
        { path => '/api/v2/tags/list', params => { 'search' => 'independent' } },
    ];

    foreach my $base_url ( @{ $urls } )
    {
        my $url = _api_request_url( $base_url->{ path }, $base_url->{ params } );

        my $response = request( $url );

        ok( $response->is_success, 'Request should succeed' );

        my $actual_response = decode_json( $response->decoded_content() );

        my $expected_response = [
            {
                "tag_sets_id"     => 2,
                "show_on_stories" => undef,
                "label"           => "Independent Group",
                "tag"             => "Independent Group",
                "tags_id"         => 4,
                "show_on_media"   => undef,
                "tag_set_name"    => 'media_type',
                "tag_set_label"   => 'Media Type',
                "tag_set_description" =>
                  'High level topology for media sources for use across a variety of different topics',
                "description" =>
"An academic or nonprofit group that is not affiliated with the private sector or government, such as the Electronic Frontier Foundation or the Center for Democracy and Technology)"
            }
        ];

        cmp_deeply( $actual_response, $expected_response, "response format mismatch for $url" );
    }
}

sub test_stories_public
{
    my ( $db ) = @_;

    my $url = _api_request_url(
        '/api/v2/stories_public/list',
        {
            q         => 'sentence:obama',
            rows      => 2,
            sentences => 1,
            text      => 1,
        }
    );

    say STDERR $url;

    my $response = request( $url );

    ok( $response->is_success, 'Request should succeed' );

    if ( !$response->is_success )
    {
        say STDERR $response->decoded_content();
    }

    my $actual_response = decode_json( $response->decoded_content() );

    my $expected_response = [
        {
            'bitly_click_count'    => undef,
            'collect_date'         => '2014-06-02 17:33:04',
            'story_tags'           => [],
            'media_name'           => 'Boing Boing',
            'media_id'             => 2,
            'publish_date'         => '2014-06-02 01:00:59',
            'processed_stories_id' => '67',
            'stories_id'           => 67,
            'url'                  => 'http://boingboing.net/2014/06/01/this-day-in-blogging-history-228.html',
            'guid'                 => 'http://boingboing.net/2014/06/01/this-day-in-blogging-history-228.html',
            'media_url'            => 'http://boingboing.net/',
            'language'             => 'en',
            'title' =>
'This Day in Blogging History: Turkish Spring in Gezi; Obama supports torture-evidence suppression law; Quaker football&#160;cheer',
            'ap_syndicated' => 0
        }
    ];

    cmp_deeply( $actual_response, $expected_response );
}

sub test_stories_non_public
{
    my ( $db ) = @_;

    my $url = _api_request_url(
        '/api/v2/stories/list',
        {
            q         => 'sentence:obama',
            rows      => 2,
            sentences => 1,
            text      => 1,
        }
    );

    say STDERR $url;

    my $response = request( $url );

    ok( $response->is_success, 'Request should succeed' );

    if ( !$response->is_success )
    {
        say STDERR $response->decoded_content();
    }

    my $actual_response = decode_json( $response->decoded_content() );

    my $expected_response = [
        {
            'story_text' => "

 This Day in Blogging History: Turkish Spring in Gezi; Obama supports torture-evidence suppression law; Quaker football cheer





 — FEATURED —



 — COMICS —



 — RECENTLY —



 — FOLLOW US —

  Find us on  Twitter ,  Google+ ,  IRC , and  Facebook . Subscribe to our  RSS feed  or  daily email .



 — POLICIES  —

  Please read our  Terms of Service ,  Privacy Policy , and  Community Guidelines . Except where indicated, Boing Boing is licensed under a Creative Commons License permitting  non-commercial sharing with attribution

  Turkish Spring: Taksim Gezi Park protests in Istanbul:  Taksim Gezi Park in Istanbul is alive with protest at this moment. The action began on May 28, when environmentalists protested plans to remove the park and replace it with a mall, and were met with a brutal police crackdown.

  Obama Supports New Law to Suppress Detainee Torture Photos:  The White House is actively supporting a new bill jointly sponsored by Sens. Lindsey Graham and Joe Lieberman -- called The Detainee Photographic Records Protection Act of 2009 -- that literally has no purpose other than to allow the government to suppress any \"photograph taken between September 11, 2001 and January 22, 2009 relating to the treatment of individuals engaged, captured, or detained after September 11, 2001, by the Armed Forces of the United States in operations outside of the United States.\"

 Knock 'em down, beat 'em senseless, Do it till we reach consensus!

",
            'is_fully_extracted'   => 1,
            'publish_date'         => '2014-06-02 01:00:59',
            'processed_stories_id' => '67',
            'url'                  => 'http://boingboing.net/2014/06/01/this-day-in-blogging-history-228.html',
            'db_row_last_updated'  => '2014-06-02 13:43:15.182044-04',
            'guid'                 => 'http://boingboing.net/2014/06/01/this-day-in-blogging-history-228.html',
            'media_url'            => 'http://boingboing.net/',
            'collect_date'         => '2014-06-02 17:33:04',
            'language'             => 'en',
            'full_text_rss'        => 0,
            'story_tags'           => [],
            'bitly_click_count'    => undef,
            'ap_syndicated'        => 0,

            #     'description'          => '<p>

            # <b>One year ago today</b>

# <a href="http://boingboing.net/2013/06/01/turkish-spring-taksim-gezi-pa.html">Turkish Spring: Taksim Gezi Park protests in Istanbul:</a> Taksim Gezi Park in Istanbul is alive with protest at this moment.</p>',
            'media_id'        => 2,
            'media_name'      => 'Boing Boing',
            'story_sentences' => [
                {
                    'sentence' =>
'This Day in Blogging History: Turkish Spring in Gezi; Obama supports torture-evidence suppression law; Quaker football cheer',
                    'sentence_number'     => 0,
                    'language'            => 'en',
                    'tags'                => [],
                    'media_id'            => 2,
                    'publish_date'        => '2014-06-02 01:00:59',
                    'stories_id'          => '67',
                    'db_row_last_updated' => '2014-06-02 13:43:15.182044-04',
                    'story_sentences_id'  => '998',
                    'is_dup'              => undef
                },
                {
                    'sentence' =>
'Turkish Spring: Taksim Gezi Park protests in Istanbul: Taksim Gezi Park in Istanbul is alive with protest at this moment.',
                    'sentence_number'     => 1,
                    'language'            => 'en',
                    'tags'                => [],
                    'media_id'            => 2,
                    'publish_date'        => '2014-06-02 01:00:59',
                    'stories_id'          => '67',
                    'db_row_last_updated' => '2014-06-02 13:43:15.182044-04',
                    'story_sentences_id'  => '999',
                    'is_dup'              => undef
                },
                {
                    'sentence' =>
'The action began on May 28, when environmentalists protested plans to remove the park and replace it with a mall, and were met with a brutal police crackdown.',
                    'sentence_number'     => 2,
                    'language'            => 'en',
                    'tags'                => [],
                    'media_id'            => 2,
                    'publish_date'        => '2014-06-02 01:00:59',
                    'stories_id'          => '67',
                    'db_row_last_updated' => '2014-06-02 13:43:15.182044-04',
                    'story_sentences_id'  => '1000',
                    'is_dup'              => undef
                },
                {
                    'sentence' =>
'Obama Supports New Law to Suppress Detainee Torture Photos: The White House is actively supporting a new bill jointly sponsored by Sens. Lindsey Graham and Joe Lieberman -- called The Detainee Photographic Records Protection Act of 2009 -- that literally has no purpose other than to allow the government to suppress any "photograph taken between September 11, 2001 and January 22, 2009 relating to the treatment of individuals engaged, captured, or detained after September 11, 2001, by the Armed Forces of the United States in operations outside of the United States."',
                    'sentence_number'     => 3,
                    'language'            => 'en',
                    'tags'                => [],
                    'media_id'            => 2,
                    'publish_date'        => '2014-06-02 01:00:59',
                    'stories_id'          => '67',
                    'db_row_last_updated' => '2014-06-02 13:43:15.182044-04',
                    'story_sentences_id'  => '1001',
                    'is_dup'              => undef
                },
                {
                    'sentence'            => 'Knock \'em down, beat \'em senseless, Do it till we reach consensus!',
                    'sentence_number'     => 4,
                    'language'            => 'en',
                    'tags'                => [],
                    'media_id'            => 2,
                    'publish_date'        => '2014-06-02 01:00:59',
                    'stories_id'          => '67',
                    'db_row_last_updated' => '2014-06-02 13:43:15.182044-04',
                    'story_sentences_id'  => '1002',
                    'is_dup'              => undef
                }
            ],
            'stories_id' => '67',
            'title' =>
'This Day in Blogging History: Turkish Spring in Gezi; Obama supports torture-evidence suppression law; Quaker football&#160;cheer'
        }
    ];

    # Remove volatile values
    for my $response ( $expected_response, $actual_response )
    {
        for my $row ( @{ $response } )
        {
            delete $row->{ 'description' };
            delete $row->{ 'db_row_last_updated' };
            delete $row->{ 'disable_triggers' };

            for my $sentence ( @{ $row->{ 'story_sentences' } } )
            {
                delete $sentence->{ 'db_row_last_updated' };
                delete $sentence->{ 'disable_triggers' };
            }

            # don't worry about small differennces in white space
            $row->{ story_text } = !s/\s+/ /g;
        }
    }

    cmp_deeply( $actual_response, $expected_response );

}

# Test querying for and returning UTF-8 stories / sentences
sub test_stories_utf8()
{
    Readonly my @utf8_strings => (

        # Test story about Tabaré Vázquez; should return single story.
        # ("á" might be treated as ISO 8859-1 by one of the dependency modules)
        'Vázquez',

        # Story about Bishkek
        'Бишкек',
    );

    foreach my $utf8_string ( @utf8_strings )
    {
        my $url = _api_request_url(
            '/api/v2/stories/list/',
            {
                q         => "sentence:$utf8_string",
                sentences => 1,
                text      => 1,
            }
        );

        say STDERR $url;

        my $response = request( $url );

        ok( $response->is_success, 'Request failed; response: ' . $response->decoded_content );

        my $actual_response = decode_json( $response->decoded_content );

        is( scalar( @{ $actual_response } ), 1, "Response for query '$utf8_string' should contain a single story" );

        my $story = $actual_response->[ 0 ];

        like( $story->{ story_text }, qr/\Q$utf8_string\E/, "Story doesn't match for query '$utf8_string'" );

        my $at_least_one_of_sentences_contains_utf8_string = 0;
        foreach my $sentence ( @{ $story->{ story_sentences } } )
        {
            if ( $sentence->{ sentence } =~ qr/\Q$utf8_string\E/ )
            {
                $at_least_one_of_sentences_contains_utf8_string = 1;
                last;
            }
        }

        ok( $at_least_one_of_sentences_contains_utf8_string, "None of the sentences match for query '$utf8_string'" );
    }
}

test_stories_public();
test_stories_non_public();
test_tags();
test_media();
test_stories_utf8();
