use strict;
use warnings;

package Dist::Zilla::Plugin::ReadmeAnyFromPod;
{
  $Dist::Zilla::Plugin::ReadmeAnyFromPod::VERSION = '0.133060'; # TRIAL
}
# ABSTRACT: Automatically convert POD to a README in any format for Dist::Zilla

use Encode qw( encode );
use IO::Handle;
use List::Util qw( reduce );
use Moose::Autobox;
use Moose::Util::TypeConstraints qw(enum);
use Moose;
use MooseX::Has::Sugar;
use PPI::Document;
use PPI::Token::Pod;
use Pod::Simple::HTML 3.23;
use Pod::Simple::Text 3.23;
use Scalar::Util 'blessed';

with 'Dist::Zilla::Role::AfterBuild';
with 'Dist::Zilla::Role::FileGatherer';
with 'Dist::Zilla::Role::FileMunger';
with 'Dist::Zilla::Role::FilePruner';

# TODO: Should these be separate modules?
our $_types = {
    pod => {
        filename => 'README.pod',
        parser => sub {
            return $_[0];
        },
    },
    text => {
        filename => 'README',
        parser => sub {
            my $pod = $_[0];

            my $parser = Pod::Simple::Text->new;
            $parser->output_string( \my $content );
            $parser->parse_characters(1);
            $parser->parse_string_document($pod);
            return $content;
        },
    },
    markdown => {
        filename => 'README.mkdn',
        parser => sub {
            my $pod = $_[0];

            require Pod::Markdown;
            my $parser = Pod::Markdown->new();

            require IO::Scalar;
            my $input_handle = IO::Scalar->new(\$pod);

            $parser->parse_from_filehandle($input_handle);
            my $content = $parser->as_markdown();
            return $content;
        },
    },
    html => {
        filename => 'README.html',
        parser => sub {
            my $pod = $_[0];

            my $parser = Pod::Simple::HTML->new;
            $parser->output_string( \my $content );
            $parser->parse_characters(1);
            $parser->parse_string_document($pod);
            return $content;
        }
    }
};


has type => (
    ro, lazy,
    isa        => enum([keys %$_types]),
    default    => sub { $_[0]->__from_name()->[0] || 'text' },
);


has filename => (
    ro, lazy,
    isa => 'Str',
    default => sub { $_types->{$_[0]->type}->{filename}; }
);


has source_filename => (
    ro, lazy,
    isa => 'Str',
    default => sub { shift->zilla->main_module->name; },
);


has location => (
    ro, lazy,
    isa => enum([qw(build root)]),
    default => sub { $_[0]->__from_name()->[1] || 'build' },
);


sub gather_files {
    my ($self) = @_;

    my $filename = $self->filename;
    if ( $self->location eq 'build'
         # allow for the file to also exist in the dist
         and not @{$self->zilla->files->grep( sub { $_->name eq $filename })}
       ) {
        require Dist::Zilla::File::InMemory;
        my $file = Dist::Zilla::File::InMemory->new({
            content => 'this will be overwritten',
            name    => $self->filename,
        });

        $self->add_file($file);
    }
    return;
}


sub prune_files {
    my ($self) = @_;

    # leave the file in the dist if another instance of us is adding it there.
    if ($self->location eq 'root'
        and not grep {
            blessed($self) eq blessed($_)
                and $_->location eq 'build'
                and $_->filename eq $self->filename
        } @{$self->zilla->plugins}) {
        for my $file ($self->zilla->files->flatten) {
            next unless $file->name eq $self->filename;
            $self->log_debug([ 'pruning %s', $file->name ]);
            $self->zilla->prune_file($file);
        }
    }
    return;
}


sub munge_files {
    my $self = shift;

    if ( $self->location eq 'build' ) {
        my $filename = $self->filename;
        my $file = $self->zilla->files->grep( sub { $_->name eq $filename } )->head;
        $self->munge_file($file);
    }
    return;
}


