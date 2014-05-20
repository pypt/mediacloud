package MediaWords::ActionRole::Logged;

#
# Action role that logs requests
#

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Moose::Role;
with 'MediaWords::ActionRole::AbstractAuthenticatedActionRole';
use namespace::autoclean;

use HTTP::Status qw(:constants);

use constant NUMBER_OF_REQUESTED_ITEMS_KEY => 'MediaWords::ActionRole::Logged::requested_items_count';

after execute => sub {
    my ( $self, $controller, $c ) = @_;

    my ( $user_email, $user_roles ) = $self->_user_email_and_roles( $c );
    unless ( $user_email and $user_roles )
    {
        $c->response->status( HTTP_FORBIDDEN );
        $c->error( 'Invalid API key or authentication cookie. Access denied.' );
        $c->detach();
        return;
    }

    my $request_path = $c->req->path;
    unless ( $request_path )
    {
        $c->error( 'request_path is undef' );
        $c->detach();
        return;
    }

    my $requested_items_count = $c->stash->{ NUMBER_OF_REQUESTED_ITEMS_KEY } // 1;

    # Log the request
    my $db = $c->dbis;

    $db->query(
        <<EOF,
        INSERT INTO auth_user_requests (email, request_path, requested_items_count)
        VALUES (?, ?, ?)
EOF
        $user_email, $request_path, $requested_items_count
    );
};

# Static helper that sets the number of requested items (e.g. stories) in the Catalyst's stash to be later used by after{}
sub set_requested_items_count($$)
{
    my ( $c, $requested_items_count ) = @_;

    # Will use it later in after{}
    $c->stash->{ NUMBER_OF_REQUESTED_ITEMS_KEY } = $requested_items_count;
}

1;
