package MediaWords::Controller::Login;
use Moose;
use namespace::autoclean;
use MediaWords::Util::Config;
use MediaWords::DBI::Auth;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

MediaWords::Controller::Login - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

Login

=cut

# Login form
sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/auth/login.yml',
            method           => 'POST',
            action           => $c->uri_for( '/login' )
        }
    );

    # In case we're coming here from /logout
    if ( $c->request->param( 'email' ) )
    {
        $form->default_values(
            {
                'email' => $c->request->param( 'email' )    # in case 'email' was passed as a parameter from '/logout'
            }
        );
    }

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form } = $form;
        $c->stash->{ c }    = $c;
        $c->stash( template => 'auth/login.tt2' );
        return;
    }

    my $email = $form->param_value( 'email' ) || $c->request->param( 'email' );
    my $password = $form->param_value( 'password' );

    if ( !( $email && $password ) )
    {
        unless ( $c->user_exists )
        {
            $c->stash->{ form } = $form;
            $c->stash->{ c }    = $c;
            $c->stash( template  => 'auth/login.tt2' );
            $c->stash( error_msg => "Empty email address and / or password." );
            return;
        }
    }

    # Attempt to log the user in
    if ( $c->authenticate( { username => $email, password => $password } ) )
    {

        # Run post-successful login tasks
        MediaWords::DBI::Auth::post_successful_login( $c->dbis, $email );

        # Redirect to default homepage
        my $config            = MediaWords::Util::Config::get_config;
        my $default_home_page = $config->{ mediawords }->{ default_home_page };
        $c->response->redirect( $c->uri_for( $default_home_page ) );
    }
    else
    {

        # Run post-unsuccessful login tasks
        MediaWords::DBI::Auth::post_unsuccessful_login( $c->dbis, $email );

        # Show form again
        $c->stash->{ form } = $form;
        $c->stash->{ c }    = $c;
        $c->stash( template  => 'auth/login.tt2' );
        $c->stash( error_msg => "Incorrect email address and / or password, or your account is not active." );
    }

}

# "Forgot password" form
sub forgot : Local
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/auth/forgot.yml',
            method           => 'POST',
            action           => $c->uri_for( '/login/forgot' ),
            default_values   => {
                'email' => $c->request->param( 'email' )    # in case 'email' was passed as a parameter
            }
        }
    );

    # Set reCAPTCHA API keys
    my $config = MediaWords::Util::Config::get_config;
    my $el_recaptcha = $form->get_element( { name => 'recaptcha', type => 'reCAPTCHA' } );
    $el_recaptcha->public_key( $config->{ mediawords }->{ recaptcha_public_key } );
    $el_recaptcha->private_key( $config->{ mediawords }->{ recaptcha_private_key } );

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form } = $form;
        $c->stash->{ c }    = $c;
        $c->stash( template => 'auth/forgot.tt2' );
        return;
    }

    my $email = $form->param_value( 'email' );
    my $error_message =
      MediaWords::DBI::Auth::send_password_reset_token_or_return_error_message( $c->dbis, $email,
        $c->uri_for( '/login/reset' ) );
    if ( $error_message )
    {
        $c->stash->{ c }    = $c;
        $c->stash->{ form } = $form;
        $c->stash( template  => 'auth/forgot.tt2' );
        $c->stash( error_msg => $error_message );
    }
    else
    {
        $c->stash->{ c } = $c;

        # Do not stash the form because the link has already been sent
        $c->stash( template => 'auth/forgot.tt2' );
        $c->stash( status_msg => "The password reset link was sent to email address '" . $email .
              "' (given that such user exists in the user database)." );
    }

}

# "Reset password" form
sub reset : Local
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/auth/reset.yml',
            method           => 'POST',
            action           => $c->uri_for( '/login/reset' )
        }
    );

    $form->process( $c->request );

    my $email                = $c->request->param( 'email' );
    my $password_reset_token = $c->request->param( 'token' );

    # Check if the password token (a required parameter in all cases for this action) exists
    my $token_is_valid = MediaWords::DBI::Auth::validate_password_reset_token( $c->dbis, $email, $password_reset_token );

    if ( !$form->submitted_and_valid() )
    {
        if ( $token_is_valid )
        {

            # Pass the parameters further
            $form->default_values(
                {
                    email => $email,
                    token => $password_reset_token
                }
            );

            $c->stash->{ email } = $email;
            $c->stash->{ form }  = $form;
        }
        else
        {

            # Don't stash form (because the token is invalid)
            $c->stash( error_msg => "Password reset token is invalid." );
        }
        $c->stash->{ c } = $c;
        $c->stash( template => 'auth/reset.tt2' );

        return;
    }

    # At this point the token has been validated and the form has been submitted.

    # Change the password
    my $password_new        = $form->param_value( 'password_new' );
    my $password_new_repeat = $form->param_value( 'password_new_repeat' );

    my $error_message =
      MediaWords::DBI::Auth::change_password_via_token_or_return_error_message( $c->dbis, $email, $password_reset_token,
        $password_new, $password_new_repeat );
    if ( $error_message ne '' )
    {

        # Pass the parameters further
        $form->default_values(
            {
                email => $email,
                token => $password_reset_token
            }
        );

        $c->stash->{ email } = $email;
        $c->stash->{ form }  = $form;
        $c->stash->{ c }     = $c;
        $c->stash( template  => 'auth/reset.tt2' );
        $c->stash( error_msg => $error_message );
    }
    else
    {
        $c->response->redirect(
            $c->uri_for(
                '/login',
                {
                    status_msg => "Your password has been changed. An email was sent to " . "'" . $email .
                      "' to inform you about this change."
                }
            )
        );
    }

}

=head1 AUTHOR

Linas Valiukas

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
