package Template::Pug::Util;

use 5.012;
use strict;
use warnings;
use utf8;

use HTML::Entities;

sub process_class_value {
	my ($value, $escape) = @_;
	my @values;

	if(ref $value and ref $value eq 'ARRAY') {
		for my $v (@{ $value }) {
			push @values, process_class_value($v, $escape);
		}
	} elsif(ref $value and ref $value eq 'HASH') {
		for my $k (keys %{$value}) {
			push @values, $escape ? encode_entities($k) : $k if $value->{$k};
		}
	} else{
		push @values, $escape ? encode_entities($value) : $value;
	}

	return @values;
}

# sub genrates string with HTML attributes
# first parameter is ref to hash generated in Compiler _attributes method
# second parameter is ref to hash set in "and attributes" block and is used to store final "name - value" pairs
sub generate_attributes {
	my ($attrs, $result, $terse) = @_;
	my $output = '';
	$result = {} unless ref $result and ref $result eq 'HASH';

	# Class is a special case
	if(exists $result->{class}) {
		$attrs->{class} = [] unless exists $attrs->{class};
		push @{ $attrs->{class} }, {value => delete $result->{class}, escape => 0};
	}
	if(exists $attrs->{class}) {
		my @values;
		for my $ref (@{ delete $attrs->{class} }) {
			push @values, process_class_value($ref->{value}, $ref->{escape});
		}
		$result->{class} = join ' ', @values if @values;
	}
	# Rest of attributes
	while(my ($name, $ref) = each %{$attrs}) {
		next if exists $result->{$name};
		my ($value, $escape) = ($ref->{value}, $ref->{escape});
		if($name eq 'style' and ref $value and ref $value eq "HASH") {
			$result->{$name} = join ';', map {$_ .':'. ($escape ? encode_entities($value->{$_}) : $value->{$_})} sort keys %{$value};
		} else {
			$result->{$name} = $escape ? encode_entities($value) : $value;
		}
	}

	for my $name (sort keys %{ $result }) {
		next unless defined $result->{$name};
		$output .= ' '. $name;
		$output .= '="'. $result->{$name} .'"' unless $name eq $result->{$name} && $terse;
	}

	return $output;

	# return join ' ', '', map {$terse && $_ eq $result->{$_} ? $_ : $_ .'="'. $result->{$_} .'"'} sort keys %{ $result };
}

1;