/* schema for MediaWords database */

-- This function is needed because date_trunc('week', date) is not consider immutable 
-- See http://www.mentby.com/Group/pgsql-general/datetrunc-on-date-is-immutable.html
--
CREATE OR REPLACE FUNCTION week_start_date(day date)
    RETURNS date AS
$$
DECLARE
    date_trunc_result date;
BEGIN
    date_trunc_result := date_trunc('week', day::timestamp);
    RETURN date_trunc_result;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE
  COST 10;

CREATE OR REPLACE FUNCTION loop_forever()
    RETURNS VOID AS
$$
DECLARE
    temp integer;
BEGIN
   temp := 1;
   LOOP
    temp := temp + 1;
    perform pg_sleep( 1 );
    RAISE NOTICE 'time - %', temp; 
   END LOOP;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE
  COST 10;


CREATE OR REPLACE FUNCTION purge_story_words(default_start_day date, default_end_day date)
  RETURNS VOID  AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
BEGIN
    current_time := timeofday()::timestamp;

    RAISE NOTICE 'time - %', current_time;

    IF ( ( not default_start_day is null ) and ( not default_end_day is null ) ) THEN
       RAISE NOTICE 'deleting for media without explict sw dates';
       DELETE from story_sentence_words where not media_id in ( select media_id from media where ( not (sw_data_start_date is null)) and (not (sw_data_end_date is null)) )
          AND ( publish_day < default_start_day or publish_day > default_end_day);
    END IF;

    FOR media_rec in  SELECT media_id, coalesce( sw_data_start_date, default_start_day ) as start_date FROM media where not (coalesce ( sw_data_start_date, default_start_day ) is null ) and (not sw_data_start_date is null) and (not sw_data_end_date is null) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, start_date - % time - %', media_rec.media_id, media_rec.start_date, current_time;
        DELETE from story_sentence_words where media_id = media_rec.media_id and publish_day < media_rec.start_date; 
    END LOOP;

  RAISE NOTICE 'time - %', current_time;  -- Prints 30
  FOR media_rec in  SELECT media_id, coalesce( sw_data_end_date, default_end_day ) as end_date FROM media where not (coalesce ( sw_data_end_date, default_end_day ) is null ) and (not sw_data_start_date is null) and (not sw_data_end_date is null) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, end_date - % time - %', media_rec.media_id, media_rec.end_date, current_time;
        DELETE from story_sentence_words where media_id = media_rec.media_id and publish_day > media_rec.end_date; 
    END LOOP;
END;
$$
LANGUAGE 'plpgsql'
 ;

CREATE OR REPLACE FUNCTION purge_story_sentences(default_start_day date, default_end_day date)
  RETURNS VOID  AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
BEGIN
    current_time := timeofday()::timestamp;

    RAISE NOTICE 'time - %', current_time;
    FOR media_rec in  SELECT media_id, coalesce( sw_data_start_date, default_start_day ) as start_date FROM media where not (coalesce ( sw_data_start_date, default_start_day ) is null ) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, start_date - % time - %', media_rec.media_id, media_rec.start_date, current_time;
        DELETE from story_sentences where media_id = media_rec.media_id and date_trunc( 'day', publish_date ) < date_trunc( 'day', media_rec.start_date ); 
    END LOOP;

  RAISE NOTICE 'time - %', current_time;  -- Prints 30
  FOR media_rec in  SELECT media_id, coalesce( sw_data_end_date, default_end_day ) as end_date FROM media where not (coalesce ( sw_data_end_date, default_end_day ) is null ) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, end_date - % time - %', media_rec.media_id, media_rec.end_date, current_time;
        DELETE from story_sentences where media_id = media_rec.media_id and date_trunc( 'day', publish_date ) > date_trunc( 'day', media_rec.end_date ); 
    END LOOP;
END;
$$
LANGUAGE 'plpgsql'
 ;

CREATE OR REPLACE FUNCTION purge_story_sentence_counts(default_start_day date, default_end_day date)
  RETURNS VOID  AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
BEGIN
    current_time := timeofday()::timestamp;

    RAISE NOTICE 'time - %', current_time;
    FOR media_rec in  SELECT media_id, coalesce( sw_data_start_date, default_start_day ) as start_date FROM media where not (coalesce ( sw_data_start_date, default_start_day ) is null ) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, start_date - % time - %', media_rec.media_id, media_rec.start_date, current_time;
        DELETE from story_sentence_counts where media_id = media_rec.media_id and publish_week < date_trunc( 'day', media_rec.start_date ); 
    END LOOP;

  RAISE NOTICE 'time - %', current_time;  -- Prints 30
  FOR media_rec in  SELECT media_id, coalesce( sw_data_end_date, default_end_day ) as end_date FROM media where not (coalesce ( sw_data_end_date, default_end_day ) is null ) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, end_date - % time - %', media_rec.media_id, media_rec.end_date, current_time;
        DELETE from story_sentence_counts where media_id = media_rec.media_id and publish_week > date_trunc( 'day', media_rec.end_date ); 
    END LOOP;
END;
$$
LANGUAGE 'plpgsql'
 ;

create table media (
    media_id            serial          primary key,
    url                 varchar(1024)   not null,
    name                varchar(128)    not null,
    moderated           boolean         not null,
    feeds_added         boolean         not null,
    moderation_notes    text            null,       
    full_text_rss       boolean,
    extract_author      boolean         default(false),
    sw_data_start_date  date            default(null),
    sw_data_end_date    date            default(null),
    CONSTRAINT media_name_not_empty CHECK (((name)::text <> ''::text))
);

create unique index media_name on media(name);
create unique index media_url on media(url);
create index media_moderated on media(moderated);

create type feed_feed_type AS ENUM ( 'syndicated', 'web_page' );

create table feeds (
    feeds_id            serial          primary key,
    media_id            int             not null references media on delete cascade,
    name                varchar(512)    not null,        
    url                 varchar(1024)   not null,
    reparse             boolean         null,
    last_download_time  timestamp       null, 
    feed_type           feed_feed_type  not null default 'syndicated'
);

create index feeds_media on feeds(media_id);
create index feeds_name on feeds(name);
create unique index feeds_url on feeds (url, media_id);
create index feeds_reparse on feeds(reparse);
create index feeds_last_download_time on feeds(last_download_time);

create table tag_sets (
    tag_sets_id            serial            primary key,
    name                varchar(512)    not null,
    CONSTRAINT tag_sets_name_not_empty CHECK (((name)::text <> ''::text))
);

create unique index tag_sets_name on tag_sets (name);

