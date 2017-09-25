package Template::Pug;

use 5.012;
use strict;
use warnings;
use utf8;

use Template::Pug::Parser;
use Template::Pug::Compiler;
use Template::Pug::Util;

use Encode 'decode';
use Path::Class;

use Data::Dumper;

# ========= Public methods =========

sub new {
	my $class = shift;
	my $self = bless @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;

	$self->{cached} = {};
	$self->{append} //= '';
	$self->{prepend} //= '';
	$self->{extension} = '.pug';
	$self->{namespace} ||= 'Template::Pug::SandBox';

	return $self;
}

sub cache { return $_[0]{cache} if @_ == 1; $_[0]{cache} = $_[1]; $_[0] };
sub append { return $_[0]{append} if @_ == 1; $_[0]{append} = $_[1]; $_[0] };
sub basedir { return $_[0]{basedir} if @_ == 1; $_[0]{basedir} = $_[1]; $_[0] };
sub prepend { return $_[0]{prepend} if @_ == 1; $_[0]{prepend} = $_[1]; $_[0] };
sub encoding { return $_[0]{encoding} if @_ == 1; $_[0]{encoding} = $_[1]; $_[0] };
sub namespace { return $_[0]{namespace} if @_ == 1; $_[0]{namespace} = $_[1]; $_[0] };

sub render {
	my ($self, $template, $options) = @_;

	$self->_init_options($options);

	return $self->_render($template);
}

sub render_file {
	my ($self, $path, $options) = @_;

	$self->_init_options($options);

	$self->_options->{filename} = $path;
	my $template = $self->_read_template($path);

	return $self->_render($template);
}

# ========= Private methods =========

# Acess methods

sub _cached { $_[0]{cached} };
sub _extension { $_[0]{extension} }
sub _options { $_[0]{options} }

# Main methods

sub _compile {
	my ($self) = @_;

	$self->{code} = Template::Pug::Compiler->new->compile({
		tree => delete $self->{tree},
		pretty => $self->_options->{pretty},
		doctype => $self->_options->{doctype}
	});

	return $self;
}

sub _init_options {
	my ($self, $options) = @_;

	die 'Expected hash reference and got '. ref $options if defined $options && ref $options ne 'HASH';

	$self->{options} = $options || {};

	return $self;
}

sub _parse {
	my ($self, $template) = @_;

	my $t = $self->_parse_template($template, $self->_options->{filename});

	# Parse and fill all includes
	my %cache;
	for my $token (@{ $t->includes }) {
		my $path = $self->_resolve_path($token->{value}, $token->{filename});

		unless(exists $cache{$path}) {
			my $template = $self->_read_template($path);

			# Treat content as a text if it isn't a template
			if($path =~ /\Q@{[$self->_extension]}\E$/) {
				my $i = $self->_parse_template($template, $path);
				$t->includes( $i->includes );
				$cache{$path} = $i->tree;
			} else {
				$cache{$path} = [{type => 'text', value => $template}];
			}

		}

		$token->{children} = $cache{$path};
	}

	$self->{tree} = $t->tree;

	return $self;
}

sub _parse_template {
	my ($self, $template, $filename) = @_;

	my $t = Template::Pug::Parser->new->parse({
		template => $template,
		filename => $filename
	});
	say "Template: ". ($t->filename || 'Pug') ."\nTree: ". Dumper( $t->tree ) if $self->{debug};

	return $t unless $t->extends;

	# Parse parent template, fill blocks and carry on includes from child
	$filename = $self->_resolve_path($t->extends, $self->_options->{filename}); 
	my $e = $self->_parse_template($self->_read_template($filename), $filename);

	for my $name (keys %{ $t->blocks }) {
		my $block = $t->blocks->{$name};

		unless(exists $e->blocks->{$name}) {
			$e->blocks->{$name} = $block;
			next;
		}

		if($block->{mode} eq 'append') {
			push @{ $e->blocks->{$name}{children} }, @{ $block->{children} };
		} elsif($block->{mode} eq 'prepend') {
			unshift @{ $e->blocks->{$name}{children} }, @{ $block->{children} };
		} else {
			$e->blocks->{$name}{children} = $block->{children};
		}
	}

	$e->includes( $t->includes );

	return $e;
}

