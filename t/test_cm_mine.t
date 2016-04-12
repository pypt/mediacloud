use strict;
use warnings;

# basic intergration test for cm spider

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Log::Log4perl qw(:easy);
Log::Log4perl::init( "$FindBin::Bin/../log4perl.conf" );

use English '-no_match_vars';

use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use HTTP::HashServer;
use Readonly;
use Test::More;
use Text::Lorem::More;

use MediaWords::CM::Mine;
use MediaWords::Test::DB;
use MediaWords::Util::SQL;

Readonly my $BASE_PORT => 8890;

Readonly my $NUM_SITES          => 10;
Readonly my $NUM_PAGES_PER_SITE => 10;
Readonly my $NUM_LINKS_PER_PAGE => 5;

Readonly my $CONTROVERSY_PATTERN => 'FOOBARBAZ';

sub get_html_link
{
    my ( $page ) = @_;

    my $lorem = Text::Lorem::More->new();

    if ( int( rand( 3 ) ) )
    {
        return "<a href='$page->{ url }'>" . $lorem->words( 2 ) . "</a>";
    }
    else
    {
        return $page->{ url };
    }
}

sub generate_content_for_site
{
    my ( $site ) = @_;

    my $lorem = Text::Lorem::More->new();

    my $body = $lorem->sentences( 5 );

    return <<HTML;
<html>
<head>
    <title>$site->{ title }</title>
</head>
<body>
    <p>
    $body
    </p>
</body>
</html>
HTML
}

sub generate_content_for_page
{
    my ( $site, $page ) = @_;

    my $lorem = Text::Lorem::More->new();

    my $num_links      = scalar( @{ $page->{ links } } );
    my $num_paragraphs = int( rand( 10 ) ) + $num_links;

    my $paragraphs = [];

    for my $i ( 0 .. $num_paragraphs - 1 )
    {
        my $text = $lorem->sentences( int( rand( 10 ) ) + 1 );
        if ( $i < $num_links )
        {
            my $html_link = get_html_link( $page->{ links }->[ $i ] );
            $text .= " $html_link";
        }

        push( @{ $paragraphs }, $text );
    }

    if ( rand( 2 ) < 1 )
    {
        push( @{ $paragraphs }, $lorem->words( 5 ) . " " . $CONTROVERSY_PATTERN );
        $page->{ matches_controversy } = 1;
    }

    my $body = join( "\n\n", map { "<p>\n$_\n</p>" } @{ $paragraphs } );

    return <<HTML;
<html>
<head>
    <title>$page->{ title }</title>
</head>
<body>
    $body
</body>
</html>
HTML

}

sub generate_content_for_sites
{
    my ( $sites ) = @_;

    for my $site ( @{ $sites } )
    {
        $site->{ content } = generate_content_for_site( $site );

        for my $page ( @{ $site->{ pages } } )
        {
            $page->{ content } = generate_content_for_page( $site, $page );
        }
    }
}

# generate test set of sites
sub get_test_sites()
{
    my $sites = [];
    my $pages = [];

    my $base_port = $BASE_PORT + int( rand( 200 ) );

    for my $site_id ( 0 .. $NUM_SITES - 1 )
    {
        my $port = $base_port + $site_id;

        my $site = {
            port  => $port,
            id    => $site_id,
            url   => "http://localhost:$port/",
            title => "site $site_id"
        };

        my $num_pages = int( rand( $NUM_PAGES_PER_SITE ) ) + 1;
        for my $page_id ( 0 .. $num_pages - 1 )
        {
            my $date = MediaWords::Util::SQL::get_sql_date_from_epoch( time() - ( rand( 365 ) * 86400 ) );

            my $path = "page-$page_id";

            my $page = {
                id          => $page_id,
                path        => "/$path",
                url         => "$site->{ url }$path",
                title       => "page $page_id",
                pubish_date => $date,
                links       => []
            };

            push( @{ $pages },           $page );
            push( @{ $site->{ pages } }, $page );
        }

        push( @{ $sites }, $site );
    }

    for my $page ( @{ $pages } )
    {
        my $num_links = int( rand( $NUM_LINKS_PER_PAGE ) );
        for my $link_id ( 0 .. $num_links - 1 )
        {
            my $linked_page_id = int( rand( scalar( @{ $pages } ) ) );
            push( @{ $page->{ links } }, $pages->[ $linked_page_id ] );
        }
    }

    generate_content_for_sites( $sites );

    return $sites;
}

# add a medium for each site so that the cm spider can find the medium that corresponds to each url
sub add_site_media
{
    my ( $db, $sites ) = @_;

    for my $site ( @{ $sites } )
    {
        $site->{ medium } = $db->create(
            'media',
            {
                url       => $site->{ url },
                name      => $site->{ title },
                moderated => 't'
            }
        );
    }
}

