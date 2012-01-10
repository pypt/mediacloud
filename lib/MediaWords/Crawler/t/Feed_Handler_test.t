#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

use MediaWords::CommonLibs;
use MediaWords::Crawler::FeedHandler;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::More;
use HTML::CruftText;
use Test::Deep;

my $test_cases = [
    {
        test_name    => 'standard_single_item',
        media_id     => 1,
        publish_date => '2012-01-10T06:20:10',
        feed_input   => <<'__END_TEST_CASE__',
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
	xmlns:content="http://purl.org/rss/1.0/modules/content/"
	xmlns:wfw="http://wellformedweb.org/CommentAPI/"
	xmlns:dc="http://purl.org/dc/elements/1.1/"
	xmlns:atom="http://www.w3.org/2005/Atom"
	xmlns:sy="http://purl.org/rss/1.0/modules/syndication/"
	xmlns:slash="http://purl.org/rss/1.0/modules/slash/"
	xmlns:creativeCommons="http://backend.userland.com/creativeCommonsRssModule"
>

<channel>
	<title>David Larochelle&#039;s Blog</title>
	<atom:link href="http://blogs.law.harvard.edu/dlarochelle/feed/" rel="self" type="application/rss+xml" />
	<link>https://blogs.law.harvard.edu/dlarochelle</link>
	<description></description>
	<lastBuildDate>Mon, 09 Jan 2012 06:20:10 +0000</lastBuildDate>

	<language>en</language>
	<sy:updatePeriod>hourly</sy:updatePeriod>
	<sy:updateFrequency>1</sy:updateFrequency>
	<generator>http://wordpress.org/?v=3.2.1</generator>
<creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>
		<item>
		<title>Why Life is Too Short for Spiral Notebooks</title>

		<link>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/</link>
		<comments>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/#comments</comments>
		<pubDate>Mon, 09 Jan 2012 06:20:10 +0000</pubDate>
		<dc:creator>dlarochelle</dc:creator>
				<category><![CDATA[Uncategorized]]></category>

		<guid isPermaLink="false">http://blogs.law.harvard.edu/dlarochelle/?p=350</guid>

		<description>One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible.</description>
			<content:encoded><p>One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible. This post will detail why I’ve switched to using wireless bound notebooks exclusively.</p></content:encoded>
			<wfw:commentRss>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/feed/</wfw:commentRss>
		<slash:comments>0</slash:comments>
	<creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>
	</item>
        </channel>
</rss>
__END_TEST_CASE__
        ,
        test_output => [
            {
                'collect_date' => '2012-01-10T20:03:48',
                'media_id'     => 1,
                'publish_date' => '2012-01-09T06:20:10',
                'url' => 'https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/',
                'title' => 'Why Life is Too Short for Spiral Notebooks',
                'guid'  => 'http://blogs.law.harvard.edu/dlarochelle/?p=350',
                'description' =>
                  'One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible.'
            }
        ]
    },
{
        test_name    => 'no title or time',
        media_id     => 1,
        publish_date => '2012-01-10 06:20:10',
        feed_input   => <<'__END_TEST_CASE__',
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
	xmlns:content="http://purl.org/rss/1.0/modules/content/"
	xmlns:wfw="http://wellformedweb.org/CommentAPI/"
	xmlns:dc="http://purl.org/dc/elements/1.1/"
	xmlns:atom="http://www.w3.org/2005/Atom"
	xmlns:sy="http://purl.org/rss/1.0/modules/syndication/"
	xmlns:slash="http://purl.org/rss/1.0/modules/slash/"
	xmlns:creativeCommons="http://backend.userland.com/creativeCommonsRssModule"
>

<channel>
	<title>David Larochelle&#039;s Blog</title>
	<atom:link href="http://blogs.law.harvard.edu/dlarochelle/feed/" rel="self" type="application/rss+xml" />
	<link>https://blogs.law.harvard.edu/dlarochelle</link>
	<description></description>
	<lastBuildDate>Mon, 09 Jan 2012 06:20:10 +0000</lastBuildDate>

	<language>en</language>
	<sy:updatePeriod>hourly</sy:updatePeriod>
	<sy:updateFrequency>1</sy:updateFrequency>
	<generator>http://wordpress.org/?v=3.2.1</generator>
<creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>
		<item>
		<title>Why Life is Too Short for Spiral Notebooks</title>

		<link>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/</link>
		<comments>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/#comments</comments>
		<dc:creator>dlarochelle</dc:creator>
				<category><![CDATA[Uncategorized]]></category>

		<guid isPermaLink="false">http://blogs.law.harvard.edu/dlarochelle/?p=350</guid>

		<description>One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible.</description>
			<content:encoded><p>One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible. This post will detail why I’ve switched to using wireless bound notebooks exclusively.</p></content:encoded>
			<wfw:commentRss>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/feed/</wfw:commentRss>
		<slash:comments>0</slash:comments>
	<creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>
	</item>
        </channel>
</rss>
__END_TEST_CASE__
        ,
        test_output => [
            {
                'collect_date' => '2012-01-10T20:03:48',
                'media_id'     => 1,
                'publish_date' => '2012-01-10 06:20:10',
                'url' => 'https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/',
                'title' => 'Why Life is Too Short for Spiral Notebooks',
                'guid'  => 'http://blogs.law.harvard.edu/dlarochelle/?p=350',
                'description' =>
                  'One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible.'
            }
        ]
    },
];

plan tests => scalar @{ $test_cases };

foreach my $test_case ( @{ $test_cases } )
{
    my $feed_input = $test_case->{ feed_input };

    say Dumper ( $test_case->{  publish_date } ); 

    my $stories = MediaWords::Crawler::FeedHandler::_get_stories_from_feed_contents_impl(
        $feed_input,
        $test_case->{ media_id },
        $test_case->{  publish_date }
    );

    foreach my $story ( @$stories )
    {
        undef( $story->{ collect_date } );
    }

    my $test_output = $test_case->{ test_output };
    foreach my $element ( @$test_output )
    {
        undef( $element->{ collect_date } );
    }

    cmp_deeply( $stories, $test_case->{ test_output } );

    #say Dumper( $stories );

    # is(
    #     join( "", map { $_ . "\n" } @{ HTML::CruftText::clearCruftText( $test_case->{ test_input } ) } ),
    #     $test_case->{ test_output },
    #     $test_case->{ test_name }
    # );

   # my $result = MediaWords::Crawler::Extractor::score_lines( HTML::CruftText::clearCruftText( $test_case->{ test_input } ),
   #     "__NO_TITLE__" );

    # ok( $result, "title_not_found_test" );
}
