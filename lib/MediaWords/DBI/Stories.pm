package MediaWords::DBI::Stories;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various helper functions for stories

use strict;
use warnings;

use Carp;
use Encode;
use HTML::Entities;

use MediaWords::Util::HTML;
use MediaWords::Util::Web;
use MediaWords::Util::Config;
use MediaWords::Util::Tags;
use MediaWords::Util::URL;
use MediaWords::DBI::Downloads;
use MediaWords::Languages::Language;
use MediaWords::StoryVectors;
use List::Compare;

# cached ids of tags, which should change rarely
my $_tags_id_cache = {};

# get cached id of the tag.  create the tag if necessary.
# we need this to make tag lookup very fast for add_default_tags
sub _get_tags_id
{
    my ( $db, $tag_sets_id, $term ) = @_;

    if ( $_tags_id_cache->{ $tag_sets_id }->{ $term } )
    {
        return $_tags_id_cache->{ $tag_sets_id }->{ $term };
    }

    my $tag = $db->find_or_create(
        'tags',
        {
            tag         => $term,
            tag_sets_id => $tag_sets_id
        }
    );

    #Commit to make sure cache and database are consistent
    $db->dbh->{ AutoCommit } || $db->commit;

    $_tags_id_cache->{ $tag_sets_id }->{ $term } = $tag->{ tags_id };

    return $tag->{ tags_id };
}

sub _get_full_text_from_rss
{
    my ( $db, $story ) = @_;

    my $ret = html_strip( $story->{ title } || '' ) . "\n" . html_strip( $story->{ description } || '' );

    return $ret;
}

# get the combined story title, story description, and download text of the text
sub combine_story_title_description_text($$$)
{
    my ( $story_title, $story_description, $download_texts ) = @_;

    return join(
        "\n***\n\n",
        html_strip( $story_title       || '' ),    #
        html_strip( $story_description || '' ),    #
        @{ $download_texts }                       #
    );
}

# get the concatenation of the story title and description and all of the download_texts associated with the story
sub get_text
{
    my ( $db, $story ) = @_;

    if ( _has_full_text_rss( $db, $story ) )
    {
        return _get_full_text_from_rss( $db, $story );
    }

    my $download_texts = $db->query(
        <<"EOF",
        SELECT download_text
        FROM download_texts AS dt,
             downloads AS d
        WHERE d.downloads_id = dt.downloads_id
              AND d.stories_id = ?
        ORDER BY d.downloads_id ASC
EOF
        $story->{ stories_id }
    )->flat;

    my $pending_download = $db->query(
        <<"EOF",
        SELECT downloads_id
        FROM downloads
        WHERE extracted = 'f'
              AND stories_id = ?
              AND type = 'content'
EOF
        $story->{ stories_id }
    )->hash;

    if ( $pending_download )
    {
        push( @{ $download_texts }, "(downloads pending extraction)" );
    }

    return combine_story_title_description_text( $story->{ title }, $story->{ description }, $download_texts );
}

# Like get_text but it doesn't include both the rss information and the extracted text.
# Including both could cause some sentences to appear twice and throw off our word counts.
sub get_text_for_word_counts
{
    my ( $db, $story ) = @_;

    if ( _has_full_text_rss( $db, $story ) )
    {
        return _get_full_text_from_rss( $db, $story );
    }

    return get_extracted_text( $db, $story );
}

sub get_first_download
{
    my ( $db, $story ) = @_;

    return $db->query(
        <<"EOF",
        SELECT *
        FROM downloads
        WHERE stories_id = ?
        ORDER BY sequence ASC
        LIMIT 1
EOF
        $story->{ stories_id }
    )->hash();
}

sub is_fully_extracted
{
    my ( $db, $story ) = @_;

    my ( $bool ) = $db->query(
        <<"EOF",
        SELECT BOOL_AND(extracted)
        FROM downloads
        WHERE stories_id = ?
EOF
        $story->{ stories_id }
    )->flat();

    say STDERR "is_fully_extracted query returns $bool [$story->{ stories_id }]";

    if ( defined( $bool ) && $bool )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub get_content_for_first_download($$)
{
    my ( $db, $story ) = @_;

    my $first_download = get_first_download( $db, $story );

    if ( $first_download->{ state } ne 'success' )
    {
        say STDERR "First download's state is not 'success' for story " . $story->{ stories_id };
        return;
    }

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $first_download );

    return $content_ref;
}

