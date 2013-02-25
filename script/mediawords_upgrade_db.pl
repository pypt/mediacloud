#!/usr/bin/env perl
#
# Concatenate and echo the database schema diff that would upgrade the Media Cloud
# database to the latest schema version (no --import parameter).
#  *or*
# Upgrade the Media Cloud database to the latest schema version (--import parameter).
#
# Usage: ./script/run_with_carton.sh ./script/mediawords_upgrade_db.pl > schema-diff.sql
#    or: ./script/run_with_carton.sh ./script/mediawords_upgrade_db.pl --import

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Getopt::Long;
use MediaWords::Pg::Schema;

sub main
{
    my $import = 0;    # script should import the diff directly instead of echoing it out

    my Readonly $usage = "Usage: $0 > schema-diff.sql\n   or: $0 --import";

    GetOptions( 'import' => \$import ) or die "$usage\n";

    my $db_label                  = undef;
    my $echo_instead_of_executing = 1;
    if ( !MediaWords::Pg::Schema::upgrade_db( $db_label, ( !$import ) ) )
    {
        if ( $import )
        {
            say STDERR 'ERROR: Error while trying to upgrade database schema.';
        }
        else
        {
            say STDERR 'ERROR: Error while trying to echo the database schema diff.';
        }

        return 1;
    }

    return 0;
}

main();
