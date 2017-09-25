use Test::More;

BEGIN { use_ok('Template::Pug') }

my $tp = Template::Pug->new;
ok(defined $tp, 'object created');
ok($tp->isa('Template::Pug'), 'and object class is Template::Pug');

done_testing();