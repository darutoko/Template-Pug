package Template::Pug::Parser;

use 5.012;
use strict;
use warnings;
use utf8;

use Text::Balanced qw/extract_delimited extract_bracketed/;


# ========= Public methods =========

sub new {
	my $class = shift;
	bless @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;
}

sub blocks {
	my ($self, $name, $ref) = @_;

	return $self->{blocks} if @_ < 3;

	$self->{blocks}{$name} = $ref;

	return $self;
}

sub includes {
	my ($self, $ref) = @_;

	return $self->{includes} if @_ < 2;

	push @{ $self->{includes} }, ref $ref eq 'ARRAY' ? @$ref : $ref;

	return $self;
}

sub parse {
	my $self = shift;

	$self->_init(shift);

	until($self->_done) {
		next if $self->_eot
			|| $self->_indent
			|| $self->_doctype
			|| $self->_extends
			|| $self->_block_append
			|| $self->_block_prepend
			|| $self->_block_replace
			|| $self->_include
			|| $self->_tag
			|| $self->_expression
			|| $self->_code
			|| $self->_dash
			|| $self->_id
			|| $self->_dot
			|| $self->_class
			|| $self->_attributes
			|| $self->_attributes_block
			|| $self->_text
			|| $self->_text_html
			|| $self->_comment
			|| $self->_slash
			|| $self->_colon
			|| $self->_fail;
	}

	return $self;
}

sub filename { return $_[0]{filename} if @_ == 1; $_[0]{filename} = $_[1]; $_[0] };
sub extends { return $_[0]{extends} if @_ == 1; $_[0]{extends} = $_[1]; $_[0] };
sub tree { return $_[0]{tree} if @_ == 1; $_[0]{tree} = $_[1]; $_[0] };

# ========= Private methods =========

sub _init {
	my ($self, $options) = @_;

	@{ $self }{qw/template filename/} = @{ $options }{qw/template filename/};

	$self->{template} =~ s/\r\n|\r/\n/g;
	$self->{t} = $self->{template};

	$self->{done} = 0;
	$self->{line} = 1;
	$self->{tree} = [];
	$self->{blocks} = {};
	$self->{context} = [{children => $self->{tree}, indent => -1, is_inline => 0}];
	$self->{indents} = [0];
	$self->{includes} = [];
	$self->{is_tag_on_line} = 0; # flag, to check if there was a tag on current line

	$self->_scan_indent;

	return $self;
}

# Acess methods

sub _t  :lvalue { $_[0]{t} };
sub _template { $_[0]{template} };
sub _context { $_[0]{context} };
sub _indents { $_[0]{indents} };
sub _done { return $_[0]{done} if @_ == 1; $_[0]{done} = $_[1]; $_[0] };
sub _line { return $_[0]{line} if @_ == 1; $_[0]{line} += $_[1]; $_[0] };
sub _indent_re { return $_[0]{indent_re} if @_ == 1; $_[0]{indent_re} = $_[1]; $_[0] };
sub _is_tag_on_line { return $_[0]{is_tag_on_line} if @_ == 1; $_[0]{is_tag_on_line} = $_[1]; $_[0] };

# ========= Parse methods =========

# End of template
sub _eot {
	my $self = shift;

	return if length $self->_t;

	$self->_done(1);

	return 1;
}

# Indent
sub _indent {
	my $self = shift;

	$_ = $self->_indent_re;
	return unless $self->_t =~ s/$_//;

	$self->_line(1)->_is_tag_on_line(0);
	my $indent = length $1;

	$self->_die('Invalid indentation, you can use tabs or spaces but not both') if $self->_t =~ /^[\t ]/;

	# ignore empty line
	return 1 if $self->_t =~ /^\n/;

	# make new indent current if new indent is greather than current
	if($indent > $self->_indents->[0]) {
		unshift @{ $self->_indents }, $indent;
		$self->_context->[0]{is_inline} = 0;
	}
	# otherwise unindent until current indent is not greather than new
	else {
		while($self->_indents->[0] > $indent) {
			if($self->_indents->[1] < $indent) {
				$self->_die('Inconsistent indentation. Expecting either '. $self->_indents->[1] .' or '. $self->_indents->[0] .' spaces/tabs.');
			}
			shift @{ $self->_indents };
		}
	}
	# make current context token the last token with indent less than new indent
	while($self->_context->[0]{indent} >= $indent) {
		shift @{ $self->_context };
	}

	return 1;
}

