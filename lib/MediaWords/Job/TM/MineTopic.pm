package MediaWords::Job::TM::MineTopic;

#
# Run through stories found for the given topic and find all the links in
# each story.
#
# For each link, try to find whether it matches any given story. If it doesn't,
# create a new story. Add that story's links to the queue if it matches the
# pattern for the topic. Write the resulting stories and links to
# topic_stories and topic_links.
#
# Options:
#
# * dedup_stories - run story deduping code over existing topic stories;
#   only necessary to rerun new dedup code
#
# * import_only - only run import_seed_urls and import_solr_seed and return
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/mjm_worker.pl lib/MediaWords/Job/TM/Minetopic.pm
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

use MediaWords::TM::Mine;
use MediaWords::DB;

# Having a global database object should be safe because
# job workers don't fork()
my $db = undef;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    unless ( $db )
    {
        # Postpone connecting to the database so that compile test doesn't do that
        $db = MediaWords::DB::connect_to_db();
    }

    my $topics_id                       = $args->{ topics_id };
    my $import_only                     = $args->{ import_only } // 0;
    my $cache_broken_downloads          = $args->{ cache_broken_downloads } // 0;
    my $skip_outgoing_foreign_rss_links = $args->{ skip_outgoing_foreign_rss_links } // 0;
    my $skip_post_processing            = $args->{ skip_post_processing } // 0;

    unless ( $topics_id )
    {
        die "'topics_id' is not set.";
    }

    my $topic = $db->find_by_id( 'topics', $topics_id )
      or die( "Unable to find topic '$topics_id'" );

    my $options = {
        import_only                     => $import_only,
        cache_broken_downloads          => $cache_broken_downloads,
        skip_outgoing_foreign_rss_links => $skip_outgoing_foreign_rss_links,
        skip_post_processing            => $skip_post_processing
    };

    MediaWords::TM::Mine::mine_topic( $db, $topic, $options );

}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
