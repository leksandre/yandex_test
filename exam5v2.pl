#! perl -w
open F,"input.txt" || die; read F,$m,999000; close F || die;
@d=split("\n",$m);
@a1=split(//,$d[0]);
@a2=split(//,$d[1]);

@sa1 = map(ord, sort @a1);
@sa2 = map(ord, sort @a2);

# $s1 = join('',@sa1);
# $s2 = join('',@sa1);
print @a1, "\n";
print @a2, "\n";

print join(", ", @sa1), "\n";
print join(", ", @sa2), "\n";
my $res = 1;
# if (@sa1 eq @sa2){$res = 1};

for my $i (0 .. $#sa1) {
    print "$sa1[$i]==$sa2[$i]","\n",$sa1[$i]==$sa2[$i];
    $tmp = 0;
    $tmp = 1 if $sa1[$i]==$sa2[$i];
    $res = $res * $tmp;
}

print "\n res",$res;
open F,">output.txt" || die; print F $res; close F || die;