sub get_existing_tags
{
    my ( $db, $story, $module ) = @_;

    my $tag_set = $db->find_or_create( 'tag_sets', { name => $module } );

    my $ret = $db->query(
        <<"EOF",
        SELECT stm.tags_id
        FROM stories_tags_map AS stm,
             tags
        WHERE stories_id = ?
              AND stm.tags_id = tags.tags_id
              AND tags.tag_sets_id = ?
EOF
        $story->{ stories_id },
        $tag_set->{ tag_sets_id }
    )->flat;

    return $ret;
}

sub get_existing_tags_as_string
{
    my ( $db, $stories_id ) = @_;

    # Take note of the old tags
    my $tags = $db->query(
        <<"EOF",
            SELECT stm.stories_id,
                   CAST(ARRAY_AGG(ts.name || ':' || t.tag) AS TEXT) AS tags
            FROM tags t,
                 stories_tags_map stm,
                 tag_sets ts
            WHERE t.tags_id = stm.tags_id
                  AND stm.stories_id = ?
                  AND t.tag_sets_id = ts.tag_sets_id
            GROUP BY stm.stories_id,
                     t.tag_sets_id
            ORDER BY tags
            LIMIT 1
EOF
        $stories_id
    )->hash;

    if ( ref( $tags ) eq 'HASH' and $tags->{ stories_id } )
    {
        $tags = $tags->{ tags };
    }
    else
    {
        $tags = '';
    }

    return $tags;
}

sub get_media_source_for_story
{
    my ( $db, $story ) = @_;

    my $medium = $db->query(
        <<"EOF",
        SELECT *
        FROM media
        WHERE media_id = ?
EOF
        $story->{ media_id }
    )->hash;

    return $medium;
}

sub update_rss_full_text_field
{
    my ( $db, $story ) = @_;

    my $medium = get_media_source_for_story( $db, $story );

    my $full_text_in_rss = 0;

    if ( $medium->{ full_text_rss } )
    {
        $full_text_in_rss = 1;
    }

    #This is a temporary hack to work around a bug in XML::FeedPP
    # Item description() will sometimes return a hash instead of text. In Handler.pm we replaced the hash ref with ''
    if ( defined( $story->{ description } ) && ( length( $story->{ description } ) == 0 ) )
    {
        $full_text_in_rss = 0;
    }

    if ( defined( $story->{ full_text_rss } ) && ( $story->{ full_text_rss } != $full_text_in_rss ) )
    {
        $story->{ full_text_rss } = $full_text_in_rss;
        $db->query(
            <<"EOF",
            UPDATE stories
            SET full_text_rss = ?
            WHERE stories_id = ?
EOF
            $full_text_in_rss, $story->{ stories_id }
        );
    }

    return $story;
}

sub _has_full_text_rss
{
    my ( $db, $story ) = @_;

    return $story->{ full_text_rss };
}

# query the download and call fetch_content
sub fetch_content($$)
{
    my ( $db, $story ) = @_;

    my $download = $db->query(
        <<"EOF",
        SELECT *
        FROM downloads
        WHERE stories_id = ?
EOF
        $story->{ stories_id }
    )->hash;

    return $download ? MediaWords::DBI::Downloads::fetch_content( $db, $download ) : \'';
}

# get the tags for the given module associated with the given story from the db
sub get_db_module_tags
{
    my ( $db, $story, $module ) = @_;

    my $tag_set = $db->find_or_create( 'tag_sets', { name => $module } );

    return $db->query(
        <<"EOF",
        SELECT t.tags_id AS tags_id,
               t.tag_sets_id AS tag_sets_id,
               t.tag AS tag
        FROM stories_tags_map AS stm,
             tags AS t,
             tag_sets AS ts
        WHERE stm.stories_id = ?
              AND stm.tags_id = t.tags_id
              AND t.tag_sets_id = ts.tag_sets_id
              AND ts.name = ?
EOF
        $story->{ stories_id },
        $module
    )->hashes;
}

sub get_extracted_text
{
    my ( $db, $story ) = @_;

    my $download_texts = $db->query(
        <<"EOF",
        SELECT dt.download_text
        FROM downloads AS d,
             download_texts AS dt
        WHERE dt.downloads_id = d.downloads_id
              AND d.stories_id = ?
        ORDER BY d.downloads_id
EOF
        $story->{ stories_id }
    )->hashes;

    return join( ".\n\n", map { $_->{ download_text } } @{ $download_texts } );
}

