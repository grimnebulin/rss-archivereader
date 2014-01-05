package DoctorFunArchive;

use URI;
use parent qw(RSS::ArchiveReader);
use strict;

use constant {
    FEED_TITLE => 'Doctor Fun Archive',
    RSS_FILE   => "$ENV{HOME}/www/rss/doctorfun.xml",
    FIRST_PAGE => 'http://www.ibiblio.org/Dave/ar00001.htm',
    NEXT_PAGE  => '//a[starts-with(normalize-space(),"next")]/@href',
};

#  Each page of this archive includes multiple images.  We render each
#  of them into a separate div.

sub render {
    my ($self, $doc) = @_;
    return map {
        $self->new_element(
            'div', [ 'img', { src => $_->attr_absolute('href') } ]
        )
    } $doc->find('//a[img[contains(@src,"/thumbs/")]]');
}


1;
