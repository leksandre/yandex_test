#! perl -w
open F,"input.txt" || die; read F,$m,999000; close F || die;
@d=split("\n",$m);
@sa1=split(//,$d[0]);
@sa2=split(//,$d[1]);

my $res = 0;

if (@sa1 eq @sa2){
    @sa1 = sort @sa1;
    @sa2 = sort @sa2;

    if (@sa1>0 && @sa2>0){
    $res = 1;   
        for my $i (0 .. $#sa1) {
            # print "$sa1[$i]==$sa2[$i]","\n",$sa1[$i]==$sa2[$i],"\n";
            $tmp = 0;
            $tmp = 1 if $sa1[$i] eq $sa2[$i];
            $res = $res * $tmp;
        }
    }
}
# print "\n res \n",$res;
open F,">output.txt" || die; print F $res; close F || die;