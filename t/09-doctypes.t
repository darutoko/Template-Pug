use strict;
use warnings;
use utf8;

use Test::More;
use Template::Pug;

my $tp     = Template::Pug->new;
my $output = $tp->render('doctype xml');
is $output, '<?xml version="1.0" encoding="utf-8" ?>', 'doctype in template';

$tp     = Template::Pug->new;
$output = $tp->render('input(foo="bar")', {doctype => 'html'});
is $output, '<input foo="bar">', 'doctype in options';

$tp     = Template::Pug->new;
$output = $tp->render('doctype html', {doctype => 'xml'});
is $output, '<!DOCTYPE html>', 'doctype in template and options';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', {pretty => 1});
doctype html
input(foo)
input(foo='foo')/
EOF
is $output, '<!DOCTYPE html>
<input foo>
<input foo/>', 'terse form';

$tp     = Template::Pug->new;
$output = $tp->render(<<'EOF', {pretty => 1});
doctype xml
input(foo)
input(foo='foo')/
EOF
is $output, '<?xml version="1.0" encoding="utf-8" ?>
<input foo="foo"></input>
<input foo="foo"/>', 'xml form';

done_testing();
