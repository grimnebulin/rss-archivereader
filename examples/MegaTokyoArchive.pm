package MegaTokyoArchive;

use parent qw(RSS::ArchiveReader);
use strict;

use constant {
    FEED_TITLE     => 'MegaTokyo Archive',
    RSS_FILE       => "$ENV{HOME}/www/rss/megatokyo.xml",
    FIRST_PAGE     => 'http://megatokyo.com/strip/1',
    ITEMS_TO_FETCH => 5,
    RENDER         => '//span[@id="strip"]//img[contains(@src,"strips/")]',
    NEXT_PAGE      => [ '//li[%s]//a/@href', 'next' ],
};

#  Here we simply use the "title" attribute of the main image (if it
#  exists) as the title of each RSS item, rather than the default
#  title (ie, the HTML title of the page).

sub title {
    my ($self, $doc) = @_;
    my ($title) = $doc->find($self->RENDER . '/@title')
        or return $self->SUPER::title($doc);
    return $title->getValue;
}


1;
