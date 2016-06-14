use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../../../lib";
    use lib "$FindBin::Bin/../../../t";
    use lib "$FindBin::Bin/../../lib";
    use lib "$FindBin::Bin/../..";
}

use Data::Dumper;
use MediaWords::Pg::Schema;

use Test::NoWarnings;
use Test::More tests => 13;

BEGIN
{
    use_ok( 'MediaWords::Util::Config' );
    use_ok( 'DBIx::Simple::MediaWords' );
    use_ok( 'MediaWords::Test::DB' );
}

require_ok( 'MediaWords::Util::Config' );
require_ok( 'DBIx::Simple::MediaWords' );
require_ok( 'MediaWords::Test::DB' );

MediaWords::Test::DB::test_on_test_database(
    sub {
        my $db = shift;

        isa_ok( $db, "DBIx::Simple::MediaWords" );

        # clear the DB
        MediaWords::Pg::Schema::reset_all_schemas( $db );

        my $script_dir = MediaWords::Util::Config->get_config()->{ mediawords }->{ script_dir };
        my $load_sql_file_result = MediaWords::Pg::Schema::load_sql_file( 'test', "$script_dir/mediawords.sql" );
        ok( $load_sql_file_result == 0, "load sql file result" );

        # transaction success
        $db->transaction(
            sub {
                $db->query( 'INSERT INTO media (url, name, moderated) VALUES(?, ?, ?)',
                    'http://www.example.com/', 'Example.com', 0 );
                return 1;
            }
        );

        is( $db->query( 'SELECT COUNT(*) FROM media' )->list, '1', 'simple transaction' );

        # transaction failure
        eval {
            $db->transaction(
                sub {
                    $db->query( 'INSERT INTO media (url, name, moderated) VALUES(?, ?, ?)',
                        'http://www.example.net/', 'Example.net', 0 );
                    die "I did too much work in the transaction!";
                }
            );
        };

        like( $@, qr/^I did too much work in the transaction!/, 'die propagation' );
        is( $db->query( 'SELECT COUNT(*) FROM media' )->list, '1', 'exceptions roll-back transactions' );

        # transaction abortion
        $db->transaction(
            sub {
                $db->query( 'INSERT INTO media (url, name, moderated) VALUES(?, ?, ?)',
                    'http://www.example.org/', 'Example.org', 0 );
                return 0;
            }
        );

        is( $db->query( 'SELECT COUNT(*) FROM media' )->list, '1', 'voluntary abortion' );
    }
);
