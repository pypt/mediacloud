# Temporary crawler

## Setting up a temporary crawler

On the system with permanent crawler:

    cd mediacloud/script
    ./dump_media_and_feeds_information.sh

Copy the contents of `mediacloud/data/media_and_feed_list` on the permanent system to `mediacloud/data/media_and_feed_list` on the backup system.

On the back up system:

* Create a new media cloud database on the backup system and set `$PGDATABASE` to the name of this database
* Add the new media cloud database to `mediawords.yml` and set it as the default db
* Run `./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl --dump-env-commands` and copy paste + execute all 4 commands
* Run `./script/run_with_carton.sh ./script/mediawords_create_db.pl`
    * WARNING: RUNNING THIS COMMAND WILL PURGE WHATEVER DATABASE IS LISTED AS THE DEFAULT IN `MEDIAWORDS.YML`
* `cd` to `mediacloud/script` and run: `./restore_media_and_feed_information.sh`
* Edit `mediawords.yml` and set `mediawords: do_not_process_feeds` to `yes`


## Stop the crawler on the permanent system

Run the crawler on the backup system.

When you're ready to switch back to the permanent system, stop the crawler on the backup system

Start the crawler on the production system

Stop the crawler on the backup system

On the backup system run `./script/mediawords_export_feed_downloads.pl`

After this script completes copy files `/tmp/downloads*.xml` to the permanent system.

On the permanent system, CD to the directory with the `download*.xml` files and run a command like the following:

    find `pwd` -iname '*.xml' -print | \
    sort | \
    nohup time parallel --keep-order --max-procs +5 \
    /space/mediacloud/mediacloud/script/run_with_carton.sh \
    /space/mediacloud/mediacloud_RELEASE_20140325/script/mediawords_import_feed_downloads.pl | \
    tee downloads_import.log
