package RSS::ArchiveReader::HtmlDocument;

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

use HTML::TreeBuilder::XPath;
use URI;
use strict;


sub new {
    my ($class, $uri, @chunk) = @_;
    ref $uri or $uri = URI->new($uri);
    defined $uri->scheme or die "URI argument must be absolute\n";
    my $tree = HTML::TreeBuilder::XPath->new(ignore_unknown => 0);
    $tree->parse($_) for @chunk;
    $tree->eof;
    bless { source => $uri->clone, tree => $tree }, $class;
}

sub source {
    return shift->{source}->clone;
}

sub base {
    my $self = shift;
    for my $base ($self->{tree}->findnodes('/html/head/base/@href')) {
        my $uri = URI->new($base->getValue);
        return $uri if defined $uri->scheme;
    }
    return;
}

sub resolve {
    my ($self, $href) = @_;
    my $uri = URI->new($href);
    return $uri if defined $uri->scheme;
    return URI->new_abs($href, $self->base || $self->source);
}

sub find {
    my ($self, $path, @classes) = @_;
    return _find_all($self->{tree}, $path, @classes);
}

sub findnodes {
    return shift->{tree}->findnodes(@_);
}

sub remove {
    my ($self, $path, @classes) = @_;
    _remove($self->{tree}, $path, @classes);
    return $self;
}

sub truncate {
    my ($self, $path, @classes) = @_;
    _truncate($self->{tree}, $path, @classes);
    return $self;
}

sub _format_path {
    my $path = shift;
    my $nwords = my @words = map { /[^\x09\x0a\x0d\x20]+/g } @_;

    my $error = sub {
        die "$_[0] the following XPath expression: $path\n";
    };

    my $miscount = sub {
        $error->(qq(Too $_[0] words ($nwords) provided to format));
    };

    my $nextword = sub {
        @words ? shift @words : $miscount->('few');
    };

    $path =~ s{
        % (?:
            (%) |
            (s) |
            \( ( [^)]* ) ( \) (s)? )?
        )
    }{
        $1  ? '%' :
        $2  ? _has_word('class', $nextword->()) :
        !$4 ? $error->('Unterminated parentheses in') :
        !$5 ? $error->('Missing "s" specifier following parentheses in') :
        _has_word($3, $nextword->())
    }gex;

    @words == 0 or $miscount->('many');

    return $path;

}

sub _has_word {
    my ($name, $word) = @_;
    my $attr = $name =~ /^[-_a-zA-Z]+\z/
        ? "\@$name"
        : sprintf '@*[name()=%s]', _xpath_string($name);
    return sprintf 'contains(concat(" ",normalize-space(%s)," "),%s)',
                   $attr, _xpath_string(" $word ");
}

