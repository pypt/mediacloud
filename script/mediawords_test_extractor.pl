#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use warnings;

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
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::MoreUtils qw( :all);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );

use Data::Dumper;
use MediaWords::Util::HTML;
use MediaWords::Util::ExtractorTest;
use Data::Compare;
use Storable;
use 5.14.2;

my $_re_generate_cache = 0;
my $_test_sentences    = 0;

my $_download_data_load_file;
my $_download_data_store_file;
my $_dont_store_preprocessed_lines;
my $_dump_training_data_csv;

sub _get_required_lines
{
    my ( $line_should_be_in_story ) = @_;

    my @required_lines = grep { $line_should_be_in_story->{ $_ } eq 'required' } keys %{ $line_should_be_in_story };

    return @required_lines;
}

sub _get_optional_lines
{
    my ( $line_should_be_in_story ) = @_;

    my @optional_lines = grep { $line_should_be_in_story->{ $_ } eq 'optional' } keys %{ $line_should_be_in_story };

    return @optional_lines;
}

sub _get_missing_lines
{
    my ( $line_should_be_in_story, $extracted_lines ) = @_;

    my @extracted_lines = @{ $extracted_lines };

    my @required_lines = _get_required_lines( $line_should_be_in_story );
    my @optional_lines = _get_optional_lines( $line_should_be_in_story );

    my @missing_lines = get_unique( [ \@required_lines, \@extracted_lines ] );

    return @missing_lines;
}

sub _get_extra_lines
{
    my ( $line_should_be_in_story, $extracted_lines ) = @_;

    my @extracted_lines = @{ $extracted_lines };

    my @required_lines = _get_required_lines( $line_should_be_in_story );
    my @optional_lines = _get_optional_lines( $line_should_be_in_story );

    my @extra_lines = get_unique( [ \@extracted_lines, get_union_ref( [ \@required_lines, \@optional_lines ] ) ] );

    return @extra_lines;
}

sub _get_non_optional_non_autoexcluded_line_count
{

    my ( $line_should_be_in_story, $line_info ) = @_;

    my @optional_lines = _get_optional_lines( $line_should_be_in_story );

    my $non_autoexcluded = [ grep { !$_->{ auto_excluded } } @{ $line_info } ];

    my $non_autoexcluded_line_numbers = [ map { $_->{ line_number } } @$non_autoexcluded ];

    # say Dumper ( \@optional_lines );
    # say Dumper ( $non_autoexcluded );
    # say Dumper ( $non_autoexcluded_line_numbers );
    # say Dumper ( scalar ( @ $non_autoexcluded_line_numbers ) );

    return scalar( @$non_autoexcluded_line_numbers );
}

sub _get_correctly_included_lines
{
    my ( $line_should_be_in_story, $extracted_lines ) = @_;

    my @extracted_lines = @{ $extracted_lines };

    my @required_lines = _get_required_lines( $line_should_be_in_story );
    my @optional_lines = _get_optional_lines( $line_should_be_in_story );

    my @extra_lines = get_unique( [ \@extracted_lines, get_union_ref( [ \@required_lines, \@optional_lines ] ) ] );

    return @extra_lines;
}

sub get_line_level_extractor_results
{
    my ( $line_should_be_in_story, $extra_lines, $missing_lines, $non_optional_non_autoexclude_line_count ) = @_;

    my $story_line_count = scalar( keys %{ $line_should_be_in_story } );

    my $extra_line_count   = scalar( @{ $extra_lines } );
    my $missing_line_count = scalar( @{ $missing_lines } );

    my $ret = {
        story_line_count                        => $story_line_count,
        extra_line_count                        => $extra_line_count,
        missing_line_count                      => $missing_line_count,
        non_optional_non_autoexclude_line_count => $non_optional_non_autoexclude_line_count,
    };

    return $ret;
}

