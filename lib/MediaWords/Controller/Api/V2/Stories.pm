package MediaWords::Controller::Api::V2::Stories;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;

use strict;
use warnings;
use base 'Catalyst::Controller';
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;

=head1 NAME

MediaWords::Controller::Stories - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    'default'   => 'application/json',
    'stash_key' => 'rest',
    'map'       => {

        #	   'text/html'          => 'YAML::HTML',
        'text/xml' => 'XML::Simple',

        # #         'text/x-yaml'        => 'YAML',
        'application/json'         => 'JSON',
        'text/x-json'              => 'JSON',
        'text/x-data-dumper'       => [ 'Data::Serializer', 'Data::Dumper' ],
        'text/x-data-denter'       => [ 'Data::Serializer', 'Data::Denter' ],
        'text/x-data-taxi'         => [ 'Data::Serializer', 'Data::Taxi' ],
        'application/x-storable'   => [ 'Data::Serializer', 'Storable' ],
        'application/x-freezethaw' => [ 'Data::Serializer', 'FreezeThaw' ],
        'text/x-config-general'    => [ 'Data::Serializer', 'Config::General' ],
        'text/x-php-serialization' => [ 'Data::Serializer', 'PHP::Serialization' ],
    },
);

__PACKAGE__->config( json_options => { relaxed => 1, pretty => 1, space_before => 1, space_after => 1 } );

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

# # list of stories with the given feed id
# sub list : Local
# {

#     my ( $self, $c, $feeds_id ) = @_;

#     if ( !$feeds_id )
#     {
#         die "no feeds id";
#     }

#     $feeds_id += 0;

#     my $p = $c->request->param( 'p' ) || 1;

#     my $feed = $c->dbis->find_by_id( 'feeds', $feeds_id );
#     $c->stash->{ feed } = $feed;

#     my ( $stories, $pager ) = $c->dbis->query_paged_hashes(
#         "select s.* from stories s, feeds_stories_map fsm where s.stories_id = fsm.stories_id " .
#           "and fsm.feeds_id = $feeds_id " . "and publish_date > now() - interval '30 days' " . "order by publish_date desc",
#         [], $p, ROWS_PER_PAGE
#     );

#     if ( @{ $stories } < ROWS_PER_PAGE )
#     {
#         ( $stories, $pager ) = $c->dbis->query_paged_hashes(
#             "select s.* from stories s, feeds_stories_map fsm where s.stories_id = fsm.stories_id " .
#               "and fsm.feeds_id = $feeds_id " . "order by publish_date desc",
#             [], $p, ROWS_PER_PAGE
#         );
#     }

#     $c->stash->{ stories }   = $stories;
#     $c->stash->{ pager }     = $pager;
#     $c->stash->{ pager_url } = $c->uri_for( "/stories/list/$feeds_id" ) . '?';

#     $c->stash->{ template } = 'stories/list.tt2';
# }

# # list of stories with the given tag id
# sub tag : Local
# {

#     my ( $self, $c, $tags_id ) = @_;

#     if ( !$tags_id )
#     {
#         die "no tags_id";
#     }

#     my $tag = $c->dbis->find_by_id( 'tags', $tags_id );
#     $c->stash->{ tag } = $tag;

#     my $stories = $c->dbis->query(
#         "select * from stories s, stories_tags_maps stm where s.stories_id = stm.stories_id and stm.tags_id = ? " .
#           "order by publish_date desc",
#         $tags_id
#     )->hashes;

#     $c->stash->{ stories } = $stories;

#     $c->stash->{ template } = 'stories/tag.tt2';
# }

# # detail page for single story
# sub view : Local
# {
#     my ( $self, $c, $stories_id ) = @_;

#     if ( !$stories_id )
#     {
#         die "no stories id";
#     }

#     my $story = $c->dbis->find_by_id( 'stories', $stories_id );
#     $c->stash->{ story } = $story;

#     my @feeds = $c->dbis->query(
#         "select f.* from feeds f, feeds_stories_map fsm where f.feeds_id = fsm.feeds_id and fsm.stories_id = ?",
#         $stories_id )->hashes;
#     $c->stash->{ feeds } = \@feeds;

#     my @downloads = $c->dbis->query(
#         "select d.* from downloads d where d.type = 'content' " . "    and d.state = 'success' and d.stories_id = ?",
#         $stories_id )->hashes;
#     $c->stash->{ downloads } = \@downloads;

#     my @tags = $c->dbis->query(
#         "select t.*, ts.name as tag_set_name from tags t, stories_tags_map stm, tag_sets ts " .
#           "where t.tags_id = stm.tags_id and stm.stories_id = ? and t.tag_sets_id = ts.tag_sets_id " .
#           "order by t.tag_sets_id",
#         $stories_id
#     )->hashes;
#     $c->stash->{ tags } = \@tags;

