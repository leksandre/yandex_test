#! perl
open F,"input.txt" || die; read F,$m,900000; close F || die;
@d=split("\n",$m); $i=rand(@d);
open F,"+>output.txt" || die; print F $d[--$i]; close F || die;




#! perl -w
@a=split(//,<STDIN>);
@b=split(//,<STDIN>);

sub intersect_arrays {
    my ($a1, $a2) = @_;
    my %seen = map { $_ => 1 } @$a1;
    my @intersection = grep { exists $seen{$_} } @$a2;
    return @intersection;
}

my @res = intersect_arrays(@a, @b);
print "$#{@array}"





