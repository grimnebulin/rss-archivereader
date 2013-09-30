package QCArchive;

use parent qw(RSS::ArchiveReader);
use strict;
use utf8;

use constant {
    FEED_TITLE     => 'Questionable Content Archive',
    RSS_FILE       => "$ENV{HOME}/www/rss/qcarchive.xml",
    FIRST_PAGE     => 'http://questionablecontent.net/view.php?comic=1',
    ITEMS_TO_FETCH => 3,
    NEXT_PAGE      => '//a[normalize-space()="Next"]/@href',
};

#  In addition to the usual image, I append the content found in the
#  <div> element with id "news", unless that content looks like "No
#  news today, sorry."

sub render {
    my ($self, $tree) = @_;
    my ($image) = $tree->findnodes('//div[@id="comic"]//img[contains(@src,"/comics/")]')
        or return;
    my ($news) = $tree->findnodes('//div[@id="news"]');
    $news = "" if $news && $news->as_trimmed_text =~ /no news today, sorry/i;
    return ($image, $news);
}


1;