sub _process {
	my ($self) = @_;

	my @variables = keys %{$self->_options};

	my $code = 'package '. $self->namespace .";\n";
	$code .= <<'EOF';
use 5.012;
use strict;
use warnings;
use utf8;

sub {
my $_TP = ''; 
EOF

	$code .= $self->prepend ."\n";
	if(@variables) {
		$code .= 'my ('. join(', ', map {"\$$_"} @variables) .') ';
		$code .= '= @{ $_[0] }{ qw/'. join(' ', @variables) ."/ };\n";
	}

	$code .= $self->{code} ."\n". $self->append .qq/\n\nreturn \$_TP; \n}/;
	say "\n===CODE===\n$code\n===END===\n" if $self->{debug};

	$self->_patch;

	die $@ unless $code = eval $code;

	my $output;
	die $@ unless eval { $output = $code->($self->_options); 1; };

	return $output;
}

sub _patch {
	my $self = shift;

	no strict 'refs';

	*{$self->namespace ."::_generate_attributes"} = \&Template::Pug::Util::generate_attributes;
	*{$self->namespace ."::encode_entities"} = \&HTML::Entities::encode_entities;

	return $self;
}

sub _read_template {
	my ($self, $path) = @_;

	my $content = file($path)->slurp;

	$content = decode($self->{encoding}, $content) if $self->{encoding};

	return $content;
}

sub _render {
	my ($self, $template) = @_;

	if($self->_options->{cache} || $self->cache) {
		my $filename = $self->_options->{filename};
		die 'the "filename" option is required for caching' unless $filename;

		if(exists $self->_cached->{$filename}) {
			say "Rendering cached template: $filename" if $self->{debug};
			$self->{code} = $self->_cached->{$filename};
		} else {
			$self->_parse($template)->_compile();
			$self->_cached->{$filename} = $self->{code};
		}
	} else {
		$self->_parse($template)->_compile();
	}

	return $self->_process();
}