create table tags (
    tags_id                serial            primary key,
    tag_sets_id            int                not null references tag_sets,
    tag                    varchar(512)    not null,
        CONSTRAINT no_lead_or_trailing_whitspace CHECK ((((((tag_sets_id = 13) OR (tag_sets_id = 9)) OR (tag_sets_id = 8)) OR (tag_sets_id = 6)) OR ((tag)::text = btrim((tag)::text, ' 
    '::text)))),
        CONSTRAINT no_line_feed CHECK (((NOT ((tag)::text ~~ '%
%'::text)) AND (NOT ((tag)::text ~~ '%
%'::text)))),
        CONSTRAINT tag_not_empty CHECK (((tag)::text <> ''::text))
);

create unique index tags_tag on tags (tag, tag_sets_id);
create index tags_tag_1 on tags (split_part(tag, ' ', 1));
create index tags_tag_2 on tags (split_part(tag, ' ', 2));
create index tags_tag_3 on tags (split_part(tag, ' ', 3));

create view tags_with_sets as select t.*, ts.name as tag_set_name from tags t, tag_sets ts where t.tag_sets_id = ts.tag_sets_id;

create table feeds_tags_map (
    feeds_tags_map_id    serial            primary key,
    feeds_id            int                not null references feeds on delete cascade,
    tags_id                int                not null references tags on delete cascade
);

create unique index feeds_tags_map_feed on feeds_tags_map (feeds_id, tags_id);
create index feeds_tags_map_tag on feeds_tags_map (tags_id);

create table media_tags_map (
    media_tags_map_id    serial            primary key,
    media_id            int                not null references media on delete cascade,
    tags_id                int                not null references tags on delete cascade
);

create unique index media_tags_map_media on media_tags_map (media_id, tags_id);
create index media_tags_map_tag on media_tags_map (tags_id);

/*
A dashboard defines which collections, dates, and topics appear together within a given dashboard screen.

For example, a dashboard might include three media_sets for russian collections, a set of dates for which 
to generate a dashboard for those collections, and a set of topics to use for specific dates for all media
sets within the collection
*/
create table dashboards (
    dashboards_id               serial          primary key,
    name                        varchar(1024)   not null,
    start_date                  timestamp       not null,
    end_date                    timestamp       not null
);

create unique index dashboards_name on dashboards ( name );

CREATE TYPE query_version_enum AS ENUM ('1.0');

create table queries (
    queries_id              serial              primary key,
    start_date              date                not null,
    end_date                date                not null,
    generate_page           boolean             not null default false,
    creation_date           timestamp           not null default now(),
    description             text                null,
    dashboards_id           int                 null references dashboards,
    md5_signature           varchar(32)         not null
);


create index queries_creation_date on queries (creation_date);
ALTER TABLE queries ADD COLUMN query_version query_version_enum DEFAULT enum_last (null::query_version_enum ) NOT NULL;
create unique index queries_signature_version on queries ( md5_signature, query_version );
create unique index queries_signature on queries (md5_signature);

create table media_cluster_runs (
	media_cluster_runs_id   serial          primary key,
	queries_id              int             not null references queries,
	num_clusters			int			    not null,
	state                   varchar(32)     not null default 'pending',
    clustering_engine       varchar(256)    not null
);

alter table media_cluster_runs add constraint media_cluster_runs_state check (state in ('pending', 'executing', 'completed'));

create table media_clusters (
	media_clusters_id		serial	primary key,
	media_cluster_runs_id	int	    not null references media_cluster_runs on delete cascade,
	description             text    null,
	centroid_media_id       int     null references media on delete cascade
);
CREATE INDEX media_clusters_runs_id on media_clusters(media_cluster_runs_id);
   
/* 
sets of media sources that should appear in the dashboard

the contents of the row depend on the set_type, which can be one of:
medium -- a single medium (media_id)
collection -- all media associated with the given tag (tags_id)
cluster -- all media within the given clusters (clusters_id)

see the check constraint for the definition of which set_type has which rows set
*/
create table media_sets (
    media_sets_id               serial      primary key,
    name                        text        not null,
    description                 text        null,
    set_type                    text        not null,
    media_id                    int         references media on delete cascade,
    tags_id                     int         references tags on delete cascade,
    media_clusters_id           int         references media_clusters on delete cascade,
    creation_date               timestamp   default now(),
    vectors_added               boolean     default false,
    include_in_dump             boolean     default true
);

CREATE VIEW media_sets_tt2_locale_format as select  '[% c.loc("' || COALESCE( name, '') || '") %]' || E'\n' ||  '[% c.loc("' || COALESCE (description, '') || '") %] ' as tt2_value from media_sets where set_type = 'collection' order by media_sets_id;

    
create table queries_media_sets_map (
    queries_id              int                 not null references queries on delete cascade,
    media_sets_id           int                 not null references media_sets on delete cascade
);

create index queries_media_sets_map_query on queries_media_sets_map ( queries_id );
create index queries_media_sets_map_media_set on queries_media_sets_map ( media_sets_id );

create table media_cluster_maps (
    media_cluster_maps_id       serial          primary key,
    method                      varchar(256)    not null,
    map_type                    varchar(32)     not null default 'cluster',
    name                        text            not null,
    json                        text            not null,
    nodes_total                 int             not null,
    nodes_rendered              int             not null,
    links_rendered              int             not null,
    media_cluster_runs_id       int             not null references media_cluster_runs on delete cascade
);
    
alter table media_cluster_maps add constraint media_cluster_maps_type check( map_type in ('cluster', 'polar' ));

create index media_cluster_maps_run on media_cluster_maps( media_cluster_runs_id );

create table media_cluster_map_poles (
    media_cluster_map_poles_id      serial      primary key,
    name                            text        not null,
    media_cluster_maps_id           int         not null references media_cluster_maps on delete cascade,
    pole_number                     int         not null,
    queries_id                      int         not null references queries on delete cascade
);

create index media_cluster_map_poles_map on media_cluster_map_poles( media_cluster_maps_id );

create table media_clusters_media_map (
    media_clusters_media_map_id     serial primary key,
	media_clusters_id               int   not null references media_clusters on delete cascade,
	media_id		                int   not null references media on delete cascade
);

create index media_clusters_media_map_cluster on media_clusters_media_map (media_clusters_id);
create index media_clusters_media_map_media on media_clusters_media_map (media_id);

create table media_cluster_words (
	media_cluster_words_id	serial	primary key,
	media_clusters_id       int	    not null references media_clusters on delete cascade,
    internal                boolean not null,
	weight			        float	not null,
	stem			        text	not null,
	term                    text    not null
);

create index media_cluster_words_cluster on media_cluster_words (media_clusters_id);

/****************************************************** 
 * Jon's table for storing links between media sources
 *  -> Used in Protovis' force visualization. 
 ******************************************************/

create table media_cluster_links (
  media_cluster_links_id    serial  primary key,
  media_cluster_runs_id	    int	    not null     references media_cluster_runs on delete cascade,
  source_media_id           int     not null     references media              on delete cascade,
  target_media_id           int     not null     references media              on delete cascade,
  weight                    float   not null
);

/****************************************************** 
 * A table to store the internal/external zscores for
 *   every source analyzed by Cluto
 *   (the external/internal similarity scores for
 *     clusters will be stored in media_clusters, if at all)
 ******************************************************/

create table media_cluster_zscores (
  media_cluster_zscores_id  serial primary key,
	media_cluster_runs_id	    int 	 not null     references media_cluster_runs on delete cascade,
	media_clusters_id         int    not null     references media_clusters     on delete cascade,
  media_id                  int    not null     references media              on delete cascade,
  internal_zscore           float  not null, 
  internal_similarity       float  not null,
  external_zscore           float  not null,
  external_similarity       float  not null     
);

-- alter table media_cluster_runs add constraint media_cluster_runs_media_set_fk foreign key ( media_sets_id ) references media_sets;
  
alter table media_sets add constraint dashboard_media_sets_type
check ( ( ( set_type = 'medium' ) and ( media_id is not null ) )
        or
        ( ( set_type = 'collection' ) and ( tags_id is not null ) )
        or
        ( ( set_type = 'cluster' ) and ( media_clusters_id is not null ) ) );

create unique index media_sets_medium on media_sets ( media_id );
create index media_sets_tag on media_sets ( tags_id );
create index media_sets_cluster on media_sets ( media_clusters_id );
create index media_sets_vectors_added on media_sets ( vectors_added );
        
create table media_sets_media_map (
    media_sets_media_map_id     serial  primary key,
    media_sets_id               int     not null references media_sets on delete cascade,    
    media_id                    int     not null references media on delete cascade
);

create index media_sets_media_map_set on media_sets_media_map ( media_sets_id );
create index media_sets_media_map_media on media_sets_media_map ( media_id );

CREATE OR REPLACE FUNCTION media_set_sw_data_retention_dates(v_media_sets_id int, default_start_day date, default_end_day date, OUT start_date date, OUT end_date date) AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
BEGIN
    current_time := timeofday()::timestamp;

    --RAISE NOTICE 'time - % ', current_time;

    SELECT media_sets_id, min(coalesce (media.sw_data_start_date, default_start_day )) as sw_data_start_date, max( coalesce ( media.sw_data_end_date,  default_end_day )) as sw_data_end_date INTO media_rec from media_sets_media_map join media on (media_sets_media_map.media_id = media.media_id ) and media_sets_id = v_media_sets_id  group by media_sets_id;

    start_date = media_rec.sw_data_start_date; 
    end_date = media_rec.sw_data_end_date;

    --RAISE NOTICE 'start date - %', start_date;
    --RAISE NOTICE 'end date - %', end_date;

    return;
END;
$$
LANGUAGE 'plpgsql' STABLE
 ;

CREATE VIEW media_sets_explict_sw_data_dates as  select media_sets_id, min(media.sw_data_start_date) as sw_data_start_date, max( media.sw_data_end_date) as sw_data_end_date from media_sets_media_map join media on (media_sets_media_map.media_id = media.media_id )   group by media_sets_id;

CREATE VIEW media_with_collections AS
    SELECT t.tag, m.media_id, m.url, m.name, m.moderated, m.feeds_added, m.moderation_notes, m.full_text_rss FROM media m, tags t, tag_sets ts, media_tags_map mtm WHERE (((((ts.name)::text = 'collection'::text) AND (ts.tag_sets_id = t.tag_sets_id)) AND (mtm.tags_id = t.tags_id)) AND (mtm.media_id = m.media_id)) ORDER BY m.media_id;


CREATE OR REPLACE FUNCTION media_set_retains_sw_data_for_date(v_media_sets_id int, test_date date, default_start_day date, default_end_day date)
  RETURNS BOOLEAN AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
    start_date   date;
    end_date     date;
BEGIN
    current_time := timeofday()::timestamp;

    -- RAISE NOTICE 'time - %', current_time;

   media_rec = media_set_sw_data_retention_dates( v_media_sets_id, default_start_day,  default_end_day ); -- INTO (media_rec);

   start_date = media_rec.start_date; 
   end_date = media_rec.end_date;

    -- RAISE NOTICE 'start date - %', start_date;
    -- RAISE NOTICE 'end date - %', end_date;

    return  ( start_date <= test_date ) and ( end_date >= test_date );    
END;
$$
LANGUAGE 'plpgsql' STABLE
 ;

CREATE OR REPLACE FUNCTION purge_daily_words_for_media_set(v_media_sets_id int, default_start_day date, default_end_day date)
RETURNS VOID AS 
$$
DECLARE
    media_rec record;
    current_time timestamp;
    start_date   date;
    end_date     date;
BEGIN
    current_time := timeofday()::timestamp;

    RAISE NOTICE ' purge_daily_words_for_media_set media_sets_id %, time - %', v_media_sets_id, current_time;

    media_rec = media_set_sw_data_retention_dates( v_media_sets_id, default_start_day,  default_end_day );

    start_date = media_rec.start_date; 
    end_date = media_rec.end_date;

    RAISE NOTICE 'start date - %', start_date;
    RAISE NOTICE 'end date - %', end_date;

    DELETE from daily_words where media_sets_id = v_media_sets_id and (publish_day < start_date or publish_day > end_date) ;
    DELETE from total_daily_words where media_sets_id = v_media_sets_id and (publish_day < start_date or publish_day > end_date) ;

    return;
END;
$$
LANGUAGE 'plpgsql' 
 ;

/*
dashboard_media_sets associates certain 'collection' type media_sets with a given dashboard.  Those assocaited media_sets will
appear on the dashboard page, and the media associated with the collections will be available from autocomplete box.

this table is also used to determine for which dates to create [daily|weekly|top_500_weekly]_words entries for which 
media_sets / topics
*/
create table dashboard_media_sets (
    dashboard_media_sets_id     serial          primary key,
    dashboards_id               int             not null references dashboards on delete cascade,
    media_sets_id               int             not null references media_sets on delete cascade,
    media_cluster_runs_id       int             null references media_cluster_runs on delete set null,
    color                       text            null
);

CREATE UNIQUE INDEX dashboard_media_sets_media_set_dashboard on dashboard_media_sets(media_sets_id, dashboards_id);
create index dashboard_media_sets_dashboard on dashboard_media_sets( dashboards_id );

/*
a topic is a query used to generate dashboard results for a subset of matching stories.  for instance,
a topic with a query of 'health' would generate dashboard results for only stories that include
the word 'health'.  a given topic is confined to a given dashbaord and optionally to date range
within the date range of the dashboard.
*/
create table dashboard_topics (
    dashboard_topics_id         serial          primary key,
    name                        varchar(256)    not null,
    query                       varchar(1024)   not null,
    dashboards_id               int             not null references dashboards on delete cascade,
    start_date                  timestamp       not null,
    end_date                    timestamp       not null,
    vectors_added               boolean         default false
);
    
create index dashboard_topics_dashboard on dashboard_topics ( dashboards_id );
create index dashboard_topics_vectors_added on dashboard_topics ( vectors_added );

CREATE VIEW dashboard_topics_tt2_locale_format as select distinct on (tt2_value) '[% c.loc("' || name || '") %]' || ' - ' || '[% c.loc("' || lower(name) || '") %]' as tt2_value from (select * from dashboard_topics order by name, dashboard_topics_id) AS dashboard_topic_names order by tt2_value;

create table stories (
    stories_id                  serial          primary key,
    media_id                    int             not null references media on delete cascade,
    url                         varchar(1024)   not null,
    guid                        varchar(1024)   not null,
    title                       text            not null,
    description                 text            null,
    publish_date                timestamp       not null,
    collect_date                timestamp       not null,
    full_text_rss               boolean         not null default 'f',
    language                    varchar(3)      null   /* 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset */
);

/*create index stories_media on stories (media_id, guid);*/
create index stories_media_id on stories (media_id);
create unique index stories_guid on stories(guid, media_id);
create index stories_url on stories (url);
create index stories_publish_date on stories (publish_date);
create index stories_collect_date on stories (collect_date);
create index stories_title_pubdate on stories(title, publish_date);
create index stories_md on stories(media_id, date_trunc('day'::text, publish_date));

CREATE TYPE download_state AS ENUM ('error', 'fetching', 'pending', 'queued', 'success');    
CREATE TYPE download_type  AS ENUM ('Calais', 'calais', 'content', 'feed', 'spider_blog_home', 'spider_posting', 'spider_rss', 'spider_blog_friends_list', 'spider_validation_blog_home','spider_validation_rss','archival_only');    

create table downloads (
    downloads_id        serial          primary key,
    feeds_id            int             null references feeds,
    stories_id          int             null references stories on delete cascade,
    parent              int             null,
    url                 varchar(1024)   not null,
    host                varchar(1024)   not null,
    download_time       timestamp       not null,
    type                download_type   not null,
    state               download_state  not null,
    path                text            null,
    error_message       text            null,
    priority            int             not null,
    sequence            int             not null,
    extracted           boolean         not null default 'f'
);

alter table downloads add constraint downloads_parent_fkey 
    foreign key (parent) references downloads on delete set null;
alter table downloads add constraint downloads_path
    check ((state = 'success' and path is not null) or 
           (state != 'success'));
alter table downloads add constraint downloads_feed_id_valid
      check ((feeds_id is not null) or 
      ( type = 'spider_blog_home' or type = 'spider_posting' or type = 'spider_rss' or type = 'spider_blog_friends_list' or type = 'archival_only') );
alter table downloads add constraint downloads_story
    check (((type = 'feed' or type = 'spider_blog_home' or type = 'spider_posting' or type = 'spider_rss' or type = 'spider_blog_friends_list' or type = 'archival_only')
    and stories_id is null) or (stories_id is not null));

-- make the query optimizer get enough stats to use the feeds_id index
alter table downloads alter feeds_id set statistics 1000;

create index downloads_parent on downloads (parent);
-- create unique index downloads_host_fetching 
--     on downloads(host, (case when state='fetching' then 1 else null end));
create index downloads_time on downloads (download_time);

/*create index downloads_sequence on downloads (sequence);*/
create index downloads_type on downloads (type);
create index downloads_host_state_priority on downloads (host, state, priority);
create index downloads_feed_state on downloads(feeds_id, state);
create index downloads_story on downloads(stories_id);
create index downloads_url on downloads(url);
CREATE INDEX downloads_state_downloads_id_pending on downloads(state,downloads_id) where state='pending';
create index downloads_extracted on downloads(extracted, state, type) 
    where extracted = 'f' and state = 'success' and type = 'content';
CREATE INDEX downloads_stories_to_be_extracted on downloads (stories_id) where extracted = false AND state = 'success' AND type = 'content';        

CREATE INDEX downloads_extracted_stories on downloads (stories_id) where type='content' and state='success';
CREATE INDEX downloads_spider_urls on downloads(url) where type = 'spider_blog_home' or type = 'spider_posting' or type = 'spider_rss' or type = 'spider_blog_friends_list';
CREATE INDEX downloads_spider_download_errors_to_clear on downloads(state,type,error_message) where state='error' and type in ('spider_blog_home','spider_posting','spider_rss','spider_blog_friends_list') and (error_message like '50%' or error_message= 'Download timed out by Fetcher::_timeout_stale_downloads') ;
CREATE INDEX downloads_state_queued_or_fetching on downloads(state) where state='queued' or state='fetching';
CREATE INDEX downloads_state_fetching ON downloads(state, downloads_id) where state = 'fetching';

create view downloads_media as select d.*, f.media_id as _media_id from downloads d, feeds f where d.feeds_id = f.feeds_id;

create view downloads_non_media as select d.* from downloads d where d.feeds_id is null;

CREATE INDEX downloads_sites_index on downloads (regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3'));
CREATE INDEX downloads_sites_pending on downloads (regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3')) where state='pending';

CREATE INDEX downloads_queued_spider ON downloads(downloads_id) where state = 'queued' and  type in  ('spider_blog_home','spider_posting','spider_rss','spider_blog_friends_list','spider_validation_blog_home','spider_validation_rss');

CREATE INDEX downloads_sites_downloads_id_pending ON downloads USING btree (regexp_replace((host)::text, E'^(.)*?([^.]+)\\.([^.]+)$'::text, E'\\2.\\3'::text), downloads_id) WHERE (state = 'pending'::download_state);

/*
CREATE INDEX downloads_sites_index_downloads_id on downloads (regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3'), downloads_id);
*/

CREATE VIEW downloads_sites as select regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3') as site, * from downloads_media;

create table feeds_stories_map
 (
    feeds_stories_map_id    serial  primary key,
    feeds_id                int        not null references feeds on delete cascade,
    stories_id                int        not null references stories on delete cascade
);

create unique index feeds_stories_map_feed on feeds_stories_map (feeds_id, stories_id);
create index feeds_stories_map_story on feeds_stories_map (stories_id);

create table stories_tags_map
(
    stories_tags_map_id     serial  primary key,
    stories_id              int     not null references stories on delete cascade,
    tags_id                 int     not null references tags on delete cascade
);

create unique index stories_tags_map_story on stories_tags_map (stories_id, tags_id);
create index stories_tags_map_tag on stories_tags_map (tags_id);
CREATE INDEX stories_tags_map_story_id ON stories_tags_map USING btree (stories_id);

create table extractor_training_lines
(
    extractor_training_lines_id     serial      primary key,
    line_number                     int         not null,
    required                        boolean     not null,
    downloads_id                    int         not null references downloads on delete cascade,
    "time" timestamp without time zone,
    submitter character varying(256)
);      

create unique index extractor_training_lines_line on extractor_training_lines(line_number, downloads_id);
create index extractor_training_lines_download on extractor_training_lines(downloads_id);
    
CREATE TABLE top_ten_tags_for_media (
    media_id integer NOT NULL,
    tags_id integer NOT NULL,
    media_tag_count integer NOT NULL,
    tag_name character varying(512) NOT NULL,
    tag_sets_id integer NOT NULL
);


CREATE INDEX media_id_and_tag_sets_id_index ON top_ten_tags_for_media USING btree (media_id, tag_sets_id);
CREATE INDEX media_id_index ON top_ten_tags_for_media USING btree (media_id);
CREATE INDEX tag_sets_id_index ON top_ten_tags_for_media USING btree (tag_sets_id);

CREATE TABLE download_texts (
    download_texts_id integer NOT NULL,
    downloads_id integer NOT NULL,
    download_text text NOT NULL,
    download_text_length int not null
);

CREATE SEQUENCE download_texts_download_texts_id_seq
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1 OWNED BY download_texts.download_texts_id;

CREATE UNIQUE INDEX download_texts_downloads_id_index ON download_texts USING btree (downloads_id);

ALTER TABLE download_texts ALTER COLUMN download_texts_id SET DEFAULT nextval('download_texts_download_texts_id_seq'::regclass);

ALTER TABLE ONLY download_texts
    ADD CONSTRAINT download_texts_pkey PRIMARY KEY (download_texts_id);

ALTER TABLE ONLY download_texts
    ADD CONSTRAINT download_texts_downloads_id_fkey FOREIGN KEY (downloads_id) REFERENCES downloads(downloads_id) ON DELETE CASCADE;

ALTER TABLE download_texts ALTER COLUMN download_text_length set NOT NULL;

ALTER TABLE download_texts add CONSTRAINT download_text_length_is_correct CHECK (length(download_text)=download_text_length);

    
create table extracted_lines
(
    extracted_lines_id          serial          primary key,
    line_number                 int             not null,
    download_texts_id           int             not null references download_texts on delete cascade
);

create index extracted_lines_download_text on extracted_lines(download_texts_id);

CREATE TYPE url_discovery_status_type as ENUM ('already_processed', 'not_yet_processed');
CREATE TABLE url_discovery_counts ( 
       url_discovery_status url_discovery_status_type PRIMARY KEY, 
       num_urls INT DEFAULT  0);

INSERT  into url_discovery_counts VALUES ('already_processed');
INSERT  into url_discovery_counts VALUES ('not_yet_processed');
    
create table word_cloud_topics (
        word_cloud_topics_id    serial      primary key,
        source_tags_id          int         not null references tags,
        set_tag_names           text        not null,
        creator                 text        not null,
        query                   text        not null,
        type                    text        not null,
        start_date              date        not null,
        end_date                date        not null,
        state                   text        not null,
        url                     text        not null
);

alter table word_cloud_topics add constraint word_cloud_topics_type check (type in ('words', 'phrases'));
alter table word_cloud_topics add constraint word_cloud_topics_state check (state in ('pending', 'generating', 'completed'));

/* VIEWS */

CREATE VIEW media_extractor_training_downloads_count AS
    SELECT media.media_id, COALESCE(foo.extractor_training_downloads_for_media_id, (0)::bigint) AS extractor_training_download_count FROM (media LEFT JOIN (SELECT stories.media_id, count(stories.media_id) AS extractor_training_downloads_for_media_id FROM extractor_training_lines, downloads, stories WHERE ((extractor_training_lines.downloads_id = downloads.downloads_id) AND (downloads.stories_id = stories.stories_id)) GROUP BY stories.media_id ORDER BY stories.media_id) foo ON ((media.media_id = foo.media_id)));

CREATE VIEW yahoo_top_political_2008_media AS
    SELECT DISTINCT media_tags_map.media_id FROM media_tags_map, (SELECT tags.tags_id FROM tags, (SELECT DISTINCT media_tags_map.tags_id FROM media_tags_map ORDER BY media_tags_map.tags_id) media_tags WHERE ((tags.tags_id = media_tags.tags_id) AND ((tags.tag)::text ~~ 'yahoo_top_political_2008'::text))) interesting_media_tags WHERE (media_tags_map.tags_id = interesting_media_tags.tags_id) ORDER BY media_tags_map.media_id;

CREATE VIEW technorati_top_political_2008_media AS
    SELECT DISTINCT media_tags_map.media_id FROM media_tags_map, (SELECT tags.tags_id FROM tags, (SELECT DISTINCT media_tags_map.tags_id FROM media_tags_map ORDER BY media_tags_map.tags_id) media_tags WHERE ((tags.tags_id = media_tags.tags_id) AND ((tags.tag)::text ~~ 'technorati_top_political_2008'::text))) interesting_media_tags WHERE (media_tags_map.tags_id = interesting_media_tags.tags_id) ORDER BY media_tags_map.media_id;

CREATE VIEW media_extractor_training_downloads_count_adjustments AS
    SELECT yahoo.media_id, yahoo.yahoo_count_adjustment, tech.technorati_count_adjustment FROM (SELECT media_extractor_training_downloads_count.media_id, COALESCE(foo.yahoo_count_adjustment, 0) AS yahoo_count_adjustment FROM (media_extractor_training_downloads_count LEFT JOIN (SELECT yahoo_top_political_2008_media.media_id, 1 AS yahoo_count_adjustment FROM yahoo_top_political_2008_media) foo ON ((foo.media_id = media_extractor_training_downloads_count.media_id)))) yahoo, (SELECT media_extractor_training_downloads_count.media_id, COALESCE(foo.count_adjustment, 0) AS technorati_count_adjustment FROM (media_extractor_training_downloads_count LEFT JOIN (SELECT technorati_top_political_2008_media.media_id, 1 AS count_adjustment FROM technorati_top_political_2008_media) foo ON ((foo.media_id = media_extractor_training_downloads_count.media_id)))) tech WHERE (tech.media_id = yahoo.media_id);

CREATE VIEW media_adjusted_extractor_training_downloads_count AS
    SELECT media_extractor_training_downloads_count.media_id, ((media_extractor_training_downloads_count.extractor_training_download_count - (2 * media_extractor_training_downloads_count_adjustments.yahoo_count_adjustment)) - (2 * media_extractor_training_downloads_count_adjustments.technorati_count_adjustment)) AS count FROM (media_extractor_training_downloads_count JOIN media_extractor_training_downloads_count_adjustments ON ((media_extractor_training_downloads_count.media_id = media_extractor_training_downloads_count_adjustments.media_id))) ORDER BY ((media_extractor_training_downloads_count.extractor_training_download_count - (2 * media_extractor_training_downloads_count_adjustments.yahoo_count_adjustment)) - (2 * media_extractor_training_downloads_count_adjustments.technorati_count_adjustment));

CREATE TABLE extractor_results_cache (
    extractor_results_cache_id integer NOT NULL,
    is_story boolean NOT NULL,
    explanation text,
    discounted_html_density double precision,
    html_density double precision,
    downloads_id integer,
    line_number integer
);
CREATE SEQUENCE extractor_results_cache_extractor_results_cache_id_seq
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;
ALTER SEQUENCE extractor_results_cache_extractor_results_cache_id_seq OWNED BY extractor_results_cache.extractor_results_cache_id;
ALTER TABLE extractor_results_cache ALTER COLUMN extractor_results_cache_id SET DEFAULT nextval('extractor_results_cache_extractor_results_cache_id_seq'::regclass);
ALTER TABLE ONLY extractor_results_cache
    ADD CONSTRAINT extractor_results_cache_pkey PRIMARY KEY (extractor_results_cache_id);
CREATE INDEX extractor_results_cache_downloads_id_index ON extractor_results_cache USING btree (downloads_id);

create table story_sentences (
       story_sentences_id           bigserial       primary key,
       stories_id                   int             not null, /* references stories on delete cascade, */
       sentence_number              int             not null,
       sentence                     text            not null,
       media_id                     int             not null, /* references media on delete cascade, */
       publish_date                 timestamp       not null,
       language                     varchar(3)      null      /* 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset */
);

create index story_sentences_story on story_sentences (stories_id, sentence_number);
create index story_sentences_publish_day on story_sentences( date_trunc( 'day', publish_date ), media_id );
ALTER TABLE  story_sentences ADD CONSTRAINT story_sentences_media_id_fkey FOREIGN KEY (media_id) REFERENCES media(media_id) ON DELETE CASCADE;
ALTER TABLE  story_sentences ADD CONSTRAINT story_sentences_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;
    
create table story_sentence_counts (
       story_sentence_counts_id     bigserial       primary key,
       sentence_md5                 varchar(64)     not null,
       media_id                     int             not null, /* references media */
       publish_week                 timestamp       not null,
       sentence_count               int             not null,
       first_stories_id             int             not null,
       first_sentence_number        int             not null
);

--# We have chossen not to make the 'story_sentence_counts_md5' index unique purely for performance reasons.
--# Duplicate rows within this index are not desirable but are relatively rare in practice.
--# Thus we have decided to avoid the performance and code complexity implications of a unique index
-- See Issue 1599
create index story_sentence_counts_md5 on story_sentence_counts( media_id, publish_week, sentence_md5 );

create index story_sentence_counts_first_stories_id on story_sentence_counts( first_stories_id );

create table story_sentence_words (
       stories_id                   int             not null, /* references stories on delete cascade, */
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   smallint        not null,
       language                     varchar(3)      not null, /* 2- or 3-character ISO 690 language code */
       sentence_number              smallint        not null,
       media_id                     int             not null, /* references media on delete cascade, */
       publish_day                  date            not null
);

create index story_sentence_words_story on story_sentence_words (stories_id, sentence_number);
create index story_sentence_words_dsm on story_sentence_words (publish_day, stem, media_id);
create index story_sentence_words_day on story_sentence_words(publish_day);
create index story_sentence_words_media_day on story_sentence_words (media_id, publish_day);
--ALTER TABLE  story_sentence_words ADD CONSTRAINT story_sentence_words_media_id_fkey FOREIGN KEY (media_id) REFERENCES media(media_id) ON DELETE CASCADE;
--ALTER TABLE  story_sentence_words ADD CONSTRAINT story_sentence_words_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;

create table daily_words (
       daily_words_id               serial          primary key,
       media_sets_id                int             not null, /* references media_sets */
       dashboard_topics_id          int             null, /* references dashboard_topics */
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       language                     varchar(3)      not null, /* 2- or 3-character ISO 690 language code */
       publish_day                  date            not null
);

create index daily_words_media on daily_words(publish_day, media_sets_id, dashboard_topics_id, stem);
create index daily_words_count on daily_words(publish_day, media_sets_id, dashboard_topics_id, stem_count);
create index daily_words_publish_week on daily_words(week_start_date(publish_day));

create UNIQUE index daily_words_unique on daily_words(publish_day, media_sets_id, dashboard_topics_id, stem);
CREATE INDEX daily_words_day_topic ON daily_words USING btree (publish_day, dashboard_topics_id);

create table weekly_words (
       weekly_words_id              serial          primary key,
       media_sets_id                int             not null, /* references media_sets */
       dashboard_topics_id          int             null, /* references dashboard_topics */
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       language                     varchar(3)      not null, /* 2- or 3-character ISO 690 language code */
       publish_week                 date            not null
);

create UNIQUE index weekly_words_media on weekly_words(publish_week, media_sets_id, dashboard_topics_id, stem);
create index weekly_words_count on weekly_words(publish_week, media_sets_id, dashboard_topics_id, stem_count);
CREATE INDEX weekly_words_publish_week on weekly_words(publish_week);
ALTER TABLE  weekly_words ADD CONSTRAINT weekly_words_publish_week_is_monday CHECK ( EXTRACT ( ISODOW from publish_week) = 1 );

create table top_500_weekly_words (
       top_500_weekly_words_id      serial          primary key,
       media_sets_id                int             not null, /* references media_sets on delete cascade, */
       dashboard_topics_id          int             null, /* references dashboard_topics */
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       language                     varchar(3)      not null, /* 2- or 3-character ISO 690 language code */
       publish_week                 date            not null
);

create UNIQUE index top_500_weekly_words_media on top_500_weekly_words(publish_week, media_sets_id, dashboard_topics_id, stem);
create index top_500_weekly_words_media_null_dashboard on top_500_weekly_words (publish_week,media_sets_id, dashboard_topics_id) where dashboard_topics_id is null;
ALTER TABLE  top_500_weekly_words ADD CONSTRAINT top_500_weekly_words_publish_week_is_monday CHECK ( EXTRACT ( ISODOW from publish_week) = 1 );
  
create table total_top_500_weekly_words (
       total_top_500_weekly_words_id       serial          primary key,
       media_sets_id                int             not null references media_sets on delete cascade, 
       dashboard_topics_id          int             null references dashboard_topics,
       publish_week                 date            not null,
       total_count                  int             not null
);
ALTER TABLE total_top_500_weekly_words ADD CONSTRAINT total_top_500_weekly_words_publish_week_is_monday CHECK ( EXTRACT ( ISODOW from publish_week) = 1 );

create unique index total_top_500_weekly_words_media 
    on total_top_500_weekly_words(publish_week, media_sets_id, dashboard_topics_id);

create view top_500_weekly_words_with_totals
    as select t5.*, tt5.total_count from top_500_weekly_words t5, total_top_500_weekly_words tt5
      where t5.media_sets_id = tt5.media_sets_id and t5.publish_week = tt5.publish_week and
        ( ( t5.dashboard_topics_id = tt5.dashboard_topics_id ) or
          ( t5.dashboard_topics_id is null and tt5.dashboard_topics_id is null ) );

create view top_500_weekly_words_normalized
    as select t5.stem, min(t5.term) as term, 
            ( least( 0.01, sum(t5.stem_count)::numeric / sum(t5.total_count)::numeric ) * count(*) ) as stem_count,
            t5.media_sets_id, t5.publish_week, t5.dashboard_topics_id
        from top_500_weekly_words_with_totals t5
        group by t5.stem, t5.publish_week, t5.media_sets_id, t5.dashboard_topics_id;
    
create table total_daily_words (
       total_daily_words_id         serial          primary key,
       media_sets_id                int             not null, /* references media_sets on delete cascade, */
       dashboard_topics_id           int            null, /* references dashboard_topics, */
       publish_day                  date            not null,
       total_count                  int             not null
);

create index total_daily_words_media_sets_id on total_daily_words (media_sets_id);
create index total_daily_words_media_sets_id_publish_day on total_daily_words (media_sets_id,publish_day);
create index total_daily_words_publish_day on total_daily_words (publish_day);
create index total_daily_words_publish_week on total_daily_words (week_start_date(publish_day));
CREATE UNIQUE INDEX total_daily_words_media_sets_id_dashboard_topic_id_publish_day ON total_daily_words (media_sets_id, dashboard_topics_id, publish_day);


create table total_weekly_words (
       total_weekly_words_id         serial          primary key,
       media_sets_id                 int             not null references media_sets on delete cascade, 
       dashboard_topics_id           int             null references dashboard_topics on delete cascade,
       publish_week                  date            not null,
       total_count                   int             not null
);
create index total_weekly_words_media_sets_id on total_weekly_words (media_sets_id);
create index total_weekly_words_media_sets_id_publish_day on total_weekly_words (media_sets_id,publish_week);
create unique index total_weekly_words_ms_id_dt_id_p_week on total_weekly_words(media_sets_id, dashboard_topics_id, publish_week);
CREATE INDEX total_weekly_words_publish_week on total_weekly_words(publish_week);
INSERT INTO total_weekly_words(media_sets_id, dashboard_topics_id, publish_week, total_count) select media_sets_id, dashboard_topics_id, publish_week, sum(stem_count) as total_count from weekly_words group by media_sets_id, dashboard_topics_id, publish_week order by publish_week asc, media_sets_id, dashboard_topics_id ;

create view daily_words_with_totals 
    as select d.*, t.total_count from daily_words d, total_daily_words t
      where d.media_sets_id = t.media_sets_id and d.publish_day = t.publish_day and
        ( ( d.dashboard_topics_id = t.dashboard_topics_id ) or
          ( d.dashboard_topics_id is null and t.dashboard_topics_id is null ) );
             
create schema stories_tags_map_media_sub_tables;

create table ssw_queue (
       stories_id                   int             not null,
       publish_date                 timestamp       not null,
       media_id                     int             not null
);

create view story_extracted_texts
       as select stories_id, 
       array_to_string(array_agg(download_text), ' ') as extracted_text 
       from (select * from downloads natural join download_texts order by downloads_id) 
       	    as downloads group by stories_id;

CREATE VIEW media_feed_counts as (SELECT media_id, count(*) as feed_count FROM feeds GROUP by media_id);

CREATE TABLE daily_country_counts (
    media_sets_id integer  not null references media_sets on delete cascade,
    publish_day date not null,
    country character varying not null,
    country_count bigint not null,
    dashboard_topics_id integer references dashboard_topics on delete cascade
);

CREATE INDEX daily_country_counts_day_media_dashboard ON daily_country_counts USING btree (publish_day, media_sets_id, dashboard_topics_id);

CREATE TABLE authors (
    authors_id serial          PRIMARY KEY,
    author_name character varying UNIQUE NOT NULL
);
create index authors_name_varchar_pattern on authors(lower(author_name) varchar_pattern_ops);
create index authors_name_varchar_pattern_1 on authors(lower(split_part(author_name, ' ', 1)) varchar_pattern_ops);
create index authors_name_varchar_pattern_2 on authors(lower(split_part(author_name, ' ', 2)) varchar_pattern_ops);
create index authors_name_varchar_pattern_3 on authors(lower(split_part(author_name, ' ', 3)) varchar_pattern_ops);

CREATE TABLE authors_stories_map (
    authors_stories_map_id  serial            primary key,
    authors_id int                not null references authors on delete cascade,
    stories_id int                not null references stories on delete cascade
);

CREATE INDEX authors_stories_map_authors_id on authors_stories_map(authors_id);
CREATE INDEX authors_stories_map_stories_id on authors_stories_map(stories_id);

CREATE TYPE authors_stories_queue_type AS ENUM ('queued', 'pending', 'success', 'failed');

CREATE TABLE authors_stories_queue (
    authors_stories_queue_id  serial            primary key,
    stories_id int                not null references stories on delete cascade,
    state      authors_stories_queue_type not null
);
   
create table queries_dashboard_topics_map (
    queries_id              int                 not null references queries on delete cascade,
    dashboard_topics_id     int                 not null references dashboard_topics on delete cascade
);

create index queries_dashboard_topics_map_query on queries_dashboard_topics_map ( queries_id );
create index queries_dashboard_topics_map_dashboard_topic on queries_dashboard_topics_map ( dashboard_topics_id );

CREATE TABLE daily_author_words (
    daily_author_words_id           serial                  primary key,
    authors_id                      integer                 not null references authors on delete cascade,
    media_sets_id                   integer                 not null references media_sets on delete cascade,
    term                            character varying(256)  not null,
    stem                            character varying(256)  not null,
    stem_count                      int                     not null,
    language                        varchar(3)              not null, /* 2- or 3-character ISO 690 language code */
    publish_day                     date                    not null
);

create UNIQUE index daily_author_words_media on daily_author_words(publish_day, authors_id, media_sets_id, stem);
create index daily_author_words_count on daily_author_words(publish_day, authors_id, media_sets_id, stem_count);

create table total_daily_author_words (
       total_daily_author_words_id  serial          primary key,
       authors_id                   int             not null references authors on delete cascade,
       media_sets_id                int             not null references media_sets on delete cascade, 
       publish_day                  timestamp       not null,
       total_count                  int             not null
);

create index total_daily_author_words_authors_id_media_sets_id on total_daily_author_words (authors_id, media_sets_id);
create unique index total_daily_author_words_authors_id_media_sets_id_publish_day on total_daily_author_words (authors_id, media_sets_id,publish_day);

create table weekly_author_words (
       weekly_author_words_id       serial          primary key,
       media_sets_id                int             not null references media_sets on delete cascade,
       authors_id                   int             not null references authors on delete cascade,
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       language                     varchar(3)      not null, /* 2- or 3-character ISO 690 language code */
       publish_week                 date            not null
);

create index weekly_author_words_media on weekly_author_words(publish_week, authors_id, media_sets_id, stem);
create index weekly_author_words_count on weekly_author_words(publish_week, authors_id, media_sets_id, stem_count);

create UNIQUE index weekly_author_words_unique on weekly_author_words(publish_week, authors_id, media_sets_id, stem);

create table top_500_weekly_author_words (
       top_500_weekly_author_words_id      serial          primary key,
       media_sets_id                int             not null references media_sets on delete cascade,
       authors_id                   int             not null references authors on delete cascade,
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       language                     varchar(3)      not null, /* 2- or 3-character ISO 690 language code */
       publish_week                 date            not null
);

create index top_500_weekly_author_words_media on top_500_weekly_author_words(publish_week, media_sets_id, authors_id);
create index top_500_weekly_author_words_authors on top_500_weekly_author_words(authors_id, publish_week, media_sets_id);

create UNIQUE index top_500_weekly_author_words_authors_stem on top_500_weekly_author_words(authors_id, publish_week, media_sets_id, stem);

    
create table total_top_500_weekly_author_words (
       total_top_500_weekly_author_words_id       serial          primary key,
       media_sets_id                int             not null references media_sets on delete cascade,
       authors_id                   int             not null references authors on delete cascade,
       publish_week                 date            not null,
       total_count                  int             not null
);

create UNIQUE index total_top_500_weekly_author_words_media 
    on total_top_500_weekly_author_words(publish_week, media_sets_id, authors_id);
create UNIQUE index total_top_500_weekly_author_words_authors 
    on total_top_500_weekly_author_words(authors_id, publish_week, media_sets_id);

CREATE TABLE popular_queries (
    popular_queries_id  serial          primary key,
    queries_id_0 integer NOT NULL,
    queries_id_1 integer,
    query_0_description character varying(1024) NOT NULL,
    query_1_description character varying(1024),
    dashboard_action character varying(1024),
    url_params character varying(1024),
    count integer DEFAULT 0,
    dashboards_id integer references dashboards NOT NULL
);

CREATE UNIQUE INDEX popular_queries_da_up ON popular_queries(dashboard_action, url_params);
CREATE UNIQUE INDEX popular_queries_query_ids ON popular_queries( queries_id_0,  queries_id_1);
CREATE INDEX popular_queries_dashboards_id_count on popular_queries(dashboards_id, count);

create table query_story_searches (
    query_story_searches_id     serial primary key,
    queries_id                  int not null references queries,
    pattern                     text,
    search_completed            boolean default false,
    csv_text                    text
);

create unique index query_story_searches_query_pattern on query_story_searches( queries_id, pattern );
  
create table query_story_searches_stories_map (
    query_story_searches_id     int,
    stories_id                  int
);

create unique index query_story_searches_stories_map_u on query_story_searches_stories_map ( query_story_searches_id, stories_id );
    
create table sopa_links (
    sopa_links_id       serial primary key,
    stories_id          int not null references stories,
    url                 text not null,
    redirect_url        text,
    ref_stories_id      int references stories,
    link_spidered       boolean default 'f'
);

create index sopa_links_story on sopa_links (stories_id);
    
create table sopa_stories (
    sopa_stories_id         serial primary key,
    stories_id              int not null references stories,
    link_mined              boolean default 'f',
    iteration               int default 0,
    link_weight             real
);

create table story_similarities (
    story_similarities_id   serial primary key,
    stories_id_a            int,
    publish_day_a           date,
    stories_id_b            int,
    publish_day_b           date,
    similarity              int
);

create index story_similarities_a_b on story_similarities ( stories_id_a, stories_id_b );
create index story_similarities_a_s on story_similarities ( stories_id_a, similarity, publish_day_b );
create index story_similarities_b_s on story_similarities ( stories_id_b, similarity, publish_day_a );
create index story_similarities_day on story_similarities ( publish_day_a, publish_day_b ); 
     
create view story_similarities_transitive as
    ( select story_similarities_id, stories_id_a, publish_day_a, stories_id_b, publish_day_b, similarity from story_similarities ) union 
        ( select story_similarities_id, stories_id_b as stories_id_a, publish_day_b as publish_day_a,
            stories_id_a as stories_id_b, publish_day_a as publish_day_b, similarity from story_similarities );
            
create table controversies (
    controversies_id        serial primary key,
    name                    varchar(1024) not null,
    query_story_searches_id int not null
);

create unique index controversies_name on controversies( name );


create table controversy_media_codes (
    controversies_id        int not null references controversies on delete cascade,
    media_id                int not null references media on delete cascade,
    code_type               text,
    code                    text
);
    
create table controversy_merged_media (
    source_media_id         int not null,
    target_media_id         int not null
);

create table controversy_links (
    controversy_links_id        serial primary key,
    controversies_id            int not null references controversies on delete cascade,
    stories_id                  int not null references stories on delete cascade,
    url                         text not null,
    redirect_url                text,
    ref_stories_id              int references stories on delete cascade,
    link_spidered               boolean default 'f'
);

create index controversy_links_story on controversy_links (stories_id, controversies_id );
    
create table controversy_stories (
    controversy_stories_id          serial primary key,
    controversies_id                int not null references controversies on delete cascade,
    stories_id                      int not null references stories on delete cascade,
    link_mined                      boolean default 'f',
    iteration                       int default 0,
    link_weight                     real,
    redirect_url                    text
);

create view controversy_links_cross_media as
  select s.stories_id, substr(sm.name::text, 0, 24) as media_name, r.stories_id as ref_stories_id, 
      substr(rm.name::text, 0, 24) as ref_media_name, substr(cl.url, 0, 144) as url, cs.controversies_id
    from media sm, media rm, controversy_links cl, stories s, stories r, controversy_stories cs
    where cl.ref_stories_id <> cl.stories_id and s.stories_id = cl.stories_id and 
      cl.ref_stories_id = r.stories_id and s.media_id <> r.media_id and 
      sm.media_id = s.media_id and rm.media_id = r.media_id and cs.stories_id = cl.ref_stories_id and
      cs.controversies_id = cl.controversies_id;
    
CREATE VIEW stories_collected_in_past_day as select * from stories where collect_date > now() - interval '1 day';

CREATE VIEW downloads_to_be_extracted as select * from downloads where extracted = 'f' and state = 'success' and type = 'content';

CREATE VIEW downloads_in_past_day as select * from downloads where download_time > now() - interval '1 day';
CREATE VIEW downloads_with_error_in_past_day as select * from downloads_in_past_day where state = 'error';

CREATE VIEW daily_stats as select * from (SELECT count(*) as daily_downloads from downloads_in_past_day) as dd, (select count(*) as daily_stories from stories_collected_in_past_day) ds , (select count(*) as downloads_to_be_extracted from downloads_to_be_extracted) dex, (select count(*) as download_errors from downloads_with_error_in_past_day ) er;

CREATE TABLE queries_top_weekly_words_json (
   queries_top_weekly_words_json_id serial primary key,
   queries_id integer references queries on delete cascade not null unique,
   top_weekly_words_json text not null 
);

CREATE TABLE queries_country_counts_json (
   queries_country_counts_json_id serial primary key,
   queries_id integer references queries on delete cascade not null unique,
   country_counts_json text not null 
);


CREATE OR REPLACE FUNCTION add_query_version (new_query_version_enum_string character varying) RETURNS void
AS 
$body$
DECLARE
    range_of_old_enum TEXT;
    new_type_sql TEXT;
BEGIN

LOCK TABLE queries;

SELECT '''' || array_to_string(ENUM_RANGE(null::query_version_enum), ''',''') || '''' INTO range_of_old_enum;

DROP TYPE IF EXISTS new_query_version_enum;

new_type_sql :=  'CREATE TYPE new_query_version_enum AS ENUM( ' || range_of_old_enum || ', ' || '''' || new_query_version_enum_string || '''' || ')' ;
--RAISE NOTICE 'Sql: %t', new_type_sql;

EXECUTE new_type_sql;

ALTER TABLE queries ADD COLUMN new_query_version new_query_version_enum DEFAULT enum_last (null::new_query_version_enum ) NOT NULL;
UPDATE queries set new_query_version = query_version::text::new_query_version_enum;
ALTER TYPE query_version_enum  RENAME to old_query_version_enum;
ALTER TABLE queries rename column query_version to old_query_version;
ALTER TABLE queries rename column new_query_version to query_version;
ALTER TYPE new_query_version_enum RENAME to query_version_enum;
ALTER TABLE queries DROP COLUMN old_query_version;
DROP TYPE old_query_version_enum ;


END;
$body$
    LANGUAGE plpgsql;
--

select enum.enum_add( 'download_state', 'feed_error' );
DROP LANGUAGE IF EXISTS plperlu CASCADE;

CREATE TYPE download_file_status AS ENUM ( 'tbd', 'missing', 'na', 'present', 'inline', 'redownloaded', 'error_redownloading' );

ALTER TABLE downloads ADD COLUMN file_status download_file_status not null default 'tbd';

ALTER TABLE downloads ADD COLUMN relative_file_path text not null default 'tbd';


ALTER TABLE downloads ADD COLUMN old_download_time timestamp without time zone;
ALTER TABLE downloads ADD COLUMN old_state download_state;
UPDATE downloads set old_download_time = download_time, old_state = state;

CREATE UNIQUE INDEX downloads_file_status on downloads(file_status, downloads_id);
CREATE UNIQUE INDEX downloads_relative_path on downloads( relative_file_path, downloads_id);

CREATE OR REPLACE FUNCTION get_relative_file_path(path text)
    RETURNS text AS
$$
DECLARE
    regex_tar_format text;
    relative_file_path text;
BEGIN
    IF path is null THEN
       RETURN 'na';
    END IF;

    regex_tar_format :=  E'tar\\:\\d*\\:\\d*\\:(mediacloud-content-\\d*\.tar).*';

    IF path ~ regex_tar_format THEN
         relative_file_path =  regexp_replace(path, E'tar\\:\\d*\\:\\d*\\:(mediacloud-content-\\d*\.tar).*', E'\\1') ;
    ELSIF  path like 'content:%' THEN 
         relative_file_path =  'inline';
    ELSEIF path like 'content/%' THEN
         relative_file_path =  regexp_replace(path, E'content\\/', E'\/') ;
    ELSE  
         relative_file_path = 'error';
    END IF;

--  RAISE NOTICE 'relative file path for %, is %', path, relative_file_path;

    RETURN relative_file_path;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE
  COST 10;

UPDATE downloads set relative_file_path = get_relative_file_path(path) where relative_file_path = 'tbd';CREATE OR REPLACE FUNCTION download_relative_file_path_trigger() RETURNS trigger AS 
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';
      IF TG_OP = 'UPDATE' then
          -- RAISE NOTICE 'UPDATE ';

	  -- The second part is needed because of the way comparisons with null are handled.
	  path_change := ( OLD.path <> NEW.path )  AND (  ( OLD.path is not null) <> (NEW.path is not null) ) ;
	  -- RAISE NOTICE 'test result % ', path_change; 
	  
          IF path_change is null THEN
	       -- RAISE NOTICE 'Path change % != %', OLD.path, NEW.path;
               NEW.relative_file_path = get_relative_file_path(NEW.path);
	  ELSE
               -- RAISE NOTICE 'NO path change % = %', OLD.path, NEW.path;
          END IF;
      ELSIF TG_OP = 'INSERT' then
	  NEW.relative_file_path = get_relative_file_path(NEW.path);
      END IF;

      RETURN NEW;
   END;
$$ 
LANGUAGE 'plpgsql';

DROP TRIGGER IF EXISTS download_relative_file_path_trigger on downloads CASCADE;
CREATE TRIGGER download_relative_file_path_trigger BEFORE INSERT OR UPDATE ON downloads FOR EACH ROW EXECUTE PROCEDURE  download_relative_file_path_trigger() ;
CREATE INDEX relative_file_paths_to_verify on downloads( relative_file_path ) where file_status = 'tbd' and relative_file_path <> 'tbd' and relative_file_path <> 'error';
CREATE OR REPLACE FUNCTION show_stat_activity()
 RETURNS SETOF  pg_stat_activity  AS
$$
DECLARE
BEGIN
    RETURN QUERY select * from pg_stat_activity;
    RETURN;
END;
$$
LANGUAGE 'plpgsql'
;
alter table weekly_words alter column weekly_words_id type bigint;
CREATE OR REPLACE FUNCTION download_relative_file_path_trigger() RETURNS trigger AS 
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';
      IF TG_OP = 'UPDATE' then
          -- RAISE NOTICE 'UPDATE ';

	  -- The second part is needed because of the way comparisons with null are handled.
	  path_change := ( OLD.path <> NEW.path )  AND (  ( OLD.path is not null) <> (NEW.path is not null) ) ;
	  -- RAISE NOTICE 'test result % ', path_change; 
	  
          IF path_change is null THEN
	       -- RAISE NOTICE 'Path change % != %', OLD.path, NEW.path;
               NEW.relative_file_path = get_relative_file_path(NEW.path);

               IF NEW.relative_file_path = 'inline' THEN
		  NEW.file_status = 'inline';
	       END IF;
	  ELSE
               -- RAISE NOTICE 'NO path change % = %', OLD.path, NEW.path;
          END IF;
      ELSIF TG_OP = 'INSERT' then
	  NEW.relative_file_path = get_relative_file_path(NEW.path);

          IF NEW.relative_file_path = 'inline' THEN
	     NEW.file_status = 'inline';
	  END IF;
      END IF;

      RETURN NEW;
   END;
$$ 
LANGUAGE 'plpgsql';

--DROP TRIGGER IF EXISTS download_relative_file_path_trigger on downloads CASCADE;
--CREATE TRIGGER download_relative_file_path_trigger BEFORE INSERT OR UPDATE ON downloads FOR EACH ROW EXECUTE PROCEDURE  download_relative_file_path_trigger() ;

-- Add column to allow more active feeds to be downloaded more frequently.
ALTER TABLE feeds ADD COLUMN last_new_story_time timestamp without time zone;
UPDATE feeds SET last_new_story_time = greatest( last_download_time, last_new_story_time );
ALTER TABLE feeds ALTER COLUMN last_download_time TYPE timestamp with time zone;
ALTER TABLE feeds ALTER COLUMN last_new_story_time TYPE timestamp with time zone;

