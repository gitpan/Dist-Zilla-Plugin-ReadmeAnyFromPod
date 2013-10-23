use strict;
use warnings;

package Dist::Zilla::Plugin::ReadmeAnyFromPod;
{
  $Dist::Zilla::Plugin::ReadmeAnyFromPod::VERSION = '0.132962'; # TRIAL
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

# This cannot be the FileGatherer role, because it needs to be called
# after file munging to get the fully-munged POD.
with 'Dist::Zilla::Role::InstallTool' => { -version => 5 };
with 'Dist::Zilla::Role::FilePruner' => { -version => 5 };

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

            require Pod::Simple::Text;
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

            require Pod::Simple::HTML;
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


sub prune_files {
    my ($self) = @_;
    if ($self->location eq 'root') {
        for my $file ($self->zilla->files->flatten) {
            next unless $file->name eq $self->filename;
            $self->log_debug([ 'pruning %s', $file->name ]);
            $self->zilla->prune_file($file);
        }
    }
    return;
}


sub setup_installer {
    my ($self) = @_;

    my $content = $self->get_readme_content();

    my $filename = $self->filename;

    if ( $self->location eq 'build' ) {
        require Dist::Zilla::File::InMemory;
        my $file = $self->zilla->files->grep( sub { $_->name eq $filename } )->head;
        if ( $file ) {
            $self->log("Override $filename in build");
            $self->zilla->prune_file($file);
        }
        my $newfile = Dist::Zilla::File::InMemory->new({
            name    => $filename,
            content => $content,
            encoding => $self->_get_source_encoding(),
        });
        $self->add_file($newfile);
    }
    elsif ( $self->location eq 'root' ) {
        my $file = $self->zilla->root->file($filename);
        if (-e $file) {
            $self->log("Override $filename in root");
        }
        my $encoded_content = encode($self->_get_source_encoding(),
                                     $content);
        File::Slurp::write_file("$file", {binmode => ':raw'}, $encoded_content);
    }
    else {
        die "Unknown location specified: ". $self->location;
    }
    return;
}

sub _file_from_filename {
    my ($self, $filename) = @_;
    for my $file ($self->zilla->files->flatten) {
        return $file if $file->name eq $filename;
    }
    return;               # let moose throw exception if nothing found
}

sub _source_file {
    my ($self) = shift;
    $self->_file_from_filename($self->source_filename);
}

sub _get_source_content {
    my ($self) = shift;
    $self->_source_file->content;
}

sub _get_source_pod {
    my ($self) = shift;
    my $mmcontent = $self->_get_source_content();

    my $doc = PPI::Document->new(\$mmcontent);
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
    $self->_source_file->encoding;
}


sub get_readme_content {
    my ($self) = shift;
    my $mmpod = $self->_get_source_pod();
    my $parser = $_types->{$self->type}->{parser};
    my $readme_content = $parser->($mmpod);
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

version 0.132962

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

=head2 prune_files

Files with C<location = root> must also be pruned, so that they don't
sneak into the I<next> build by virtue of already existing in the root
dir.

=head2 setup_installer

Adds the requested README file to the dist.

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
