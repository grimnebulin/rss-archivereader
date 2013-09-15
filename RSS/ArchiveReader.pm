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
        } qw(agent_id rss_file items_to_fetch items_to_keep next_page
             feed_title feed_link feed_description)
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
    return 10;
}

sub FIRST_PAGE {
    return undef;
}

sub NEXT_PAGE {
    return undef;
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
        my $link = $items->[-1]{link};
        my $tree = $self->_get_tree($link);
        my $next = $self->next_page($tree);
        $uri = $next && URI->new_abs($next, $link);
    } else {
        $uri = $self->{first_page};
    }

    while (--$count >= 0 && $uri) {
        my $tree = $self->_get_tree($uri);
        $rss->add_item(
            link        => $uri,
            title       => scalar $self->title($tree, $uri),
            description => _render($self->render($tree)),
            pubDate     => DateTime::Format::Mail->format_datetime($time),
        );
        $time += $ONE_SECOND;
        my $next_uri = $self->next_page($tree);
        $uri = $next_uri && URI->new_abs($next_uri, $uri);
    }

    splice @$items, 0, -$self->{items_to_keep} if @$items > $self->{items_to_keep};

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

sub channel {
    my $self = shift;
    return (
        title       => scalar $self->feed_title,
        link        => scalar $self->feed_link,
        description => scalar $self->feed_description,
    );
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
    my ($title) = $tree->findnodes('//title');
    return $title ? $title->as_trimmed_text : $uri;
}

sub next_page {
    my ($self, $tree) = @_;

    defined(my $xpath = $self->{next_page})
        or die "Don't know how to advance to next page\n";

    my ($href) = $tree->findnodes($xpath) or return;

    if (Scalar::Util::blessed($href)) {
        if ($href->isa('HTML::TreeBuilder::XPath::Attribute')) {
            return $href->getValue;
        } elsif ($href->isa('HTML::Element')) {
            return $href->as_trimmed_text;
        }
    }

    return "$href";

}

sub render {
    shift->_undefined('render');
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

sub _undefined {
    my ($self, $method) = @_;
    die "No $method method defined for class ", ref $self, "\n";
}

sub _get_rss {
    my $self = shift;
    my $rss  = eval { XML::RSS->new->parsefile($self->{rss_file}) };
    return $rss if $rss;
    die $@ if $@ !~ /no such file/i;
    $rss = XML::RSS->new(version => $RSS_VERSION);
    $rss->channel($self->channel);
    return $rss;
}

sub _get_tree {
    my ($self, $uri) = @_;
    my $response = $self->agent->get($uri);
    $response->is_success or die "Failed to download $uri\n";
    return HTML::TreeBuilder::XPath->new_from_content(
        $self->decode_response($response)
    );
}

sub _render {
    return join "", map {
        Scalar::Util::blessed($_) && $_->isa('HTML::Element')
            ? $_->as_HTML("", undef, { })
            : $_
    } @_;
}


1;
