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
    NEXT_PAGE        => '//a[normalize-space()="»"]/@href',
};

#  We jigger the title a bit so that it incorporates the day of the
#  week when it was originally posted.

sub title {
    my ($self, $doc) = @_;
    my $title = $self->SUPER::title($doc);
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
    my ($self, $doc) = @_;
    my ($image) = $doc->find('//img[%s]', 'comic') or die;
    my $title   = $image->attr('title', undef);
    return $self->new_element(
        'div', $image, $title ? [ 'div', [ 'i', $title ] ] : (),
    );
}


1;
