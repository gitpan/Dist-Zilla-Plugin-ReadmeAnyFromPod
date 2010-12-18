
use strict;
use warnings;

BEGIN { require 5.006; }

use ExtUtils::MakeMaker 6.31;



my %WriteMakefileArgs = (
  'ABSTRACT' => 'Automatically convert POD to a README for Dist::Zilla',
  'AUTHOR' => 'Ryan C. Thompson <rct@thompsonclan.org>',
  'BUILD_REQUIRES' => {
    'Carp' => '0',
    'English' => '0',
    'File::Find' => '0',
    'File::Temp' => '0',
    'Scalar::Util' => '0',
    'Test::More' => '0.94',
    'perl' => '5.004'
  },
  'CONFIGURE_REQUIRES' => {
    'ExtUtils::MakeMaker' => '6.31'
  },
  'DISTNAME' => 'Dist-Zilla-Plugin-ReadmeAnyFromPod',
  'EXE_FILES' => [],
  'LICENSE' => 'perl',
  'NAME' => 'Dist::Zilla::Plugin::ReadmeAnyFromPod',
  'PREREQ_PM' => {
    'Dist::Zilla::File::InMemory' => '0',
    'Dist::Zilla::Role::InstallTool' => '0',
    'Encode' => '0',
    'File::Slurp' => '0',
    'IO::Handle' => '0',
    'IO::Scalar' => '0',
    'Moose' => '0',
    'Moose::Autobox' => '0',
    'Moose::Util::TypeConstraints' => '0',
    'MooseX::Has::Sugar' => '0',
    'Pod::Markdown' => '0',
    'Pod::Select' => '0',
    'Pod::Simple::HTML' => '0',
    'Pod::Text' => '0'
  },
  'VERSION' => '0.103520',
  'test' => {
    'TESTS' => 't/*.t'
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



