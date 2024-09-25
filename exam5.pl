#! perl -w
open F,"input.txt" || die; read F,$m,999000; close F || die;
@d=split("\n",$m);

$d[0] =~ s/^\s+|\s+$//g;
$d[0] =~ s/\h+//g;
$d[0] =~ s/\s+//g;
$d[1] =~ s/^\s+|\s+$//g;
$d[1] =~ s/\h+//g;
$d[1] =~ s/\s+//g;

@a1=split(//,$d[0]);
@a2=split(//,$d[1]);

$res = 0;
$res = 1 if @a1 eq @a2 && @d==2 && @a1>0;

open F,">output.txt" || die; print F $res; close F || die;