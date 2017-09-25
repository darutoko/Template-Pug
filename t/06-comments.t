use strict;
use warnings;
use utf8;

use Test::More;
use Template::Pug;

my $tp     = Template::Pug->new;
my $output = $tp->render(<<'EOF', {pretty => 1});
// some comments
div.main foo bar
EOF
is $output, '
<!-- some comments -->
<div class="main">foo bar</div>', 'simple comment';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', {pretty => 1});
//- comment not shown in markup
p foo
p bar
EOF
is $output, '
<p>foo</p>
<p>bar</p>', 'comment that is not shown in markup';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', {pretty => 1});
body
  // big
    multiline
    comment
  p foo
p bar
EOF
is $output, '
<body>
  <!-- big
  multiline
  comment -->
  <p>foo</p>
</body>
<p>bar</p>', 'multiline comment';

done_testing();
