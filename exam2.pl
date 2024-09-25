open F,"input.txt" || die; read F,$m,99900000; close F || die;
@d=split("\n",$m);
@d = (@d[1..$#d]);
my $max = 0;
my $cur = 0;
my $min = 0;

my $prev = "";
foreach  (@d) {

    if ($_+0 eq 1) {
        
        $min=$cur=1 if $min==0;

        $cur++ if $prev+0 eq 1;
        
    } else {
        $max=$cur if $cur>$max;
        $cur = $min;
    }

    $prev = $_;

}
$max=$cur if $cur>$max;

open F,">output.txt" || die; print F $max; close F || die;