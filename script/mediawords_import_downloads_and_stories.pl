#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::MC_Fork;

use XML::LibXML;
use MIME::Base64;
use Encode;
use Data::Dumper;
use MediaWords::Crawler::Handler;
use Carp;
use Try::Tiny;

sub hash_from_element
{
    my ( $element, $excluded_keys ) = @_;

    say "start hash_from_element ";
    say Dumper( $element );

    try
    {
        say 'starting hash_from_element for ' . $element->nodeName();
    }
    catch
    {
        warning( "error outputing nodeName $_" );
    };

    my @childNodes = $element->childNodes();

    say Dumper ( @childNodes );

    my $node_types = [ map { $_->nodeType } @childNodes ];

    say Dumper ( $node_types );

    my $ret;

    $ret = { map { $_->nodeName() => $_->textContent() } @childNodes };

    say Dumper ( $ret );

    #say 'hash_from_element returning ' . Dumper ( $ret );

    if ( $excluded_keys )
    {
        foreach my $excluded_key ( @$excluded_keys )
        {
            delete( $ret->{ $excluded_key } );
        }
    }

    foreach my $key ( sort keys %{ $ret } )
    {
        if ( !$ret->{ $key } )
        {

            if ( !defined( $ret->{ $key } ) )
            {
                delete( $ret->{ $key } );
                next;
            }

            if ( $ret->{ $key } eq '' )
            {

                #say STDERR "Deleting '$key' ";
                delete( $ret->{ $key } );
            }
        }
    }

    return $ret;
}

sub import_downloads
{
    my ( $xml_file_name ) = @_;

    open my $fh, $xml_file_name || die "Error opening file:$xml_file_name $@";

    my $parser = XML::LibXML->new;

    #my $doc = $parser->parse_fh( $fh, { no_blanks => 1 } );
    my $doc = XML::LibXML->load_xml(
        {
            IO        => $fh,
            no_blanks => 1,
        }
    );

    my $root = $doc->documentElement() || die;

    my $db = MediaWords::DB::connect_to_db;

    my $downloads_processed = 0;

    $DB::single = 2;

    foreach my $child_node ( $root->childNodes() )
    {

        say STDERR "child_node: " . $child_node->nodeName();

        $DB::single = 2;

        my $download = hash_from_element( $child_node, [ qw ( child_stories ) ] );

        #say STDERR $root->toString( 2);
        say STDERR Dumper( $child_node );

        #say STDERR $child_node->toString( 2 );
        #say STDERR Dumper( $download );

        my $old_downloads_id = $download->{ downloads_id };
        delete( $download->{ downloads_id } );

        my $decoded_content = $download->{ encoded_download_content_base_64 }
          && decode_base64( $download->{ encoded_download_content_base_64 } );
        delete( $download->{ encoded_download_content_base_64 } );

        #say STDERR Dumper( $download );

        #exit;

        say STDERR Dumper( $download );

        next if ( '(redundant feed)' eq $decoded_content );    # The download contains no content so don't add it.

        my @child_stories_list = $child_node->getElementsByTagName( "child_stories" );

        die unless ( scalar( @child_stories_list ) == 1 );

        my $child_stories_element = $child_stories_list[ 0 ];

        say "Dumping child stories list";

        say Dumper ( [ @child_stories_list ] );

        say "Dumping child stories element";

        say Dumper ( $child_stories_element );

        my $story_elements = [ $child_stories_element->getElementsByTagName( "story" ) ];

        my $new_stories = [];

        foreach my $story_element ( @{ $story_elements } )
        {

            #say Dumper ( $story_elements );
            my $story = hash_from_element( $story_element, [ qw ( story_downloads ) ] );

            if ( MediaWords::DBI::Stories::is_new( $db, $story ) )
            {

                #say 'new story:';
                #say Dumper( $story );

                push @{ $new_stories }, $story_element;
            }
        }

        #say 'got new stories';
        #say Dumper ( $new_stories );

        my $db_download = $db->create( 'downloads', $download );

        foreach my $story_element ( @$new_stories )
        {

            # dump stories and downloads.

            my $story_hash;

            try
            {
                $DB::single = 2;
                $story_hash = hash_from_element( $story_element, [ qw ( story_downloads ) ] );
                confess 'null story_hash ' unless $story_hash;
            }
            catch
            {
                confess STDERR "error in hash_from_element: $_";
            };

            confess 'null story_hash ' unless $story_hash;

            my $old_stories_id = $story_hash->{ stories_id };

            delete( $story_hash->{ stories_id } );

            MediaWords::Crawler::FeedHandler::_add_story_using_parent_download( $db, $story_hash, $db_download );

            my $db_story;
        }

        exit;

        #TODO find new stories.

        eval {
            MediaWords::Crawler::FeedHandler::handle_feed_content( $db, $db_download, $decoded_content );
            $downloads_processed++;

            say STDERR "Processed $downloads_processed downloads";

            #say STDERR Dumper( $db_download );
        };

        if ( $@ )
        {
            warn $@;

            #say "'$decoded_content'";
            say $old_downloads_id;

            #exit;
        }
    }
}

# fork of $num_processes
sub main
{
    my $xml_file_name = shift( @ARGV );

    die "Must specify file name" unless $xml_file_name;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    import_downloads( $xml_file_name );
}

main();
