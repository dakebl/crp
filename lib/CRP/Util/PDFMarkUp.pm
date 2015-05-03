package CRP::Util::PDFMarkUp;
use Moose;

has file_path => (is => 'ro', isa => 'Str', required => 1);
has test_mode => (is => 'ro', isa => 'Bool', default => 0);

has _temp_file_list => (
    traits  => ['Array'],
    is      => 'rw',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
    handles => {
        _add_temp_file  => 'push',
        _temp_files     => 'elements',
    },
);
has _data       => (is => 'rw', isa => 'HashRef');
has _items      => (is => 'rw', isa => 'ArrayRef', default => sub { [] });
has _repeats    => (is => 'rw', isa => 'ArrayRef', default => sub { [] });
has _scale      => (is => 'rw', isa => 'Num', default => 1);
has _y_offset   => (is => 'rw', isa => 'Num', default => 0);
has _x_offset   => (is => 'rw', isa => 'Num', default => 0);
has _pdf        => (is => 'rw', isa => 'PDF::API2');

use constant QRCODE_SCALE => 0.33;

use Mojo::Util;

use warnings;
use strict;

use Carp;
use PDF::API2;

use CRP::Util::Graphics;

sub DEMOLISH {
    my $self = shift;

    foreach my $temp_file ($self->_temp_files) {
        unlink $temp_file;
    }
}

