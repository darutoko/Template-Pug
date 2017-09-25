use strict;
use warnings;
use utf8;

use Test::More;
use Template::Pug;

my $tp     = Template::Pug->new;
my $output = $tp->render('p= \'This is <escaped> expression\'');
is $output, '<p>This is &lt;escaped&gt; expression</p>', 'escaped expression';

$tp     = Template::Pug->new;
$output = $tp->render('p!= \'This is <unescaped> expression\'');
is $output, '<p>This is <unescaped> expression</p>', 'unescaped expression';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', {pretty => 1});
ul
  - for(my $i = 0; $i < 3; $i++)
    li item
EOF
is $output, '
<ul>
  <li>item</li>
  <li>item</li>
  <li>item</li>
</ul>', 'simple code';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', {pretty => 1});
ul
  -
    my @list = qw/one
      			  two
      			  three/;
  - for(@list)
    li= $_
EOF
is $output, '
<ul>
  <li>one</li>
  <li>two</li>
  <li>three</li>
</ul>', 'multiline code block';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', { foo => 1, bar => 2 });
p= $foo . $bar
EOF
is $output, '<p>12</p>', 'variables';

$tp     = Template::Pug->new(append => 'sub foo { "appended" }');
$output = $tp->render('p= foo()');
is $output, '<p>appended</p>', 'append';

$tp     = Template::Pug->new(prepend => 'my $p = "prepended";');
$output = $tp->render('p= $p');
is $output, '<p>prepended</p>', 'prepend';

done_testing();