# Doctype
sub _doctype {
	my $self = shift;

	return unless $self->_t =~ s/^doctype +(.+)//;

	my %token = (
		type => 'doctype',
		value => $1
	);

	$self->_add_token(\%token);

	return $self;
}

# Extends
sub _extends {
	my $self = shift;

	return unless $self->_t =~ s/^extends?\s(.+)//;

	$self->_die('missing path for extends') unless $1;

	$self->extends($self->_trim($1));

	return 1;
}

# Block append
sub _block_append {
	my $self = shift;

	return unless $self->_t =~ s/^(?:block +)?append +(.+)//;

	$self->_add_block($self->_trim($1), 'append');

	return 1;
}

# Block prepend
sub _block_prepend {
	my $self = shift;

	return unless $self->_t =~ s/^(?:block +)?prepend +(.+)//;

	$self->_add_block($self->_trim($1), 'prepend');

	return 1;
}

# Block replace
sub _block_replace {
	my $self = shift;

	return unless $self->_t =~ s/^block +(.+)//;

	$self->_add_block($self->_trim($1), 'replace');

	return 1;
}

#Include
sub _include {
	my $self = shift;

	return unless $self->_t =~ s/^include +(.+)//;

	$self->_die('missing path for include') unless $1;

	my $include = $self->_trim($1);
	my %token = (
		type => 'include',
		value => $include,
		filename => $self->filename
	);

	$self->_add_token(\%token);
	$self->includes(\%token);

	return 1;
}


# Tag
sub _tag {
	my $self = shift;

	return unless $self->_t =~ s/^(\w(?:[-:\w]*\w)?)//;

	$self->_add_tag($1);

	return 1;
}

# Expression
sub _expression {
	my $self = shift;

	return unless $self->_t =~ s/^(!?=)[ \t]*(.+)//;

	$self->_add_expression($2, $1 eq '=');

	return 1;
}

# Code
sub _code {
	my $self = shift;

	return unless $self->_t =~ s/^-[ \t]*(\S.*)//;

	my %token = (
		type => 'code',
		value => $1,
		children => [],
		indent => $self->_indents->[0]
	);

	$self->_add_parent(\%token);

	return 1;
}

# Dash
sub _dash {
	my $self = shift;

	return unless $self->_t =~ s/^-[ \t]*//;

	my %token = (
		type => 'code',
		value => $self->_slurp,
	);

	$self->_add_token(\%token);

	return 1;
}

# Id
sub _id {
	my $self = shift;

	return unless $self->_t =~ /^#/;

	$self->_die('Invalid Id. Id can contain alphanumeric and "-" only.') unless $self->_t =~ s/^#([\w-]+)//;

	$self->_add_tag('div') unless $self->_is_tag_on_line;

	$self->_add_attribute('id', "'$1'");

	return 1;
}

# Dot
sub _dot {
	my $self = shift;

	return unless $self->_t =~ /^\.\s+/;

	$self->_t =~ s/^\..*//;

	$self->_add_text($self->_slurp);

	return 1;
}

# Class
sub _class {
	my $self = shift;

	return unless $self->_t =~ /^\./;

	$self->_die('Invalid class name. Class names must begin with "-" or "_", followed by a letter, or a letter and can only contain "_", "-", a-z and 0-9') unless $self->_t =~ s/^\.((?:[_a-z][a-z0-9-]|-[_a-z])[_a-z0-9-]*)//i;

	$self->_add_tag('div') unless $self->_is_tag_on_line;

	$self->_add_attribute('class', "'$1'");

	return 1;
}

