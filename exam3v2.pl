#! perl -w
open F,"<input.txt" || die; 
open O,">output.txt" || die;
<F>;
my @s = ();
my $prev = "1000001";
while (<F>) {
    if($_ != $prev){
     print O $_;
     $prev = $_;
    }
}
close F;
close O;