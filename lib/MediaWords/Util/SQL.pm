package MediaWords::Util::SQL;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# misc utility functions for sql

use strict;

use Time::Local;

# given a ref to a list of ids, return a list suitable
# for including in a query as an in list, eg:
# 1,2,3,4
sub get_ids_in_list
{
    my ( $list ) = @_;

    if ( grep( /[^0-9]/, @{ $list } ) )
    {
        die( "non-number list id list: " . join( ', ', @{ $list } ) );
    }

    return join( ',', @{ $list } );
}

# given a date in the sql format 'YYYY-MM-DD', return the epoch time
sub get_epoch_from_sql_date
{
    my ( $date ) = @_;
    
    my $year  = substr( $date, 0, 4 );
    my $month = substr( $date, 5, 2 );
    my $day   = substr( $date, 8, 2 );

    return Time::Local::timelocal( 0, 0, 0, $day, $month - 1, $year );
}

# given a date in the sql format 'YYYY-MM-DD', increment it by $days days
sub increment_day
{
    my ( $date, $days ) = @_;

    return $date if ( defined( $days ) && ( $days == 0 ) );

    $days = 1 if ( !defined( $days ) );

    my $epoch_date = get_epoch_from_sql_date( $date ) + ( ( ( $days * 24 ) + 12 ) * 60 * 60 );

    my ( undef, undef, undef, $day, $month, $year ) = localtime( $epoch_date );

    return sprintf( '%04d-%02d-%02d', $year + 1900, $month + 1, $day );
}

1;
