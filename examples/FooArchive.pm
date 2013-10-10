package FooArchive;

use File::Temp;
use Image::Size ();
use parent qw(RSS::ArchiveReader);
use strict;

#  The webcomic on which this example is based is often NSFW, so I've
#  obscured the real name.
#
#  This archive presents a special problem.  The server which provides
#  the images checks the HTTP Referer header and serves up alternate
#  content if it's not as expected.  To get around this, we download
#  each image to a local web server directory, providing the
#  appropriate Referer header, and then render the RSS content as an
#  <img> element that points to our cached copy.  A separate cron job
#  can then clean up older images.

use constant {
    FEED_TITLE     => 'Foo Archive',
    RSS_FILE       => "$ENV{HOME}/www/rss/foo.xml",
    FIRST_PAGE     => 'http://www.foo_.com/start.html',
    ITEMS_TO_FETCH => 3,
    NEXT_PAGE      => '//a[img[contains(@src,"next_day")]]/@href',
};

my $IMAGE_DIR = "$ENV{HOME}/www/foo";

my $IMAGE_DIR_URL = "http://my_host.name/foo";


sub render {
    my ($self, $tree, $uri) = @_;
    my ($img) = $tree->findnodes('//img[starts-with(@src,"/comics/")]') or return;
    my $copy  = File::Temp->new(DIR => $IMAGE_DIR, SUFFIX => '.jpg', UNLINK => 0);

    my $response = $self->agent->get(
        $self->resolve($img->attr('src'), $tree, $uri),
        Referer => $uri,
        ':content_file' => "$copy",
    );

    $response->is_success or return;
    chmod 0744, $copy;
    my ($width, $height) = Image::Size::imgsize($copy);

    return $self->new_element('img', {
        src    => $IMAGE_DIR_URL . substr($copy, length $IMAGE_DIR),
        width  => $width,
        height => $height,
    });

}


1;
