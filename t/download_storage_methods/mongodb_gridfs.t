use strict;

use MediaWords::Util::Config;
use IO::Socket;

use Test::More;

sub host_port_is_available($$)
{
    my ( $host, $port ) = @_;

    my $socket = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port,
        Proto    => 'tcp',
        Type     => SOCK_STREAM
    );
    if ( $socket )
    {
        close( $socket );
        return 1;
    }
    else
    {
        return 0;
    }
}

my $mongodb_settings = MediaWords::Util::Config::get_config->{ mongodb_gridfs }->{ test };
unless ( $mongodb_settings )
{
    plan skip_all => "MongoDB's testing database is not configured";
}
else
{
    unless ( host_port_is_available( $mongodb_settings->{ host }, $mongodb_settings->{ port } ) )
    {
        # Skipping test if "mongod" is not running because the point of this test is to validate
        # download storage handler and not service availability
        plan skip_all => "Unable to connect to MongoDB's testing database";
    }
    else
    {
        plan tests => 20;
    }
}

use Data::Dumper;
use MongoDB;
use MongoDB::GridFS;
use MediaWords::DBI::Downloads::Store::GridFS;
use MediaWords::DB;

my $gridfs = MediaWords::DBI::Downloads::Store::GridFS->new( { use_testing_database => 1 } );
ok( $gridfs, "MongoDB initialized" );

my $db = MediaWords::DB::connect_to_db;
ok( $db, "PostgreSQL initialized " );

my $test_download_id = 999999999999999;
my $test_download    = { downloads_id => $test_download_id };
my $test_content     = 'Loren ipsum dolor sit amet.';
my $content_ref;

#
# Store content
#

my $gridfs_id;
eval { $gridfs_id = $gridfs->store_content( $db, $test_download, \$test_content ); };
ok( ( !$@ ), "Storing content failed: $@" );
ok( $gridfs_id,                                                          'Object ID was returned' );
ok( length( $gridfs_id ) == length( 'gridfs:5152138e3e7062d55800057c' ), 'Object ID is of the valid size' );

#
# Fetch content, compare
#

eval { $content_ref = $gridfs->fetch_content( $db, $test_download ); };
ok( ( !$@ ), "Fetching download failed: $@" );
ok( $content_ref, "Fetching download did not die but no content was returned" );
is( $$content_ref, $test_content, "Content doesn't match." );

#
# Remove content, try fetching again
#

$gridfs->remove_content( $db, $test_download );
$content_ref = undef;
eval { $content_ref = $gridfs->fetch_content( $db, $test_download ); };
ok( $@, "Fetching download that does not exist should have failed" );
ok( ( !$content_ref ),
    "Fetching download that does not exist failed (as expected) but the content reference ($content_ref) was returned" );

#
# Check GridFS thinks that the content exists
#
ok( ( !$gridfs->content_exists( $db, $test_download ) ),
    "content_exists() reports that content exists (although it shouldn't)" );

#
# Store content twice
#

my $gridfs_id;
eval {
    $gridfs_id = $gridfs->store_content( $db, $test_download, \$test_content );
    $gridfs_id = $gridfs->store_content( $db, $test_download, \$test_content );
};
ok( ( !$@ ), "Storing content twice failed: $@" );
ok( $gridfs_id,                                                          'Object ID was returned' );
ok( length( $gridfs_id ) == length( 'gridfs:5152138e3e7062d55800057c' ), 'Object ID is of the valid size' );

# Fetch content again, compare
eval { $content_ref = $gridfs->fetch_content( $db, $test_download ); };
ok( ( !$@ ), "Fetching download failed: $@" );
ok( $content_ref, "Fetching download did not die but no content was returned" );
is( $$content_ref, $test_content, "Content doesn't match." );

# Remove content, try fetching again
$gridfs->remove_content( $db, $test_download );
$content_ref = undef;
eval { $content_ref = $gridfs->fetch_content( $db, $test_download ); };
ok( $@, "Fetching download that does not exist should have failed" );
ok( ( !$content_ref ),
    "Fetching download that does not exist failed (as expected) but the content reference ($content_ref) was returned" );

# Check GridFS thinks that the content exists
ok( ( !$gridfs->content_exists( $db, $test_download ) ),
    "content_exists() reports that content exists (although it shouldn't)" );
