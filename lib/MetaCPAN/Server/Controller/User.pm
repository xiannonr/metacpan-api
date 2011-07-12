package MetaCPAN::Server::Controller::User;

use Moose;
BEGIN { extends 'Catalyst::Controller::REST' }
use DateTime;

__PACKAGE__->config(
    json_options => { relaxed => 1, allow_nonref => 1 },
    default      => 'text/html',
    map => { 'text/html' => [qw(View JSON)] }
);

sub auto : Private {
    my ( $self, $c ) = @_;
    if ( my $token = $c->req->params->{access_token} ) {
        my $user = $c->model('User::Account')->find_token($token);
        $c->authenticate( { user => $user } ) if ($user);
    }
    return $c->user_exists;
}

sub index : Path {
    my ( $self, $c ) = @_;
    $c->stash( $c->user->data );
    $c->detach($c->view('JSON'));
}

sub identity : Local : ActionClass('REST') {
}

sub identity_GET {
    my ( $self, $c ) = @_;
    my ($identity) = @{ $c->req->arguments };
    ($identity)
        = grep { $_->{name} eq $identity } @{ $c->user->data->{identity} };
    $identity
        ? $self->status_ok( $c, entity => $identity )
        : $self->status_not_found( $c, message => 'Identity doesn\'t exist' );
}

sub identity_DELETE {
    my ( $self, $c ) = @_;
    my ($identity) = @{ $c->req->arguments };
    my $ids = $c->user->identity;
    ($identity) = grep { $_->name eq $identity } @$ids;
    if ($identity) {
        @$ids = grep { $_->{name} ne $identity->name } @$ids;
        $c->user->put( { refresh => 1 } );
        $self->status_ok( $c, entity => $identity );
    }
    else {
        $self->status_not_found( $c, message => 'Identity doesn\'t exist' );
    }
}

sub profile : Local : ActionClass('REST') {
    my ( $self, $c ) = @_;
    my ($pause) = $c->user->get_identities('pause');
    use Data::Printer; warn p($c->user->identity);
    my $profile = $c->model('CPAN::Author')->inflate(0)->get( $pause->key );
    $c->stash->{profile} = $profile->{_source};
}

sub profile_GET {
    my ( $self, $c ) = @_;
    $self->status_ok( $c, entity => $c->stash->{profile} );
}

sub profile_PUT {
    my ( $self, $c ) = @_;
    my $profile = $c->stash->{profile};
    use Data::Printer;

    map {
        defined $c->req->data->{$_}
            ? $profile->{$_} = $c->req->data->{$_}
            : delete $profile->{$_}
        } qw(name asciiname website email
        gravatar_url profile blog
        donation city region country
        location extra);
    $profile->{updated} = DateTime->now;
    my @errors = $c->model('CPAN::Author')->new_document->validate($profile);
    if (@errors) {
            $self->status_bad_request( $c, message => 'Validation failed' );
            $c->stash->{rest}->{errors} = \@errors;
    }
    else {
            $profile = $c->model('CPAN::Author')
                ->put( $profile, { refresh => 1 } );
            $self->status_created(
                $c,
                location => $c->uri_for( '/author/' . $profile->{pauseid} ),
                entity   => $profile->meta->get_data($profile)
            );
    }
}

1;