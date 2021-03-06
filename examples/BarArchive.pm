package BarArchive;

use HTTP::Request::Common ();
use parent qw(RSS::ArchiveReader);
use strict;

#  The webcomic on which this example is based is often NSFW, so I've
#  obscured the real name.

use constant {
    FEED_TITLE     => 'Bar Archive',
    RSS_FILE       => "$ENV{HOME}/www/rss/bar.xml",
    FIRST_PAGE     => 'http://bar_.com/first/',
    ITEMS_TO_FETCH => 5,
    RENDER         => '//img[@id="strip"]',
    NEXT_PAGE      => '//a[div[@id="nx"]]/@href',
};

#  Visitors to this site are greeted by a page asking if they're over
#  18 years old, and must click a button to continue to the
#  originally-requested page.
#
#  To get around this, we override the default make_request method
#  (which uses HTTP GET) to provide a POST request instead, providing
#  the "over18" form parameter that the confirmation page normally
#  provides, thereby bypassing that page.

sub make_request {
    my ($self, $uri) = @_;
    return HTTP::Request::Common::POST($uri, { over18 => 'y' });
}


1;