#     $c->stash->{ storytext } = MediaWords::DBI::Stories::get_text( $c->dbis, $story );

#     $c->stash->{ stories_id } = $stories_id;

#     $c->stash->{ template } = 'stories/view.tt2';
# }

# # delete tag
# sub delete : Local
# {
#     my ( $self, $c, $stories_id, $tags_id, $confirm ) = @_;

#     if ( $stories_id == "" || $tags_id == "" )
#     {
#         die "incorrectly formed link because must have Stories ID number
#         and Tags ID number. ex: stories/delete/637467/128";
#     }

#     my $story = $c->dbis->find_by_id( "stories", $stories_id );

#     my $tag = $c->dbis->find_by_id( "tags", $tags_id );

#     my $status_msg;

#     if ( !defined( $confirm ) )
#     {
#         $c->stash->{ story }    = $story;
#         $c->stash->{ tag }      = $tag;
#         $c->stash->{ template } = 'stories/delete.tt2';
#     }
#     else
#     {
#         if ( $confirm ne 'yes' )
#         {
#             $status_msg = 'Tag NOT deleted.';
#         }
#         else
#         {
#             $c->dbis->query( "delete from stories_tags_map where tags_id = ?", $tags_id );
#             $status_msg = 'Tag \'' . $tag->{ tag } . '\' deleted from this story.';
#         }

#         $c->response->redirect( $c->uri_for( '/stories/view/' . $story->{ stories_id }, { status_msg => $status_msg } ) );
#     }
# }

# # sets up add tag
# sub add : Local
# {
#     my ( $self, $c, $stories_id ) = @_;

#     my $story = $c->dbis->find_by_id( "stories", $stories_id );
#     $c->stash->{ story } = $story;

#     my @tags =
#       $c->dbis->query( "select t.* from tags t, stories_tags_map stm where t.tags_id = stm.tags_id and stm.stories_id = ?",
#         $stories_id )->hashes;
#     $c->stash->{ tags } = \@tags;

#     my @tagsets = $c->dbis->query( "select ts.* from tag_sets ts" )->hashes;
#     $c->stash->{ tagsets } = \@tagsets;

#     $c->stash->{ template } = 'stories/add.tt2';
# }

# # executes add tag
# sub add_do : Local
# {
#     my ( $self, $c, $stories_id ) = @_;

#     my $story = $c->dbis->find_by_id( "stories", $stories_id );
#     $c->stash->{ story } = $story;

#     my $new_tag = $c->request->params->{ new_tag };
#     if ( $new_tag eq '' )
#     {
#         die( "Tag NOT added.  Tag name left blank." );
#     }

#     my $new_tag_sets_id = $c->request->params->{ tagset };
#     if ( !$new_tag_sets_id )
#     {
#         $new_tag_sets_id = $c->dbis->find_or_create( 'tag_sets', { name => 'manual_term' } )->{ tag_sets_id };
#     }

#     my $added_tag = $c->dbis->find_or_create(
#         "tags",
#         {
#             tag         => $new_tag,
#             tag_sets_id => $new_tag_sets_id,
#         }
#     );

#     my $stm = $c->dbis->create(
#         'stories_tags_map',
#         {
#             tags_id    => $added_tag->{ tags_id },
#             stories_id => $stories_id,
#         }
#     );

#     $c->stash->{ added_tag } = $added_tag;

#     $c->response->redirect(
#         $c->uri_for(
#             '/stories/add/' . $story->{ stories_id },
#             { status_msg => 'Tag \'' . $added_tag->{ tag } . '\' added.' }
#         )
#     );
# }

sub _add_data_to_stories
{

    my ( $self, $db, $stories, $show_raw_1st_download ) = @_;

    foreach my $story ( @{ $stories } )
    {
        my $story_text = MediaWords::DBI::Stories::get_text_for_word_counts( $db, $story );
        $story->{ story_text } = $story_text;
    }

    foreach my $story ( @{ $stories } )
    {
        my $fully_extracted = MediaWords::DBI::Stories::is_fully_extracted( $db, $story );
        $story->{ fully_extracted } = $fully_extracted;
    }

    if ( $show_raw_1st_download )
    {
        foreach my $story ( @{ $stories } )
        {
            my $content_ref = MediaWords::DBI::Stories::get_content_for_first_download( $db, $story );

            if ( !defined( $content_ref ) )
            {
                $story->{ first_raw_download_file }->{ missing } = 'true';
            }
            else
            {

                #say STDERR "got content_ref $$content_ref";

                $story->{ first_raw_download_file } = $$content_ref;
            }
        }
    }

    foreach my $story ( @{ $stories } )
    {
        my $story_sentences =
          $db->query( "SELECT * from story_sentences where stories_id = ? ORDER by sentence_number", $story->{ stories_id } )
          ->hashes;
        $story->{ story_sentences } = $story_sentences;
    }

    foreach my $story ( @{ $stories } )
    {
        say STDERR "adding story tags ";
        my $story_tags = $db->query(
"select tags.tags_id, tags.tag, tag_sets.tag_sets_id, tag_sets.name as tag_set from stories_tags_map natural join tags natural join tag_sets where stories_id = ? ORDER by tags_id",
            $story->{ stories_id }
        )->hashes;
        $story->{ story_tags } = $story_tags;
    }

    return $stories;
}

