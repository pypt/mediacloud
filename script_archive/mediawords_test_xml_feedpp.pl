#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::DownloadTexts;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use XML::LibXML;
use Data::Dumper;
use Perl6::Say;
use Digest::SHA qw(sha1 sha1_hex sha1_base64);

use MediaWords::CommonLibs;

#use XML::LibXML::CDATASection;
use Encode;
use MIME::Base64;
use Lingua::EN::Sentence::MediaWords;

use XML::FeedPP;

#use XML::LibXML::Enhanced;

# do a test run of the text extractor
sub main
{

    my $content;

    my $dump_file = 'content.txt';

    open CONTENT_FILE, "<", $dump_file;

    while ( <CONTENT_FILE> )
    {
        $content .= $_;
    }

    my $type = 'string';

    my $fp;

    say "starting eval for content:\n$content";

    eval { $fp = XML::FeedPP->new( $content, -type => $type ); };

    say "finished";
}

main();
