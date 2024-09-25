#! perl -w
open F,"input.txt" || die; read F,$_,99900000; close F || die;
s%(?!1)(.)% %ig; 
@d = split(' ',$_);
foreach  (@d) {
    push (@s,length($_))
}
my $max = 0;    
foreach  (@s) {
    $max=$_ if $_>$max;
}
open F,"+>output.txt" || die; print F $max; close F || die;