## TODO rename this function
sub get_extracted_html_from_db
{
    my ( $db, $story ) = @_;

    my $download_texts = $db->query( <<END, $story->{ stories_id } )->hashes;
select dt.downloads_id, dt.download_texts_id
	from downloads d, download_texts dt
	where dt.downloads_id = d.downloads_id and d.stories_id = ? order by d.downloads_id
END

    return join( "\n", map { MediaWords::DBI::DownloadTexts::get_extracted_html_from_db( $db, $_ ) } @{ $download_texts } );
}

sub get_first_download_for_story
{
    my ( $db, $story ) = @_;

    my $download = $db->query(
        <<"EOF",
        SELECT *
        FROM downloads
        WHERE stories_id = ?
        ORDER BY downloads_id ASC
        LIMIT 1
EOF
        $story->{ stories_id }
    )->hash;

    return $download;
}

sub get_initial_download_content($$)
{
    my ( $db, $story ) = @_;

    my $download = get_first_download_for_story( $db, $story );

    my $content = MediaWords::DBI::Downloads::fetch_content( $db, $download );

    return $content;
}

# add a { similarities } field that holds the cosine similarity scores between each of the
# stories to each other story.  Assumes that a { vector } has been added to each story
# using add_word_vectors above.
sub add_cos_similarities
{
    my ( $db, $stories ) = @_;

    require MediaWords::Util::BigPDLVector;

    unless ( scalar @{ $stories } )
    {
        die "'stories' is not an arrayref.";
    }

    unless ( $stories->[ 0 ]->{ vector } )
    {
        die "must call add_word_vectors before add_cos_similarities";
    }

    my $num_words = List::Util::max( map { scalar( @{ $_->{ vector } } ) } @{ $stories } );

    if ( $num_words )
    {
        print STDERR "add_cos_similarities: create normalized pdl vectors ";
        for my $story ( @{ $stories } )
        {
            print STDERR ".";
            my $pdl_vector = MediaWords::Util::BigPDLVector::vector_new( $num_words );

            for my $i ( 0 .. $num_words - 1 )
            {
                MediaWords::Util::BigPDLVector::vector_set( $pdl_vector, $i, $story->{ vector }->[ $i ] );
            }
            $story->{ pdl_norm_vector } = MediaWords::Util::BigPDLVector::vector_normalize( $pdl_vector );
            $story->{ vector }          = undef;
        }
        print STDERR "\n";
    }

    print STDERR "add_cos_similarities: adding sims\n";
    for my $i ( 0 .. $#{ $stories } )
    {
        print STDERR "sims: $i / $#{ $stories }: ";
        $stories->[ $i ]->{ cos }->[ $i ] = 1;

        for my $j ( $i + 1 .. $#{ $stories } )
        {
            print STDERR "." unless ( $j % 100 );
            my $sim = 0;
            if ( $num_words )
            {
                $sim = MediaWords::Util::BigPDLVector::vector_dot( $stories->[ $i ]->{ pdl_norm_vector },
                    $stories->[ $j ]->{ pdl_norm_vector } );
            }

            $stories->[ $i ]->{ similarities }->[ $j ] = $sim;
            $stories->[ $j ]->{ similarities }->[ $i ] = $sim;
        }

        print STDERR "\n";
    }

    map { $_->{ pdl_norm_vector } = undef } @{ $stories };
}

# Determines if similar story already exist in the database
# Note that calling this function on stories already in the database makes no sense.
sub is_new
{
    my ( $dbs, $story ) = @_;

    my $db_story = $dbs->query( <<"END", $story->{ guid }, $story->{ media_id } )->hash;
SELECT *
    FROM stories
    WHERE
        guid = ?
        AND media_id = ?
END

    return 0 if ( $db_story );

    return 0 if ( $story->{ title } eq '(no title)' );

    # TODO -- DRL not sure if assuming UTF-8 is a good idea but will experiment with this code from the gsoc_dsheets branch
    my $title;

    # This unicode decode may not be necessary! XML::Feed appears to at least /sometimes/ return
    # character strings instead of byte strings. Decoding a character string is an error. This code now
    # only fails if a non-ASCII byte-string is returned from XML::Feed.

    # very misleadingly named function checks for unicode character string
    # in perl's internal representation -- not a byte-string that contains UTF-8
    # data

    if ( Encode::is_utf8( $story->{ title } ) )
    {
        $title = $story->{ title };
    }
    else
    {
        # TODO: A utf-8 byte string is only highly likely... we should actually examine the HTTP
        #   header or the XML pragma so this doesn't explode when given another encoding.
        $title = decode( 'utf-8', $story->{ title } );
    }

    # we do the goofy " + interval '1 second'" to force postgres to use the stories_title_hash index
    $db_story = $dbs->query( <<END, $title, $story->{ media_id }, $story->{ publish_date } )->hash;
SELECT 1
    FROM stories
    WHERE
        md5( title ) = md5( ? ) AND
        media_id = ? AND
        date_trunc( 'day', publish_date )  + interval '1 second' =
            date_trunc( 'day', ?::date ) + interval '1 second'
    FOR UPDATE
END

    return 0 if ( $db_story );

    return 1;
}

# re-extract the story for the given download
sub reextract_download
{
    my ( $db, $download ) = @_;

    if ( $download->{ url } =~ /jpg|pdf|doc|mp3|mp4$/i )
    {
        warn "Won't reextract download " .
          $download->{ downloads_id } . " because the URL doesn't look like it could contain text.";
        return;
    }

    eval { MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, "restore", 1, 1 ); };
    if ( $@ )
    {
        warn "extract error processing download $download->{ downloads_id }: $@";
    }
}

sub _get_current_extractor_version
{
    my $config           = MediaWords::Util::Config::get_config;
    my $extractor_method = $config->{ mediawords }->{ extractor_method };

    my $extractor_version;

    if ( $extractor_method eq 'PythonReadability' )
    {
        $extractor_version = MediaWords::Util::ThriftExtractor::extractor_version();
    }
    else
    {
        my $old_extractor = MediaWords::Util::ExtractorFactory::createExtractor();
        $extractor_version = $old_extractor->extractor_version();
    }

    die unless defined( $extractor_version ) && $extractor_version;

    return $extractor_version;
}

sub extract_and_process_story
{
    my ( $story, $db, $process_num ) = @_;

    #say STDERR "Starting extract_and_process_story for " . $story->{ stories_id };

    my $query = <<"EOF";
        SELECT *
        FROM downloads
        WHERE stories_id = ?
              AND type = 'content'
        ORDER BY downloads_id ASC
EOF

    my $downloads = $db->query( $query, $story->{ stories_id } )->hashes();

    foreach my $download ( @{ $downloads } )
    {
        my $download_text = MediaWords::DBI::Downloads::extract_only( $db, $download );

        #say STDERR "Got download_text";
    }

    my $no_dedup_sentences = 0;
    my $no_vector          = 0;

    process_extracted_story( $story, $db, 0, 0 );

    #say STDERR "Finished extract_and_process_story for " . $story->{ stories_id };

    # Extraction succeeded
    $db->commit;
}

sub process_extracted_story
{
    my ( $story, $db, $no_dedup_sentences, $no_vector ) = @_;

    unless ( $no_vector )
    {
        MediaWords::StoryVectors::update_story_sentences_and_language( $db, $story, 0, $no_dedup_sentences );
    }

    $db->query(
        "UPDATE stories SET disable_triggers  = ? WHERE stories_id = ?",
        MediaWords::DB::story_triggers_disabled(),
        $story->{ stories_id }
    );

    MediaWords::DBI::Stories::_update_extractor_version_tag( $db, $story );

    my $stories_id = $story->{ stories_id };

    if (    MediaWords::Util::CoreNLP::annotator_is_enabled()
        and MediaWords::Util::CoreNLP::story_is_annotatable( $db, $stories_id ) )
    {
        # Story is annotatable with CoreNLP; enqueue for CoreNLP annotation
        # (which will run mark_as_processed() on its own)
        MediaWords::GearmanFunction::AnnotateWithCoreNLP->enqueue_on_gearman( { stories_id => $stories_id } );

    }
    else
    {
        # Story is not annotatable with CoreNLP; add to "processed_stories" right away
        unless ( MediaWords::DBI::Stories::mark_as_processed( $db, $stories_id ) )
        {
            die "Unable to mark story ID $stories_id as processed";
        }
    }
}

sub restore_download_content
{
    my ( $db, $download, $story_content ) = @_;

    MediaWords::DBI::Downloads::store_content( $db, $download, \$story_content );
    reextract_download( $db, $download );
}

# check to see whether the given download is broken
sub download_is_broken($$)
{
    my ( $db, $download ) = @_;

    my $content_ref;
    eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download ); };

    return 0 if ( $content_ref && ( length( $$content_ref ) > 32 ) );

    return 1;
}