sub munge_file {
    my ($self, $file) = @_;

    # Ensure that we repeat the munging if the source file is modified
    # after we run.
    my $source_file = $self->_source_file();
    if (not $source_file->does('Dist::Zilla::Role::File::ChangeNotification'))
    {
        require Dist::Zilla::Role::File::ChangeNotification;
        Dist::Zilla::Role::File::ChangeNotification->meta->apply($source_file);
        my $plugin = $self;
        $source_file->on_changed(sub {
            my ($self, $newcontent) = @_;

            # If the new content is actually different, recalculate
            # the content based on the updates.
            if ($newcontent ne $plugin->_last_source_content)
            {
                $plugin->log('someone tried to munge ' . $source_file->name . ' after we read from it. Making modifications again...');
                $plugin->munge_file($file);
            }
        });

        $source_file->watch_file;
    }

    $self->log_debug([ 'ReadmeAnyFromPod updating contents of %s in dist', $file->name ]);
    $file->content($self->get_readme_content);
    return;
}


sub after_build {
    my $self = shift;

    if ( $self->location eq 'root' ) {
        my $filename = $self->filename;
        $self->log_debug([ 'ReadmeAnyFromPod updating contents of %s in root', $filename ]);

        my $content = $self->get_readme_content();

        require Path::Tiny;
        my $file = $self->zilla->root->file($filename);
        if (-e $file) {
            $self->log("overriding $filename in root");
        }
        my $encoding = $self->_get_source_encoding();
        Path::Tiny::path($file)->spew_raw(
            $encoding eq 'raw'
                ? $content
                : encode($encoding, $content)
        );
    }

    return;
}

sub _file_from_filename {
    my ($self, $filename) = @_;
    for my $file ($self->zilla->files->flatten) {
        return $file if $file->name eq $filename;
    }
    die 'no README found (place [ReadmeAnyFromPod] below [Readme] in dist.ini)!';
}

sub _source_file {
    my ($self) = shift;
    $self->_file_from_filename($self->source_filename);
}

# Holds the contents of the source file as of the last time we
# generated a readme from it. We use this to detect when the source
# file is modified so we can update the README file again.
has _last_source_content => (
    is => 'rw', isa => 'Str',
    default => '',
);

sub _get_source_content {
    my ($self) = shift;
    $self->_last_source_content($self->_source_file->content);
}

sub _get_source_pod {
    my ($self) = shift;
    my $source_content = $self->_get_source_content();

    my $doc = PPI::Document->new(\$source_content);
    my $pod_elems = $doc->find('PPI::Token::Pod');
    my $pod_content = "";
    if ($pod_elems) {
        # Concatenation should stringify it
        $pod_content .= PPI::Token::Pod->merge(@$pod_elems);
    }

    return $pod_content;
}

sub _get_source_encoding {
    my ($self) = shift;
    return
        $self->_source_file->can('encoding')
            ? $self->_source_file->encoding
            : 'raw';        # Dist::Zilla pre-5.0
}


sub get_readme_content {
    my ($self) = shift;
    my $source_pod = $self->_get_source_pod();
    my $parser = $_types->{$self->type}->{parser};
    # Save the POD text used to generate the README.
    return $parser->($source_pod);
}

{
    my %cache;
    sub __from_name {
        my ($self) = @_;
        my $name = $self->plugin_name;

        # Use cached values if available
        if ($cache{$name}) {
            return $cache{$name};
        }

        # qr{TYPE1|TYPE2|...}
        my $type_regex = join('|', map {quotemeta} keys %$_types);
        # qr{LOC1|LOC2|...}
        my $location_regex = join('|', map {quotemeta} qw(build root));
        # qr{(?:Readme)? (TYPE1|TYPE2|...) (?:In)? (LOC1|LOC2|...) }x
        my $complete_regex = qr{ (?:Readme)? ($type_regex) (?:(?:In)? ($location_regex))? }ix;
        my ($type, $location) = (lc $name) =~ m{(?:\A|/) \s* $complete_regex \s* \Z}ix;
        $cache{$name} = [$type, $location];
        return $cache{$name};
    }
}

