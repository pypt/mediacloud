package MediaWords::DBI::Downloads::Store::AmazonS3;

# class for storing / loading downloads in Amazon S3

use strict;
use warnings;

use Moose;
with 'MediaWords::DBI::Downloads::Store';

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use Net::Amazon::S3;
use Net::Amazon::S3::Client;
use Net::Amazon::S3::Client::Bucket;
use POSIX qw(floor);

# Should the Amazon S3 module use secure (SSL-encrypted) connections?
use constant AMAZON_S3_USE_SSL => 0;

# How many seconds should the module wait before bailing on a request to S3 (in seconds)
# (Timeout should "fit in" at least AMAZON_S3_READ_ATTEMPTS number of retries
# within the time period)
use constant AMAZON_S3_TIMEOUT => 60;

# Check if content exists before storing (good for debugging, slows down the stores)
use constant AMAZON_S3_CHECK_IF_EXISTS_BEFORE_STORING => 1;

# Check if content exists before fetching (good for debugging, slows down the fetches)
use constant AMAZON_S3_CHECK_IF_EXISTS_BEFORE_FETCHING => 1;

# Check if content exists before deleting (good for debugging, slows down the deletes)
use constant AMAZON_S3_CHECK_IF_EXISTS_BEFORE_DELETING => 1;

# S3's number of read / write attempts
# (in case waiting 20 seconds for the read / write to happen doesn't help, the instance should
# retry writing a couple of times)
use constant AMAZON_S3_READ_ATTEMPTS  => 3;
use constant AMAZON_S3_WRITE_ATTEMPTS => 3;

# Net::Amazon::S3 instance, bucket (lazy-initialized to prevent multiple forks using the same object)
has '_s3'                       => ( is => 'rw' );
has '_s3_client'                => ( is => 'rw' );
has '_s3_bucket'                => ( is => 'rw' );
has '_s3_downloads_folder_name' => ( is => 'rw', default => '' );

# Process PID (to prevent forks attempting to clone the Net::Amazon::S3 accessor objects)
has '_pid' => ( is => 'rw', default => 0 );

# True if the package should connect to the Amazon S3 bucket used for testing
has '_use_testing_database' => ( is => 'rw', default => 0 );

# Constructor
sub BUILD
{
    my ( $self, $args ) = @_;

    # Get settings
    if ( $args->{ use_testing_database } )
    {
        $self->_use_testing_database( 1 );
    }
    else
    {
        $self->_use_testing_database( 0 );
    }

    if ( AMAZON_S3_READ_ATTEMPTS < 1 )
    {
        die "AMAZON_S3_READ_ATTEMPTS must be >= 1\n";
    }
    if ( AMAZON_S3_WRITE_ATTEMPTS < 1 )
    {
        die "AMAZON_S3_WRITE_ATTEMPTS must be >= 1\n";
    }

    $self->_pid( $$ );
}

sub _initialize_s3_or_die($)
{
    my ( $self ) = @_;

    if ( $self->_pid == $$ and ( $self->_s3 and $self->_s3_bucket ) )
    {

        # Already initialized on the very same process
        return;
    }

    # Get settings
    my $config = MediaWords::Util::Config::get_config;

    unless ( defined( $config->{ amazon_s3 } ) and defined( $config->{ amazon_s3 }->{ mediawords } ) )
    {
        die "AmazonS3: Amazon S3 connection settings in mediawords.yml are not configured properly.\n";
    }

    my $access_key_id     = $config->{ amazon_s3 }->{ access_key_id };
    my $secret_access_key = $config->{ amazon_s3 }->{ secret_access_key };
    my $bucket_name;
    my $downloads_folder_name;

    if ( $self->_use_testing_database )
    {
        say STDERR "AmazonS3: Will use testing bucket.";
        $bucket_name           = $config->{ amazon_s3 }->{ test }->{ bucket_name };
        $downloads_folder_name = $config->{ amazon_s3 }->{ test }->{ downloads_folder_name };
    }
    else
    {
        $bucket_name           = $config->{ amazon_s3 }->{ mediawords }->{ bucket_name };
        $downloads_folder_name = $config->{ amazon_s3 }->{ mediawords }->{ downloads_folder_name };
    }

    # Downloads folder is optional
    unless ( $access_key_id and $secret_access_key and $bucket_name )
    {
        die "AmazonS3: Amazon S3 connection settings in mediawords.yml are not configured properly.\n";
    }

    # Add slash to the end of the folder name (if it doesn't exist yet)
    if ( $downloads_folder_name and substr( $downloads_folder_name, -1, 1 ) ne '/' )
    {
        $downloads_folder_name .= '/';
    }

    # Timeout should "fit in" at least AMAZON_S3_READ_ATTEMPTS number of retries
    # within the time period
    my $request_timeout = floor( ( AMAZON_S3_TIMEOUT / AMAZON_S3_READ_ATTEMPTS ) - 1 );
    if ( $request_timeout < 10 )
    {
        die "Amazon S3 request timeout ($request_timeout) too small.\n";
    }

    # Initialize
    $self->_s3_downloads_folder_name( $downloads_folder_name || '' );
    $self->_s3(
        Net::Amazon::S3->new(
            aws_access_key_id     => $access_key_id,
            aws_secret_access_key => $secret_access_key,
            retry                 => 1,
            secure                => AMAZON_S3_USE_SSL,
            timeout               => $request_timeout
        )
    );
    unless ( $self->_s3 )
    {
        die "AmazonS3: Unable to initialize Net::Amazon::S3 instance.\n";
    }
    $self->_s3_client( Net::Amazon::S3::Client->new( s3 => $self->_s3 ) );

    # Get the bucket ($_s3->bucket would not verify that the bucket exists)
    my @buckets = $self->_s3_client->buckets;
    foreach my $bucket ( @buckets )
    {
        if ( $bucket->name eq $bucket_name )
        {
            $self->_s3_bucket( $bucket );
        }
    }
    unless ( $self->_s3_bucket )
    {
        die "AmazonS3: Unable to get bucket '$bucket_name'.";
    }

    # Save PID
    $self->_pid( $$ );

    my $path = ( $self->_s3_downloads_folder_name ? "$bucket_name/$downloads_folder_name" : "$bucket_name" );
    say STDERR "AmazonS3: Initialized Amazon S3 download storage at '$path' for PID $$.";
}

