package MediaWords::Controller::Admin::Downloads;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

# MODULES
use Data::Dumper;
use DateTime;
use Encode;
use HTML::Entities;
use Readonly;

use MediaWords::Crawler::Engine;
use MediaWords::Crawler::Provider;
use MediaWords::Crawler::Handler;
use MediaWords::DBI::Downloads;

# CONSTANTS
Readonly my $ROWS_PER_PAGE => 100;

# METHODS

sub list : Local
{
    my ( $self, $c ) = @_;

    my $p        = $c->request->param( 'p' ) || 1;
    my $media_id = $c->request->param( 'm' );
    my $feeds_id = $c->request->param( 'f' );
    my $error    = $c->request->param( 'e' );

    my $query =
      "select d.* from downloads d, feeds f, media m " .
      "where d.feeds_id = f.feeds_id and f.media_id = m.media_id and d.download_time > now() - interval '1 month'";

    if ( $feeds_id )
    {
        $c->stash->{ feed } = $c->dbis->find_by_id( 'feeds', $feeds_id );
        $query .= " and d.feeds_id = " . ( $feeds_id + 0 );
    }
    elsif ( $media_id )
    {
        $c->stash->{ medium } = $c->dbis->find_by_id( 'media', $media_id );
        $query .= " and f.media_id = " . ( $media_id + 0 );
    }
    else
    {
        $query .= " and d.download_time > now() - interval '1 day'";
    }

    if ( $error )
    {
        $query .= " and d.state = 'error'";
    }

    $query .= " order by download_time desc";

    my ( $downloads, $pager ) = $c->dbis->query_paged_hashes( $query, [], $p, $ROWS_PER_PAGE );

    for my $d ( @{ $downloads } )
    {
        $d->{ feed }   = $c->dbis->find_by_id( 'feeds', $d->{ feeds_id } );
        $d->{ medium } = $c->dbis->find_by_id( 'media', $d->{ feed }->{ media_id } );
    }

    $c->stash->{ downloads } = $downloads;
    $c->stash->{ pager }     = $pager;
    $c->stash->{ pager_url } = $c->uri_for( '/admin/downloads/list', { f => $feeds_id, m => $media_id, e => $error } );
    $c->stash->{ template }  = 'downloads/list.tt2';
}

sub view : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    if ( !$downloads_id )
    {
        $c->response->redirect( $c->uri_for( '/admin/downloads/list', { error_msg => 'no download specified' } ) );
        return;
    }

    my $download = $c->dbis->find_by_id( 'downloads', $downloads_id );

    if ( !$download )
    {
        die( "No such download" );
    }

    my $content_ref;
    eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $c->dbis, $download ) };
    if ( $@ )
    {
        my $content = "Error fetching download:\n" . $@;
        $content_ref = \$content;
    }

    if ( !$content_ref || !$$content_ref )
    {
        $content_ref = \"no content available for this download";
    }

    my $encoded_content = Encode::encode( 'utf-8', $$content_ref );

    $c->response->content_type( 'text/plain; charset=UTF-8' );
    $c->response->content_length( bytes::length( $encoded_content ) );
    $c->response->body( $encoded_content );
}

sub view_extracted : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    if ( !$downloads_id )
    {
        $c->response->redirect( $c->uri_for( '/admin/downloads/list', { error_msg => 'no download specified' } ) );
        return;
    }

    my $download_text = $c->dbis->select( 'download_texts', '*', { downloads_id => $downloads_id } )->hash;

    if ( !$download_text )
    {
        die( "No such download" );
    }

    $c->response->content_type( 'text/plain; charset=UTF-8' );
    $c->response->content_length( bytes::length( $download_text->{ download_text } ) );

    $c->response->body( $download_text->{ download_text } );
}

sub redownload : Local
{
    my ( $self, $c, $download_id ) = @_;

    say STDERR "starting redownload";
    my ( $download );

    if ( $download_id )
    {
        my $crawler_engine = MediaWords::Crawler::Engine->new();

        $download = $c->dbis->find_by_id( 'downloads', $download_id );
        my $response = MediaWords::Crawler::Fetcher::do_fetch( $download, $c->dbis );
        my $handler = MediaWords::Crawler::Handler->new( $crawler_engine );

        $handler->handle_response( $download, $response );
    }

    say STDERR "Finished download";

}

1;
