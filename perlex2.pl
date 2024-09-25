#! perl -w
@d=split(//,<STDIN>);
@t=(2,4,10,3,5,9,4,6,8);
$l=@d-2;
if ($l==11){@t=(7,@t); $l-=1}
t: until ($l--==0){$s+=$t[$l] * $d[$l]}
$s%=11; $s%=10;
print '1' if $s==$d[@d-2];
if (@t==10) {@t=(3,@t); $l=11; $s=0; goto t}
<STDIN>