sub _resolve_path {
	my ($self, $path, $filename) = @_;
	my $basedir = $self->_options->{basedir} || $self->basedir;

	$path .= $self->_extension unless $path =~ /^.+\..+$/;

	die 'the "filename" option is required to use includes and extends with "relative" paths' if $path !~ /^\// && !$filename;
	die 'the "basedir" option is required to use includes and extends with "absolute" paths' if $path =~ /^\// && !$basedir;

	return file( ($path =~ /^\// ? dir($basedir) : file($filename)->dir), $path)->absolute->stringify;
}

1;

__END__

=encoding utf8

=head1 NAME

Template::Pug - Pug templates implementation for Perl

=head1 SYNOPSIS

	use Template::Pug;

	my $tp = Template::Pug->new;
	$tp->render(<<'EOF', {list_name => 'List', list => ['foo', 'bar']});
	div
		p= $list_name
		ul#some_id
			- for my $item (@$list)
				li.some_class= $item

	my $tp = Template::Pug->new;
	$tp->render_file('template.pug', { user => {name => 'Foo', count => 42} });
	# template.pug
	# div.
	# 	Hello, #{$user->{name}}!
	# 	You are #{$user->{count}}'th user to signup here!


=head1 DESCRIPTION

L<Template::Pug> is a Perl implementation of JavaScript template engine L<Pug|https://pugjs.org/>

=head1 SYNTAX

=head2 Attributes

Tag attributes look similar to HTML, but their values are Perl expressions.

	a(href="yandex.ru") Yandex
	// <a href="yandex.ru">Yandex</a>

	a(href="yandex.ru" class="button") Yandex
	// <a href="yandex.ru" class="button">Yandex</a>

B<Note:> since it is impossible(for me) to parse Perl, you can define multiple attributes in one line if expression consists only of single/double quoted string followed by space or comma.
Otherwise, every thing until the end of line or end of attribute block is considered single Perl expression.

	// Wrong!
	- my $authenticated = 1;
	div(class=$authenticated ? 'auth' : 'anon' id="bar") Content

	// Right
	div(id="bar" class=$authenticated ? 'auth' : 'anon') Content

	// Right
	div(
		id=$id
		class=$authenticated ? 'auth' : 'anon'
		foo=$bar->baz()
	) Content

By default, all attribute values are escaped.  If you need to use special characters, use C<!=> instead of C<=>.

	div(escaped="<code>")
	// <div escaped="&lt;code&gt;"></div>

	div(unescaped!="<code>")
	// <div unescaped="<code>"></div>

Boolean attributes are mirrored by Pug. Only literal string C<undef> is considered false, every thing else is true. When no value is specified  true is assumed.

	input(foo bar='baz')
	// <input bar="baz" foo="foo"/>

	input(foo="foo" bar='baz')
	// <input bar="baz" foo="foo"/>

	input(bar='baz' foo=undef)
	// <input bar="baz"/>

The C<style> attribute can be a hash.

	a(style={color => 'red', background => 'green'})
	// <a style="background:green;color:red"></a>

The C<class> attribute can be an array of names.

	- my $classes = ['foo', 'bar', 'baz'];
	a(class=$classes)
	// <a class="foo bar baz"></a>

	a.bang(
	  class=$classes
	  class=['bing']
	)
	// <a class="bang foo bar baz bing"></a>

It can also be a hash which maps class names to true or false values. This is useful for applying conditional classes

	- my $currentUrl = '/about';
	a(href='/' class={active => $currentUrl eq '/'}) Home
	// <a href="/">Home</a>

	a(href='/about' class={active => $currentUrl eq '/about'}) About
	// <a class="active" href="/about">About</a>

Classes may be defined using a C<.classname> syntax.

	div.foo
	// <div class="foo"></div>

C<div> is the default tag so you can omit its tag name.

	.foo
	// <div class="foo"></div>

IDs may be defined using a C<#idname> syntax.

	div#foo
	// <div id="foo"></div>

C<div> is the default tag so you can omit its tag name.

	#foo
	// <div id="foo"></div>

Pronounced as “and attributes”, the C<&attributes> syntax can be used to explode a hach into attributes of an element.

	div#foo(data-bar="foo")&attributes({"data-foo" => "bar"})
	// <div data-bar="foo" data-foo="bar" id="foo"></div>

	- my $attributes = {id => undef, class => 'baz'};
	div#foo(data-bar="foo")&attributes($attributes)
	// <div class="baz" data-bar="foo"></div>

B<Attributes applied using> C<&attributes> B<are not automatically escaped.>

=head2 Code

Code starts with C<- > and does not directly add anything to the output. If code element have child than open and closing curly braces added around its content.

	// Wrong!
	- for (0..2) {
		li item
	- }

	// Right
	- for (0..2)
		li item
	// <li>item</li><li>item</li><li>item</li>

Code block starts with C<-\n>.

	-
		my @list = qw/one
	  			  two
	  			  three/;
	- for(@list)
		li= $_
	// <li>one</li><li>two</li><li>three</li>

=head2 Comments

Buffered comments C<//> act like markup tags, producing HTML comments in the rendered page. Like tags, they must appear on their own line.

	// some comments
	div foo

Will produce:

	<!-- some comments -->
	<div>foo</div>

Unbuffered comments C<//-> are only for commenting on the Pug code itself, and do not appear in the rendered HTML.

	//- some comments
	div foo

Will produce:

	<div>foo</div>

Block comments are also an option.

	// some
		multiline
		comment
	div foo

Will produce:

	<-- some
		multiline
		comment -->
	<div>foo</div>

Moreover, since all lines beginning with C<E<lt>> are treated as plain text, normal HTML-style conditional comments work just fine.

	div
		<-- HTML comments -->
		foo

Will produce:

	<div><-- HTML comments -->foo</div>

=head2 Doctype

There are shortcuts for commonly used doctypes:

	doctype html
	// <!DOCTYPE html>,
	
	doctype xml
	// <?xml version="1.0" encoding="utf-8" ?>,
	
	doctype transitional
	// <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">,
	
	doctype strict
	// <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">,
	
	doctype frameset
	// <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">,
	
	doctype 1.1
	// <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">,
	
	doctype basic
	// <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML Basic 1.1//EN" "http://www.w3.org/TR/xhtml-basic/xhtml-basic11.dtd">,
	
	doctype mobile
	// <!DOCTYPE html PUBLIC "-//WAPFORUM//DTD XHTML Mobile 1.2//EN" "http://www.openmobilealliance.org/tech/DTD/xhtml-mobile12.dtd">,
	
	doctype plist
	// <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">

Or you can use custom doctype.

	doctype html PUBLIC "-//W3C//DTD XHTML Basic 1.1//EN"
	// <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML Basic 1.1//EN">

If, for whatever reason, it is not possible to use the C<doctype> keyword, but you would still like to specify the doctype of the template, you can do so via the C<doctype> option.

	$tp->render('img src="foo"', {doctype => 'html'})
	// <img src="foo">

	$tp->render('img src="foo"', {doctype => 'xml'})
	// <img src="foo"></img>

=head2 Expressions

Expression starts with C<=>. It evaluates the Perl code and outputs the result. For security, expression output is HTML escaped.

	p= 'This is <escaped> expression'
	// <p>This is &lt;escaped&gt; expression</p>

Unescaped expression starts with C<!=>.

	p!= 'This is <unescaped> expression'
	// <p>This is <unescaped> expression</p>

=head2 Includes

Includes allow you to insert the contents of one L<Template::Pug> file into another.

	// main.pug
	div
		include head.pug
		p content
		include foot.pug

	// head.pug
	p head

	// foot.pug
	p foot

Will produce:

	<div>
		<p>head</p>
		<p>content</p>
		<p>foot</p>
	</div>

If the path is absolute (e.g., include /root.pug), it is resolved by prepending C<basedir> option. Otherwise, paths are resolved relative to the current file being compiled.
If no file extension is given, C<.pug> is automatically appended to the file name.

Including files that are not a L<Template::Pug> templates simply includes their raw text.

	// main.pug
	head
		style
			include style.css
		script
			include script.js
	body
		div foo

	// style.css
	div {
		color: red;
	}

	// script.js
	console.log('Hi!');

Will produce:

	<head>
		<style>
			div {
				color: red;
			}
		</style>
		<script>
			console.log('Hi!');
		</script>
	</head>
	<body>
		<div>foo</div>
	</body>

=head2 Inheritance

L<Template::Pug> supports template inheritance. Template inheritance works via the C<block> and C<extends> keywords. If no file extension is given, C<.pug> is automatically appended to the file name.
In a template, a C<block> is simply a “block” of L<Template::Pug> code that a child template may replace. This process is recursive. Blocks can have default content.

	// layout.pug
	html
		head
			title My Title
			block scripts
				script(src='/jquery.js')
		body
			block content
			block foot
				#footer
					p some footer content
	
	//- page-a.pug
	extends layout.pug

	block scripts
		script(src='/jquery.js')
		script(src='/pets.js')

	block content
		h1= $title
		- my $pets = ['cat', 'dog'];
		- for my $pet (@$pets)
			include pet.pug

	//- pet.pug
	p= $pet

L<Template::Pug> allows you to C<replace> (default), C<prepend>, or C<append> blocks.
For example you can have default scripts in C<head> block that you want to use on every page and just C<append> scripts you need for current page.

	// layout.pug
	html
		head
			block head
				script(src='/jquery.js')
				script(src='/default.js')
	body
		block content

	// page.pug
	extends layout.pug

	block append head
		script(src='/actions.js')

When using C<block append> or C<block prepend>, the word “block” is optional.

=head2 Interpolation

In text block any Perl expression put between C<#{> and C<}> will be evaluated and result will be escaped and put in its place.

	- my $foo = 'simple string';
	- my $bar = '<p>string inside tag</p>';
	p some text #{10+10} some text #{$foo} some text #{$bar}
	// <p>some text 20 some text simple string some text &lt;p&gt;string inside tag&lt;/p&gt;</p> 

If you need to put literal C<#{> in text just put slash in front of it to escape.

	p some text \#{foo} some text
	// <p>some text #{foo} some text</p>

Use C<!{ }> if you want an unescaped result.

	- my $foo = '<p>string inside tag</p>';
	div some text !{$foo}
	// <div>some text<p>string inside tag</p></div>

Text between C<#[> and C<]> will be evaluated as L<Template::Pug> code and result will be put in its place.

	p text #[em foo] text #[em(foo='bar') baz] text
	// <p>text <em>foo</em> text <em foo="bar">baz</em> text</p>

=head2 Mixins

There is no Mixins yet.

=head2 Tags

By default, text at the start of a line represents an HTML tag. Indented tags are nested, creating the tree structure of HTML.

	body
		div
			h1 title
			p text

	// <body>
	// 	<div>
	// 		<h1>title</h1>
	// 		<p>text</p>
	//	</div>
	// </body>

To save space, L<Template::Pug> provides an inline syntax for nested tags.

	a: img
	// <a><img /></a>

Tags such as img, meta, and link are automatically self-closing (unless you use the XML doctype).
You can also explicitly self close a tag by appending the / character.

	foo/
	foo(bar='baz')/
	// <foo/>
	// <foo bar="baz" />

=head2 Text

The easiest way to add plain text is inline. The first term on the line is the tag itself. Everything after the tag and one space will be the text contents of that tag. 

	p some plain <em>text</em>
	// <p>some plain <em>text</em></p>

Lines starting with C<E<lt>> or C<|> are treated as plain text.

	<body>
		p
			| some 
			| text
	</body>

	// <body>
	//	<p>some text</p>
	// </body>

To add block of text to a tag use C<.> followed by a new line.

	script.
		if(true) {
			console.log('true');
		} else {
			console.log('false');
		}

=head1 ATTRIBUTES

L<Template::Pug> implements the following attributes.

=head2 append

	my $code = $tp->append;
	$tp = $tp->append('warn "Processed template"');

Append Perl code to compiled template.

=head2 basedir

	my $basedir = $tp->basedir;
	$tp = $tp->basedir('templates');

Bsaedir used to resolve absolute path in template includes and extends.

=head2 cache

	my $cache = $tp->cache;
	$tp = $tp->cache(1);

Cache is a flag, if set to true will cache and reuse compiled templates. Requires C<filename> as a cache key. Defaults to false.

=head2 doctype

	my $doctype = $tp->doctype;
	$tp = $tp->doctype('html');

Doctype used to specify C<doctype> if unable to do it in template.

=head2 encoding

	my $encoding = $tp->encoding;
	$tp = $tp->encoding('cp1251');

Encoding used for template files, defaults to C<UTF-8>.

=head2 namespace

	my $namespace = $tp->namespace;
	$tp = $tp->namespace('main');

Namespace used to compile templates, defaults to C<Template::Pug::SandBox>.
Note that namespaces should only be shared very carefully between templates, since functions and global variables will not be cleared automatically.

=head2 prepend

	my $code = $tp->prepend;
	$tp = $tp->prepend('my $self = shift;');

Prepend Perl code to compiled template.

=head2 pretty

	my $pretty = $tp->pretty;
	$tp = $tp->pretty(1);

Pretty is a flag, if set to true adds whitespace to the resulting HTML to make it easier for a human to read using C<'  '> as indentation. Used for debugging only. Defaults to false.

=head1 METHODS

=head2 render

	my $output = $tp->render('div Hello world!');
	my $output = $tp->render('p= $foo', {foo => 'bar'});
	my $output = $tp->render('p= 1 + 1', {namespace => 'main'});

Render inline template and return the result.

=head2 render_file

	my $output = $tp->render_file('templates/foo.pug');
	my $output = $tp->render_file('templates/foo.pug', {foo => 'bar'});
	my $output = $tp->render_file('templates/foo.pug', {cache => 1});

Same as L</"render">, but renders a template file.

=head1 SEE ALSO

L<Pug|https://pugjs.org/> L<Mojolicious::Plugin::PugRenderer>

=cut