sub fill_template {
    my $self = shift;
    my($crp_data) = @_;

    $self->_pdf(PDF::API2->open($self->file_path)) or croak "Couldn't read PDF file '" . $self->file_path . "': $!";
    $self->_load_markup;
    $self->_data($crp_data // {});
    $self->_markup_pdf;
    foreach my $repeat (@{$self->_repeats}) {
        $self->_markup_pdf($repeat->{x_offset}, $repeat->{y_offset});
    };

    return $self->_pdf->stringify;
}

sub _load_markup {
    my $self = shift;
    
    my $file_path = $self->file_path;
    $file_path =~ s{\.pdf$}{};
    $file_path .= '.mark';
    if(-r $file_path) {
        my $markup_file = Mojo::Util::slurp($file_path);
        $markup_file = eval $markup_file;
        unless($@) {
            eval {
                if(ref $markup_file eq 'ARRAY') {
                    $self->_items($markup_file);
                    $self->_scale(1);
                    $self->_repeats([]);
                }
                elsif(ref $markup_file eq 'HASH') {
                    my $version = $markup_file->{version} // '';
                    die "Unrecognised markup version '$version'" unless $version eq '1';
                    $self->_items($markup_file->{items} // []);
                    $self->_scale($markup_file->{scale} // 1);
                    $self->_repeats($markup_file->{repeats} // []);
                }
                else {
                    die "Unrecognised markup file format";
                }
            };
        }
        warn "PDF Markup error in '$file_path': $@" if $@;
    }
}

sub _markup_pdf {
    my $self = shift;
    my($x_offset, $y_offset) = @_;

    $self->_x_offset($x_offset // 0);
    $self->_y_offset($y_offset // 0);
    foreach my $markup_item(@{$self->_items}) {
        my $action = $markup_item->{action} // 'text';
        if   ($action eq 'text')                { $self->_markup_pdf_text($markup_item); }
        elsif($action eq 'qrcode_signature')    { $self->_markup_pdf_qrcode_signature($markup_item); }
        elsif($action eq 'qrcode')              { $self->_markup_pdf_qrcode($markup_item); }
        elsif($action eq 'image')               { $self->_markup_pdf_image($markup_item); }
    }
}

sub _markup_pdf_text {
    my $self = shift;
    my($markup_item) = @_;

    my $string = $self->_replace_place_holders($markup_item->{text} || '');
    my $page = $self->_pdf->openpage($markup_item->{page} || 1);
    my $font = $self->_pdf->corefont($markup_item->{font} || 'Helvetica', -dokern => 1);
    my $text = $page->text();
    $text->textlabel(
        $self->_get_x_coordinate($markup_item->{x}),
        $self->_get_y_coordinate($markup_item->{y}),
        $font,
        $self->_get_size($markup_item->{size} || 12),
        $string,
        -align => $markup_item->{align} || 'left',
        -color => $markup_item->{colour} || '#000',
    );
}

sub _replace_place_holders {
    my $self = shift;
    my($text) = @_;

    $text =~ s{\[%\s*(.+?)\s*%]}{$self->_data_value($1)}gsmixe;
    return $text;
}

sub _data_value {
    my $self = shift;
    my($key) = @_;

    my $data = $self->_data;
    return $data->{$key} if exists $data->{$key};
    return $self->test_mode ? "[[ $key ]]" : '';
}

sub _markup_pdf_image {
    my $self = shift;
    my($markup_item) = @_;
 
    my($path_name, $page_number, $x, $y, $scale, $align) = @$markup_item{qw(path_name page x y scale align)};
    $scale ||= 1;
    $page_number ||= 1;
    $align //= 'left';
    $path_name = $self->_replace_place_holders($path_name);

    my $image = $self->_pdf->image_jpeg($path_name);
    my $width = $image->width;
    my $page = $self->_pdf->openpage($page_number);
    my $gfx = $page->gfx;
    $x -= $width * $scale if $align eq 'right';
    $x -= $width / 2 * $scale if $align eq 'center';
    $gfx->image($image, $self->_get_x_coordinate($x), $self->_get_y_coordinate($y), $self->_get_size($scale));
}

sub _markup_pdf_qrcode_signature {
    my $self = shift;
    my($markup_item) = @_;

    my $font_size = $markup_item->{size} || 12;
    my $line_height = $font_size * 1.2;
    my $data = $self->_data;

    my $signature_url = $self->test_mode
        ? 'http://www.kidsreflexology.co.uk/me/-175347/certificate' # Long enough to generate a typically sized QRCode
        : $data->{signature_url} // '';
    my($width, $height) = $self->_add_qr_code_link(
        $signature_url, $markup_item->{page} || 1, $markup_item->{x}, $markup_item->{y}, $markup_item->{align}
    );

    my $text_markup_item = { %$markup_item };

    $text_markup_item->{text} = $text_markup_item->{text1};
    $text_markup_item->{x} += ($width * QRCODE_SCALE) * (($markup_item->{align} // '') eq 'right' ? -1 : 1);
    $text_markup_item->{y} += 10 * QRCODE_SCALE; # Width of QRCode white border
    $text_markup_item->{y} += $line_height;
    $self->_markup_pdf_text($text_markup_item);

    $text_markup_item->{text} = $text_markup_item->{text2};
    $text_markup_item->{y} -= $line_height;
    $self->_markup_pdf_text($text_markup_item);
}

sub _add_qr_code_link {
    my $self = shift;
    my($url, $page_number, $x, $y, $align) = @_;

    my ($file_name, $width, $height) = CRP::Util::Graphics::qr_code_link_jpeg_tmp_file($url);
    my $page = $self->_pdf->openpage($page_number || 1);
    my $gfx = $page->gfx;
    my $image = $self->_pdf->image_jpeg($file_name);
    $align //= 'left';
    $x -= $width * QRCODE_SCALE if $align eq 'right';
    $x -= $width / 2 * QRCODE_SCALE if $align eq 'center';
    $gfx->image($image, $self->_get_x_coordinate($x), $self->_get_y_coordinate($y), $self->_get_size(QRCODE_SCALE));
    $self->_add_temp_file($file_name);
    return($width, $height);
}

sub _markup_pdf_qrcode {
    my $self = shift;
    my($markup_item) = @_;

    my $data = $self->_data;

    my $string = $self->test_mode
        ? 'http://www.kidsreflexology.co.uk/me/-175347/icourse/88' # Long enough to generate a typically sized QRCode
        : $markup_item->{text} // '';
    $string = $self->_replace_place_holders($string);
    return unless $string;
    $self->_add_qr_code_link(
        $string, $markup_item->{page} || 1, $markup_item->{x}, $markup_item->{y}, $markup_item->{align}
    );
}

sub _get_x_coordinate {
    my $self = shift;
    my($x) = @_;

    return $self->_get_size($x + $self->_x_offset);
}

sub _get_y_coordinate {
    my $self = shift;
    my($y) = @_;

    return $self->_get_size($y + $self->_y_offset);
}

sub _get_size {
    my $self = shift;
    my($size) = @_;

    return $size * $self->_scale;
}



no Moose;
__PACKAGE__->meta->make_immutable;
1;


