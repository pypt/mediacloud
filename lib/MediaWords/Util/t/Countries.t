#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More tests => 438 + 1;
use utf8;

use Lingua::Stem;
use Lingua::Stem::Ru;
use Data::Dumper;

use MediaWords::Util::Countries;

{

    my $all_countries = [ sort map { lc } @{ MediaWords::Util::Countries::get_countries_for_counts() } ];

    foreach my $country ( @{ $all_countries } )
    {
        ok( MediaWords::Util::Countries::_get_country_data_base_value( $country ), "database value: $country" );
        my $country_db_value = MediaWords::Util::Countries::_get_country_data_base_value( $country );
        ok( MediaWords::Util::Countries::get_country_code_for_stemmed_country_name( $country_db_value ),
            "database value: $country" );

    }
}
