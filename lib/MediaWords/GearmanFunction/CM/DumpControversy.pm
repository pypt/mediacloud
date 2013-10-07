package MediaWords::GearmanFunction::CM::DumpControversy;

#
# Dump various controversy queries to csv and build a gexf file
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/CM/DumpControversy.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::GearmanFunction';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::CM::Dump;
use MediaWords::DB;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $controversies_id = $args->{ controversies_id };
    unless ( defined $controversies_id )
    {
        die "'controversies_id' is undefined.";
    }

    my $db = MediaWords::DB::connect_to_db();

    # No transaction started because apparently dump_controversy() does start one itself
    MediaWords::CM::Dump::dump_controversy( $db, $controversies_id );
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