sub _xpath_string {
    my $str = shift;
    return qq("$str") if $str !~ /"/;
    return qq('$str') if $str !~ /'/;
    return sprintf 'concat(%s)',
                   join ',',
                   map /"/ ? qq('$_') : qq("$_"),
                   grep length > 0,
                   split /("+)/, $str;
}

sub _remove {
    $_->detach for _find_all(@_);
}

sub _truncate {
    for my $node (_find_all(@_)) {
        my $parent = $node->parent;
        $parent->splice_content($node->pindex) if $parent;
    }
}

sub _find_all {
    my ($context, $path, @classes) = @_;
    return $context->findnodes(_format_path($path, @classes));
}


1;

__END__

=head1 NAME

RSS::ArchiveReader::HtmlDocument - represents a downloaded HTML page

=head1 SYNOPSIS

    my $uri  = URI->new('http://my_host.com/');
    my $text = LWP::Simple::get($uri);
    my $doc  = RSS::ArchiveReader::HtmlDocument->new($uri, $text);

    print $doc->source;  # returned saved $uri

    print $doc->base;  # URI of <base> element, if any

    print $doc->resolve('relative-url');  # resolves to absolute URI

    # Find nodes using enhanced XPath:
    for my $node ($doc->find('//div[%s]', 'entry')) {
        # ...
    }

    # delete all matching nodes:
    $doc->remove('//span[%s]', 'ad');

    # delete all matching nodes and their right siblings:
    $doc->truncate('//div[@id="divider"]');

=head1 DESCRIPTION

C<RSS::ArchiveReader::HtmlDocument> objects represent HTML documents
that have been downloaded from a particular URI and parsed into a tree
of nodes.  Objects of this class remember what URI they originated
from, and can resolve relative URIs found within themselves into
absolute URIs in the appropriate way.  That is, given a relative URI,
the C<resolve> method converts it into an absolute URI by taking it as
relative to the document's <base> element, if it exists, or else as
relative to the URI from which the document originated.

=head1 CONSTRUCTOR

=over 4

=item RSS::ArchiveReader::HtmlDocument->new($uri, @chunk)

Creates a new C<RSS::ArchiveReader::HtmlDocument> object.  The strings
in C<@chunk> are processed into a tree of nodes by passing them to a
new instance of the C<HTML::TreeBuilder::XPath> class.  C<$uri> is
cloned and saved for later reference; it must be a C<URI> object
representing an absolute URI.

=back

=head1 METHODS

=over 4

=item $doc->source

Returns a copy of the C<URI> object C<$doc> was created with.

=item $doc->base

Returns a C<URI> object derived from the first <base> element found
within the <head> of the tree of nodes rooted at C<$doc>, if there is
such an element.  If there are multiple such elements in the document
for some reason, the first element whose "href" attribute contains an
absolute URI is the one used.  If no <base> elements qualify, nothing
is returned.

This process is repeated each time the method is called using the
current state of the (mutable) tree, so the results may differ across
calls if <base> elements are added to or removed from the tree.

=item $doc->resolve($uri)

Resolves C<$uri> (either a string or a C<URI> object) into an absolute
URI.  If C<$uri> is absolute to begin with, a copy of it is returned.
Otherwise, it is resolved to an absolute URI by taking it relative to
C<$doc-E<gt>base>, if that is defined, or else relative to
C<$doc-E<gt>source>.  That absolute URI (a new C<URI> object) is
returned.

=item $doc->find($xpath [, @classes ])

This method forwards the given XPath expression to the C<findnodes>
method of the enclosed tree's root node; see the documentation of the
class C<HTML::TreeBuilder::XPath> for details.  The scalar or list
context of the call to this method is propagated to the root node's
C<findnodes> method.

In dealing with HTML, one often wants to select elements with an
attribute (typically "class") which contains a given word.  Doing this
properly requires an inconveniently lengthy XPath test:

    contains(concat(" ",normalize-space(@attribute)," ")," my-word ")

To relieve clients of the job of writing this test over and over,
C<"%(attribute)s"> sequences in the XPath expression are expanded into
tests of this form, where the text between the parentheses replaces
the word "attribute" above.  Each time such a sequence occurs, it
consumes another word from the words in C<@words>, and that word
replaces the string "my-word" above.

The words which are consumed by this substitution are not necessarily
the elements of C<@words> directly, but rather the list of contiguous
sequences of non-whitespace characters from the elements of C<@words>,
in order.

Since it is especially common to want to examine the HTML "class"
attribute, the sequence C<"%(class)s"> can be shortened to simply
C<"%s">.

For example, the first argument in this call:

    $document->find('//div[%s]/div[%s]', 'header', 'subheader')

...or equivalently:

    $doc->find('//div[%s]/div[%s]', 'header subheader')

...is expanded into the following XPath expression:

    //div[contains(concat(" ",normalize-space(@class)," ")," header ")]/
      div[contains(concat(" ",normalize-space(@class)," ")," subheader ")]

Doubled "%" characters in the path are collapsed into a single such
character.  "%" characters not preceding a "s" or "(" character need
not be doubled.  An error is thrown if the number of provided words
does not match the number of C<"%(...)s"> sequences in the path.

The "whitespace" on which the supplied classes are split is of the
XML/XPath variety, that is, characters with ordinal value 0x09, 0x0a,
0x0d, or 0x20.  The generated XPath string literal containing the
class name is replaced with an equivalent expression if the name
contains any quotation marks, even though one would be extremely
unlikely to need such a thing.

=item $doc->findnodes($xpath)

This method call is simply forwarded to the enclosed
C<HTML::TreeBuilder::XPath> object.

=item $doc->remove($xpath [, @classes ])

Removes all elements matching C<$xpath> and C<@classes>, using the
same element-finding functionality as the C<find> method, above.
Returns C<$doc>.

=item $doc->truncate($xpath [, @classes ])

Removes all elements matching C<$xpath> and C<@classes>, using the
same element-finding functionality as the C<find> method, above.  The
following sibling elements of each matching element are removed as
well.  Returns C<$doc>.

=back
