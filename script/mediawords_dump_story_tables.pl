#!/usr/bin/env perl

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use DBIx::Simple::MediaWords;
use TableCreationUtils;
use File::Temp qw/ tempfile tempdir /;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Copy;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use MediaWords::Controller::Dashboard;
use IO::Compress::Zip qw(:all);

use Getopt::Long;
use Date::Parse;
use Data::Dumper;
use Carp;
use Dir::Self;
use Cwd;

my $_stories_id_window_size = 1000;

# base dir
my $_base_dir = __DIR__ . '/..';

# if set by the --dashboards option, only dump stories in media sets belonging to the given dashboards
my $_dump_dashboards;

sub get_max_stories_id
{
    my ( $dbh ) = @_;

    my $max_stories_id_row = $dbh->query( "select max(stories_id) as max_id from story_sentence_words" );

    my $max_stories_id = $max_stories_id_row->hash()->{ max_id };

    return $max_stories_id;
}

sub get_min_stories_id
{
    my ( $dbh ) = @_;

    my $min_stories_id_row = $dbh->query( "select min(stories_id) as min_id from story_sentence_words" );

    my $min_stories_id = $min_stories_id_row->hash()->{ min_id };

    return $min_stories_id;
}

sub scroll_stories_id_window
{
    my ( $_stories_id_start, $_stories_id_stop, $max_stories_id ) = @_;

    $_stories_id_start = $_stories_id_stop + 1;
    $_stories_id_stop  = $_stories_id_start + $_stories_id_window_size - 1;

    $_stories_id_stop = min( $_stories_id_stop, $max_stories_id );

    return ( $_stories_id_start, $_stories_id_stop );
}

sub isNonnegativeInteger
{
    my ( $val ) = @_;

    return int( $val ) eq $val;
}

# return an in clause for a table identified by $table_name with a media_id that belongs
# to a media_set in one of the $_dump_dashboards dashboards.
# if $_dump_dashboards is empty, return an empty string.
sub get_dashboards_clause
{
    my ( $table_name ) = @_;

    return '' unless ( defined( $_dump_dashboards ) && @{ $_dump_dashboards } );

    my $dashboards_list = join( ',', @{ $_dump_dashboards } );

    my $clause =
      "and ${ table_name }.media_id in " .
      "  ( select msmm.media_id from media_sets_media_map msmm, dashboard_media_sets dms " .
      "      where msmm.media_sets_id = dms.media_sets_id and dms.dashboards_id in ( $dashboards_list ) )";

    return $clause;
}

sub dump_story_words
{

    my ( $dbh, $dir, $first_dumped_id, $last_dumped_id ) = @_;

    if ( !defined( $first_dumped_id ) )
    {
        $first_dumped_id = 0;
    }

    if ( !defined( $last_dumped_id ) )
    {
        my $max_stories_id = get_max_stories_id( $dbh );
        $last_dumped_id = $max_stories_id;
    }

    my $file_name = "$dir/story_words_" . $first_dumped_id . "_$last_dumped_id" . ".csv";
    open my $output_file, ">", $file_name
      or die "Can't open $file_name $@";

    my $dashboards_clause = get_dashboards_clause( 'story_sentence_words' );

    my $select_query = <<"EOF";
        SELECT stories_id,
               media_id,
               publish_day,
               stem,
               term,
               SUM(stem_count) AS count
        FROM story_sentence_words
        WHERE stories_id >= ?
          AND stories_id <= ?
          $dashboards_clause
        GROUP BY stories_id,
                 media_id,
                 publish_day,
                 stem,
                 term
        ORDER BY stories_id,
                 term
EOF

    $dbh->query_csv_dump( $output_file, " $select_query  limit 0 ", [ 0, 0 ], 1 );

    my $_stories_id_start = $first_dumped_id;
    my $_stories_id_stop  = $_stories_id_start + $_stories_id_window_size;

    while ( $_stories_id_start <= $last_dumped_id )
    {
        $dbh->query_csv_dump( $output_file, " $select_query ", [ $_stories_id_start, $_stories_id_stop ], 0 );

        last if ( $_stories_id_stop ) >= $last_dumped_id;

        ( $_stories_id_start, $_stories_id_stop ) =
          scroll_stories_id_window( $_stories_id_start, $_stories_id_stop, $last_dumped_id );
        print STDERR "story_id windows: $_stories_id_start -- $_stories_id_stop   (max_dumped_id: " .
          $last_dumped_id . ")  -- " .
          localtime() . "\n";

    }

    return [ $first_dumped_id, $last_dumped_id ];
}

