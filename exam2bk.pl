#! perl -w
open F,"./input.txt" || die; read F,$m,900000; close F || die;
@d=split("\n",$m);

my $max = 0;
my $cur = 0;
my $min = 0;

my $prev = "";
foreach  (@d) {

    if ($_ eq 1) {
       
        if($prev == ""){
            $min=1;
            $cur++;
        }
        if ($prev eq 1) {$cur++;}
        
    } else {
        if($cur>$max){$max=$cur;}
        $cur = $min;
    }

    $prev = $_;

}
if($cur>$max){$max=$cur;}

open F,">output.txt" || die; print F $max; close F || die;