sub get_character_level_extractor_results
{
    my ( $download, $line_should_be_in_story, $missing_lines, $extra_lines, $correctly_included_lines, $preprocessed_lines,
        $line_info )
      = @_;

    my $extra_line_count   = scalar( @{ $extra_lines } );
    my $missing_line_count = scalar( @{ $missing_lines } );

    my $errors = 0;

    die unless $line_info;

    #say STDERR Dumper ( $line_info );

    #say STDERR "Dumping";

    #say STDERR "correctly_included_lines " . Dumper( $correctly_included_lines );

    #say STDERR Dumper ( [ map { $line_info->[ $_ ]->{html_stripped_text_length } } @$correctly_included_lines ] );
    my $correctly_included_character_length =
      sum( map { $line_info->[ $_ ]->{ html_stripped_text_length } } @$correctly_included_lines );

    my $story_lines_character_length =
      sum( map { $line_info->[ $_ ]->{ html_stripped_text_length } // 0 } keys %{ $line_should_be_in_story } );
    my $missing_lines_character_length =
      sum( map { $line_info->[ $_ ]->{ html_stripped_text_length } // 0 } @$missing_lines );
    my $extra_lines_character_length = sum( map { $line_info->[ $_ ]->{ html_stripped_text_length } // 0 } @$extra_lines );

    $correctly_included_character_length ||= 0;

    $missing_lines_character_length ||= 0;
    $extra_lines_character_length   ||= 0;

    my $ret = {
        story_characters   => $story_lines_character_length,
        extra_characters   => $extra_lines_character_length,
        errors             => $errors,
        missing_characters => $missing_lines_character_length,
        accuracy           => (
            $story_lines_character_length
            ? int(
                ( $extra_lines_character_length + $missing_lines_character_length ) / $story_lines_character_length * 100
              )
            : 0
        ),
    };

    return $ret;
}

sub get_story_level_extractor_results
{
    my ( $download, $line_should_be_in_story, $missing_lines, $extra_lines, $correctly_included_lines, $preprocessed_lines,
        $dbs )
      = @_;

    my $story = $dbs->find_by_id( 'stories', $download->{ stories_id } );

    #say Dumper( $story );

    my $extra_line_sentence_info =
      MediaWords::Util::ExtractorTest::get_sentence_info_for_lines( $extra_lines, $preprocessed_lines, $story, $dbs );

    my $extra_sentences_dedupped     = $extra_line_sentence_info->{ sentences_dupped };
    my $extra_sentences_not_dedupped = $extra_line_sentence_info->{ sentences_not_dupped };
    my $extra_sentences_missing      = $extra_line_sentence_info->{ sentences_missing };

    my $extra_sentences_total = $extra_line_sentence_info->{ sentences_total };

    my $correctly_included_line_sentence_info =
      MediaWords::Util::ExtractorTest::get_sentence_info_for_lines( $correctly_included_lines, $preprocessed_lines, $story,
        $dbs );

    my $correctly_included_sentences_dedupped     = $correctly_included_line_sentence_info->{ sentences_dupped };
    my $correctly_included_sentences_not_dedupped = $correctly_included_line_sentence_info->{ sentences_not_dupped };
    my $correctly_included_sentences_missing      = $correctly_included_line_sentence_info->{ sentences_missing };

    my $correctly_included_sentences_total = $correctly_included_line_sentence_info->{ sentences_total };

    my $missing_line_sentence_info =
      MediaWords::Util::ExtractorTest::get_sentence_info_for_lines( $missing_lines, $preprocessed_lines, $story, $dbs );

    my $missing_sentences_dedupped     = $missing_line_sentence_info->{ sentences_dupped };
    my $missing_sentences_not_dedupped = $missing_line_sentence_info->{ sentences_not_dupped };
    my $missing_sentences_missing      = $missing_line_sentence_info->{ sentences_missing };

    my $missing_sentences_total = $missing_line_sentence_info->{ sentences_total };

    my $ret = {
        extra_sentences_total        => $extra_sentences_total,
        extra_sentences_dedupped     => $extra_sentences_dedupped,
        extra_sentences_not_dedupped => $extra_sentences_not_dedupped,
        extra_sentences_missing      => $extra_sentences_missing,

        missing_sentences_total        => $missing_sentences_total,
        missing_sentences_dedupped     => $missing_sentences_dedupped,
        missing_sentences_not_dedupped => $missing_sentences_not_dedupped,
        missing_sentences_missing      => $missing_sentences_missing,

        correctly_included_sentences_total        => $correctly_included_sentences_total,
        correctly_included_sentences_dedupped     => $correctly_included_sentences_dedupped,
        correctly_included_sentences_not_dedupped => $correctly_included_sentences_not_dedupped,
        correctly_included_sentences_missing      => $correctly_included_sentences_missing,
    };

    return $ret;
}

sub compare_extraction_with_training_data
{
    my ( $line_should_be_in_story, $extracted_lines, $download, $preprocessed_lines, $dbs, $line_info ) = @_;

    #say STDERR Dumper( $line_info );

    my @extracted_lines = @{ $extracted_lines };

    my @missing_lines = _get_missing_lines( $line_should_be_in_story, $extracted_lines );

    my @extra_lines = _get_extra_lines( $line_should_be_in_story, $extracted_lines );

    my @correctly_included_lines = _get_correctly_included_lines( $line_should_be_in_story, $extracted_lines );

    my $missing_lines            = \@missing_lines;
    my $extra_lines              = \@extra_lines;
    my $correctly_included_lines = \@correctly_included_lines;

    my $non_optional_non_autoexcluded_line_count =
      _get_non_optional_non_autoexcluded_line_count( $line_should_be_in_story, $line_info );

    my $line_level_results = get_line_level_extractor_results( $line_should_be_in_story, $extra_lines, $missing_lines,
        $non_optional_non_autoexcluded_line_count );

    my $character_level_results =
      get_character_level_extractor_results( $download, $line_should_be_in_story, $missing_lines, $extra_lines,
        $correctly_included_lines, $preprocessed_lines, $line_info );

    my $sentence_level_results = {};

    if ( $_test_sentences )
    {
        $sentence_level_results =
          get_story_level_extractor_results( $download, $line_should_be_in_story, $missing_lines, $extra_lines,
            \@correctly_included_lines, $preprocessed_lines, $dbs );
    }

    my $ret = { %{ $line_level_results }, %{ $character_level_results }, %{ $sentence_level_results }, };

    return $ret;
}

sub store_test_in_xml_file
{
    my ( $line_should_be_in_story, $line_info ) = @_;

    my $stored_object = {
        line_should_be_in_story => $line_should_be_in_story,
        line_info               => $line_info
    };

    #store ( $stored_object, '/tmp/foo');
    #retreive
}

sub analyze_download
{
    my ( $download, my $dbs ) = @_;
    my $preprocessed_lines = MediaWords::Util::ExtractorTest::get_preprocessed_content_lines_for_download( $download );

    my $line_info = MediaWords::Util::ExtractorTest::get_line_analysis_info( $download, $dbs, $preprocessed_lines );

    my $line_should_be_in_story = MediaWords::Util::ExtractorTest::get_lines_that_should_be_in_story( $download, $dbs );

    my $ret = {
        download                => $download,
        line_info               => $line_info,
        preprocessed_lines      => $preprocessed_lines,
        line_should_be_in_story => $line_should_be_in_story,
    };

    return $ret;
}

my $chldout;
my $chldin;
my $pid;
use IPC::Open2;

sub pipe_to_streaming_model
{
    my ( $feature_string ) = @_;

    die unless $feature_string;

    if ( !defined( $chldout ) )
    {
        my $script_path =
          '~/ML_code/apache-opennlp-1.5.2-incubating-src/opennlp-maxent/samples/sports_dev/run_predict_stream_input.sh';

        #my $model_path = 'training_data_features_top_1000_unigrams_2_prior_states_MaxEntModel_Iterations_1500.txt';
        my $model_path = 'training_data_features_top_1000_unigrams_no_prior_states_MaxEntModel_Iterations_1000.txt';

        my $cmd = "$script_path $model_path";

        say STDERR "Starting cmd:\n$cmd";

        $pid = open2( $chldout, $chldin, "$cmd" );

        use POSIX ":sys_wait_h";

        sleep 2;

        my $reaped_pid = waitpid( $pid, WNOHANG );

        die if ( $reaped_pid == $pid );
    }

    #say STDERR "sending '$feature_string'";

    say $chldin $feature_string;

    my $string = <$chldout>;

    my $reaped_pid = waitpid( $pid, WNOHANG );

    die $string if ( $reaped_pid == $pid );

    my $prob_strings = [ split /\s+/, $string ];

    #say Dumper( $prob_strings );

    my $prob_hash = {};

    foreach my $prob_string ( @{ $prob_strings } )
    {
        $prob_string =~ /([a-z]+)\[([0-9.]+)\]/;

        die "Invalid prob string '$prob_string' from '$string'" unless defined( $1 ) && defined( $2 );

        $prob_hash->{ $1 } = $2;

    }

    return $prob_hash;
}

sub get_extracted_line_with_maxent
{
    my ( $line_infos, $preprocessed_lines ) = @_;

    my $ea = each_arrayref( $line_infos, $preprocessed_lines );

    my $extracted_lines = [];

    my $last_in_story_line;

    my $line_num = 0;

    #TODO DRY out this code so it doesn't duplicate mediawords_extractor_test_to_features.pl
    my $previous_states = [ qw ( prestart 'start' ) ];

    while ( my ( $line_info, $line_text ) = $ea->() )
    {

        my $prior_state_string = join '_', @$previous_states;
        $line_info->{ "priors_$prior_state_string" } = 1;
        if ( $previous_states->[ 1 ] eq 'auto_excluded' )
        {
            $line_info->{ previous_line_auto_excluded } = 1;
        }

        shift $previous_states;

        if ( $line_info->{ auto_excluded } == 1 )
        {
            push $previous_states, 'auto_excluded';
            next if $line_info->{ auto_excluded } == 1;
        }

        my $line_number = $line_info->{ line_number };

        if ( defined( $last_in_story_line ) )
        {
            $line_info->{ distance_from_previous_in_story_line } = $line_number - $last_in_story_line;
        }

        MediaWords::Crawler::AnalyzeLines::add_additional_features( $line_info, $line_text );

        my $feature_string = MediaWords::Crawler::AnalyzeLines::get_feature_string_from_line_info( $line_info, $line_text );

        #say STDERR "got feature_string: $feature_string";

        my $model_result = pipe_to_streaming_model( $feature_string );

        #say STDERR Dumper( $model_result );

        my $prediction = reduce { $model_result->{ $a } > $model_result->{ $b } ? $a : $b } keys %{ $model_result };

        if ( $model_result->{ excluded } < 0.85 )
        {
            push $extracted_lines, $line_info->{ line_number };
            $last_in_story_line = $line_number;

            #say STDERR "including line because of exclude prob:  $model_result->{ excluded } ";
        }
        else
        {

            #say STDERR "Excluded line because of exclude prob:  $model_result->{ excluded } ";
        }

        push $previous_states, $prediction;

        #say Dumper( $model_result );
    }

    return $extracted_lines;
}

sub processDownload
{
    ( my $analyzed_download, my $dbs ) = @_;

    my $download           = $analyzed_download->{ download };
    my $line_info          = $analyzed_download->{ line_info };
    my $preprocessed_lines = $analyzed_download->{ preprocessed_lines };

    my $line_should_be_in_story = $analyzed_download->{ line_should_be_in_story };

    my $scores = MediaWords::Crawler::HeuristicLineScoring::_score_lines_with_line_info( $line_info );
    my @extracted_lines = map { $_->{ line_number } } grep { $_->{ is_story } } @{ $scores };

    my $extracted_lines = \@extracted_lines;

    #$extracted_lines = get_extracted_line_with_maxent( $line_info, $preprocessed_lines );

    #say Dumper ( $extracted_lines );
    #exit;

    return compare_extraction_with_training_data( $line_should_be_in_story, $extracted_lines, $download, $preprocessed_lines,
        $dbs, $line_info );
}

sub analyze_downloads
{
    my ( $downloads ) = @_;

    my @downloads = @{ $downloads };

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $dbs = MediaWords::DB::connect_to_db();

    my $analyzed_downloads = [];

    for my $download ( @downloads )
    {
        my $download_result = analyze_download( $download, $dbs );

        push( @{ $analyzed_downloads }, $download_result );
    }

    return $analyzed_downloads;
}

sub dump_training_data_csv
{
    my ( $analyzed_downloads ) = @_;

    say "starting dump_training_data_csv";

    say "shuffling analyzed_downloads";

    srand( 12345 );

    $analyzed_downloads = [ shuffle @{ $analyzed_downloads } ];

    say " dump_training_data_csv add line should be in story";

    foreach my $analyzed_download ( @{ $analyzed_downloads } )
    {

        my $line_info = $analyzed_download->{ line_info };

        my $line_should_be_in_story = $analyzed_download->{ line_should_be_in_story };

        my $downloads_id = $analyzed_download->{ download }->{ downloads_id };
        foreach my $line ( @{ $line_info } )
        {
            $line->{ in_story } = defined( $line_should_be_in_story->{ $line->{ line_number } } ) ? 1 : 0;
            $line->{ training_result } = $line_should_be_in_story->{ $line->{ line_number } } // 'exclude';
            $line->{ downloads_id } = $downloads_id;
        }

    }

    say " dump_training_data_csv creating all_line_infos";

    #$analyzed_downloads =  [ ( @{ $analyzed_downloads } [ 0 ... 2000 ] ) ];

    my @all_line_infos = map { @{ $_->{ line_info } } } ( @{ $analyzed_downloads } );

    #say Dumper ( [ @all_line_infos ] );

    say " dump_training_data_csv creating lines_not_autoexcluded";

    my @lines_not_autoexcluded = grep { !$_->{ auto_excluded } } @all_line_infos;

    #say Dumper ( [ @lines_not_autoexcluded ] );

    use Class::CSV;

    my $first_line = [ @lines_not_autoexcluded ]->[ 0 ];

    my $fields = [ keys %{ $first_line } ];

    my $csv = Class::CSV->new(
        fields         => $fields,
        line_separator => "\r\n",
    );

    $csv->add_line( $fields );

    foreach my $line_not_autoexcluded ( @lines_not_autoexcluded )
    {
        $csv->add_line( $line_not_autoexcluded );
    }

    Readonly my $training_data_csv_filename => '/tmp/training_data.csv';

    open( my $csv_fh, '>', $training_data_csv_filename ) or die "cannot open > $training_data_csv_filename: $!";

    say $csv_fh $csv->string();

    say STDERR "CSV dump complete";

    exit;
}

sub extractAndScoreDownloads
{
    my $downloads = shift;

    my $analyzed_downloads = [];

    if ( defined( $_download_data_load_file ) )
    {
        say STDERR "reading datafile $_download_data_load_file ";
        $analyzed_downloads = retrieve( $_download_data_load_file ) || die;
        say STDERR "read datafile $_download_data_load_file ";
    }
    else
    {
        $analyzed_downloads = analyze_downloads( $downloads );
    }

    if ( defined( $_dump_training_data_csv ) )
    {
        dump_training_data_csv( $analyzed_downloads );
    }

    if ( $_download_data_store_file )
    {
        my $preprocessed_lines_tmp;

        if ( $_dont_store_preprocessed_lines )
        {
            foreach my $analyzed_download ( @$analyzed_downloads )
            {
                push @{ $preprocessed_lines_tmp }, $analyzed_download->{ preprocessed_lines };
                undef( $analyzed_download->{ preprocessed_lines } );
            }
        }

        store( $analyzed_downloads, $_download_data_store_file );

        if ( defined( $preprocessed_lines_tmp ) )
        {
            foreach my $analyzed_download ( @$analyzed_downloads )
            {
                $analyzed_download->{ preprocessed_lines } = shift @{ $preprocessed_lines_tmp };
            }
        }
    }

    my $download_results = [];

    my $dbs = MediaWords::DB::connect_to_db();

    for my $analyzed_download ( @$analyzed_downloads )
    {
        my $download_result = processDownload( $analyzed_download, $dbs );

        push( @{ $download_results }, $download_result );
    }

    process_download_results( $download_results );
}

sub process_download_results
{
    my ( $download_results, $download_count ) = @_;

    #say STDERR Dumper( $download_results );

    my $all_story_characters   = sum( map { $_->{ story_characters } } @{ $download_results } );
    my $all_extra_characters   = sum( map { $_->{ extra_characters } } @{ $download_results } );
    my $all_missing_characters = sum( map { $_->{ missing_characters } } @{ $download_results } );
    my $all_story_lines        = sum( map { $_->{ story_line_count } } @{ $download_results } );
    my $all_extra_lines        = sum( map { $_->{ extra_line_count } } @{ $download_results } );
    my $all_missing_lines      = sum( map { $_->{ missing_line_count } } @{ $download_results } );
    my $errors                 = sum( map { $_->{ errors } } @{ $download_results } );

    my $non_optional_non_autoexclude_line_count =
      sum( map { $_->{ non_optional_non_autoexclude_line_count } } @{ $download_results } );

    print "$errors errors / " . scalar( @$download_results ) . " downloads\n";
    print "story lines: $all_story_lines story / $all_extra_lines (" . $all_extra_lines / $all_story_lines .
      ") extra / $all_missing_lines (" . $all_missing_lines / $all_story_lines . ") missing\n";

    print "non_ignoreable lines: $non_optional_non_autoexclude_line_count / $all_extra_lines (" .
      $all_extra_lines / $non_optional_non_autoexclude_line_count . ") extra / $all_missing_lines (" .
      $all_missing_lines / $non_optional_non_autoexclude_line_count . ") missing\n";

    if ( $all_story_characters == 0 )
    {
        print "Error no story charcters\n";
    }
    else
    {
        print "characters: $all_story_characters story / $all_extra_characters (" .
          $all_extra_characters / $all_story_characters . ") extra / $all_missing_characters (" .
          $all_missing_characters / $all_story_characters . ") missing\n";
    }

    if ( $_test_sentences )
    {
        my $all_extra_sentences_total        = sum( map { $_->{ extra_sentences_total } } @{ $download_results } );
        my $all_extra_sentences_dedupped     = sum( map { $_->{ extra_sentences_dedupped } } @{ $download_results } );
        my $all_extra_sentences_not_dedupped = sum( map { $_->{ extra_sentences_not_dedupped } } @{ $download_results } );
        my $all_extra_sentences_missing      = sum( map { $_->{ extra_sentences_missing } } @{ $download_results } );

        my $all_missing_sentences_total    = sum( map { $_->{ missing_sentences_total } } @{ $download_results } );
        my $all_missing_sentences_dedupped = sum( map { $_->{ missing_sentences_dedupped } } @{ $download_results } );
        my $all_missing_sentences_not_dedupped =
          sum( map { $_->{ missing_sentences_not_dedupped } } @{ $download_results } );
        my $all_missing_sentences_missing = sum( map { $_->{ missing_sentences_missing } } @{ $download_results } );

        my $all_correctly_included_sentences_total =
          sum( map { $_->{ correctly_included_sentences_total } } @{ $download_results } );
        my $all_correctly_included_sentences_dedupped =
          sum( map { $_->{ correctly_included_sentences_dedupped } } @{ $download_results } );
        my $all_correctly_included_sentences_not_dedupped =
          sum( map { $_->{ correctly_included_sentences_not_dedupped } } @{ $download_results } );
        my $all_correctly_included_sentences_missing =
          sum( map { $_->{ correctly_included_sentences_missing } } @{ $download_results } );

        if ( $all_extra_sentences_total )
        {
            print " Extra sentences              : $all_extra_sentences_total\n";

            print " Extra sentences dedupped     : $all_extra_sentences_dedupped (" .
              ( $all_extra_sentences_dedupped / $all_extra_sentences_total ) . ")\n";
            print " Extra sentences not dedupped : $all_extra_sentences_not_dedupped (" .
              $all_extra_sentences_not_dedupped / $all_extra_sentences_total . ")\n";
            print " Extra sentences missing : $all_extra_sentences_missing (" .
              $all_extra_sentences_missing / $all_extra_sentences_total . ")\n";

        }

        if ( $all_correctly_included_sentences_total )
        {
            print " Correctly_Included sentences              : $all_correctly_included_sentences_total\n";

            print " Correctly_Included sentences dedupped     : $all_correctly_included_sentences_dedupped (" .
              ( $all_correctly_included_sentences_dedupped / $all_correctly_included_sentences_total ) . ")\n";
            print " Correctly_Included sentences not dedupped : $all_correctly_included_sentences_not_dedupped (" .
              $all_correctly_included_sentences_not_dedupped / $all_correctly_included_sentences_total . ")\n";
            print " Correctly_Included sentences missing : $all_correctly_included_sentences_missing (" .
              $all_correctly_included_sentences_missing / $all_correctly_included_sentences_total . ")\n";
        }

        if ( $all_missing_sentences_total )
        {
            print " Missing sentences              : $all_missing_sentences_total\n";

            print " Missing sentences dedupped     : $all_missing_sentences_dedupped (" .
              ( $all_missing_sentences_dedupped / $all_missing_sentences_total ) . ")\n";
            print " Missing sentences not dedupped : $all_missing_sentences_not_dedupped (" .
              $all_missing_sentences_not_dedupped / $all_missing_sentences_total . ")\n";
            print " Missing sentences missing : $all_missing_sentences_missing (" .
              $all_missing_sentences_missing / $all_missing_sentences_total . ")\n";

        }

    }

}

# do a test run of the text extractor
sub main
{

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'                      => \$file,
        'downloads|d=s'                 => \@download_ids,
        'regenerate_database_cache'     => \$_re_generate_cache,
        'test_sentences'                => \$_test_sentences,
        'download_data_load_file=s'     => \$_download_data_load_file,
        'download_data_store_file=s'    => \$_download_data_store_file,
        'dont_store_preprocessed_lines' => \$_dont_store_preprocessed_lines,
        'dump_training_data_csv'        => \$_dump_training_data_csv,
    ) or die;

    my $downloads;

    if ( !$_download_data_load_file )
    {

        my $db = MediaWords::DB->authenticate();

        my $dbs = MediaWords::DB::connect_to_db();

        if ( @download_ids )
        {
            $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
        }
        elsif ( $file )
        {
            open( DOWNLOAD_ID_FILE, $file ) || die( "Could not open file: $file" );
            @download_ids = <DOWNLOAD_ID_FILE>;
            $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
        }
        else
        {
            $downloads = $dbs->query(
"SELECT * from downloads where downloads_id in (select distinct downloads_id from extractor_training_lines order by downloads_id)"
            )->hashes;
        }
    }

    extractAndScoreDownloads( $downloads );
}

main();
