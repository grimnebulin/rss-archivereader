package RSS::ArchiveReader;

# Copyright 2013 Sean McAfee

# This file is part of RSS::ArchiveReader.

# RSS::ArchiveReader is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# RSS::ArchiveReader is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with RSS::ArchiveReader.  If not, see
# <http://www.gnu.org/licenses/>.

use DateTime;
use DateTime::Duration;
use DateTime::Format::Mail;
use HTML::TreeBuilder::XPath;
use LWP::UserAgent;
use Scalar::Util;
use URI;
use XML::RSS;
use strict;

my $RSS_VERSION = '2.0';

my $RUNS_TO_KEEP = 5;

my $ONE_SECOND = DateTime::Duration->new(seconds => 1);

########################################

sub new {
    my ($class, %param) = @_;

    my $param = sub {
        my $arg = $_[0];
        exists $param{$arg}
            ? $param{$arg}
            : do { my $uc = uc($arg); scalar $class->$uc() }
    };

    my $self = bless {
        map {
            $_ => scalar $param->($_)
        } qw(
             agent_id feed_title feed_link feed_description
             rss_file items_to_fetch items_to_keep render next_page
             autoresolve)
    }, $class;

    defined(my $first_page = $param->('first_page'))
        or die "No first page defined\n";
    my $uri = URI->new($first_page);
    defined $uri->scheme or die "First page URI $uri is not absolute\n";
    $self->{first_page} = $uri;

    return $self;

}

sub AGENT_ID {
    return "";
}

sub FEED_TITLE {
    return undef;
}

sub FEED_LINK {
    return undef;
}

sub FEED_DESCRIPTION {
    return undef;
}

sub RSS_FILE {
    return undef;
}

sub ITEMS_TO_FETCH {
    return 1;
}

sub ITEMS_TO_KEEP {
    return undef;
}

sub RENDER {
    return undef;
}

sub NEXT_PAGE {
    return undef;
}

sub FIRST_PAGE {
    return undef;
}

sub AUTORESOLVE {
    return 1;
}

sub agent {
    my $self = shift;
    return $self->{agent} ||= LWP::UserAgent->new(
        defined $self->{agent_id} ? (agent => $self->{agent_id}) : (),
    );
}

sub run {
    my ($self, %param) = @_;
    my $time  = DateTime->now - $ONE_SECOND * $self->{items_to_fetch};
    my $rss   = $self->_get_rss;
    my $items = $rss->{items};
    my $count = $self->{items_to_fetch};
    my $uri;

    if (@$items) {
        my $link = URI->new($items->[-1]{link});
        my $tree = $self->get_tree($link);
        my $next = $self->next_page($tree, $link->clone);
        $uri = $next && $self->resolve($next, $tree, $link->clone);
    } else {
        $uri = $self->{first_page};
    }

    while (--$count >= 0 && $uri) {
        my $tree = $self->get_tree($uri);
        $rss->add_item(
            link        => "$uri",
            title       => scalar $self->title($tree, $uri->clone),
            description => $self->_stringify($tree, $uri->clone, $self->render($tree, $uri->clone)),
            pubDate     => DateTime::Format::Mail->format_datetime($time),
        );
        if ($count > 0) {
            $time += $ONE_SECOND;
            my $next_uri = $self->next_page($tree, $uri->clone);
            $uri = $next_uri && $self->resolve($next_uri, $tree, $uri->clone);
        }
    }

    my $keep = defined $self->{items_to_keep}
        ? $self->{items_to_keep}
        : $RUNS_TO_KEEP * $self->{items_to_fetch};

    splice @$items, 0, -$keep if @$items > $keep;

    if ($param{print}) {
        print $rss->as_string;
    } else {
        my $tmpfile = $self->{rss_file} . '.tmp';
        $rss->save($tmpfile);
        rename $tmpfile, $self->{rss_file}
            or die "Failed to rename $tmpfile to $self->{rss_file}: $!\n";
    }

    return;

}

sub feed_title {
    my $self = shift;
    return $self->{feed_title} if defined $self->{feed_title};
    return $self->{first_page}->host;
}

sub feed_link {
    my $self = shift;
    return $self->{feed_link} if defined $self->{feed_link};
    my $uri = $self->{first_page}->clone;
    $uri->$_(undef) for qw(path query fragment);
    return $uri;
}

sub feed_description {
    my $self = shift;
    return $self->{feed_description} if defined $self->{feed_description};
    return $self->feed_title;
}

sub title {
    my ($self, $tree, $uri) = @_;
    my ($title) = $tree->findnodes('/html/head/title');
    return defined $title ? $title->as_trimmed_text : $uri;
}

