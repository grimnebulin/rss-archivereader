package FooArchive;

use parent qw(RSS::ArchiveReader);
use strict;

#  The webcomic on which this example is based is often NSFW, so I've
#  obscured the real name.
#
#  The server which provides the images checks the HTTP Referer header
#  and serves up alternate content if it's not as expected.  To get
#  around this, we employ the cache_image method, which downloads
#  images to a local cache directory (passing the correct Referer
#  header) and constructs a new <img> element that refers to the
#  cached copy.  A separate cron job can then clean up older images.

use constant {
    FEED_TITLE     => 'Foo Archive',
    RSS_FILE       => "$ENV{HOME}/www/rss/foo.xml",
    FIRST_PAGE     => 'http://www.foo_.com/start.html',
    ITEMS_TO_FETCH => 3,
    NEXT_PAGE      => '//a[img[contains(@src,"next_day")]]/@href',
    CACHE_DIR      => "$ENV{HOME}/www/foo",
    CACHE_URL      => 'http://my_host.name/foo',
};


sub render {
    my ($self, $doc) = @_;
    my ($img) = $doc->findnodes('//img[starts-with(@src,"/comics/")]') or return;
    return $self->cache_image($doc, $img);
}


1;
