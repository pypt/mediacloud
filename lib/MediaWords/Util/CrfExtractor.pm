package MediaWords::Util::CrfExtractor;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;

use Data::Dumper;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);

#use List::MoreUtils qw( :all);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use IPC::Open2;
use CRF::CrfUtils;
use Text::Trim;

use Moose;

with 'MediaWords::Util::Extractor';

sub getExtractedLines
{
    my ( $self, $line_infos, $preprocessed_lines ) = @_;

    return get_extracted_lines_with_crf( $line_infos, $preprocessed_lines );
}

sub get_extracted_lines_with_crf
{
    my ( $line_infos, $preprocessed_lines ) = @_;

    my $feature_strings =
      MediaWords::Crawler::AnalyzeLines::get_feature_strings_for_download( $line_infos, $preprocessed_lines );

    my $model_file_name = '/home/dlarochelle/mc/mediacloud-code/branches/extractor_inline_java/crf_model';
    
    $model_file_name = '/home/dlarochelle/mc/mediacloud-code/branches/extractor_inline_java/features_outputModel.txt';

    #my $predictions = CRF::CrfUtils::run_model_inline_java_data_array( $model_file_name, $feature_strings );
    my $predictions = CRF::CrfUtils::run_model_with_separate_exec( $model_file_name, $feature_strings );

    #say STDERR ( Dumper( $line_infos ) );
    #say STDERR Dumper( $feature_strings );
    #say STDERR ( Dumper( $predictions ) );

    die unless scalar( @ $predictions ) == scalar( @ $feature_strings );

    my $line_index       = 0;
    my $prediction_index = 0;

    my @extracted_lines;

    die unless scalar( @ $predictions ) <= scalar( @ $line_infos );

    while ( $line_index < scalar( @{ $line_infos } ) )
    {
        if ( $line_infos->[ $line_index ]->{ auto_excluded } )
        {
            $line_index++;
            next;
        }

        my $prediction = rtrim $predictions->[ $prediction_index ];

        die "Invalid prediction: '$prediction' for line index $line_index and prediction_index $prediction_index " . Dumper( $predictions )
          unless ( $prediction eq 'excluded' )
          or ( $prediction eq 'required' )
          or ( $prediction eq 'optional' );

	#say STDERR "$prediction";
        if ( $prediction ne 'excluded' )
        {
            push @extracted_lines, $line_infos->[ $line_index ]->{ line_number };
        }
        $line_index++;
        $prediction_index++;
    }

    my $extracted_lines = \@extracted_lines;
    return $extracted_lines;
}
1;