sub get_tree {
    my ($self, $uri) = @_;
    my $response = $self->get_page($uri);
    $response->is_success or die "Failed to download $uri: ", $response->as_string, "\n";
    return HTML::TreeBuilder::XPath->new_from_content(
        $self->decode_response($response)
    );
}

sub get_page {
    my ($self, $uri) = @_;
    return $self->agent->get($uri);
}

sub render {
    my ($self, $tree) = @_;
    defined(my $xpath = $self->{render})
        or die "Don't know how to render pages\n";
    my ($elem) = $tree->findnodes($xpath) or return;
    return $elem;
}

sub next_page {
    my ($self, $tree) = @_;

    defined(my $xpath = $self->{next_page})
        or die "Don't know how to advance to next page\n";

    my ($href) = $tree->findnodes($xpath) or return;

    Scalar::Util::blessed($href) && $href->isa('HTML::TreeBuilder::XPath::Attribute')
        or die "next_page parameter did not return an attribute node\n";

    return $href->getValue;

}

sub new_element {
    my $self = shift;
    require HTML::Element;
    return HTML::Element->new_from_lol([ @_ ]);
}

sub decode_response {
    my ($self, $response) = @_;
    return $response->decoded_content;
}

sub resolve {
    my ($self, $href, $tree, $uri) = @_;
    $href = URI->new($href);
    return $href if defined $href->scheme;
    if (my ($base) = $tree->findnodes('/html/head/base/@href')) {
        $base = URI->new($base->getValue);
        $uri = $base if defined $base->scheme;
    }
    return URI->new_abs($href, $uri);
}

sub _get_rss {
    my $self = shift;
    my $rss  = eval { XML::RSS->new->parsefile($self->{rss_file}) };
    return $rss if $rss;
    die $@ if $@ !~ /no such file/i;
    $rss = XML::RSS->new(version => $RSS_VERSION);
    $rss->channel(
        title       => scalar $self->feed_title,
        link        => scalar $self->feed_link,
        description => scalar $self->feed_description,
        $self->extra_channel_params,
    );
    return $rss;
}

sub extra_channel_params {
    return;
}

sub _stringify {
    my ($self, $tree, $uri, @chunk) = @_;
    return join "", map {
        Scalar::Util::blessed($_) && $_->isa('HTML::Element')
            ? ($self->{autoresolve} ? $self->_resolve_element($_, $tree, $uri) : $_)
                  ->as_HTML("", undef, { })
            : $_
    } @chunk;
}

sub _resolve_element {
    my ($self, $elem, $tree, $uri) = @_;
    my $clone = $elem->clone;
    for my $e ($clone->find_by_tag_name('img', 'iframe', 'embed')) {
        $e->attr('src', $self->resolve($e->attr('src'), $tree, $uri));
    }
    return $clone;
}


1;

__END__

=head1 NAME

RSS::ArchiveReader - present archived Web content as an RSS feed

=head1 SYNOPSIS

    package SomeArchive;

    use parent qw(RSS::ArchiveReader);

    use constant {
        FEED_TITLE => 'Title',
        RSS_FILE   => '/path/to/rss.xml',
        FIRST_PAGE => 'http://my_archive.com/index?page=1',
        RENDER     => '//div[@id="body"]',
        NEXT_PAGE  => '//a[@class="nextpage"]/@href',
    };

    1;

    package main;

    SomeArchive->new->run;

=head1 DESCRIPTION

C<RSS::ArchiveReader> is a framework for rendering a sequence of web
pages into items in an RSS feed.  A client can designate the URI of
the first page in the series, and also a method for traversing from
one page to the next.  Each time the framework is run, it examines the
RSS file it left on the previous run and traverses a given number of
pages from the last page it visited, rendering each page into an RSS
item, which is saved back to the same file.

The framework is most easily utilized by defining a subclass of
C<RSS::ArchiveReader>.  The C<run> method, which does most of the
heavy lifting, calls down into various overridable methods to assemble
the output RSS file.  The default implementations of these methods
suffice for many kinds of simpler content; a subclass may not need to
override any methods at all, but only define constants, as in the
Synopsis example above.

The name of the package reflects its expected use of providing
bite-sized, sequential pieces of archived web content, such as
webcomics, blog entries, and the like.  A cron job might be employed
to pull in a fixed number of archived pages once per day, saving them
to an RSS file to which an aggregator service can be directed.  One
can then use a feed reader to follow old web content as if it were
being published now.

=head1 CONSTRUCTOR

=over 4

=item RSS::ArchiveReader->new(%param)