sub dump_stories
{
    my ( $dbh, $dir, $first_dumped_id, $last_dumped_id ) = @_;

    my $file_name = "$dir/stories_" . $first_dumped_id . "_$last_dumped_id" . ".csv";
    open my $output_file, ">", "$file_name"
      or die "Can't open $file_name: $@";

    my $dashboards_clause = get_dashboards_clause( 'stories' );

    $dbh->query_csv_dump(
        $output_file,
        " select stories_id, media_id, url, guid, title, publish_date, collect_date from stories " .
          "   where stories_id >= ? and stories_id <= ? $dashboards_clause order by stories_id",
        [ $first_dumped_id, $last_dumped_id ],
        1
    );
}

sub dump_weekly_words
{
    my ( $dbh, $dir, $first_dumped_id, $last_dumped_id ) = @_;

    my $file_name = "$dir/weekly_words_" . $first_dumped_id . "_$last_dumped_id" . ".csv";
    open my $output_file, ">", "$file_name"
      or die "Can't open $file_name: $@";

    my $dashboards_clause         = get_dashboards_clause( 'weekly_words' );
    my $stories_dashboards_clause = get_dashboards_clause( 'stories' );

    $dbh->query_csv_dump(
        $output_file,
        " select * from weekly_words where publish_week in                                    " .
          " (select distinct (date_trunc('week', publish_date)::date ) as publish_week from stories" .
          " where stories_id >= ? and stories_id <=? $stories_dashboards_clause order by publish_week) " .
          "    $dashboards_clause order by weekly_words_id ",
        [ $first_dumped_id, $last_dumped_id ],
        1
    );
}

sub dump_total_weekly_words
{
    my ( $dbh, $dir, $first_dumped_id, $last_dumped_id ) = @_;

    my $file_name = "$dir/total_weekly_words_" . $first_dumped_id . "_$last_dumped_id" . ".csv";
    open my $output_file, ">", "$file_name"
      or die "Can't open $file_name: $@";

    my $dashboards_clause         = get_dashboards_clause( 'total_weekly_words' );
    my $stories_dashboards_clause = get_dashboards_clause( 'stories' );

    $dbh->query_csv_dump(
        $output_file,
        " select * from total_weekly_words where publish_week in                                    " .
          " (select distinct (date_trunc('week', publish_date)::date ) as publish_week from stories" .
          " where stories_id >= ? and stories_id <=? $stories_dashboards_clause order by publish_week) " .
          "   $dashboards_clause order by total_weekly_words_id ",
        [ $first_dumped_id, $last_dumped_id ],
        1
    );
}

sub dump_media
{
    my ( $dbh, $dir ) = @_;

    my $file_name = "$dir/media.csv";
    open my $output_file, ">", "$file_name"
      or die "Can't open $file_name: $@";

    my $dashboards_clause = get_dashboards_clause( 'media' );

    $dbh->query_csv_dump( $output_file,
        " select media_id, url, name from media where 1=1 $dashboards_clause order by media_id",
        [], 1 );
}

sub dump_media_sets
{
    my ( $dbh, $dir ) = @_;

    my $file_name = "$dir/media_sets.csv";
    open my $output_file, ">", "$file_name"
      or die "Can't open $file_name: $@";

    my $dashboards_clause = get_dashboards_clause( 'msmm' );

    $dbh->query_csv_dump(
        $output_file, "select ms.media_sets_id, ms.name, ms.set_type, msmm.media_id
  from media_sets ms, media_sets_media_map msmm
  where ms.media_sets_id = msmm.media_sets_id $dashboards_clause
    and ms.include_in_dump order by media_sets_id, media_id, ms.set_type", [], 1
    );
}

sub _current_date
{
    my $ret = localtime();

    $ret =~ s/ /_/g;

    return $ret;
}

sub _get_time_from_file_name
{
    my ( $file_name ) = @_;

    $file_name =~ /media_.*dump_(.*)_\d+_(\d+)\.zip/;
    my $date = $1;
    $date =~ s/_/ /g;
    return str2time( $date );
}

sub _get_last_story_id_from_file_name
{
    my ( $file_name ) = @_;

    $file_name =~ /media_.*dump_(.*)_\d+_(\d+)\.zip/;
    my $stories_id = $2;

    return $stories_id;
}

