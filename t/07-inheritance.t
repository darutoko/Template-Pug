use strict;
use warnings;
use utf8;

use FindBin;
use Test::More;
use Template::Pug;

my $templates = "$FindBin::Bin/templates/";
my $tp     = Template::Pug->new;
my $output = $tp->render_file($templates .'t1.pug', {basedir => $templates, pretty => 1});
is $output, '
<p>extends</p>
<p>foo</p>
<p>extends-include</p>
<p>extends-include-include</p>', 'path resolve';

$tp     = Template::Pug->new;
$output = $tp->render_file($templates .'t2.pug', {pretty => 1});
is $output, '
<p>head</p>
<p>content</p>
<p>foot</p>', 'simple block';

$tp     = Template::Pug->new;
$output = $tp->render_file($templates .'t3.pug', {pretty => 1});
is $output, '
<p>head</p>
<p>content</p>
<p>foot</p>', 'simple include';

$tp     = Template::Pug->new;
$output = $tp->render_file($templates .'t4.pug', {pretty => 1});
is $output, '
<div>top</div>
<div>
  Hello world!
  foo
  bar
</div>
<div>extends-extends app</div>
<div>template app</div>
<div>middle_</div>
<div>extends-include</div>
<div>template a</div>
Hello world!
foo
bar
<div>extends b</div>
<div>template b</div>
<div>include</div>
<div>_middle</div>
<div>extends prep</div>
<div>extends-extends prep</div>
<div>template prep</div>
<div>bottom</div>', 'complex inheritance';

# $tp     = Template::Pug->new;
# $output = $tp->render_file($templates .'.pug', {pretty => 1});
# is $output, '
# ', 'simple include';

done_testing();