Create a new C<RSS::ArchiveReader> object.  C<%param> is a (possibly
empty) hash of parameters, of which the following are recognized.

=over 4

=item agent_id

This is the User-Agent string that will be used by the
C<LWP::UserAgent> object that performs web requests related to this
object.  It defaults to C<""> (the empty string).  If undefined, no
explicit user-agent will be set, and so the default agent supplied by
the C<LWP::UserAgent> module will be used.

=item feed_title

The default implementation of the C<feed_title> method uses this
parameter as the "title" field of the output RSS feed, if it's
defined.

=item feed_link

The default implementation of the C<feed_link> method uses this
parameter as the "link" field of the output RSS feed, if it's defined.

=item feed_description

The default implementation of the C<feed_description> method uses this
parameter as the "description" field of the output RSS feed, if it's
defined.

=item rss_file

The path to the output RSS file.

=item items_to_fetch

The number of archived web items to fetch per invocation of the C<run>
method.   Defaults to 1.

=item items_to_keep

The maximum number of items to retain in the output RSS file.  If
undefined, then a number of items will be retained equal to five times
the value of the C<items_to_fetch> paramter.  Defaults to C<undef>.

=item first_page

The URI of the first page in the archive.  It must be defined, and
also be an absolute URI, or the constructor will throw an exception.

=item render

The default implementation of the C<render> method uses this parameter
as an XPath expression to extract web content.  Elements matched by
this expression are concatenated into the "description" field of an
item in the output RSS feed.  The default implementation throws an
exception if the parameter is not defined, but a subclass may override
this method with a subroutine that does not care if it's defined or
not.

=item next_page

The default implementation of the C<next_page> method uses this
parameter as an XPath expression to locate the "next" link on a web
page.

=item autoresolve

A boolean flag.  If true, then the C<src> attributes of any C<img>,
C<iframe>, and C<embed> elements returned by the C<render> method
(either directly, or as descendant elements) are resolved to absolute
URIs if necessary by calling the C<resolve> method (which see).

The default value is true.

=back

It is convenient not to have to write a constructor for every subclass
of C<RSS::ArchiveBuilder>, so each of the parameters described above
can also be supplied by a class method with the same name as the
parameter, but uppercased.  Explicitly:

=over 4

=item AGENT_ID

=item FEED_TITLE

=item FEED_LINK

=item FEED_DESCRIPTION

=item RSS_FILE

=item ITEMS_TO_FETCH

=item ITEMS_TO_KEEP

=item FIRST_PAGE

=item RENDER

=item NEXT_PAGE

=item AUTORESOLVE

=back

Such methods can be easily defined by the C<constant> pragma, e.g.:

    package MyArchive;
    use parent qw(RSS::ArchiveBuilder);
    use constant { FEED_TITLE => '...', RSS_FILE => '...'  };

A parameter passed to the constructor overrides the parameter value
returned by these methods.

=back

=head1 METHODS

=over 4

=item $reader->agent

Returns the C<LWP::UserAgent> object used by this object, creating it
if it does not already exist.

=item $reader->run(%param)

The main entry point of the framework.  It performs the following
steps.

=over 4

=item

Examines the RSS file referred to by its C<rss_file> parameter.  If it
does not exist, a new file will be created, with the RSS C<title>,
C<link> and C<description> fields obtained by calling the
C<feed_title>, C<feed_link>, and C<feed_description> methods
respectively; and the web page identified by the C<first_page>
parameter is fetched.

If the RSS file already exists, the page linked to by the final item
is fetched, and the C<next_page> method is called to obtain the URI of
the next page in sequence.

=item

The retrieved page content is parsed into a tree structure by the
C<HTML::TreeBuilder::XPath> class.

=item

The page's content is rendered into the C<description> field of a new
RSS item by passing the HTML tree to the C<render> method.

=item

A number of pages equal to the value of the C<items_to_fetch> method
are processed in this way, each page reached from the previous one by
passing the HTML tree to the C<next_page> method.

=item

The new items are appended to the old items in the original RSS file.
A number of most-recent items derived from the C<items_to_keep>
parameter are kept; the rest are discarded.  See the description of
the C<items_to_keep> parameter for details.

To be precise, a new RSS file is created by appending ".tmp" to the
name of the original one; then the new file is renamed to the
original's name, replacing it.

=back

=item $reader->feed_title

Returns the title of the RSS file created by this object: the
C<feed_title> parameter, if it's defined, or else the hostname of the
archive, taken from the C<first_page> parameter.  May be overridden to
give the feed a different title.

=item $reader->feed_link