sub main
{

    my $incremental;
    my $full;
    my $dashboards;
    my $dumpdir;

    my $usage = "mediawprds_dump_story_tables.pl <--incremental| | --full> [ --dashboard ]";
    GetOptions(
        'incremental'  => \$incremental,
        'full'         => \$full,
        'dashboard=s@' => \$dashboards,
        'dumpdir=s'    => \$dumpdir
    ) or die "$usage\n";

    die $usage unless $incremental || $full;
    die $usage if $incremental && $full;

    $full = !$incremental;
    $_dump_dashboards = $dashboards if ( $dashboards && @{ $dashboards } );

    my $config = MediaWords::Util::Config::get_config;

    #my $data_dir = $config->{ mediawords }->{ data_dir };

    my $data_dir = $dumpdir ? $dumpdir : $_base_dir . "/root/include/data_dumps";

    mkdir( $data_dir );

    my $temp_dir_path = $config->{ mediawords }->{ data_dump_tmp_dir };

    $temp_dir_path //= $data_dir;

    my $temp_dir = tempdir( DIR => $temp_dir_path, CLEANUP => 1 );

    my $current_date = _current_date();

    my $dump_name;

    if ( $full )
    {
        $dump_name = 'media_word_story_full_dump_';
    }
    else
    {
        $dump_name = 'media_word_story_incremental_dump_';
    }
    $dump_name .= $current_date;

    my $dir = $temp_dir . "/$dump_name";

    mkdir( $dir ) or die "$@";

    my $dbh = MediaWords::DB::connect_to_db;

    my $stories_id_start;

    if ( $full )
    {
        $stories_id_start = get_min_stories_id( $dbh );
    }
    else
    {

        my $existing_dump_files = MediaWords::Controller::Dashboard::get_data_dump_file_list( $data_dir );
        say STDERR Dumper( $existing_dump_files );
        say STDERR Dumper(
            [
                map { $_ . ' -- ' . _get_time_from_file_name( $_ ) . ' ' . _get_last_story_id_from_file_name( $_ ); }
                  @$existing_dump_files
            ]
        );

        #exit;
        my $previous_max = max( map { _get_last_story_id_from_file_name( $_ ); } @$existing_dump_files );

        $stories_id_start = $previous_max + 1;
    }

    my $last_dumped_id = get_max_stories_id( $dbh );

    say "Starting dump_media";

    dump_media( $dbh, $dir );

    say "Starting dump_media_sets";

    dump_media_sets( $dbh, $dir );

    say "Starting dump_stories";

    dump_stories( $dbh, $dir, $stories_id_start, $last_dumped_id );

    my $existing_dump_files = MediaWords::Controller::Dashboard::get_data_dump_file_list( $data_dir );
    say STDERR Dumper( $existing_dump_files );
    say STDERR Dumper(
        [
            map { $_ . ' -- ' . _get_time_from_file_name( $_ ) . ' ' . _get_last_story_id_from_file_name( $_ ); }
              @$existing_dump_files
        ]
    );

    #exit;

    say "Starting dump_story_words";

    my $dumped_stories = dump_story_words( $dbh, $dir, $stories_id_start, $last_dumped_id );

    if ( $full )
    {
        say "Starting dump_weekly_words";
        dump_weekly_words( $dbh, $dir, $stories_id_start, $last_dumped_id );
        say "Starting dump_total_weekly_words";
        dump_total_weekly_words( $dbh, $dir, $stories_id_start, $last_dumped_id );
    }

    $dbh->disconnect;

    my $zip = Archive::Zip->new();

    # my $dir_member = $zip->addTree( "$temp_dir" );

    # Save the Zip file

    my $dump_zip_file_name = $dump_name . '_' . $dumped_stories->[ 0 ] . '_' . $dumped_stories->[ 1 ];

    if ( defined( $_dump_dashboards ) && @{ $_dump_dashboards } )
    {
        $dump_zip_file_name .= '_' . join( '-', @{ $_dump_dashboards } );
    }

    my $tmp_zip_file_path = "/$data_dir/tmp_$dump_zip_file_name" . ".zip";

    # unless ( $zip->writeToFileNamed( $tmp_zip_file_path ) == AZ_OK )
    # {
    #     die 'write error';
    # }

    {
        my $old_dir = getcwd();
        chdir( $temp_dir );

        my @files = <*/*>;

        say Dumper( [ @files ] );

        zip \@files =>, "$tmp_zip_file_path", Zip64 => 1 or die "Cannot create zip file: $ZipError\n";

        chdir( $old_dir );
    }

    move( $tmp_zip_file_path, "/$data_dir/$dump_zip_file_name" . ".zip" ) || die "Error renaming file $@";

    #move( $tmp_zip_file_path . '2', "/$data_dir/$dump_zip_file_name" . ".zip_2" ) || die "Error renaming file $@";

    say STDERR "Dump completed";
    say "Dump completed";
}

main();