# for each download, refetch the content and add a { content } field with the
# fetched content
sub get_broken_download_content
{
    my ( $db, $downloads ) = @_;

    my $urls = [ map { URI->new( $_->{ url } )->as_string } @{ $downloads } ];

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );

    my $download_lookup = {};
    map { $download_lookup->{ URI->new( $_->{ url } )->as_string } = $_ } @{ $downloads };

    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;

        $download_lookup->{ $original_url }->{ content } = $response->decoded_content;
    }
}

# if this story is one of the ones for which we lost the download, refetch the content_ref
sub fix_story_downloads_if_needed
{
    my ( $db, $story ) = @_;

    if ( $story->{ url } =~ /livejournal.com/ )
    {

        # hack to fix livejournal extra pages, which are misparsing errors from Pager.pm
        $db->query( <<END, $story->{ stories_id } );
delete from downloads where stories_id = ? and sequence > 1
END
    }

    my $downloads = $db->query( <<END, $story->{ stories_id } )->hashes;
select * from downloads where stories_id = ? order by downloads_id
END

    my $broken_downloads = [ grep { download_is_broken( $db, $_ ) } @{ $downloads } ];

    my $fetch_downloads = [];
    for my $download ( @{ $broken_downloads } )
    {
        if ( my $cached_download = $story->{ cached_downloads }->{ $download->{ downloads_id } } )
        {
            $download->{ content } = MediaWords::Util::Web::get_cached_link_download( $cached_download );
        }
        else
        {
            push( @{ $fetch_downloads }, $download );
        }
    }

    get_broken_download_content( $db, $fetch_downloads );

    for my $download ( @{ $broken_downloads } )
    {
        restore_download_content( $db, $download, $download->{ content } );
    }
}

