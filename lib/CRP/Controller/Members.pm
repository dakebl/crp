package CRP::Controller::Members;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util;

use Try::Tiny;


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
sub welcome {
    my $c = shift;

    my $profile = $c->_load_profile;
    $c->stash(incomplete_profile => ! $profile->is_complete);
    $c->render;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
sub page {
    my $c = shift;

    my $page = shift // $c->stash('page');
    $c->stash('page', $page);

    $c->render(template => "members/pages/$page");
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
sub profile {
    my $c = shift;

    my $profile = $c->_load_profile;
    $c->stash(site_profile => $profile);

    if($c->req->method eq 'POST') {
        my $validation = $c->validation;

        $c->_process_uploaded_photo;
        foreach my $field (qw(name address postcode telephone mobile blurb)) {
            eval { $profile->$field($c->param($field)); };
            my $error = $@;
            if($error =~ m{^CRP::Util::Types::(.+?) }) {
                $validation->error($field => ["invalid_column_$1"]);
            }
            else {
                die $error if $error;
            }
        }
        if($validation->has_error) {
            $c->stash(msg => 'fix_errors');
        }
        else {
            $c->_notify_admins_of_changes($profile);
            $profile->update;
            $c->flash(msg => 'profile_update');
            return $c->redirect_to('crp.members.profile');
        }
    }

    $c->render;
}

use CRP::Util::Graphics;
sub _process_uploaded_photo {
    my $c = shift;

    my $photo = $c->req->upload('photo');
    return unless $photo->size;

    if($photo->size > ($c->config->{instructor_photo}->{max_size} || 10_000_000)) {
        $c->validation->error(photo => ['file_too_large']);
        return;
    }

    use File::Temp;
    my($fh, $temp_file) = tmpnam();
    close $fh;

    my $error;
    try {
        $photo->move_to($temp_file);
        if(CRP::Util::Graphics::resize(
                $temp_file,
                $c->config->{instructor_photo}->{width},
                $c->config->{instructor_photo}->{height},
            )) {
            use File::Copy;
            my $target = $c->crp->path_for_instructor_photo($c->crp->logged_in_instructor_id);
            move $temp_file, $target or die "Failed to move '$temp_file' to '$target': $!";
        }
        else {
            $c->validation->error(photo => ['invalid_image_file']);
        }
    }
    catch {
        $error = $_;
    };
    unlink $temp_file;
    die $error if $error;
}

sub _notify_admins_of_changes {
    my $c = shift;
    my($profile) = @_;

    my %changes = $profile->get_dirty_columns;
    my %important_changes;
    foreach my $important_column (qw(name address telephone)) {
        $important_changes{$important_column} = $changes{$important_column} if exists $changes{$important_column};
    }
    if(%important_changes) {
        my $slug = '-' . CRP::Util::WordNumber::encipher($profile->instructor_id);
        $c->mail(
            to          => $c->crp->email_to($c->app->config->{email_addresses}->{user_admin}),
            template    => 'members/email/profile_update',
            info        => {
                changes => \%important_changes,
                id      => $profile->instructor_id,
                url     => $c->url_for('crp.membersite.home', slug => $slug)->to_abs,
            },
        );
    }
}


sub _load_profile {
    my $c = shift;

    my $instructor_id = $c->crp->logged_in_instructor_id or die "Not logged in";
    my $profile = $c->crp->model('Profile')->find_or_create({instructor_id => $instructor_id});
    $c->stash('profile_record', $profile);
    return $profile;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
use CRP::Util::PDF;
sub get_pdf {
    my $c = shift;

    my $pdf = shift // $c->stash('pdf');
    $pdf = $c->app->home->rel_file("pdfs/members/$pdf.pdf");
    return $c->reply->not_found unless -r $pdf;

    my $profile = $c->_load_profile;
    my $url = $c->url_for('crp.membersite.home', slug => $profile->web_page_slug)->to_abs;
    $url =~ s{.+?://}{};
    my $pdf_doc = CRP::Util::PDF::fill_template(
        $pdf,
        {
            profile => $profile,
            url     => $url,
            email   => $c->stash('crp_session')->variable('email'),
        }
    );

    $c->render_file(
        data                => $pdf_doc,
        format              => 'pdf',
        content_disposition => $c->param('download') ? 'attachment' : 'inline',
    );
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
sub find_enquiries {
    my $c = shift;

    $c->_load_profile;
    my $latitude = $c->param('latitude') // '';
    my $longitude = $c->param('longitude') // '';
    my $file_name_location = $c->param('location') // '';
    $file_name_location =~ s{[^a-z0-9\s]}{}gi;
    $c->stash(file_name_location => substr($file_name_location, 0, 20));
    if($latitude ne '' && $longitude ne '') {
        my $enquiries_list = [
            $c->crp->model('Enquiry')->search_near_location(
                $latitude,
                $longitude,
                $c->config->{'enquiry_search_distance'},
                { notify_tutors => 1 },
                { order_by => {-desc => 'create_date'} },
            )
        ];
        $c->stash(enquiries_list => $enquiries_list);
    }
    $c->render(template => 'members/find_enquiries');
}

1;

