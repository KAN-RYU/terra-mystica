use strict;

package Server::ListGames;

use Moose;
use Method::Signatures::Simple;
use Server::Server;

extends 'Server::Server';

use CGI qw(:cgi);

use DB::Connection;
use DB::EditLink;
use DB::Game;
use DB::UserInfo;
use Util::NaturalCmp;
use Server::Session;

has 'mode' => (is => 'ro', required => 1);

method handle($q, $path_suffix) {
    $self->no_cache();
    $self->set_header("Connection", "Close");

    ensure_csrf_cookie $q, $self;

    my $dbh = get_db_connection;
    my $mode = $q->param('mode') // $self->mode() // 'all';
    my $status = $q->param('status') // 'running';

    my %res = (error => []);

    if ($mode eq 'user' or $mode eq 'admin' or $mode eq 'other-user') {
        my $user = username_from_session_token($dbh,
                                               $q->cookie('session-token') // '');
        if ($mode eq 'other-user') {
            $user = $q->param("args");
        } else {
            eval {
                verify_csrf_cookie_or_die $q, $self;
            }; if ($@) {
                $self->output_json({ error => ["csrf-error"] });
                return;
            }
        }

        my %status = (finished => 1, running => 0);
        $self->user_games($dbh,
                          \%res,
                          $user,
                          $mode,
                          $status{$status},
                          1*!!($mode eq 'admin'));
    } elsif ($mode eq 'open') {
        my $user = username_from_session_token($dbh,
                                               $q->cookie('session-token') // '');
        $self->open_games($dbh, \%res, $user);
    } elsif ($mode eq 'by-pattern') {
        $self->allow_cross_domain();
        my $pattern = $path_suffix;
        $pattern =~ s/[*]/%/g;
        $res{games} = get_game_list_by_pattern $dbh, $pattern;
        $res{error} = [];
    }

    $self->output_json({%res});
}

method open_games($dbh, $res, $user) {
    if (!defined $user) {
        $res->{error} = ["Not logged in <a href='/login/'>(login)</a>"];
    } else {
        my $user_info = fetch_user_metadata $dbh, $user;
        my $user_rating = $user_info->{rating} // 0;
        my $games = get_open_game_list $dbh;
        for my $game (@{$games}) {
            if (grep { $_ eq $user } @{$game->{players}}) {
                next;
            }
            if (($game->{minimum_rating} and
                 $game->{minimum_rating} > $user_rating) or
                ($game->{maximum_rating} and
                 $game->{maximum_rating} < $user_rating)) {
                $game = undef;
            }
        }
        $res->{games} = [ grep { $_ } @{$games} ];
    }
}

method user_games($dbh, $res, $user, $mode, $status, $admin) {
    if (!defined $user) {
        $res->{error} = ["Not logged in <a href='/login/'>(login)</a>"]
    } else {
        $res->{games} = get_user_game_list $dbh, $user, $mode, $status, $admin;
    }
}

1;
