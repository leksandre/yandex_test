#! perl -w
@a=split(//,<STDIN>);
@b=split(//,<STDIN>);
splice @a, -1;
splice @b, -1;

my %seen;
my @au = sort{$a cmp $b} grep {!$seen{$_}++} (@a);

foreach (@b) {
	foreach my $e (@au) {
    	if ($e eq $_) {
        	$f++;
    	}
    }
}
print $f||0;
<STDIN>
