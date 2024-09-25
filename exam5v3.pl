#! perl -w
open F,"input.txt" || die; read F,$m,999000; close F || die;
@d=split("\n",$m);
@a1=split(//,$d[0]);
@a2=split(//,$d[1]);

my $res = 0;

if (@a1 eq @a2){
    my @sa1 = map(ord, sort @a1);
    my @sa2 = map(ord, sort @a2);

    if (@sa1>0 && @sa2>0){
    $res = 1;   
        for my $i (0 .. $#sa1) {
            print "$sa1[$i]==$sa2[$i]","\n",$sa1[$i]==$sa2[$i],"\n";
            $tmp = 0;
            $tmp = 1 if $sa1[$i]==$sa2[$i];
            $res = $res * $tmp;
        }
    }
}
print "\n res \n",$res;
open F,">output.txt" || die; print F $res; close F || die;