#!perl
use Test::Most;

use strict;
use warnings FATAL => 'all';

use utf8;
binmode STDOUT, ':utf8';

use autodie;
use Test::DZil;
use Path::Tiny;

use Dist::Zilla::Plugin::ReadmeAnyFromPod;

my $tzil = Builder->from_config(
    { dist_root => 'corpus/dist/DZT' },
    {
        add_files => {
            'source/dist.ini' => simple_ini(
                'GatherDir',
                [ 'ReadmeAnyFromPod', 'ReadmeTextInBuild' ],
            ),
        },
    }
);

lives_ok { $tzil->build; } "Built dist successfully";

my $build_dir = $tzil->tempdir->subdir('build');
my $file = path($build_dir, 'README');
ok( -e $file, 'README created in build');

my $content = $file->slurp_utf8;
like($content, qr/Dagfinn Ilmari Mannsåker/m,
     'file was written with correct encoding');

done_testing();
