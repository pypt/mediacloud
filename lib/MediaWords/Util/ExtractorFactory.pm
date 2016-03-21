package MediaWords::Util::ExtractorFactory;
use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;
use MediaWords::Util::HeuristicExtractor;

use strict;

sub createExtractor
{
    my ( $extractor_method ) = @_;

    my $config = MediaWords::Util::Config::get_config;

    if ( !defined( $extractor_method ) )
    {
        $extractor_method = $config->{ mediawords }->{ extractor_method };
    }

    die unless defined( $extractor_method );

    my $ret;
    if ( $extractor_method eq 'HeuristicExtractor' )
    {
        $ret = MediaWords::Util::HeuristicExtractor->new();
    }
    else
    {
        die "Invalid extractor methods: $extractor_method";
    }

    die unless defined( $ret );

    return $ret;
}

1;
