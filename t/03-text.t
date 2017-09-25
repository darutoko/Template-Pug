use strict;
use warnings;
use utf8;

use Test::More;
use Template::Pug;

my $tp     = Template::Pug->new;
my $output = $tp->render('p Inline text with <strong>html</strong>');
is $output, '<p>Inline text with <strong>html</strong></p>', 'inline text with html tag';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', {pretty => 1});
| Piped text with <strong>html</strong>
p
	| Piped text inside tag
EOF
is $output, '
Piped text with <strong>html</strong>
<p>
  Piped text inside tag
</p>', 'piped text';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', {pretty => 1});
<!--[if IE 8]>
<html lang="en" class="lt-ie9">
<![endif]-->
<!--[if gt IE 8]><!-->
<html lang="en">
<!--<![endif]-->
EOF
is $output, '
<!--[if IE 8]>
<html lang="en" class="lt-ie9">
<![endif]-->
<!--[if gt IE 8]><!-->
<html lang="en">
<!--<![endif]-->', 'standard HTML tags';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', {pretty => 1});
script.
  if (myVar)
    console.log('It is true')
  else
    console.log('It is false')
EOF
is $output, '
<script>
  if (myVar)
    console.log(\'It is true\')
  else
    console.log(\'It is false\')
</script>', 'text block in a tag';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', {pretty => 1});
script.

		// some comment
	some deep
			indent with tabs

			after
		empty
	line
EOF
is $output, '
<script>
  
  	// some comment
  some deep
  		indent with tabs
  
  		after
  	empty
  line
</script>', 'text block with slash and empty line at start and inside indent';

done_testing();