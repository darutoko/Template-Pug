package Template::Pug::Compiler;

use 5.012;
use strict;
use warnings;
use utf8;

my %doctypes = (
	'html' => '<!DOCTYPE html>',
	'xml' => '<?xml version="1.0" encoding="utf-8" ?>',
	'transitional' => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">',
	'strict' => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">',
	'frameset' => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">',
	'1.1' => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">',
	'basic' => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML Basic 1.1//EN" "http://www.w3.org/TR/xhtml-basic/xhtml-basic11.dtd">',
	'mobile' => '<!DOCTYPE html PUBLIC "-//WAPFORUM//DTD XHTML Mobile 1.2//EN" "http://www.openmobilealliance.org/tech/DTD/xhtml-mobile12.dtd">',
	'plist' => '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
);

# ========= Public methods =========

sub new {
	my $class = shift;
	bless @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;
}

sub compile {
	my $self = shift;

	$self->_init(shift)->_mode('string');

	$self->_compile_children($self->{tree});

	$self->_mode('code');

	return $self->{compiled};
}

sub doctype {
	my ($self, $doctype) = @_;

	return $self->{doctype} unless $doctype;

	$doctype =~ s/\s+$//;

	$self->{doctype} = quotemeta($doctypes{lc $doctype} || '<!DOCTYPE '. $doctype .'>');

	$self->_terse(1) if lc $doctype eq 'html';
	$self->_xml(1) if lc $doctype eq 'xml';

	return $self;
}

# ========= Private methods =========

sub _init {
	my ($self, $options) = @_;

	@{ $self }{qw/tree pretty doctype/} = @{ $options }{qw/tree pretty doctype/};

	die 'There is no tree' unless defined $self->{tree};

	$self->{compiled} = '';
	$self->{xml} = 0;
	$self->{mode} = '';
	$self->{terse} = 0;
	$self->{indent} = 0;
	$self->{is_inlines} = [0];
	$self->{indent_char} = '  ';

	$self->doctype($self->{doctype}) if $self->{doctype};

	return $self;
}

# Acess methods

sub _c { $_[0]{compiled} .= $_[1]; $_[0] }
sub _xml { return $_[0]{xml} if @_ == 1; $_[0]{xml} = $_[1]; $_[0] };
sub _terse { return $_[0]{terse} if @_ == 1; $_[0]{terse} = $_[1]; $_[0] };
sub _pretty { return $_[0]{pretty} if @_ == 1; $_[0]{pretty} = $_[1]; $_[0] };
sub _indent { return $_[0]{indent} if @_ == 1; $_[0]{indent} += $_[1]; $_[0] };
sub _is_inlines { $_[0]{is_inlines} };
sub _indent_char { $_[0]{indent_char} };

# Compile methods

# Process children's tokens
sub _compile_children {
	my ($self, $children) = @_;

	for my $token (@{ $children }) {
		my $method = '_'. $token->{type};

		die 'Unknown token type ', $token->{type} unless $self->can($method);

		$self->$method($token);
	}

	return $self;
}

# Attributes
sub _attributes {
	my ($self, $attributes) = @_;
	my $attributes_block = '{}';

	if(exists $attributes->{'=attributes_block'}) {
		$attributes_block = delete $attributes->{'=attributes_block'};
	}

	$self->_mode('code');

	$self->_c("{my \%_TP_attributes = (\n");
	while(my ($name, $ref) = each %{ $attributes }) {
		if($name eq 'class') {
			$self->_c("$name => [\n");
			for my $r (@{ $ref }) {
				$self->_c("{value => ". $r->{value} .", escape => ". ($r->{escape}||0) ."},\n");
			}
			$self->_c("],\n");
		} else {
			$self->_c("'$name' => {value => ". $ref->{value} .", escape => ". ($ref->{escape}||0) ."},\n");
		}
	}
	$self->_c('); $_TP .= _generate_attributes(\%_TP_attributes, '. $attributes_block .', '. $self->_terse .');}');

	return $self;
}

# Block
sub _block {
	my ($self, $token) = @_;

	$self->_compile_children($token->{children});

	return $self;
}

