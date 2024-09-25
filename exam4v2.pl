#! perl -w
open F,"input.txt" || die; read F,$m,99900000; close F || die;
my $n = $m*1;
my @res;
sub gen {my ($n, $open, $close, $str) = @_;
    if ((2 * $n)==($open + $close)) {
        push @res, $str;
        return;
    }
    gen($n , $open + 1, $close, $str . '(') if $open < $n;
    gen($n , $open, $close + 1, $str . ')') if $close < $open;
}
gen($n, 0, 0, '');
@sres = sort @res;
open F,">output.txt" || die; print F "$_\n" for @sres; close F || die;
