package RSS::ArchiveReader;

# Copyright 2013-2016 Sean McAfee

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
use HTTP::Request;
use RSS::ArchiveReader::HtmlDocument;
use Scalar::Util;
use URI;
use XML::RSS;
use strict;

my $RSS_VERSION = '2.0';

my $RUNS_TO_KEEP = 5;

my $ONE_SECOND = DateTime::Duration->new(seconds => 1);

my %AUTORESOLVE = (
    src  => [ qw(img iframe embed) ],
    href => [ qw(a) ],
);

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
        (
            map {
                $_ => $param->($_)
            } qw(feed_title feed_link feed_description
                 rss_file items_to_fetch items_to_keep
                 autoresolve cache_dir cache_mode cache_url
                 end_of_archive_notify end_of_archive_message)
        ),
        (
            map {
                $_ => scalar _normalize($param->($_))
            } qw(render next_page filter)
        ),
    }, $class;

    defined(my $first_page = $param->('first_page'))
        or die "No first page defined\n";
    my $uri = URI->new($first_page);
    defined $uri->scheme or die "First page URI $uri is not absolute\n";

    $self->{first_page} = $uri;

    if (exists $param{agent}) {
        $self->{agent} = $param{agent};
    } else {
        my $config = $param->('agent_config');
        my $id     = $param->('agent_id');
        my $jar    = $self->_cookie_jar($param->('cookies'));
        $self->{agent_config} = {
            defined $id ? (agent => $id) : (),
            defined $jar ? (cookie_jar => $jar) : (),
            defined $config ? %$config : (),
        };
    }

    return $self;

}

sub _cookie_jar {
    my ($self, $cookies) = @_;
    return if !$cookies;
    require HTTP::Cookies;
    my $jar = HTTP::Cookies->new;
    if (ref $cookies eq 'ARRAY') {
        my @cookies = @$cookies;
        my $domain = $self->{first_page}->host;
        while (@cookies) {
            $jar->set_cookie('1', splice(@cookies, 0, 2), '/', $domain);
        }
    }
    return $jar;
}

sub _normalize {
    my $value = shift;
    if (!defined $value) {
        return;
    } elsif (!defined Scalar::Util::blessed($value) &&
             Scalar::Util::reftype($value) eq 'ARRAY') {
        return RSS::ArchiveReader::HtmlDocument::_format_path(@$value);
    } else {
        return $value;
    }
}

sub AGENT_ID {
    return "";
}

sub AGENT_CONFIG {
    return undef;
}

