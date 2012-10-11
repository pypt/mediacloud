#!/usr/bin/env perl

# run a loop extracting the text of any downloads that have not been extracted yet

# usage: mediawords_extract_text.pl [<num of processes>] [<number of total jobs>] [<number of this job>]
#
# example:
# mediawords_extract_text.pl 20 2 1
# (extracts with 20 total processes, divided into 2 jobs, of which this is the first one)

# number of downloads to fetch at a time
use constant PROCESS_SIZE => 100;

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

# extract, story, and tag downloaded text a slice of downloads.
# downloads are extracted by a total of num_total_jobs processings
# a total of num_total_processes, with a unique 1-indexed job_number
# for each job
sub extract_text
{
    my ( $process_num, $num_total_processes, $num_total_jobs, $job_number ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    my $job_process_num = $process_num + int( ( $num_total_processes / $num_total_jobs ) * ( $job_number - 1 ) );

    while ( 1 )
    {

        #my ( $num_downloads ) = $db->query(
        #    "SELECT count(*) from downloads d " .
        #    "  where d.extracted='f' and d.type='content' and d.state='success' " )->flat;

        my $num_downloads = 0;
        print STDERR "[$process_num, $job_process_num] find new downloads ($num_downloads remaining) ...\n";

        my $downloads = $db->query(
            "SELECT d.* from downloads d " . "  where d.extracted='f' and d.type='content' and d.state='success' " .
              "    and  (( ( d.downloads_id + $job_process_num ) % $num_total_processes ) = 0 ) " . "order by stories_id asc " .
              "  limit " . PROCESS_SIZE );

        # my $downloads = $db->query( "select * from downloads where stories_id = 418981" );
        my $download_found;
        while ( my $download = $downloads->hash() )
        {
            $download_found = 1;

            eval {
                MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download,
                    "$process_num, $job_process_num" );

            };

            if ( $@ )
            {
                say STDERR "[$process_num] extractor error processing download " . $download->{ downloads_id } . ": $@";
                $db->rollback;

                $db->query(
                    "update downloads set state = 'error', error_message = ? where downloads_id = ?",
                    "extractor error: $@",
                    $download->{ downloads_id }
                );
            }
            $db->commit;
        }

        if ( !$download_found )
        {
            print STDERR "[$process_num] no downloads found. sleeping ...\n";
            sleep 60;
        }

    }
}

# fork of $num_processes
sub main
{
    my ( $num_total_processes, $num_total_jobs, $job_number ) = @ARGV;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    $num_total_processes ||= 1;
    $num_total_jobs      ||= 1;
    $job_number          ||= 1;

    # turn off buffering so processes don't write over each other as much
    $| = 1;

    my $num_processes = int( $num_total_processes / $num_total_jobs );

    for ( my $i = 0 ; $i < $num_processes ; $i++ )
    {
        if ( !mc_fork )
        {
            while ( 1 )
            {
                eval {
                    print STDERR "[$i] START\n";
                    extract_text( $i, $num_total_processes, $num_total_jobs, $job_number );
                };
                if ( $@ )
                {
                    print STDERR "[$i] extract_text failed with error: $@\n";
                    print STDERR "[$i] sleeping before restart ...\n";
                    sleep 60;
                }
            }
        }
    }

    while ( wait > -1 )
    {
    }
}

# use Test::LeakTrace;
# leaktrace { main(); };

main();
