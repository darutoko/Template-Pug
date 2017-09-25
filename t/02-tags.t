use strict;
use warnings;
use utf8;

use Test::More;
use Template::Pug;

my $tp     = Template::Pug->new;
my $output = $tp->render('');
is $output, '', 'empty template';

$tp     = Template::Pug->new;
$output = $tp->render('div');
is $output, '<div></div>', 'sipmle tag';

$tp     = Template::Pug->new;
$output = $tp->render('img');
is $output, '<img/>', 'sipmle self closing tag';

$tp     = Template::Pug->new;
$output = $tp->render('foo/');
is $output, '<foo/>', 'forced self closing tag';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
ul
  li
  li
  li
EOF
is $output, '<ul><li></li><li></li><li></li></ul>', 'nested tags';

$tp     = Template::Pug->new;
$output = $tp->render('a: img');
is $output, '<a><img/></a>', 'nested inline tag';

done_testing();