sub start_hash_servers
{
    my ( $sites ) = @_;

    my $hash_servers = [];

    for my $site ( @{ $sites } )
    {
        my $site_hash = {};

        $site_hash->{ '/' } = $site->{ content };

        map { $site_hash->{ $_->{ path } } = $_->{ content } } @{ $site->{ pages } };

        my $hs = HTTP::HashServer->new( $site->{ port }, $site_hash );

        DEBUG( sub { "starting hash server $site->{ id }" } );

        $hs->start( 0 );

        push( @{ $hash_servers }, $hs );
    }

    # wait for the hash servers to start
    sleep( 1 );

    return $hash_servers;
}

sub test_page
{
    my ( $label, $url, $expected_content ) = @_;

    my $got_content = LWP::Simple::get( $url );

    is( $got_content, $expected_content, "simple page test: $label" );
}

sub test_pages
{
    my ( $sites ) = @_;

    for my $site ( @{ $sites } )
    {
        DEBUG( sub { "testing pages for site $site->{ id }" } );
        test_page( "site $site->{ id }", $site->{ url }, $site->{ content } );

        map { test_page( "page $site->{ id } $_->{ id }", $_->{ url }, $_->{ content } ) } @{ $site->{ pages } };
    }
}

sub seed_unlinked_urls
{
    my ( $db, $controversy, $sites ) = @_;

    my $all_pages = [];
    map { push( @{ $all_pages }, @{ $_->{ pages } } ) } @{ $sites };

    my $non_seeded_url_lookup = {};
    for my $page ( @{ $all_pages } )
    {
        if ( $page->{ matches_controversy } )
        {
            map { $non_seeded_url_lookup->{ $_->{ url } } = 1 } @{ $page->{ links } };
        }
    }

    my $seed_pages = [];
    for my $page ( @{ $all_pages } )
    {
        if ( $non_seeded_url_lookup->{ $page->{ url } } )
        {
            DEBUG( "non seeded url: $page->{ url }" );
        }
        else
        {
            DEBUG( "seed url: $page->{ url }" );
            push( @{ $seed_pages }, $page );
        }
    }

    for my $seed_page ( @{ $all_pages } )
    {
        $db->create(
            'controversy_seed_urls',
            {
                controversies_id => $controversy->{ controversies_id },
                url              => $seed_page->{ url }
            }
        );
    }
}

sub create_controversy
{
    my ( $db, $sites ) = @_;

    my $controversy_tag_set = $db->create( 'tag_sets', { name => 'test controversy' } );

    my $controversy = $db->create(
        'controversies',
        {
            name                    => 'test controversy',
            description             => 'test controversy',
            pattern                 => $CONTROVERSY_PATTERN,
            solr_seed_query         => 'stories_id:0',
            solr_seed_query_run     => 't',
            controversy_tag_sets_id => $controversy_tag_set->{ controversy_tag_sets_id }
        }
    );

    $db->create(
        'controversy_dates',
        {
            controversies_id => $controversy->{ controversies_id },
            start_date       => '2000-01-01',
            end_date         => '2030-01-01',
            boundary         => 't'
        }
    );

    seed_unlinked_urls( $db, $controversy, $sites );

    # avoid race condition in CM::Mine
    $db->create( 'tag_sets', { name => 'extractor_version' } );

    return $controversy;
}

sub test_controversy_stories
{
    my ( $db, $controversy, $sites ) = @_;

    my $controversy_stories = $db->query( <<SQL, $controversy->{ controversies_id } )->hashes;
select cs.*, s.*
    from controversy_stories cs
        join stories s on ( s.stories_id = cs.stories_id )
    where cs.controversies_id = ?
SQL

    my $all_pages = [];
    map { push( @{ $all_pages }, @{ $_->{ pages } } ) } @{ $sites };

    say STDERR "ALL PAGES: " . scalar( @{ $all_pages } );

    my $controversy_pages = [ grep { $_->{ matches_controversy } } @{ $all_pages } ];

    is(
        scalar( @{ $controversy_stories } ),
        scalar( @{ $controversy_pages } ),
        "number of controversy stories equals number of controversy matching pages"
    );

    my $controversy_pages_lookup = {};
    map { $controversy_pages_lookup->{ $_->{ url } } = $_ } @{ $controversy_stories };

    for my $controversy_story ( @{ $controversy_stories } )
    {
        ok( $controversy_pages_lookup->{ $controversy_story->{ url } },
            "controversy story found for controversy page '$controversy_story->{ url }'" );
    }

}

sub test_spider_results
{
    my ( $db, $controversy, $sites ) = @_;

    test_controversy_stories( $db, $controversy, $sites );
}

sub test_spider
{
    my ( $db ) = @_;

    # we want repeatable tests
    srand( 1 );

    my $sites = get_test_sites();

    add_site_media( $db, $sites );

    my $hash_servers = start_hash_servers( $sites );

    test_pages( $sites );

    my $controversy = create_controversy( $db, $sites );

    my $mine_options = { cache_broken_downloads => 0, import_only => 0, skip_outgoing_foreign_rss_links => 0 };

    MediaWords::CM::Mine::mine_controversy( $db, $controversy, $mine_options );

    test_spider_results( $db, $controversy, $sites );

    map { $_->stop } @{ $hash_servers };

    done_testing();
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_spider( $db );
        }
    );
}

main();
