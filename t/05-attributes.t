use strict;
use warnings;
use utf8;

use Test::More;
use Template::Pug;

my $tp     = Template::Pug->new;
my $output = $tp->render(<<'EOF');
a(class="button" href="google.com") Google
div(class="foo" (bar)="baz()")
EOF
is $output, '<a class="button" href="google.com">Google</a><div (bar)="baz()" class="foo"></div>', 'Simple attributes';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', {pretty => 1});
input(foo bar='baz')
input(foo="foo" bar='baz')
input(foo=undef bar='baz')
EOF
is $output, '
<input bar="baz" foo="foo"/>
<input bar="baz" foo="foo"/>
<input bar="baz"/>', 'Boolean attribute';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
- my $authenticated = 1;
body(class=$authenticated ? 'authed' : 'anon')
EOF
is $output, '<body class="authed"></body>', 'Simple expression in rvalue';

$tp     = Template::Pug->new;
$output = $tp->render('foo(bar="baz")/');
is $output, '<foo bar="baz"/>', 'Self closing tag with an attribute';

$tp     = Template::Pug->new;
$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
div(escaped="<code>")
div(unescaped!="<code>")
EOF
is $output, '<div escaped="&lt;code&gt;"></div><div unescaped="<code>"></div>', 'Escaped and unescaped attributes';

$tp     = Template::Pug->new;
$output = $tp->render(q/a(style={color => 'red', background => 'green'})/);
is $output, '<a style="background:green;color:red"></a>', 'Style attribute';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
- my $classes = ['foo', 'bar', 'baz'];
a.bang(
  class=$classes
  class=['bing']
)
EOF
is $output, '<a class="bang foo bar baz bing"></a>', 'Class attribute';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
- my $currentUrl = '/about';
a(href='/' class={active => $currentUrl eq '/'}) Home
a(href='/about' class={active => $currentUrl eq '/about'}) About
EOF
is $output, '<a href="/">Home</a><a class="active" href="/about">About</a>', 'Conditional class attribute';

$tp     = Template::Pug->new;
$output = $tp->render('a#main-link');
is $output, '<a id="main-link"></a>', 'Id attribute';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
.content
  #panel
EOF
is $output, '<div class="content"><div id="panel"></div></div>', 'Attribute with no tag specified';

$tp     = Template::Pug->new;
$output = $tp->render('div#foo(data-bar="foo")&attributes({"data-foo" => "bar"})');
is $output, '<div data-bar="foo" data-foo="bar" id="foo"></div>', 'And attributes block';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF');
- my $attributes = {};
- $attributes->{id} = undef;
- $attributes->{class} = 'baz';
div#foo(data-bar="foo")&attributes($attributes)
EOF
is $output, '<div class="baz" data-bar="foo"></div>', 'And attributes block in the variable';

done_testing();