Returns the link of the RSS file created by this object: the
C<feed_link> parameter, if it's defined, or else a copy of the
C<first_page> URI with the path, query, and fragment components
removed.  May be overridden to give the feed a different link.

=item $reader->feed_description

Returns the description of the RSS file created by this object: the
C<feed_description> parameter, if it's defined, or else whatever the
C<feed_title> method returns.  May be overridden to give the feed a
different description.

=item $reader->extra_channel_params()

When the RSS file associated with C<$reader> is created (because it
did not already exist), the following key-value pairs are passed to
its C<channel> method:

=over 4

=item title       => $reader->feed_title

=item link        => $reader->feed_link

=item description => $reader->feed_description

=back

Any additional values returned by C<extra_channel_params> are also
passed.  Any C<title>, C<link>, or C<description> keys override the
default values listed above.  The default implementation returns
nothing.

=item $reader->title($tree, $uri)

Returns the title to be given to the RSS item derived from the archive
page at the URI C<$uri> (a C<URI> object), whose page content has been
parsed into the C<HTML::TreeBuilder::XPath> object C<$tree>.  The
default implementation simply returns the page's HTML title, or if
that is undefined for some reason, then the URI C<$uri>.  May be
overridden to provide different logic for titling items.

=item $reader->get_page($uri)

Returns the web page referred to by the C<URI> object C<$uri> as an
C<HTTP::Response> object.  The default implementation simply returns
C<$reader-E<gt>agent-E<gt>get($uri)>.  May be overridden.

=item $reader->get_tree($uri)

A convenience method that fetches the page at C<$uri> by calling
C<$reader-E<gt>get_page($uri)> and parses the returned content into an
C<HTML:::TreeBuilder::XPath> tree, which is returned.  The page is
fetched using C<$reader>'s agent and the response is decoded by
calling C<$reader>'s C<decode_response> method, so this method may not
be suitable for processing pages outside of the main archive.

=item $reader->render($tree, $uri)

Returns a list of values that will be used to create the
C<description> field of the RSS item for the archive page at the URI
C<$uri> (a C<URI> object), whose page content has been parsed into the
C<HTML::TreeBuilder::XPath> object C<$tree>.  C<HTML::Element> objects
in the returned list will be mapped into strings by calling their
C<as_HTML> method; after that, all of the return values are
concatenated together into one string, which becomes an RSS item's
C<description>.

The default implementation uses the C<render> parameter (throwing an
exception if it is not defined) as an XPath expression, applying it to
C<$tree>.  The first matching node is returned.

This method may be overridden to provide different logic for rendering
the pages of an archive.

=item $reader->next_page($tree, $uri)

Returns the URI of the archive page following the one at the URI
C<$uri> (a C<URI> object), whose page content has been parsed into the
C<HTML::TreeBuilder::XPath> object C<$tree>.  The returned URI need
not be absolute; if relative, it is taken to be relative to its page's
E<lt>baseE<gt> element, if it has one, or else relative to C<$uri>.

The default implementation uses the C<next_page> parameter (throwing
an exception if it is not defined) as an XPath expression, applying it
to C<$tree>.  If no node is matched by the expression, then nothing is
returned, indicating that the end of the archive has been reached.
Otherwise, the first of the matching nodes must be an instance of the
class C<HTML::TreeBuilder::XPath::Attribute> (that is, it must match
an attribute node), or an exception is thrown.  The attribute's value
is returned otherwise.

This method may be overridden to provide different logic for
traversing the pages of an archive.

=item $reader->decode_response($response)

This method should return the decoded content of C<$response>, an
C<HTTP::Response> object which was returned by an HTTP GET request to
C<$uri>, the link to one of the items handled by this tree.

The default implementation simply returns
C<$response-E<gt>decoded_content()>, but a subclass may override this
method if special handling is needed.

=item $reader->resolve($href, $tree, $uri)

Resolves C<$href> into an absolute URI.  If C<$href> is already
absolute, it is simply returned.  Otherwise, a new absolute C<URI>
object is returned which is constructed from C<$href> by taking it as
relative to one of two absolute URIs:

=over 4

=item

The <base> element of the HTML page which has been parsed into
C<$tree>, if the page has one; or else

=item

C<$uri>, the URI of the page which was parsed into C<$tree>.

=back

=item $reader->new_element(...)

This method is a convenience wrapper for the C<new_from_lol>
constructor of the C<HTML::Element> class.  The arguments to this
method are wrapped in an array reference, which is passed to
C<new_from_lol>.  Example:

    my $elem = $self->new_element(
        'p', 'This is ', [ 'i', 'italicized' ], ' text'
    );

=back
