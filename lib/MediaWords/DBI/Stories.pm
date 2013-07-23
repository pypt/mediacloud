package MediaWords::DBI::Stories;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# various helper functions for stories

use strict;

use Encode;

use MediaWords::Util::BigPDLVector qw(vector_new vector_set vector_dot vector_normalize);
use MediaWords::Util::HTML;
use MediaWords::Util::Web;
use MediaWords::Tagger;
use MediaWords::Util::Config;
use MediaWords::Util::Tags;
use MediaWords::DBI::StoriesTagsMapMediaSubtables;
use MediaWords::DBI::Downloads;
use List::Compare;

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
sub _get_text_from_download_text
{
    my ( $story, $download_texts ) = @_;

    return join( "\n***\n\n",
        html_strip( $story->{ title }       || '' ),
        html_strip( $story->{ description } || '' ),
        @{ $download_texts } );
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

    return _get_text_from_download_text( $story, $download_texts );

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

    say STDERR "is_fully_extracted query returns $bool";

    if ( defined( $bool ) && $bool )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub get_content_for_first_download
{
    my ( $db, $story ) = @_;

    my $first_download = get_first_download( $db, $story );

    say STDERR "got first_download " . Dumper( $first_download );

    if ( $first_download->{ state } ne 'success' )
    {
        return;
    }

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $first_download );

    return $content_ref;
}