# Code
sub _code {
	my ($self, $token) = @_;

	$self->_mode('code');

	$self->_c($token->{value} ."\n");

	if(defined $token->{children} && @{ $token->{children} }) {
		$self->_c("{\n");

		$self->_compile_children($token->{children});

		$self->_mode('code')->_c("}");
	}
}

# Comment
sub _comment {
	my ($self, $token) = @_;

	$token->{value} = "<!--". $token->{value} ." -->";

	$self->_text($token);

	return $self;
}

# Doctype
sub _doctype {
	my ($self, $token) = @_;

	$self->doctype($token->{value});

	$self->_mode('string');

	$self->_c($self->doctype);

	return $self;
}

# Expression
sub _expression {
	my ($self, $token) = @_;

	$self->_mode('code');

	$self->_c('$_TP .= '. $self->_expression_token($token) .';');
}

# Include
sub _include {
	my ($self, $token) = @_;

	$self->_compile_children($token->{children});

	return $self;
}

# Tag
sub _tag {
	my ($self, $token) = @_;

	$self->_mode('string')->_prettify;

	$self->_c('<'. $token->{value});
	$self->_attributes($token->{attributes}) if keys %{ $token->{attributes} };
	$self->_mode('string');

	# Close and done if tag is self closing
	if($token->{self_closing} || (!$self->_xml && $self->_self_closing_tag($token))) {
		die $token->{value} .' is self closing tag and should not have content' if scalar @{ $token->{children} };
		if($self->_terse && !$token->{self_closing}) {
			$self->_c('>');

		} else {
			$self->_c('/>');
		}
		return;
	}

	$self->_c('>');

	if(@{ $token->{children} }) {
		# increase indentation and set inline status for descendants
		$self->_indent(1);
		unshift @{ $self->_is_inlines }, $token->{is_inline};

		$self->_compile_children($token->{children});

		# restore indentation level, restore inline status
		$self->_indent(-1)->_mode('string')->_prettify;
		shift @{ $self->_is_inlines };
	}

	$self->_c('</'. $token->{value} .'>');
}

# Text
sub _text {
	my ($self, $token) = @_;

	$self->_mode('string');

	if($self->_pretty) {
		$self->_prettify->_c(quotemeta) for split "\n", $token->{value};
	} else {
		$self->_c(quotemeta $token->{value});
	}
}

# ========= Helpers ========

sub _expression_token {
	my ($self, $expression) = @_;

	# Escape HTML
	if($expression->{escape}) {
		return 'encode_entities('. $expression->{value} .')';
	}
	# Do not escape HTML
	return $expression->{value};

	return $self;
}

# Method handles switch between code and string generation
sub _mode {
	my ($self, $new_mode) = @_;

	return $self if $self->{mode} eq $new_mode;

	if($new_mode eq 'string') {
		$self->_c("\n\$_TP .= \"");
	} elsif($new_mode eq 'code') {
		$self->_c("\";\n");
	}

	$self->{mode} = $new_mode;

	return $self;
}

# Method handles pretty output if 'pretty' option is true
sub _prettify {
	my $self = shift;

	return $self if !$self->_pretty or $self->_is_inlines->[0];

	$self->_c("\n". ($self->_indent_char x $self->_indent) );

	return $self;
}

sub _self_closing_tag {
	my ($self, $tag) = @_;
	# https://html.spec.whatwg.org/multipage/syntax.html#void-elements
	my @self_closing_tags = qw/area base br col embed hr img input link meta param source track wbr/;

	return scalar grep $_ eq $tag->{value}, @self_closing_tags;
}

1;

__END__

=encoding utf8

=head1 NAME

Template::Pug::Compiler - converts parsed template tree in to a Perl code.

=head1 SYNOPSIS

	use Template::Pug::Compiler;

	my $tpc = Template::Pug::Compiler->new;
	$code = $tpc->compile({tree => \@tree});

=head1 METHODS

=head2 compile

	my $code = $tpc->compile({tree => \@tree, pretty => 1});

Convert tree in to string containing Perl code and return the result.

=cut