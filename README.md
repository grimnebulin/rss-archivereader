# SUMMARY

`RSS::ArchiveReader` is a Perl framework that accesses archived web
content and presents its entries as an RSS feed.

An "archive" in the sense of this framework is simply a set of HTML
pages, each connected to the next by a link of some kind (typically a
"next" hyperlink).  Each time the framework is run, it accesses the
page it most recently visited and follows the link to the next page
(or starts on a given page if it hasn't been run before), renders that
page into the body of an RSS item, follows the link to the next page,
and so on, until it has rendered a fixed number of pages.

# EXAMPLE

I recently became aware of the webcomic
[Spacetrawler](http://spacetrawler.com/) which has been around for a
few years.  I wanted to start reading it from the beginning, but it's
kind of a hassle to read a few strips, bookmark a stopping place,
return to the bookmark later, delete it, and repeat until I'm all
caught up.  Instead, I'd rather have a fixed number of strips
automatically served up in my RSS reader every day.  I created the
following subclass of `RSS::ArchiveReader`:

    package SpacetrawlerArchive;

    use parent qw(RSS::ArchiveReader);
    use strict;

    use constant {
        FEED_TITLE => 'Spacetrawler Archive',
        RSS_FILE   => "$ENV{HOME}/www/rss/spacetrawler.xml",
        FIRST_PAGE => 'http://spacetrawler.com/2010/01/01/spacetrawler-4/',
        RENDER     => '//div[contains(@class,"comicpane")]//img',
        NEXT_PAGE  => '//a[contains(@class,"navi-next")]/@href',
    };

    1;

Now, whenever I run the command

    perl -MSpacetrawlerArchive -e 'SpacetrawlerArchive->new->run'

...another comic is appended to the `spacetrawler.xml` file.  I can
run this command in a daily cron job to get a steady stream of comics.

The base class `RSS::ArchiveReader` provides a number of overridable
method, but (as in the example) no overriding may be needed if an
archive's content is simple enough:

* If the content to be rendered into the RSS feed is single HTML
  element accessible by an XPath expression, the default `render`
  method does so using the `RENDER` parameter.
* If each page is reached from the previous one via an attribute node
  (most commonly, if not always, by an `<a>` element's `href`
  attribute) accessible by an XPath expression, the default
  `next_page` method does so using the `NEXT_PAGE` parameter.
* The default `title` method titles each RSS item using the source
  page's HTML title.

See the documentation of the
[RSS::ArchiveReader](RSS/ArchiveReader.pm) class for more complete
information.  More extensive examples can be found in the
[examples](examples) directory.
