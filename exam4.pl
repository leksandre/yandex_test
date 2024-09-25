#! perl -w
open F,"input.txt" || die; read F,$m,99900000; close F || die;
my $n = $m*1;
my @res;

sub gen {my ($n, $open, $close, $str) = @_;
    if ($n==0) {
        push @res, $str;
        return;
    }
    gen($n - 1, $open + 1, $close, $str . '(') if $open < $n;
    gen($n - 1, $open, $close + 1, $str . ')') if $close < $open;
}

gen(2 * $n, 0, 0, '');
@sres = sort @res;
open F,">output.txt" || die; print F "$_\n" for @sres; close F || die;