sub stories_query : Local : ActionClass('REST')
{
}

sub stories_query_GET : Local
{
    my ( $self, $c, $stories_id ) = @_;

    my $query = "select s.* from stories s where stories_id = ? ";

    say STDERR "QUERY $query";

    my $stories = $c->dbis->query( $query, $stories_id )->hashes();

    my $show_raw_1st_download = $c->req->param( 'raw_1st_download' );

    $show_raw_1st_download //= 0;

    $self->_add_data_to_stories( $c->dbis, $stories, $show_raw_1st_download );

    $self->status_ok( $c, entity => $stories );
}

sub all_processed : Local : ActionClass('REST')
{
}

sub all_processed_GET : Local
{
    my ( $self, $c ) = @_;

    say STDERR "starting stories_query_json";

    my $last_processed_stories_id = $c->req->param( 'last_processed_stories_id' );
    say STDERR "last_processed_stories_id: $last_processed_stories_id";

    $last_processed_stories_id //= 0;

    my $show_raw_1st_download = $c->req->param( 'raw_1st_download' );

    $show_raw_1st_download //= 0;

    my $stories = $c->dbis->query(
        "select s.*, ps.processed_stories_id from stories s, processed_stories ps where s.stories_id = ps.stories_id " .
          " AND processed_stories_id > ? order by processed_stories_id  asc limit ?",
        $last_processed_stories_id, ROWS_PER_PAGE
    )->hashes;

    $self->_add_data_to_stories( $c->dbis, $stories, $show_raw_1st_download );

    $self->status_ok( $c, entity => $stories );
}

sub subset_processed : Local : ActionClass('REST')
{
}

sub subset_processed_GET : Local
{
    my ( $self, $c, $story_subsets_id ) = @_;

    my $last_processed_stories_id = $c->req->param( 'last_processed_stories_id' );

    $last_processed_stories_id //= 0;

    say STDERR "last_processed_stories_id: $last_processed_stories_id";

    my $show_raw_1st_download = $c->req->param( 'raw_1st_download' );

    $show_raw_1st_download //= 0;

    my $query =
      "select s.*, ps.processed_stories_id from stories s, processed_stories ps, story_subsets_processed_stories_map sspsm  "
      . "where s.stories_id = ps.stories_id and ps.processed_stories_id = sspsm.processed_stories_id and sspsm.story_subsets_id = ? and ps.processed_stories_id > ? "
      . "order by ps.processed_stories_id  asc limit ?";

    say STDERR "QUERY $query";

    my $stories = $c->dbis->query( $query, $story_subsets_id, $last_processed_stories_id, ROWS_PER_PAGE )->hashes();

    $self->_add_data_to_stories( $c->dbis, $stories, $show_raw_1st_download );

    $self->status_ok( $c, entity => $stories );
}

sub subset : Local : ActionClass('REST')
{
}

sub subset_PUT : Local
{
    my ( $self, $c ) = @_;
    my $subset = $c->req->data;

    my $story_subset = $c->dbis->create( 'story_subsets', $subset );

    die unless defined( $story_subset );

    $story_subset = $c->dbis->find_by_id( 'story_subsets', $story_subset->{ story_subsets_id } );

    die unless defined( $story_subset );

    $self->status_created(
        $c,
        location => $c->req->uri->as_string,
        entity   => $story_subset,
    );

}

sub subset_GET : Local
{
    my ( $self, $c, $id ) = @_;
    my $subset = $c->req->data;

    my $story_subset = $c->dbis->find_by_id( 'story_subsets', $id );

    if ( !defined( $story_subset ) )
    {
        $self->status_not_found( $c, message => "no story_subset $id", );
    }
    else
    {
        $self->status_created(
            $c,
            location => $c->req->uri->as_string,
            entity   => $story_subset,
        );
    }

}

# # display regenerated tags for story
# sub retag : Local
# {
#     my ( $self, $c, $stories_id ) = @_;

#     my $story = $c->dbis->find_by_id( 'stories', $stories_id );
#     my $story_text = MediaWords::DBI::Stories::get_text( $c->dbis, $story );

#     my $tags = MediaWords::Tagger::get_all_tags( $story_text );

#     $c->stash->{ story }      = $story;
#     $c->stash->{ story_text } = $story_text;
#     $c->stash->{ tags }       = $tags;
#     $c->stash->{ template }   = 'stories/retag.tt2';
# }

=head1 AUTHOR

Alexandra J. Sternburg

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
