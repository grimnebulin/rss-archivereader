package PennyArcadeArchive;

use parent qw(RSS::ArchiveReader);
use strict;

use constant {
    FEED_TITLE     => 'Penny Arcade Archive',
    RSS_FILE       => "$ENV{HOME}/www/rss/pennyarcade.xml",
    FIRST_PAGE     => 'http://www.penny-arcade.com/comic/1998/11/18',
    ITEMS_TO_FETCH => 5,
    RENDER         => '//div[contains(@class,"comic")]/img',
    NEXT_PAGE      => '//a[@title="Next"]/@href',
};

#  Here I simply incorporate the date of each comic, as extracted from
#  its URL, into the RSS item's title.  (I like to know when a comic
#  was originally posted.)

sub title {
    my ($self, $doc) = @_;
    my $title = $self->SUPER::title($doc);
    $title .= " - $2-$3-$1" if $doc->source =~ m|/comic/(\d+)/(\d+)/(\d+)|;
    return $title;
}


1;
