package MediaWords::Job::Facebook::FetchStoryStats;

#
# Fetch story's share count statistics via Facebook's Graph API
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/mjm_worker.pl lib/MediaWords/Job/Facebook/FetchStoryStats.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/mjm_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::Config;
use MediaWords::Util::Facebook;
use MediaWords::Util::Process;
use Readonly;
use Data::Dumper;

# Having a global database object should be safe because
# job workers don't fork()
my $db = undef;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $config = MediaWords::Util::Config::get_config();
    unless ( $config->{ facebook }->{ enabled } eq 'yes' )
    {
        fatal_error( 'Facebook API processing is not enabled.' );
    }

    # Postpone connecting to the database so that compile test doesn't do that
    $db ||= MediaWords::DB::connect_to_db();

    my $stories_id = $args->{ stories_id } or die "'stories_id' is not set.";

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story )
    {
        die "Story ID $stories_id was not found.";
    }

    say STDERR "Fetching story stats for story $stories_id...";
    eval {

        my $stories_url = $story->{ url };
        unless ( $stories_url )
        {
            die "Story URL for story ID $stories_id is empty.";
        }
        say STDERR "Story URL: $stories_url";

        my ( $share_count, $comment_count ) = MediaWords::Util::Facebook::get_and_store_share_comment_counts( $db, $story );
        say STDERR "share count: $share_count, comment count: $comment_count";
    };
    if ( $@ )
    {
        die "Facebook helper died while fetching and storing statistics: $@";
    }
    else
    {
        say STDERR "Done fetching story stats for story $stories_id.";
    }
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
