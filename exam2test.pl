#! perl -w

@d=(0,923478,54678,11,111,-1,9999,11,'1',1,,1,1);

my $max = 0;
my $cur = 0;
my $min = 0;

my $prev = "0";
foreach  (@d) {

    if ($_ *1 eq 1) {
        
        $min=$cur=1 if $min==0;

        $cur++ if $prev*1 eq 1;
        
    } else {
        $max=$cur if $cur>$max;
        $cur = $min;
    }

    $prev = $_;

}
$max=$cur if $cur>$max;

print 'max:',$max; 
print @d; 
<STDIN>