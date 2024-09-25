#! perl -w
use warnings;
use Switch;
my $l2=1; my $l3=2; my $l4=3; my $l5=4; my $l6=5;
open F,"+>f3.txt"; close F;
open F,">>f3.txt";
for (my $a1=1;$a1<=34;$a1++){
$r[0]=$a1;
$l2++;$l3++;$l4++;$l5++;$l6++;
for (my $a2=$l2;$a2<=35;$a2++){
if($a2==$r[0]){$a2++}
if($a2<=35){$r[1]=$a2;}

for (my $a3=$l3;$a3<=36;$a3++){
while(($a3==$r[0])or($a3==$r[1])){$a3++}
if($a3<=36){$r[2]=$a3;}

for (my $a4=$l4;$a4<=37;$a4++){
while(($a4==$r[0])or($a4==$r[1])or($a4==$r[2])){$a4++}
if($a4<=37){$r[3]=$a4;}

for (my $a5=$l5;$a5<=38;$a5++){
while(($a5==$r[0])or($a5==$r[1])or($a5==$r[2])or($a5==$r[3])){$a5++}
if($a5<=38){$r[4]=$a5;}

for (my $a6=$l6;$a6<=39;$a6++){
while(($a6==$r[0])or($a6==$r[1])or($a6==$r[2])or($a6==$r[3])or($a6==$r[4])){$a6++}
if($a6<=39){$r[5]=$a6;}

 print F "\n".join(" ",@r); 
}}}}}}
close F;