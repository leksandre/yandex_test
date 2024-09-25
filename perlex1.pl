#! perl -w
@d=split(' ',<STDIN>); @r=(0);
foreach (@d) {$r[$_]++}; $m=0;
for ($i=0; $i<@r; $i++) {if ($r[$i]>$m) {$m=$r[$i]; $mn=$i} }
for ($i=0; $i<@d; $i++) {delete $d[$i] if $d[$i]==$mn } 
for ($i=0; $i<$m; $i++) {push (@d,$mn)}
print join(' ',@d); <STDIN>
)