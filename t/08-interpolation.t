use strict;
use warnings;
use utf8;

use Test::More;
use Template::Pug;

my $tp     = Template::Pug->new;
my $output = $tp->render(<<'EOF', { foo => '<foo>', bar => '<bar>' });
p text #{1+1} text #{$foo} text !{$bar}
EOF
is $output, '<p>text 2 text &lt;foo&gt; text <bar></p>', 'expression';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
p text \#{foo} text #\{bar} text
EOF
is $output, '<p>text #{foo} text #\{bar} text</p>', 'escaped expression tag';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
p foo #{'}'} bar
EOF
is $output, '<p>foo } bar</p>', 'expression with barcket inside';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
p text #[em foo] text #[em(foo='bar') bar baz]
EOF
is $output, '<p>text <em>foo</em> text <em foo="bar">bar baz</em></p>', 'tag';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
p text #[em foo] text #{'foo'} text #[em bar] text \#{'bar'} text #[em baz] text #{'baz'}
EOF
is $output, '<p>text <em>foo</em> text foo text <em>bar</em> text #{\'bar\'} text <em>baz</em> text baz</p>', 'mix of tag and expression';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
p text #{'#[foo]'} text #[q #{'bar'}] text
EOF
is $output, '<p>text #[foo] text <q>bar</q> text</p>', 'expression inside tag and vice versa';

done_testing();