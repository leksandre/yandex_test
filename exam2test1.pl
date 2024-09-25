#! perl -w


@d=(0,923478,54678,11,111,-1,9999,11,'1',1,,1,1);
$_ = join('',@d);
print $_; 
print "\n"; 
s%(?!1)(.)% %ig; 
print $_,"\n"; 
@d = split(' ',$_);

foreach  (@d) {
print $_,"\n";

push (@s,length($_))
}
    
foreach  (@s) {
print $_,"\n";
}

my $max = 0;    
foreach  (@s) {
    $max=$_ if $_>$max;
}
print "\n",$max;
<STDIN>