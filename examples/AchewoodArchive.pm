package AchewoodArchive;

use Date::Parse;
use POSIX;
use parent qw(RSS::ArchiveReader);
use strict;
use utf8;

use constant {
    FEED_TITLE       => 'Achewood Archive',
    RSS_FILE         => "$ENV{HOME}/www/rss/achewood-archive.xml",
    FIRST_PAGE       => 'http://achewood.com/index.php?date=10012001',
    ITEMS_TO_FETCH   => 10,
    ITEMS_TO_KEEP    => 40,
    NEXT_PAGE        => '//a[normalize-space()="»"]/@href',
};

#  We jigger the title a bit so that it incorporates the day of the
#  week when it was originally posted.

sub title {
    my ($self, $tree, $uri) = @_;
    my $title = $self->SUPER::title($tree, $uri);
    if ($title =~ /^(achewood\s+\S+\s+)(.+)/is) {
        if (defined(my $time = Date::Parse::str2time($2))) {
            $title = $1 . POSIX::strftime('%A', gmtime $time) . ', ' . $2;
        }
    }
    return $title;
}

#  Also, if the main image has a "title" attribute, include it in
#  italics below the image in its own <div>.

sub render {
    my ($self, $tree) = @_;
    my ($image) = $tree->findnodes('//img[contains(@class,"comic")]') or die;
    my $title   = $image->attr('title', undef);
    return $self->new_element(
        'div', $image, $title ? [ 'div', [ 'i', $title ] ] : (),
    );
}


1;