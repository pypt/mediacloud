package MediaWords::KeyValueStore::GridFS;

# class for storing / loading objects (raw downloads, CoreNLP annotator results, ...) to / from Mongo GridFS

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::Util::Compress;
use MongoDB 0.704.1.0;
use MongoDB::GridFS;
use FileHandle;
use Carp;
use Readonly;

# MongoDB's query timeout, in ms
# (default timeout is 30 s, but MongoDB sometimes creates a new 2 GB data file for ~38 seconds,
#  so we set it to 60 s)
Readonly my $MONGODB_QUERY_TIMEOUT => 60 * 1000;

# MongoDB's number of read / write retries
# (in case waiting 60 seconds for the read / write to happen doesn't help, the instance should
#  retry writing a couple of times)
Readonly my $MONGODB_READ_RETRIES  => 10;
Readonly my $MONGODB_WRITE_RETRIES => 10;

# MongoDB client, GridFS instance (lazy-initialized to prevent multiple forks using the same object)
has '_mongodb_client'   => ( is => 'rw' );
has '_mongodb_database' => ( is => 'rw' );
has '_mongodb_gridfs'   => ( is => 'rw' );

# Process PID (to prevent forks attempting to clone the MongoDB accessor objects)
has '_pid' => ( is => 'rw', default => 0 );

# Configuration
has '_conf_host'          => ( is => 'rw' );
has '_conf_port'          => ( is => 'rw' );
has '_conf_username'      => ( is => 'rw' );
has '_conf_password'      => ( is => 'rw' );
has '_conf_database_name' => ( is => 'rw' );

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    # Get arguments
    unless ( $args->{ database_name } )
    {
        confess "Please provide 'database_name' argument.";
    }
    my $gridfs_database_name = $args->{ database_name };

    # Get configuration
    my $config          = MediaWords::Util::Config::get_config;
    my $gridfs_host     = $config->{ mongodb_gridfs }->{ host } // 'localhost';
    my $gridfs_port     = $config->{ mongodb_gridfs }->{ port } // 27017;
    my $gridfs_username = $config->{ mongodb_gridfs }->{ username };
    my $gridfs_password = $config->{ mongodb_gridfs }->{ password };

    unless ( $gridfs_host and $gridfs_port )
    {
        confess "GridFS: MongoDB connection settings in mediawords.yml are not configured properly.";
    }

    # Store configuration
    $self->_conf_host( $gridfs_host );
    $self->_conf_port( $gridfs_port );
    $self->_conf_username( $gridfs_username );
    $self->_conf_password( $gridfs_password );
    $self->_conf_database_name( $gridfs_database_name );

    $self->_pid( $$ );
}

sub _connect_to_mongodb_or_die($)
{
    my ( $self ) = @_;

    if ( $self->_pid == $$ and ( $self->_mongodb_client and $self->_mongodb_database and $self->_mongodb_gridfs ) )
    {

        # Already connected on the very same process
        return;
    }

    # Connect
    if ( $self->_conf_username and $self->_conf_password )
    {
        # Authenticated login
        $self->_mongodb_client(
            MongoDB::MongoClient->new(
                host          => sprintf( 'mongodb://%s:%d', $self->_conf_host, $self->_conf_port ),
                username      => $self->_conf_username,
                password      => $self->_conf_password,
                query_timeout => $MONGODB_QUERY_TIMEOUT
            )
        );
    }
    else
    {
        # Unauthenticated login
        $self->_mongodb_client(
            MongoDB::MongoClient->new(
                host          => sprintf( 'mongodb://%s:%d', $self->_conf_host, $self->_conf_port ),
                query_timeout => $MONGODB_QUERY_TIMEOUT
            )
        );
    }
    unless ( $self->_mongodb_client )
    {
        confess "GridFS: Unable to connect to MongoDB.";
    }

    $self->_mongodb_database( $self->_mongodb_client->get_database( $self->_conf_database_name ) );
    unless ( $self->_mongodb_database )
    {
        confess "GridFS: Unable to choose a MongoDB database.";
    }

    $self->_mongodb_gridfs( $self->_mongodb_database->get_gridfs );
    unless ( $self->_mongodb_gridfs )
    {
        confess "GridFS: Unable to connect use the MongoDB database as GridFS.";
    }

    # Save PID
    $self->_pid( $$ );

    say STDERR "GridFS: Connected to GridFS storage at '" .
      $self->_conf_host . ":" . $self->_conf_port . "/" . $self->_conf_database_name . "' for PID $$.";
}

# Moose method
sub content_exists($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    $self->_connect_to_mongodb_or_die();

    my $filename = '' . $object_id;
    my $file = $self->_mongodb_gridfs->find_one( { "filename" => $filename } );

    return ( defined $file );
}

# Moose method
sub remove_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    $self->_connect_to_mongodb_or_die();

    my $filename = '' . $object_id;

    # Remove file(s) if already exist(s) -- MongoDB might store several versions of the same file
    while ( my $file = $self->_mongodb_gridfs->find_one( { "filename" => $filename } ) )
    {
        say STDERR "GridFS: Removing existing file '$filename'.";

        # "safe -- If true, each remove will be checked for success and die on failure."
        $self->_mongodb_gridfs->remove( { "filename" => $filename }, { safe => 1 } );
    }
}