my $_extractor_version_tag_set;

sub _get_extractor_version_tag_set
{

    my ( $db ) = @_;

    if ( !defined( $_extractor_version_tag_set ) )
    {
        $_extractor_version_tag_set = MediaWords::Util::Tags::lookup_or_create_tag_set( $db, "extractor_version" );
    }

    return $_extractor_version_tag_set;
}

sub get_current_extractor_version_tags_id
{
    my ( $db ) = @_;

    my $extractor_version = _get_current_extractor_version();
    my $tag_set           = _get_extractor_version_tag_set( $db );

    my $tags_id = _get_tags_id( $db, $tag_set->{ tag_sets_id }, $extractor_version );

    return $tags_id;
}

# add extractor version tag
sub _update_extractor_version_tag
{
    my ( $db, $story ) = @_;

    my $tag_set = _get_extractor_version_tag_set( $db );

    $db->query( <<END, $tag_set->{ tag_sets_id }, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where
        t.tags_id = stm.tags_id and
        ts.tag_sets_id = ? and
        stm.stories_id = ?
END

    my $tags_id = get_current_extractor_version_tags_id( $db );

    $db->query( <<END, $story->{ stories_id }, $tags_id );
insert into stories_tags_map ( stories_id, tags_id, db_row_last_updated ) values ( ?, ?, now() )
END

}

# if no story_sentences exist for the story, add them
sub add_missing_story_sentences
{
    my ( $db, $story ) = @_;

    my $ss = $db->query( "select 1 from story_sentences ss where stories_id = ?", $story->{ stories_id } )->hash;

    return if ( $ss );

    print STDERR "ADD SENTENCES [$story->{ stories_id }]\n";

    MediaWords::StoryVectors::update_story_sentences_and_language( $db, $story, 0, 0, 1 );
}

# get list of all sentences in story from the extracted text and annotate each with a dup_stories_id
# field if it is a duplicate sentence
sub get_all_sentences
{
    my ( $db, $story ) = @_;

    # Tokenize into sentences
    my $lang = MediaWords::Languages::Language::language_for_code( $story->{ language } )
      || MediaWords::Languages::Language::default_language();

    my $text = get_text( $db, $story );
    unless ( defined $text )
    {
        warn "Text for story " . $story->{ stories_id } . " is undefined.";
        return;
    }
    unless ( length( $text ) )
    {
        warn "Story " . $story->{ stories_id } . " text is an empty string.";
        return;
    }

    my $raw_sentences = $lang->get_sentences( $text );
    unless ( defined $raw_sentences )
    {
        die "Sentences for story " . $story->{ stories_id } . " are undefined.";
    }
    unless ( scalar @{ $raw_sentences } )
    {
        warn "Story " . $story->{ stories_id } . " doesn't have any sentences.";
        return;
    }

    my $all_sentences = [];
    for my $sentence ( @{ $raw_sentences } )
    {
        my $ssc = $db->query( <<END, $sentence, $story->{ media_id }, $story->{ publish_date } )->hash;
select *
    from story_sentence_counts
    where sentence_md5 = MD5( ? ) and
        media_id = ? and
        publish_week = DATE_TRUNC( 'week', ?::date )
    limit 1
END
        push( @{ $all_sentences }, { sentence => $sentence, count => $ssc, stories_id => $story->{ stories_id } } );
    }

    return $all_sentences;
}

# Mark the story as processed by INSERTing an entry into "processed_stories"
#
# Parameters:
# * $db -- database object
# * $stories_id -- "stories_id" to insert into "processed_stories"
#
# Return true on success, false on failure
sub mark_as_processed($$)
{
    my ( $db, $stories_id ) = @_;

    eval {
        $db->insert( 'processed_stories',
            { stories_id => $stories_id, disable_triggers => MediaWords::DB::story_triggers_disabled() } );
    };
    if ( $@ )
    {
        warn "Unable to insert story ID $stories_id into 'processed_stories': $@";
        return 0;
    }
    else
    {
        return 1;
    }
}

# given two lists of hashes, $stories and $story_data, each with
# a stories_id field in each row, assign each key:value pair in
# story_data to the corresponding row in $stories.  if $list_field
# is specified, push each the value associate with key in each matching
# stories_id row in story_data field into a list with the name $list_field
# in stories
sub attach_story_data_to_stories
{
    my ( $stories, $story_data, $list_field ) = @_;

    map { $_->{ $list_field } = [] } @{ $stories } if ( $list_field );

    unless ( scalar @{ $story_data } )
    {
        return;
    }

    my $story_data_lookup = {};
    for my $sd ( @{ $story_data } )
    {
        if ( $list_field )
        {
            $story_data_lookup->{ $sd->{ stories_id } } //= { $list_field => [] };
            push( @{ $story_data_lookup->{ $sd->{ stories_id } }->{ $list_field } }, $sd );
        }
        else
        {
            $story_data_lookup->{ $sd->{ stories_id } } = $sd;
        }
    }

    for my $story ( @{ $stories } )
    {
        if ( my $sd = $story_data_lookup->{ $story->{ stories_id } } )
        {
            map { $story->{ $_ } = $sd->{ $_ } } keys( %{ $sd } );
        }
    }
}

# call attach_story_data_to_stories_ids with a basic query that includes the fields:
# stories_id, title, publish_date, url, guid, media_id, language, media_name
sub attach_story_meta_data_to_stories
{
    my ( $db, $stories ) = @_;

    $db->begin;

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    my $story_data = $db->query( <<END )->hashes;
select s.stories_id, s.title, s.publish_date, s.url, s.guid, s.media_id, s.language, m.name media_name
    from stories s join media m on ( s.media_id = m.media_id )
    where s.stories_id in ( select id from $ids_table )
END

    attach_story_data_to_stories( $stories, $story_data );

    $db->commit;

    return $stories;
}

# break a story down into parts separated by [-:|]
sub get_title_parts
{
    my ( $title ) = @_;

    $title = decode_entities( $title );

    $title = lc( $title );
    $title =~ s/\s+/ /g;
    $title =~ s/^\s+//;
    $title =~ s/\s+$//;

    my $title_parts;
    if ( $title =~ m~http://[^ ]*^~ )
    {
        $title_parts = [ $title ];
    }
    else
    {
        $title_parts = [ split( /\s*[-:|]+\s*/, $title ) ];
    }

    map { s/^\s+//; s/\s+$//; s/[[:punct:]]//g; } @{ $title_parts };

    if ( @{ $title_parts } > 1 )
    {
        unshift( @{ $title_parts }, $title );
    }

    return $title_parts;
}

# get duplicate stories within the set of stories by breaking the title
# of each story into parts by [-:|] and looking for any such part
# that is the sole title part for any story and is at least 4 words long and
# is not the title of a story with a path-less url.  Any story that includes that title
# part becames a duplicate.  return a list of duplciate story lists. do not return
# any list of duplicates with greater than 25 duplicates for fear that the title deduping is
# interacting with some title form in a goofy way
sub get_medium_dup_stories_by_title
{
    my ( $db, $stories ) = @_;

    my $title_part_counts = {};
    for my $story ( @{ $stories } )
    {
        # don't try to dedup twitter stories by title, because the title of a tweet
        # is just the tweet, and we want to capture retweets
        next if ( $_->{ url } && ( $_->{ url } =~ /https?:\/\/(twitter\.com|t\.co)/i ) );

        my $title_parts = get_title_parts( $story->{ title } );

        for ( my $i = 0 ; $i < @{ $title_parts } ; $i++ )
        {
            my $title_part = $title_parts->[ $i ];

            if ( $i == 0 )
            {
                # solo title parts that are only a few words might just be the media source name
                my $num_words = scalar( split( / /, $title_part ) );
                next if ( $num_words < 5 );

                # likewise, a solo title of a story with a url with no path is probably
                # the media source name
                next if ( URI->new( $story->{ url } )->path =~ /^\/?$/ );

                $title_part_counts->{ $title_parts->[ 0 ] }->{ solo } = 1;
            }

            my $id = $story->{ stories_id } || $story->{ guid };

            $title_part_counts->{ $title_part }->{ count }++;
            $title_part_counts->{ $title_part }->{ stories }->{ $id } = $story;
        }
    }

    my $duplicate_stories = [];
    for my $t ( grep { $_->{ solo } } values( %{ $title_part_counts } ) )
    {
        my $num_stories = scalar( keys( %{ $t->{ stories } } ) );
        if ( $num_stories > 1 )
        {
            if ( $num_stories < 26 )
            {
                push( @{ $duplicate_stories }, [ values( %{ $t->{ stories } } ) ] );
            }
            else
            {
                my $dup_title = ( values( %{ $t->{ stories } } ) )[ 0 ]->{ title };
                warn( "cowardly refusing to mark $num_stories stories as dups [$dup_title]" );
            }
        }
    }

    return $duplicate_stories;
}

# get duplicate stories within the given set that are duplicates because the normalized url
# for two given stories is the same.  return a list of story duplicate lists.  do not return
# any list of duplicates with greater than 5 duplicates for fear that the url normalization is
# interacting with some url form in a goofy way
sub get_medium_dup_stories_by_url
{
    my ( $db, $stories ) = @_;

    my $url_lookup = {};
    for my $story ( @{ $stories } )
    {
        if ( !$story->{ url } )
        {
            warn( "no url in story: " . Dumper( $story ) );
            next;
        }

        my $nu = MediaWords::Util::URL::normalize_url_lossy( $story->{ url } )->as_string;
        $story->{ normalized_url } = $nu;
        push( @{ $url_lookup->{ $nu } }, $story );
    }

    return [ grep { ( @{ $_ } > 1 ) && ( @{ $_ } < 6 ) } values( %{ $url_lookup } ) ];
}

# get duplicate stories within the given set that have duplicate guids
sub get_medium_dup_stories_by_guid
{
    my ( $db, $stories ) = @_;

    my $guid_lookup = {};
    for my $story ( @{ $stories } )
    {
        die( "no guid in story: " . Dumper( $story ) ) unless ( $story->{ guid } );
        push( @{ $guid_lookup->{ $story->{ guid } } }, $story );
    }

    return [ grep { @{ $_ } > 1 } values( %{ $guid_lookup } ) ];
}

# parse the content for tags that might indicate the story's title
sub get_story_title_from_content
{
    my ( $content, $url ) = @_;

    my $title;

    if ( $content =~ m~<meta property=\"og:title\" content=\"([^\"]+)\"~si )
    {
        $title = $1;
    }
    elsif ( $content =~ m~<meta property=\"og:title\" content=\'([^\']+)\'~si )
    {
        $title = $1;
    }
    elsif ( $content =~ m~<title>([^<]+)</title>~si )
    {
        $title = $1;
    }
    else
    {
        $title = $url;
    }

    if ( length( $title ) > 1024 )
    {
        $title = substr( $title, 0, 1024 );
    }

    return $title;
}

1;