# Attributes
sub _attributes {
	my $self = shift;

	return unless $self->_t =~ /^\(/;

	my $string = extract_bracketed($self->_t, q/("'`)/);
	$self->_die('Unable to find closing parenthesis') unless $string;

	$string =~ s/^\(|\)$//g;
	my $lines =()= $string =~ /(\n)/g;
	until($string =~ /^\s*$/) {
		my ($name, $value, $escape);

		$string =~ s/^\s*,//;

		# attribute name acording to https://www.w3.org/TR/html-markup/syntax.html#syntax-attributes
		# plus ',' and '!'
		$string =~ s|^\s*([^\s\N{U+0000}'">/=!,]+)||;
		$name = $1;
		unless($name) {
			$self->_t = $string . $self->_t; # prepend rest of the string for output
			$self->_die('Unexpected character');
		}
		# no expression start character or there is a comma means attribute has ended
		if($string =~ s/^\s*,// or $string !~ /^\s*!?=/) {
			$self->_add_attribute($name, "'$name'", 1);
			next;
		}

		$string =~ s/^\s*(!?=)//;
		$escape = $1 ne '!=';
		$value = '';

		# if value starts with a quote assume it is a simple string
		if($string =~ /^\s*['"]/) {
			$value = extract_delimited($string, q/'"/);
			if(!$string or $string =~ s/^(?:\s|,)//) {
				$self->_add_attribute($name, $value, $escape);
				next;
			}
		}
		if($string =~ s/^\s*undef(?:\s|,|$)//) {
			$self->_add_attribute($name, 'undef', 0);
			next;
		}

		# if value isn't undef or didn't start with quote or didn't end with ',' or whitespace
		# then value is till the end of the line
		$string =~ s/^(.+)//;
		$value .= $1;
		$self->_add_attribute($name, $value, $escape);
	}

	$self->_line($lines);
	return 1;
}

# Attributes block
sub _attributes_block {
	my $self = shift;

	return unless $self->_t =~ s/^&attributes\b//;

	$self->_die('Unexpected text. Expecting "(".') unless $self->_t =~ /^\(/;

	my $string = extract_bracketed($self->_t, q/("')/);
	$self->_die('Unable to find closing parenthesis') unless $string;
	$string =~ s/^\(|\)$//g;

	$self->_add_attributes_block($string);

	return 1;
}

# Text
sub _text {
	my $self = shift;

	return unless $self->_t =~ s/^(?:\|? )(.*)//;

	$self->_add_text($1);

	return 1;
}

# Text HTML
sub _text_html {
	my $self = shift;

	return unless $self->_t =~ s/^(<.*)//;

	$self->_add_text($1);

	return 1;
}

# Comment
sub _comment {
	my $self = shift;

	return unless $self->_t =~ s|^//(-)?(.*)||;

	my $skip = length $1;

	my %token = (
		type => 'comment',
		value => join "\n", $2, $self->_slurp,
	);

	return 1 if $skip;

	$self->_add_token(\%token);

	return 1;
}

# Slash
sub _slash {
	my $self = shift;

	return unless $self->_t =~ s|^/||;

	$self->_context->[0]{self_closing} = 1;

	return 1;
}

# Colon
sub _colon {
	my $self = shift;

	return unless $self->_t =~ s/^: +//;

	$self->_context->[0]{is_inline} = 1;

	return 1;
}

# Unexpected text
sub _fail { shift->_die('Unexpected text') }

# ========= Helpers ========

# add attribute to current tag
sub _add_attribute {
	my ($self, $name, $value, $escape) = @_;
	my $attributes = $self->_context->[0]{attributes};

	if($name eq 'class') {
		$attributes->{$name} = [] unless exists $attributes->{$name};
		push @{ $attributes->{$name} }, {value => $value, escape => $escape};
	} else {
		$attributes->{$name} = {value => $value, escape => $escape};
	}

	return $self;
}

# add "and attributes" block to current tag 
sub _add_attributes_block {
	my ($self, $value) = @_;

	$self->_context->[0]{attributes}{'=attributes_block'} = $value;

	return $self;
}

sub _add_block {
	my ($self, $value, $mode) = @_;

	my %token = (
		type => 'block',
		value => $value,
		mode => $mode,
		cihldren => [],
		indent => $self->_indents->[0]
	);

	$self->blocks($value, \%token);
	$self->_add_parent(\%token);

	return $self;
}

# Add expression
sub _add_expression {
	my ($self, $expression, $escape) = @_;

	$self->_add_token({
		type => 'expression',
		value => $expression,
		escape => $escape
	});

	return $self;
}

# Make token the new context
sub _add_parent {
	my ($self, $token) = @_;

	$self->_add_token($token);
	unshift @{ $self->_context }, $token;

	return $self;
}

# Add a new tag
sub _add_tag {
	my ($self, $tag) = @_;

	my %token = (
		type => 'tag',
		value => $tag,
		is_inline => 1,
		children => [],
		attributes => {},
		indent => $self->_indents->[0]
	);

	$self->_add_parent(\%token)->_is_tag_on_line(1);

	return $self;
}

# Add text
sub _add_text {
	my ($self, $string) = @_;
	my ($text, $tag, $expression, $escape, $tag_index, $expression_index);

	return $self if !defined $string || $string eq '';

	$expression_index = $-[0] if $string =~ /(?<!\\)[!#]{/;
	$tag_index = $-[0] if $string =~ /(?<!\\)#\[/;

	if(defined $expression_index && (!defined $tag_index || $expression_index < $tag_index)) {
		$text = substr $string, 0, $expression_index, '';
		$escape = substr($string, 0, 1, '') eq '#';
		$self->_die('Unable to find closing bracket', $string) unless $expression = extract_bracketed($string, q/{'"`}/);
		$expression =~ s/^{|}$//g;
		$self->_add_text($text);
		$self->_add_expression($expression, $escape);
		$self->_add_text($string);
	} elsif(defined $tag_index && (!defined $expression_index || $tag_index < $expression_index)) {
		$text = substr $string, 0, $tag_index, '';
		substr($string, 0, 1, '');
		$self->_die('Unable to find closing bracket', $string) unless $tag = extract_bracketed($string, q/['"`]/);
		$tag =~ s/^\[|\]$//g;
		$tag = $self->new->parse({template => $tag})->tree->[0];
		$self->_add_text($text);
		$self->_add_token($tag);
		$self->_add_text($string);
	} else {
		# Handle escaping of interpolation
		$string =~ s/\\([!#]{)/$1/g;
		$string =~ s/\\(#\[)/$1/g;

		$self->_add_token({
			type => 'text',
			value => $string
		});
	}

	return $self;
}

# Add token to the tree
sub _add_token { push @{ shift->_context->[0]{children} }, shift }

sub _die {
	my ($self, $message, $prefix) = @_;
	my @lines = split "\n", $self->_template;
	my ($start, $end) = ($self->_line - 3, $self->_line + 1);

	$start = 0 if $start < 0;
	$end = scalar @lines if $end > scalar @lines;

	my $src = join "\n", map { sprintf '%6u | %s', ++$start, $_ || '' } @lines[$start..$end];

	die sprintf "Parsing error at %s:%d\n%s\n\n%s\n\n around '%s'", ($self->filename || 'Pug'), $self->_line, $message, $src, substr( ($prefix || '') . $self->_t, 0, 10);
}

# Detect if spaces or tabs are used for indentation
sub _scan_indent {
	my $self = shift;

	if($self->_t =~ /\n\t+/) {
		$self->_indent_re(qr/^\n((?:\t)*)/);
	} elsif($self->_t =~ /\n +/) {
		$self->_indent_re(qr/^\n((?: )*)/);
	} else {
		$self->_indent_re(qr/^\n((?:[\t ])*)/);
	}

	return $self;
}

# Consume whole indentend block of text
sub _slurp {
	my $self = shift;
	my @lines;
	my $indent_re = $self->_indent_re;
	my $indent;
	my $indent_min;

	while(!$self->_eot) {
		# empty line
		if($self->_t =~ s/^\n[\t ]*\n/\n/) {
			push @lines, '';
			$self->_line(1);
			next;
		}

		$self->_t =~ /$indent_re/;
		$indent = length $1;
		last unless $indent > $self->_indents->[0];

		# find minimal indentation in the block
		$indent_min = $1 if !defined $indent_min or length $indent_min > $indent;

		# consume line
		$self->_t =~ s/^(\n.+)//;
		push @lines, $1;
		$self->_line(1);
	}

	if(@lines) {
		$self->_context->[0]{is_inline} = 0; 
	} else {
		return;
	}
	
	# trim the minimal indent from the start of the lines
	# this assumes that extra indentation in the block is relevant for user
	return join "\n", map { s/\n$indent_min//; $_ } @lines;
}

sub _trim {
	my ($self, $string) = @_;

	$string =~ s/^\s+//;
	$string =~ s/\s+$//;

	return $string;
}

1;

__END__

=encoding utf8

=head1 NAME

Template::Pug::Parser - converts template in to a tree of Perl structures.

=head1 SYNOPSIS

	use Template::Pug::Parser;

	my $tpp = Template::Pug::Parser->new;
	$tree = $tpp->parse({template => $template});

=head1 METHODS

=head2 compile

	my $tree = $tpp->parse({template => $template, filename => $filename});

Converts string containig pug template in to a tree of Perl stuctures and returns it as reference to an array.

=cut