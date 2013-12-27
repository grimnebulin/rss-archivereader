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

use URI;
use parent qw(HTML::TreeBuilder::XPath);
use strict;


sub new {
    my ($class, $uri, @chunk) = @_;
    defined $uri->scheme or die "URI argument must be absolute\n";
    my $self = $class->SUPER::new(ignore_unknown => 0);
    $self->parse($_) for @chunk;
    $self->eof;
    $self->{__source} = $uri->clone;
    return $self;
}

sub source {
    return shift->{__source}->clone;
}

sub base {
    my $self = shift;
    for my $base ($self->findnodes('/html/head/base/@href')) {
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

=head1 DESCRIPTION

C<RSS::ArchiveReader::HtmlDocument> objects represent HTML documents
that have been downloaded from a particular URI and parsed into a tree
of nodes.  The class is a subclass of C<HTML::TreeBuilder::XPath>,
from which it inherits its document-parsing and node-finding
functionality.  Additionally, objects of this class remember what URI
they originated from, and can resolve relative URIs found within
themselves into absolute URIs in the appropriate way.  That is, given
a relative URI, the C<resolve> method converts it into an absolute URI
by taking it as relative to the document's <base> element, if it
exists, or else as relative to the URI from which the document
originated.

=head1 CONSTRUCTOR

=over 4

=item RSS::ArchiveReader::HtmlDocument->new($uri, @chunk)

Creates a new C<RSS::ArchiveReader::HtmlDocument> object.  The strings
in C<@chunk> are processed by repeated calls to the
C<HTML::TreeBuilder::XPath> superclass's C<parse> method.  C<$uri> is
cloned and saved for later reference; it must be a C<URI> object.

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

=back
