#!/usr/bin/perl
# Swiftの通常文字列に無効なエスケープが無いか調べる。
# raw string (#"..."#) の中は対象外。
use strict; use warnings; use utf8;
binmode(STDOUT, ":encoding(UTF-8)");

my %valid = map { $_ => 1 } split //, '0\tnr"\'u(';
my $failures = 0;
my $checked = 0;

for my $path (@ARGV) {
    open my $fh, '<:encoding(UTF-8)', $path or die "cannot open $path: $!";
    local $/; my $src = <$fh>; close $fh;
    $checked++;
    my @errors;
    my $line = 1;
    my $i = 0;
    my $len = length $src;

    while ($i < $len) {
        my $c = substr($src, $i, 1);
        if ($c eq "\n") { $line++; $i++; next; }
        # 行コメント / ブロックコメント
        if (substr($src, $i, 2) eq '//') { $i += 2; $i++ while $i < $len && substr($src, $i, 1) ne "\n"; next; }
        if (substr($src, $i, 2) eq '/*') {
            $i += 2;
            while ($i < $len && substr($src, $i, 2) ne '*/') { $line++ if substr($src,$i,1) eq "\n"; $i++ }
            $i += 2; next;
        }
        # raw string: 直前に # が並んでいれば raw
        if ($c eq '"') {
            my $hashes = 0;
            my $j = $i - 1;
            while ($j >= 0 && substr($src, $j, 1) eq '#') { $hashes++; $j-- }
            my $multi = (substr($src, $i, 3) eq '"""');
            my $close = $multi ? ('"""' . ('#' x $hashes)) : ('"' . ('#' x $hashes));
            $i += $multi ? 3 : 1;
            while ($i < $len) {
                my $ch = substr($src, $i, 1);
                if ($ch eq "\n") { $line++; $i++; next }
                if ($ch eq "\\" && $hashes == 0) {
                    my $next = substr($src, $i + 1, 1);
                    if (defined $next && $next eq "(") {
                        # 文字列補間の中はSwiftのコード。エスケープの規則は当てはまらない。
                        my $depth = 1;
                        $i += 2;
                        while ($i < $len && $depth > 0) {
                            my $k = substr($src, $i, 1);
                            $line++ if $k eq "
";
                            $depth++ if $k eq "(";
                            $depth-- if $k eq ")";
                            $i++;
                        }
                        next;
                    }
                    # 複数行文字列では、行末の backslash は行continuationで正しい書き方。
                    if ($multi && defined $next && $next eq "\n") { $line++; $i += 2; next }
                    unless (defined $next && $valid{$next}) {
                        push @errors, "line $line: 無効なエスケープ backslash-$next";
                    }
                    $i += 2; next;
                }
                if (substr($src, $i, length $close) eq $close) { $i += length $close; last }
                $i++;
            }
            next;
        }
        $i++;
    }

    if (@errors) {
        $failures++;
        print "NG $path\n";
        print "   - $_\n" for @errors;
    }
}
if ($failures) { print "\nswift escape check: $failures / $checked files failed\n"; exit 1 }
print "swift escape check: OK ($checked files)\n";