# store any content returned by the tagging module in the downloads table
sub _store_tags_content
{
    my ( $db, $story, $module, $tags ) = @_;

    if ( !$tags->{ content } )
    {
        return;
    }

    my $download = $db->query(
        <<"EOF",
        SELECT *
        FROM downloads
        WHERE stories_id = ?
              AND type = 'content'
        ORDER BY downloads_id ASC
        LIMIT 1
EOF
        $story->{ stories_id }
    )->hash;

    my $tags_download = $db->create(
        'downloads',
        {
            feeds_id      => $download->{ feeds_id },
            stories_id    => $story->{ stories_id },
            parent        => $download->{ downloads_id },
            url           => $download->{ url },
            host          => $download->{ host },
            download_time => 'NOW()',
            type          => $module,
            state         => 'pending',
            priority      => 10,
            sequence      => 1
        }
    );

    #my $content = $tags->{content};

    MediaWords::DBI::Downloads::store_content( $db, $tags_download, \$tags->{ content } );
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

# add a tags list as returned by MediaWords::Tagger::get_tags_for_modules to the database.
# handle errors from the tagging module.
# store any content returned by the tagging module.
sub _add_module_tags
{
    my ( $db, $story, $module, $tags ) = @_;

    if ( !$tags->{ tags } )
    {
        print STDERR "tagging error - module: $module story: $story->{stories_id} error: $tags->{error}\n";
        return;
    }

    my $tag_set = $db->find_or_create( 'tag_sets', { name => $module } );

    $db->query(
        <<"EOF",
        DELETE FROM stories_tags_map AS stm USING tags AS t
        WHERE stm.tags_id = t.tags_id
              AND t.tag_sets_id = ?
              AND stm.stories_id = ?
EOF
        $tag_set->{ tag_sets_id },
        $story->{ stories_id }
    );

    my @terms = @{ $tags->{ tags } };

    #print STDERR "tags [$module]: " . join( ',', map { "<$_>" } @terms ) . "\n";

    my @tags_ids = map { _get_tags_id( $db, $tag_set->{ tag_sets_id }, $_ ) } @terms;

    #my $existing_tags = _get_existing_tags( $db, $story, $module );
    #my $lc = List::Compare->new( \@tags_ids, $existing_tags );
    #@tags_ids = $lc->get_Lonly();

    $db->dbh->do( "COPY stories_tags_map (stories_id, tags_id) FROM STDIN" );
    for my $tags_id ( @tags_ids )
    {
        $db->dbh->pg_putcopydata( $story->{ stories_id } . "\t" . $tags_id . "\n" );
    }

    $db->dbh->pg_endcopy();

    my $media_id = $story->{ media_id };
    my $subtable_name =
      MediaWords::DBI::StoriesTagsMapMediaSubtables::get_or_create_sub_table_name_for_media_id( $media_id );

    $db->query(
        <<"EOF",
        DELETE FROM $subtable_name AS stm USING tags AS t
        WHERE stm.tags_id = t.tags_id
              AND t.tag_sets_id = ?
              AND stm.stories_id = ?
EOF
        $tag_set->{ tag_sets_id },
        $story->{ stories_id }
    );

    $db->dbh->do( "COPY $subtable_name (media_id, publish_date, stories_id, tags_id, tag_sets_id) FROM STDIN" );
    for my $tags_id ( @tags_ids )
    {
        my $put_statement =
          join( "\t", $media_id, $story->{ publish_date }, $story->{ stories_id }, $tags_id, $tag_set->{ tag_sets_id } ) .
          "\n";
        $db->dbh->pg_putcopydata( $put_statement );
    }
    $db->dbh->pg_endcopy();

    _store_tags_content( $db, $story, $module, $tags );
}

# add tags for all default modules to the story in the database.
# handle errors and store any content returned by the tagging module.
sub add_default_tags
{
    my ( $db, $story ) = @_;

    my $text = get_text( $db, $story );

    my $default_tag_modules_list = MediaWords::Util::Config::get_config->{ mediawords }->{ default_tag_modules };
    $default_tag_modules_list ||= 'NYTTopics';

    my $default_tag_modules = [ split( /[,\s+]/, $default_tag_modules_list ) ];

    my $module_tags = MediaWords::Tagger::get_tags_for_modules( $text, $default_tag_modules );

    for my $module ( keys( %{ $module_tags } ) )
    {
        _add_module_tags( $db, $story, $module, $module_tags->{ $module } );
    }

    return $module_tags;
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
sub fetch_content
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
    return MediaWords::DBI::Downloads::fetch_content( $download );
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

    return join( ". ", map { $_->{ download_text } } @{ $download_texts } );
}

sub get_extracted_html_from_db
{
    my ( $db, $story ) = @_;

    my $download_texts = $db->query(
        "select dt.* from downloads d, download_texts dt " .
          "  where dt.downloads_id = d.downloads_id and d.stories_id = ? order by d.downloads_id",
        $story->{ stories_id }
    )->hashes;

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

sub get_initial_download_content
{
    my ( $db, $story ) = @_;

    my $download = get_first_download_for_story( $db, $story );

    my $content = MediaWords::DBI::Downloads::fetch_content( $download );

    return $content;
}

# get word vectors for the top 1000 words for each story.
# add a { vector } field to each story where the vector for each
# query is the list of the counts of each word, with each word represented
# by an index value shared across the union of all words for all stories.
# if keep_words is true, also add a { words } field to each story
# with the list of words for each story in { stem => s, term => s, stem_count => s } form.
# if a { words } field is present, reuse that field rather than querying
# the data from the database.
# if $num_words is included, use $num_words max words per story.  default to 100.
# if $stopword_length is included, use 'tiny', 'short', or 'long'.  default to 'short'.
sub add_word_vectors
{
    my ( $db, $stories, $keep_words, $num_words, $stopword_length ) = @_;

    $num_words ||= 100;

    $stopword_length ||= 'short';

    die( "unknown stopword_length '$stopword_length'" ) unless ( grep { $_ eq $stopword_length } qw(tiny short long) );

    my $word_hash;

    my $i               = 0;
    my $next_word_index = 0;
    for my $story ( @{ $stories } )
    {
        print STDERR "add_word_vectors: " . $i++ . "[ $story->{ stories_id } ]\n" unless ( $i % 100 );

        my $sw_check;
        if ( $stopword_length eq 'tiny' )
        {
            $sw_check = '';
        }
        else
        {
            $sw_check = "AND NOT is_stop_stem( '$stopword_length', ssw.stem, ssw.language )";
        }

        my $words = $story->{ words } || $db->query(
            <<"EOF",
            SELECT ssw.stem,
                   MIN(ssw.term) AS term,
                   SUM(stem_count) AS stem_count
            FROM story_sentence_words AS ssw
            WHERE ssw.stories_id = ?
                  $sw_check
            GROUP BY ssw.stem
            ORDER BY SUM(stem_count) DESC
            LIMIT ?
EOF
            $story->{ stories_id },
            $num_words
        )->hashes;

        $story->{ vector } = [ 0 ];

        for my $word ( @{ $words } )
        {
            if ( !defined( $word_hash->{ $word->{ stem } } ) )
            {
                $word_hash->{ $word->{ stem } } = $next_word_index++;
            }

            my $word_index = $word_hash->{ $word->{ stem } };

            $story->{ vector }->[ $word_index ] = $word->{ stem_count };
        }

        if ( $keep_words )
        {
            print STDERR "keep words: " . scalar( @{ $words } ) . "\n";
            $story->{ words } = $words;
        }
    }

    return $stories;
}

# add a { similarities } field that holds the cosine similarity scores between each of the
# stories to each other story.  Assumes that a { vector } has been added to each story
# using add_word_vectors above.
sub add_cos_similarities
{
    my ( $db, $stories ) = @_;

    return if ( !@{ $stories } );

    die( "must call add_word_vectors before add_cos_similarities" ) if ( !$stories->[ 0 ]->{ vector } );

    my $num_words = List::Util::max( map { scalar( @{ $_->{ vector } } ) } @{ $stories } );

    if ( $num_words )
    {
        print STDERR "add_cos_similarities: create normalized pdl vectors ";
        for my $story ( @{ $stories } )
        {
            print STDERR ".";
            my $pdl_vector = vector_new( $num_words );

            for my $i ( 0 .. $num_words - 1 )
            {
                vector_set( $pdl_vector, $i, $story->{ vector }->[ $i ] );
            }
            $story->{ pdl_norm_vector } = vector_normalize( $pdl_vector );
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
                $sim = vector_dot( $stories->[ $i ]->{ pdl_norm_vector }, $stories->[ $j ]->{ pdl_norm_vector } );
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

    my $db_story = $dbs->query(
        <<"EOF",
        SELECT *
        FROM stories
        WHERE guid = ?
              AND media_id = ?
EOF
        $story->{ guid }, $story->{ media_id }
    )->hash;

    $db_story ||= $dbs->query( <<END, $story->{ guid }, $story->{ media_id } )->hash;
select * from stories where guid = ? and media_id = ?
END

    if ( !$db_story )
    {

        my $date = DateTime->from_epoch( epoch => Date::Parse::str2time( $story->{ publish_date } ) );

        my $start_date = $date->subtract( hours => 12 )->iso8601();
        my $end_date = $date->add( hours => 12 )->iso8601();

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

        #say STDERR "Searching for story by title";

        $db_story = $dbs->query(
            <<"EOF",
            SELECT *
            FROM stories
            WHERE title = ?
                  AND media_id = ?
                  AND publish_date BETWEEN ?::DATE AND ?::DATE FOR UPDATE
EOF
            $title,
            $story->{ media_id },
            $start_date,
            $end_date
        )->hash;
    }

    if ( !$db_story )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# re-extract the story for the given download
sub reextract_download
{
    my ( $db, $download ) = @_;

    return if ( $download->{ url } =~ /jpg|pdf|doc|mp3|mp4$/i );

    eval { MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, "restore", 1, 1 ); };
    warn "extract error processing download $download->{ downloads_id }" if ( $@ );
}

sub restore_download_content
{
    my ( $db, $download, $story_content ) = @_;

    MediaWords::DBI::Downloads::store_content( $db, $download, \$story_content );
    reextract_download( $db, $download );
}

# check to see whether the given download is broken
sub download_is_broken
{
    my ( $db, $download ) = @_;

    my $content_ref;
    eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $download ); };

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

# confirm that the date for the story is correct by changing the date_guess_method of the given
# story to 'manual'
sub confirm_date
{
    my ( $db, $story ) = @_;

    $db->query( <<END, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t, tag_sets ts
    where t.tag_sets_id = ts.tag_sets_id and
        stm.tags_id = t.tags_id and
        ts.name = 'date_guess_method' and
        stm.stories_id = ?
END

    my $t = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:manual' );
    $db->query( <<END, $story->{ stories_id }, $t->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END
}

# if the date guess method is manual, remove and replace with an ;unconfirmed' method tag
sub unconfirm_date
{
    my ( $db, $story ) = @_;

    return unless ( date_is_confirmed( $db, $story ) );

    my $manual      = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:manual' );
    my $unconfirmed = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_guess_method:unconfirmed' );

    $db->query( <<END, $story->{ stories_id }, $manual->{ tags_id } );
delete from stories_tags_map where stories_id = ? and tags_id = ?
END

    $db->query( <<END, $story->{ stories_id }, $unconfirmed->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END

}

# return true if the date guess method is manual, which means that the date has been confirmed
sub date_is_confirmed
{
    my ( $db, $story ) = @_;

    my $r = $db->query( <<END, $story->{ stories_id } )->hash;
select 1 from stories_tags_map stm, tags t, tag_sets ts
    where stm.tags_id = t.tags_id and
        ts.tag_sets_id = t.tag_sets_id and
        t.tag = 'manual' and
        ts.name = 'date_guess_method' and
        stm.stories_id = ?
END

    return $r ? 1 : 0;
}

# return true if the date is reliable
sub date_is_reliable
{
    my ( $db, $story ) = @_;

    my $reliable_methods = [ qw(guess_by_url guess_by_url_and_date_text merged_story_rss manual) ];
    my $reliable_methods_list = join( ',', map { $db->dbh->quote( $_ ) } @{ $reliable_methods } );

    my $unreliable_method = $db->query( <<END, $story->{ stories_id } )->hash;
select stm.* 
    from stories_tags_map stm
        join tags t on ( stm.tags_id = t.tags_id ) 
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where
        t.tag not in ( $reliable_methods_list ) and
        ts.name = 'date_guess_method' and
        stm.stories_id = ?
END

    return $unreliable_method ? 0 : 1;
}

# set the undateable status of the story by adding or removing the 'date_guess_method:undateable' tage
sub mark_undateable
{
    my ( $db, $story, $undateable ) = @_;

    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'date_invalid:undateable' );

    $db->query( <<END, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id ) 
    where
        t.tags_id = stm.tags_id and
        ts.name = 'date_invalid' and
        stories_id = ?
END

    if ( $undateable )
    {
        $db->query( <<END, $story->{ stories_id }, $tag->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END
    }
}

# return true if the story has been marked as undateable
sub is_undateable
{
    my ( $db, $story ) = @_;

    my $tag = $db->query( <<END, $story->{ stories_id } )->hash;
select 1
    from stories_tags_map stm
        join tags t on ( stm.tags_id = t.tags_id )
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where
        stm.stories_id = ? and
        ts.name = 'date_invalid' and
        t.tag = 'undateable'
END

    return $tag ? 1 : 0;
}

# assign a tag to the story for the date guess method
sub assign_date_guess_method
{
    my ( $db, $story, $date_guess_method, $no_delete ) = @_;

    if ( !$no_delete )
    {
        for my $tag_set_name ( 'date_guess_method', 'date_invalid' )
        {
            $db->query( <<END, $tag_set_name, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where 
        t.tags_id = stm.tags_id and
        ts.name = ? and
        s.stories_id = ?
END
        }
    }

    my $tag_set_name = ( $date_guess_method eq 'undateable' ) ? 'date_invalid' : 'date_guess_method';

    my $date_guess_method_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "$tag_set_name:$date_guess_method" );
    $db->query( <<END, $story->{ stories_id }, $date_guess_method_tag->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END

}

1;