sub COOKIES {
    return;
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

sub FILTER {
    return undef;
}

sub FIRST_PAGE {
    return undef;
}

sub AUTORESOLVE {
    return 1;
}

sub END_OF_ARCHIVE_NOTIFY {
    return 1;
}

sub END_OF_ARCHIVE_MESSAGE {
    return 'End of archive has been reached.';
}

sub CACHE_DIR {
    return undef;
}

sub CACHE_URL {
    return undef;
}

sub CACHE_MODE {
    return 0644;
}

sub agent {
    my $self = shift;
    return $self->{agent} ||= do {
        require LWP::UserAgent;
        my $agent = LWP::UserAgent->new(%{ $self->{agent_config} });
        $self->configure_agent($agent);
        $agent;
    };
}

sub configure_agent {
    return;
}

sub run {
    my ($self, %param) = @_;
    my $now   = DateTime->now;
    my $count = $self->{items_to_fetch};
    my $time  = $now - $ONE_SECOND * $count;
    my $rss   = $self->_get_rss;
    my $items = $rss->{items};
    my $doc;

    if (@$items) {
        my $final = $items->[-1];
        if (defined $final->{link}) {
            my $link = URI->new($final->{link});
            $doc = $self->get_doc($link);
            $doc = $self->_get_next_page($doc);
            if (!$doc && $self->{end_of_archive_notify} &&
                $final->{description} ne $self->{end_of_archive_message}) {
                $self->_notify_end_of_archive($rss, $now);
            }
        }
    } else {
        $doc = $self->get_doc($self->{first_page}->clone);
    }

    while (--$count >= 0 && $doc) {
        $rss->add_item(
            link        => $doc->source->as_string,
            title       => scalar $self->title($doc),
            description => $self->_stringify($doc, $self->render($doc)),
            pubDate     => DateTime::Format::Mail->format_datetime($time),
        );
        if ($count > 0) {
            $time += $ONE_SECOND;
            $doc = $self->_get_next_page($doc);
            if (!$doc && $self->{end_of_archive_notify}) {
                $self->_notify_end_of_archive($rss, $time);
            }
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
    my ($self, $doc) = @_;
    my ($title) = $doc->findnodes('/html/head/title');
    return defined $title ? $title->as_trimmed_text : $doc->source;
}

sub get_doc {
    my ($self, $uri) = @_;
    my $response = $self->agent->request($self->make_request($uri));
    $response->is_success
        or die "Failed to download $uri: ", $response->as_string, "\n";
    return RSS::ArchiveReader::HtmlDocument->new(
        $uri, $self->decode_response($response)
    );
}

sub make_request {
    my ($self, $uri) = @_;
    return HTTP::Request->new(GET => $uri);
}

sub render {
    my ($self, $doc) = @_;
    defined(my $xpath = $self->{render})
        or die "Don't know how to render pages\n";
    my @elems = $doc->findnodes($xpath);
    return @elems    if wantarray;
    return $elems[0] if @elems;
    return;
}

sub next_page {
    my ($self, $doc) = @_;

    defined(my $xpath = $self->{next_page})
        or die "Don't know how to advance to next page\n";

    my ($href) = $doc->findnodes($xpath) or return;

    defined Scalar::Util::blessed($href)
        && $href->isa('HTML::TreeBuilder::XPath::Attribute')
            or die "next_page parameter did not return an attribute node\n";

    return $href->getValue;

}

sub filter {
    my ($self, $doc) = @_;
    my $filter = $self->{filter};
    return !defined $filter || $doc->findnodes($filter)->size > 0;
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
    my ($self, $doc, @chunk) = @_;
    return join "", map {
        defined Scalar::Util::blessed($_) && $_->isa('HTML::Element')
            ? ($self->{autoresolve} ? $self->_resolve_element($_, $doc) : $_)
                  ->as_HTML("", undef, { })
            : $_
    } @chunk;
}

sub _resolve_element {
    my ($self, $elem, $doc) = @_;
    my $clone = $elem->clone;
    while (my ($attr, $tags) = each %AUTORESOLVE) {
        for my $e ($clone->find_by_tag_name(@$tags)) {
            defined(my $attrval = $e->attr($attr)) or next;
            $e->attr($attr, $doc->resolve($attrval));
        }
    }
    return $clone;
}

sub _notify_end_of_archive {
    my ($self, $rss, $time) = @_;
    $rss->add_item(
        title       => $self->{end_of_archive_message},
        description => $self->{end_of_archive_message},
        pubDate     => $time,
    );
}

sub _get_next_page {
    my ($self, $doc) = @_;
    do {
        my $href = $self->next_page($doc);
        $doc = defined $href && $self->get_doc($doc->resolve($href));
    } while ($doc && !$self->filter($doc));
    return $doc || ();
}

sub cache_file {
    my ($self, $doc, $href, $mode) = @_;
    defined $self->{cache_dir}
        or die "Cannot cache file; cache directory is undefined\n";

    my ($suffix) = $href =~ m|(\.[^/]+)\z|;

    require File::Temp;

    my $copy = File::Temp->new(
        DIR    => $self->{cache_dir},
        UNLINK => 0,
        defined $suffix ? (SUFFIX => $suffix) : (),
    );

    my $request = $self->make_request($doc->resolve($href));
    $request->header(Referer => $doc->source);
    my $response = $self->agent->request($request, $copy->filename);

    $response->is_success or return;
    defined $mode or $mode = $self->{cache_mode};
    chmod $mode, $copy if defined $mode;

    return $copy;

}

sub cache_image {
    my ($self, $doc, $img, $mode) = @_;
    defined $self->{cache_url} or die "Cannot cache image: cache URL is undefined\n";

    require File::Basename;

    my ($src, $width, $height, $alt, $title) =
        map $img->attr($_), qw(src width height alt title);

    my $copy = $self->cache_file($doc, $src, $mode) or return;

    if (!defined $width || !defined $height) {
        eval {
            require Image::Size;
            my ($w, $h) = Image::Size::imgsize($copy);
            defined $width  or $width  = $w;
            defined $height or $height = $h;
        };
    }

    return $self->new_element('img', {
        src => $self->{cache_url} . '/' . File::Basename::fileparse($copy),
        defined $width  ? (width  => $width)  : (),
        defined $height ? (height => $height) : (),
        defined $alt    ? (alt    => $alt)    : (),
        defined $title  ? (title  => $title)  : (),
    });

}

sub find {
    my ($self, $context, $path, @classes) = @_;
    return RSS::ArchiveReader::HtmlDocument::_find_all($context, $path, @classes)
}

sub remove {
    my ($self, $context, $path, @classes) = @_;
    RSS::ArchiveReader::HtmlDocument::_remove($context, $path, @classes);
    return $self;
}

sub truncate {
    my ($self, $context, $path, @classes) = @_;
    RSS::ArchiveReader::HtmlDocument::_truncate($context, $path, @classes);
    return $self;
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

=item agent

This is a user-agent object which will be used to dispatch requests to
the archive referred to by the new object; it should be an instance of
the C<LWP::UserAgent> class.

If this parameter is not present, an C<LPW::UserAgent> object will be
constructed when needed.  This automatically-constructed object can be
configured by the parameters C<agent_config>, C<agent_id>, and
C<cookies>, below.

=item agent_config

If defined, this parameter should be a hash of parameters that will be
passed to the C<LWP::UserAgent> constructor when such an object is
created.  It is ignored if the C<agent> parameter is present.

The default value is C<undef>.

If the only parameter to be set is C<agent> (which sets the object's
user-agent), the C<agent_id> parameter provides a slightly more
convenient way to set it.

=item agent_id

This parameter specifies the user-agent that will be passed to the
C<LWP::UserAgent> constructor when such an object is created.  It is
ignored if the C<agent> parameter is present, or if an C<agent> key is
present in the C<agent_config> parameter.

The default value is C<""> (the empty string).  If undefined, no
explicit user-agent will be set, and so the default agent supplied by
the C<LWP::UserAgent> module will be used.

=item cookies

This parameter describes the cookie jar that will be passed to the
C<LWP::UserAgent> constructor when such an object is created.  It is
ignored if the C<agent> parameter is present.

If the parameter is false, no cookie jar will be used by the agent.
This is the default.

If the parameter is true, but not an array reference, the agent will
be constructed with an empty cookie jar.

If the parameter is an array reference, it is taken to be a flat list
of key-value pairs.  Each pair is passed to the C<set_cookie> method
of a new instance of the C<HTTP::Cookies> class as the C<$key> and
C<$value> parameters.  The other cookie parameters required by that
method are generated automatically: C<$version> is C<'1'>, C<$path> is
C<'/'>, and C<$domain> is taken from this object's C<first_page> URL
parameter.

This C<cookies> parameter is meant to be a simple way to presupply
cookies for common use cases.  If cookies are needed which don't
conform to the pattern described above, they can be added in an
overridden C<configure_agent> method (which see).

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

Alternately, the value of this parameter may be an unblessed array
reference.  If so, its first element is interpreted as an XPath
expression which may contain embedded C<%s> sequences, and its
remaining elements are classes which will be expanded into XPath
expressions that match those classes and substituted in place of the
C<%s> sequences in the first element, in order.  See the C<find>
method in the C<RSS::ArchiveReader::HtmlDocument> class for more
details on how this expansion is performed.

=item next_page

The default implementation of the C<next_page> method uses this
parameter as an XPath expression to locate the "next" link on a web
page.  The parameter may also be an unblessed array reference, which
has the same meaning as for the C<render> parameter above.

=item filter

The default implementation of the C<filter> method applies this
parameter as an XPath expression to downloaded archive pages; those
which return a nonempty nodeset are propagated to the output RSS
feed.  The default value is C<undef>, meaning that no filtering is
applied.

The parameter may also be an unblessed array reference, which
has the same meaning as for the C<render> parameter above.

=item autoresolve

A boolean flag.  If true, then the C<src> attributes of any C<img>,
C<iframe>, and C<embed> elements returned by the C<render> method
(either directly, or as descendant elements) are resolved to absolute
URIs if necessary by calling the C<resolve> method of the
C<RSS::ArchiveReader::HtmlDocument> object from which the archive page
originated.

The default value is true.

=item end_of_archive_notify

A boolean flag.  If true, then when the end of an archive is reached
(as indicated by the C<next_page> method returning nothing), a special
"end of archive" message is appended to the output RSS feed.  The
default value is true.

=item end_of_archive_message

This parameter contains the content of the special "end of archive"
message that is created when the end of an archive is reached and the
C<end_of_archive_notify> parameter is true.  The default value is the
string "End of archive has been reached."

=item cache_dir

A directory for cached files.  See the C<cache_file> method for more
information.  The default value is C<undef>.

=item cache_mode

The default mode for cached files.  See the C<cache_file> method for
more information.  The default value is C<0644>.

=item cache_url

A URL for cached images.  See the C<cache_image> method for more
information.  The default value is C<undef>.

=back

It is convenient not to have to write a constructor for every subclass
of C<RSS::ArchiveBuilder>, so most of the parameters described above
can also be supplied by a class method with the same name as the
parameter, but uppercased.  Specifically:

=over 4

=item AGENT_ID

=item AGENT_CONFIG

=item COOKIES

=item FEED_TITLE

=item FEED_LINK

=item FEED_DESCRIPTION

=item RSS_FILE

=item ITEMS_TO_FETCH

=item ITEMS_TO_KEEP

=item FIRST_PAGE

=item RENDER

=item NEXT_PAGE

=item FILTER

=item AUTORESOLVE

=item END_OF_ARCHIVE_NOTIFY

=item END_OF_ARCHIVE_MESSAGE

=item CACHE_DIR

=item CACHE_MODE

=item CACHE_URL

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

=item $reader->configure_agent($agent)

This method is called after an agent object has been created
automatically.  The default implementation does nothing, but a
subclass may override the method to perform additional configuration
of the agent, perhaps beyond what is convenient to do by means of the
C<agent_config> parameter.

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

=item $reader->title($doc)

Returns the title to be given to the RSS item derived from the
C<RSS::ArchiveReader::HtmlDocument> object C<$doc>.  The default
implementation simply returns the document's HTML title, or if that is
undefined for some reason, then the URI from which the document was
downloaded.  May be overridden to provide different logic for titling
items.

=item $reader->get_doc($uri)

A convenience method that fetches the page at C<$uri> and parses the
returned content into an C<RSS::ArchiveReader::HtmlDocument> object,
which is returned.  The page is fetched using C<$reader>'s agent and
the response is decoded by calling C<$reader>'s C<decode_response>
method, so this method may not be suitable for processing pages
outside of the main archive.

=item $reader->render($doc)

Returns a list of values that will be used to create the
C<description> field of the RSS item for the archived
C<RSS::ArchiveReader::HtmlDocument> object C<$doc>.  C<HTML::Element>
objects in the returned list will be mapped into strings by calling
their C<as_HTML> method; after that, all of the return values are
concatenated together into one string, which becomes an RSS item's
C<description>.

The default implementation uses the C<render> parameter (throwing an
exception if it is not defined) as an XPath expression, applying it to
C<$doc>.  The first matching node is returned.

This method may be overridden to provide different logic for rendering
the pages of an archive.

=item $reader->next_page($doc)

Returns the URI of the archive page following the page represented by
the C<RSS::ArchiveReader::HtmlDocument> object C<$doc>.  The returned
URI need not be absolute; it is resolved into an absolute URI if
necessary.  The method may return nothing, which indicates that the
end of the archive has been reached.

The default implementation uses the C<next_page> parameter (throwing
an exception if it is not defined) as an XPath expression, applying it
to C<$doc>.  If no node is matched by the expression, then nothing is
returned.  Otherwise, the first of the matching nodes must be an
instance of the class C<HTML::TreeBuilder::XPath::Attribute> (that is,
it must match an attribute node), or an exception is thrown.  The
attribute's value is returned otherwise.

This method may be overridden to provide different logic for
traversing the pages of an archive.

=item $reader->filter($doc)

This method should return true if the archive page represented by the
C<RSS::ArchiveReader::HtmlDocument> object C<$doc> should be
propagated to the output RSS feed.

The default implementation examines the C<filter> parameter.  If it is
undefined (the default), a true value is returned, meaning that no
filtering is performed.  Otherwise, the parameter's value is applied
to C<$doc> as an XPath expression.  The method returns true if the
expression returns a nonempty nodeset, and false otherwise.

This method may be overridden to provide different logic for filtering
pages from the output RSS feed.

=item $reader->decode_response($response)

This method should return the decoded content of C<$response>, an
C<HTTP::Response> object which was returned by an HTTP GET request to
C<$uri>, the link to one of the items handled by this tree.

The default implementation simply returns
C<$response-E<gt>decoded_content()>, but a subclass may override this
method if special handling is needed.

=item $reader->cache_file($doc, $href, $mode)

Downloads a file which is referenced in an archive page represented by
the C<RSS::ArchiveReader::HtmlDocument> object C<$doc>.  C<$href> is
the URI of the file; it is resolved to an absolute URI by calling
C<$doc-E<gt>resolve($href)>.

The remote file is downloaded into a local file referenced by a new
C<File::Temp> object, which is returned.  The "Referer" HTTP request
header is set to C<$doc-E<gt>source>.  The local file's name is given
the same suffix as the remote file's, if it has one.  The local file
is stored in a directory named by the C<cache_dir> parameter; if that
parameter is undefined, C<cache_file> will raise an exception
immediately.  The local file's mode will be set to C<$mode> if it's
defined, or to the value of the C<cache_mode> parameter if that is
defined; otherwise the file's mode will not be changed from whatever
C<File::Temp> created it as.

=item $reader->cache_image($doc, $img, $mode)

A convenience wrapper around the C<cache_file> method that's
specialized for HTML <img> elements.  The C<$doc> and C<$mode>
parameters have the same meanings as for that method; C<$img> is an
HTML <img> element which should be a descendant of C<$doc>.  The image
file referenced by that element's C<src> attribute is downloaded as
per the C<cache_file> method, but rather than returning the
C<File::Temp> object that references the file, a brand-new <img>
C<HTML::Element> is returned.  The C<src> attribute of this object is
created by appending the a slash and base name of the new file to the
value of the C<cache_url> parameter, which must be defined or an
exception will be raised.  The new element inherits the C<width>,
C<height>, C<alt>, and C<title> attributes of the original element,
except that whichever of the C<width> or C<height> attributes were not
present (if any) are set by examining the file with the C<Image::Size>
module, if it's available.

=item $reader->find($context, $path [, @classes ])

This method is an alternate entry point for the enhanced node-finding
functionality offered by the C<RSS::ArchiveReader::HtmlDocument>
class.  It simply returns C<$context-E<gt>findnodes($path)> after
replacing C<"%s"> escape sequences in C<$path> by an XPath expression
for the classes in C<@classes>.  See C<RSS::ArchiveReader::HtmlDocument> for
more details.

=item $reader->remove($context, $path [, @classes ]);

This method is an alternate entry point for the node-removing
functionality of the C<RSS::ArchiveReader::HtmlDocument> class.  In
short, the nodes returned by C<$reader-E<gt>find($context, $path,
@classes)> are removed from the document to which they belong.

=item $reader->truncate($context, $path [, @classes ]);

This method is an alternate entry point for the node-truncating
functionality of the C<RSS::ArchiveReader::HtmlDocument> class.  In
short, the nodes returned by C<$reader-E<gt>find($context, $path,
@classes)>, along with the following sibling elements of each, are
removed from the document to which they belong.

=item $reader->new_element(...)

This method is a convenience wrapper for the C<new_from_lol>
constructor of the C<HTML::Element> class.  The arguments to this
method are wrapped in an array reference, which is passed to
C<new_from_lol>.  Example:

    my $elem = $self->new_element(
        'p', 'This is ', [ 'i', 'italicized' ], ' text'
    );

=back
