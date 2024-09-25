#! perl -w
open F,"<input.txt" || die; 
<F>;
my @s = ();
my $prev = "1000001";
while (<F>) {
    if($_ != $prev){
     push (@s,$_);
     $prev = $_;
    }
}
close F;
$res=join("",@s);
open F,">output.txt" || die; print F $res; close F || die;