__PACKAGE__->meta->make_immutable;

__END__

=pod

=head1 NAME

Dist::Zilla::Plugin::ReadmeAnyFromPod - Automatically convert POD to a README in any format for Dist::Zilla

=head1 VERSION

version 0.133060

=head1 SYNOPSIS

In your F<dist.ini>

    [ReadmeAnyFromPod]
    ; Default is plaintext README in build dir

    ; Using non-default options: POD format with custom filename in
    ; dist root, outside of build. Including this README in version
    ; control makes Github happy.
    [ReadmeAnyFromPod / ReadmePodInRoot]
    type = pod
    filename = README.pod
    location = root

    ; Using plugin name autodetection: Produces README.html in root
    [ ReadmeAnyFromPod / HtmlInRoot ]

=head1 DESCRIPTION

Generates a README for your L<Dist::Zilla> powered dist from its
C<main_module> in any of several formats. The generated README can be
included in the build or created in the root of your dist for e.g.
inclusion into version control.

=head2 PLUGIN NAME AUTODETECTION

If you give the plugin an appropriate name (a string after the slash)
in your dist.ini, it will can parse the C<type> and C<location>
attributes from it. The format is "Readme[TYPE]In[LOCATION]". The
words "Readme" and "In" are optional, and the whole name is
case-insensitive. The SYNOPSIS section above gives one example.

When run with C<location = dist>, this plugin runs in the C<FileMunger> phase
to create the new file. If it runs before another C<FileMunger> plugin does,
that happens to modify the input pod (like, say,
L<C<[PodWeaver]>|Dist::Zilla::Plugin::PodWeaver>), the README file contents
will be recalculated, along with a warning that you should modify your
F<dist.ini> by referencing C<[ReadmeAnyFromPod]> lower down in the file (the
build still works, but is less efficient).

=head1 ATTRIBUTES

=head2 type

The file format for the readme. Supported types are "text", "markdown", "pod", and "html".

=head2 filename

The file name of the README file to produce. The default depends on the selected format.

=head2 source_filename

The file from which to extract POD for the content of the README.
The default is the file of the main module of the dist.

=head2 location

Where to put the generated README file. Choices are:

=over 4

=item build

This puts the README in the directory where the dist is currently
being built, where it will be incorporated into the dist.

=item root

This puts the README in the root directory (the same directory that
contains F<dist.ini>). The README will not be incorporated into the
built dist.

=back

=head1 METHODS

=head2 gather_files

We create the file early, so other plugins that need to have the full list of
files are aware of what we will be generating.

=head2 prune_files

Files with C<location = root> must also be pruned, so that they don't
sneak into the I<next> build by virtue of already existing in the root
dir.  (The alternative is that the user doesn't add them to the build in the
first place, with an option to their C<GatherDir> plugin.)

=head2 munge_files

=head2 munge_file

Edits the content into the requested README file in the dist.

=head2 after_build

Create the requested README file in the root.

=head2 get_readme_content

Get the content of the README in the desired format.

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
C<rct+perlbug@thompsonclan.org>.

=head1 SEE ALSO

=over 4

=item *

L<Dist::Zilla::Plugin::ReadmeFromPod> - The base for this module

=item *

L<Dist::Zilla::Plugin::ReadmeMarkdownFromPod> - Functionality subsumed by this module

=item *

L<Dist::Zilla::Plugin::CopyReadmeFromBuild> - Functionality partly subsumed by this module

=back

=head1 INSTALLATION

See perlmodinstall for information and options on installing Perl modules.

=head1 AUTHOR

Ryan C. Thompson <rct@thompsonclan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Ryan C. Thompson.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT
WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER
PARTIES PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND,
EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE
SOFTWARE IS WITH YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME
THE COST OF ALL NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE LIABLE
TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE
SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
DAMAGES.

=cut