sub _object_for_download($$)
{
    my ( $self, $download ) = @_;

    unless ( $download and $download->{ downloads_id } )
    {
        die "Download is invalid: " . Dumper( $download );
    }

    my $filename = $self->_s3_downloads_folder_name . $download->{ downloads_id };
    my $object = $self->_s3_bucket->object( key => $filename );

    return $object;
}

# Returns true if a download already exists in a database
sub content_exists($$)
{
    my ( $self, $download ) = @_;

    $self->_initialize_s3_or_die();

    my $object = $self->_object_for_download( $download );
    if ( $object->exists )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Removes content
sub remove_content($$)
{
    my ( $self, $download ) = @_;

    $self->_initialize_s3_or_die();

    if ( AMAZON_S3_CHECK_IF_EXISTS_BEFORE_DELETING )
    {
        unless ( $self->content_exists( $download ) )
        {
            die "AmazonS3: download ID " . $download->{ downloads_id } . " does not exist.\n";
        }
    }

    my $object = $self->_object_for_download( $download );

    $object->delete;

    return 1;
}

# Moose method
sub store_content($$$$;$)
{
    my ( $self, $db, $download, $content_ref, $skip_encode_and_gzip ) = @_;

    $self->_initialize_s3_or_die();

    if ( AMAZON_S3_CHECK_IF_EXISTS_BEFORE_STORING )
    {
        if ( $self->content_exists( $download ) )
        {
            say STDERR "AmazonS3: download ID " . $download->{ downloads_id } . " already exists, " .
              "will store a new version or overwrite (depending on whether or not versioning is enabled).\n";
        }
    }

    # Encode + gzip
    my $content_to_store;
    if ( $skip_encode_and_gzip )
    {
        $content_to_store = $$content_ref;
    }
    else
    {
        $content_to_store = $self->encode_and_gzip( $content_ref, $download->{ downloads_id } );
    }

    my $write_was_successful = 0;
    my $object;

    # S3 sometimes times out when writing, so we'll try to write several times
    for ( my $retry = 0 ; $retry < AMAZON_S3_WRITE_ATTEMPTS ; ++$retry )
    {
        if ( $retry > 0 )
        {
            say STDERR "Retrying ($retry)...";
        }

        eval {

            # Store; will die() on failure
            $object = $self->_object_for_download( $download );
            $object->put( $content_to_store );
            $write_was_successful = 1;

        };

        if ( $@ )
        {
            say STDERR "Attempt to write to '" . $download->{ downloads_id } . "' didn't succeed because: $@";
        }
        else
        {
            last;
        }
    }

    unless ( $write_was_successful )
    {
        die "Unable to write '" .
          $download->{ downloads_id } . "' from Amazon S3 after " . AMAZON_S3_WRITE_ATTEMPTS . " retries.\n";
    }

    return 's3:' . $object->key;
}

# Moose method
sub fetch_content($$;$)
{
    my ( $self, $download, $skip_gunzip_and_decode ) = @_;

    $self->_initialize_s3_or_die();

    if ( AMAZON_S3_CHECK_IF_EXISTS_BEFORE_FETCHING )
    {
        unless ( $self->content_exists( $download ) )
        {
            die "AmazonS3: download ID " . $download->{ downloads_id } . " does not exist.\n";
        }
    }

    my $object;
    my $gzipped_content;

    # S3 sometimes times out when reading, so we'll try to read several times
    for ( my $retry = 0 ; $retry < AMAZON_S3_READ_ATTEMPTS ; ++$retry )
    {
        if ( $retry > 0 )
        {
            say STDERR "Retrying ($retry)...";
        }

        eval {

            # Read; will die() on failure
            $object          = $self->_object_for_download( $download );
            $gzipped_content = $object->get;

        };

        if ( $@ )
        {
            say STDERR "Attempt to read from '" . $download->{ downloads_id } . "' didn't succeed because: $@";
        }
        else
        {
            last;
        }
    }

    unless ( defined $gzipped_content )
    {
        die "Unable to read '" .
          $download->{ downloads_id } . "' from Amazon S3 after " . AMAZON_S3_READ_ATTEMPTS . " retries.\n";
    }

    # Gunzip + decode
    my $decoded_content;
    if ( $skip_gunzip_and_decode )
    {
        $decoded_content = $gzipped_content;
    }
    else
    {
        $decoded_content = $self->gunzip_and_decode( \$gzipped_content, $download->{ downloads_id } );
    }

    return \$decoded_content;
}

no Moose;    # gets rid of scaffolding

1;