# Moose method
sub store_content($$$$;$)
{
    my ( $self, $db, $object_id, $content_ref, $use_bzip2_instead_of_gzip ) = @_;

    $self->_connect_to_mongodb_or_die();

    # Encode + compress
    my $content_to_store;
    eval {
        if ( $use_bzip2_instead_of_gzip )
        {
            $content_to_store = MediaWords::Util::Compress::encode_and_bzip2( $$content_ref );
        }
        else
        {
            $content_to_store = MediaWords::Util::Compress::encode_and_gzip( $$content_ref );
        }
    };
    if ( $@ or ( !defined $content_to_store ) )
    {
        confess "Unable to compress object ID $object_id: $@";
    }

    my $filename = '' . $object_id;
    my $gridfs_id;

    # MongoDB sometimes times out when writing because it's busy creating a new data file,
    # so we'll try to write several times
    for ( my $retry = 0 ; $retry < $MONGODB_WRITE_RETRIES ; ++$retry )
    {
        if ( $retry > 0 )
        {
            say STDERR "GridFS: Retrying...";
        }

        eval {

            # Remove file(s) if already exist(s) -- MongoDB might store several versions of the same file
            while ( my $file = $self->_mongodb_gridfs->find_one( { "filename" => $filename } ) )
            {
                say STDERR "GridFS: Removing existing file '$filename'.";
                $self->remove_content( $db, $object_id );
            }

            # Write
            my $basic_fh;
            open( $basic_fh, '<', \$content_to_store );
            my $fh = FileHandle->new;
            $fh->fdopen( $basic_fh, 'r' );
            $gridfs_id = $self->_mongodb_gridfs->put( $fh, { "filename" => $filename } );
            unless ( $gridfs_id )
            {
                confess "GridFS: MongoDBs OID is empty.";
            }

            $gridfs_id = "gridfs:$gridfs_id";
        };

        if ( $@ )
        {
            say STDERR "GridFS: Write to '$filename' didn't succeed because: $@";
        }
        else
        {
            last;
        }
    }

    unless ( $gridfs_id )
    {
        confess "GridFS: Unable to store object ID $object_id to GridFS after $MONGODB_WRITE_RETRIES retries.";
    }

    return $gridfs_id;
}

# Moose method
sub fetch_content($$$;$$)
{
    my ( $self, $db, $object_id, $object_path, $use_bunzip2_instead_of_gunzip ) = @_;

    $self->_connect_to_mongodb_or_die();

    unless ( defined $object_id )
    {
        confess "GridFS: Object ID is undefined.";
    }

    my $filename = '' . $object_id;

    my $id = MongoDB::OID->new( filename => $filename );

    # MongoDB sometimes times out when reading because it's busy creating a new data file,
    # so we'll try to read several times
    my $attempt_to_read_succeeded = 0;
    my $file                      = undef;
    for ( my $retry = 0 ; $retry < $MONGODB_READ_RETRIES ; ++$retry )
    {
        if ( $retry > 0 )
        {
            say STDERR "GridFS: Retrying...";
        }

        eval {

            # Read
            my $gridfs_file = $self->_mongodb_gridfs->find_one( { 'filename' => $filename } );
            $attempt_to_read_succeeded = 1;

            unless ( defined $gridfs_file )
            {
                confess "GridFS: unable to find file '$filename'.";
            }
            $file = $gridfs_file->slurp;
        };

        if ( $@ )
        {
            say STDERR "GridFS: Read from '$filename' didn't succeed because: $@";
            if ( $attempt_to_read_succeeded )
            {
                last;
            }
        }
        else
        {
            last;
        }
    }

    if ( $attempt_to_read_succeeded )
    {
        unless ( defined $file )
        {
            confess "GridFS: Could not get file '$filename' (probably the file does not exist).";
        }
    }
    else
    {
        confess "GridFS: Unable to read object ID $object_id from GridFS after $MONGODB_READ_RETRIES retries.";
    }
    unless ( defined( $file ) )
    {
    }

    my $compressed_content = $file;

    # Uncompress + decode
    unless ( defined $compressed_content and $compressed_content ne '' )
    {
        # MongoDB returns empty strings on some cases of corrupt data, but
        # an empty string can't be a valid Gzip/Bzip2 archive, so we're
        # checking if we're about to attempt to decompress an empty string
        confess "GridFS: Compressed data is empty for filename $filename.";
    }

    my $decoded_content;
    eval {
        if ( $use_bunzip2_instead_of_gunzip )
        {
            $decoded_content = MediaWords::Util::Compress::bunzip2_and_decode( $compressed_content );
        }
        else
        {
            $decoded_content = MediaWords::Util::Compress::gunzip_and_decode( $compressed_content );
        }
    };
    if ( $@ or ( !defined $decoded_content ) )
    {
        confess "Unable to uncompress object ID $object_id: $@";
    }

    return \$decoded_content;
}

no Moose;    # gets rid of scaffolding

1;
