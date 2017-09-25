use strict;
use warnings;
use utf8;

use Test::More;
use Template::Pug;

my $tp = Template::Pug->new;
my $template = <<'EOF';
body
  div
  	p Template with tabs and spaces
EOF
eval { $tp->render($template) };
like $@, qr/Invalid indentation.+tabs or spaces/, 'tabs and spaces in indentation';

$tp = Template::Pug->new;
$template = <<'EOF';
body
  div
 p Template with inconsistent indentation
EOF
eval { $tp->render($template) };
like $@, qr/Inconsistent indentation.+0 or 2/, 'inconsistent indentation';

$tp = Template::Pug->new;
$template = <<'EOF';
div
  p Template with unknown symbol
  % like this
EOF
eval { $tp->render($template) };
like $@, qr/:3.+Unexpected text/s, 'unexpexted text';

$tp = Template::Pug->new;
$template = <<'EOF';
img
  p Self closing tag with some content
EOF
eval { $tp->render($template) };
like $@, qr/img.*self closing.*content/, 'self closing tag with content';

SKIP: {
	skip 'some stderr odd behavior', 1;
	$tp = Template::Pug->new;
	$template = <<'EOF';
p foo
EOF
	eval { $tp->render($template, { 'inv idt' => 1 }) };
	like $@, qr/Bareword found where operator expected/, 'Invalid variable identifier';
}

done_testing();