package CRP::Controller::Premium;
use Mojo::Base 'Mojolicious::Controller';

#  Premium content delivery. Auth process is designed such that:
#  - Most authorisation is by cookie, so it's quick
#  - New cookies are generated reasonably often so lockouts etc are effective
#  - Most access is through a URL that doesn't include the ID so sharing it won't work

use CRP::Util::WordNumber;
use CRP::Util::PremiumContent;

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
sub content {
    my $c = shift;

    my $subpath = $c->stash('subpath') // '';
    my($id, $path) = split('/', $subpath, 2);
    my $premium_content = CRP::Util::PremiumContent->new(
        c    => $c,
        dir  => $c->stash('dir'),
        id   => $id,
        path => $path,
    );

    if($premium_content->cookie && ($id eq $premium_content->authorised_id || $premium_content->cookie_id_matches)) {
        if($premium_content->cookie_dir_matches) {
            if($premium_content->cookie_expired) {
                $premium_content->generate_cookie;
                return $premium_content->show_access_page unless $premium_content->cookie;
            }
        }
        else {
            return $premium_content->show_not_found_page unless $premium_content->dir_exists;
            $premium_content->generate_cookie;
            return $premium_content->show_access_page unless $premium_content->cookie;
        }
        return $premium_content->redirect_to_authorised_path if $premium_content->id ne $premium_content->authorised_id;
    }
    else {
        $premium_content->generate_cookie;
        return $premium_content->show_access_page unless $premium_content->cookie;
        return $premium_content->redirect_to_authorised_path;
    }

    return $premium_content->send_content($premium_content);
}

1;

