#!/usr/bin/perl
# Swiftの括弧・文字列・コメントの対応を確かめる簡易チェック。
# 文字列と補間を追いながら {} () [] の対応を数える。
use strict;
use warnings;
use utf8;
binmode(STDOUT, ":encoding(UTF-8)");

my $failures = 0;
my $checked  = 0;

for my $path (@ARGV) {
    open my $fh, '<:encoding(UTF-8)', $path or die "cannot open $path: $!";
    local $/;
    my $src = <$fh>;
    close $fh;
    $checked++;

    my @stack;          # 括弧の種類と行番号
    my $line     = 1;
    my $i        = 0;
    my $len      = length $src;
    my $in_line_comment  = 0;
    my $block_comment    = 0;
    my $in_string        = 0;
    my $multiline_string = 0;
    my @errors;

    while ($i < $len) {
        my $c  = substr($src, $i, 1);
        my $c2 = $i + 1 < $len ? substr($src, $i, 2) : '';
        my $c3 = $i + 2 < $len ? substr($src, $i, 3) : '';

        if ($c eq "\n") {
            $line++;
            $in_line_comment = 0;
            $i++;
            next;
        }
        if ($in_line_comment) { $i++; next; }
        if ($block_comment) {
            if ($c2 eq '*/') { $block_comment--; $i += 2; next; }
            if ($c2 eq '/*') { $block_comment++; $i += 2; next; }
            $i++;
            next;
        }
        if ($in_string) {
            if ($c eq "\\") {
                # 文字列補間 \( ... ) は括弧として数える
                if ($i + 1 < $len && substr($src, $i + 1, 1) eq "(") {
                    push @stack, ["(", $line, $multiline_string ? "interp_multi" : "interp"];
                    $in_string = 0;
                    $multiline_string = 0;
                    $i += 2;
                    next;
                }
                $i += 2;
                next;
            }
            if ($multiline_string) {
                if ($c3 eq '"""') { $in_string = 0; $multiline_string = 0; $i += 3; next; }
            }
            elsif ($c eq '"') { $in_string = 0; $i++; next; }
            $i++;
            next;
        }

        if ($c3 eq '"""') { $in_string = 1; $multiline_string = 1; $i += 3; next; }
        if ($c eq '"')    { $in_string = 1; $i++; next; }
        if ($c2 eq '//')  { $in_line_comment = 1; $i += 2; next; }
        if ($c2 eq '/*')  { $block_comment = 1; $i += 2; next; }

        if ($c =~ /[\{\[\(]/) { push @stack, [$c, $line, 'code']; $i++; next; }
        if ($c =~ /[\}\]\)]/) {
            my %pair = ('}' => '{', ']' => '[', ')' => '(');
            my $top = pop @stack;
            if (!defined $top) {
                push @errors, "line $line: 対応する開き括弧のない '$c'";
            }
            elsif ($top->[0] ne $pair{$c}) {
                push @errors, "line $line: '$c' が line $top->[1] の '$top->[0]' と合わない";
            }
            elsif ($top->[2] =~ /^interp/) {
                # 補間の終わりなので文字列へ戻る
                $in_string = 1;
                $multiline_string = ($top->[2] eq "interp_multi") ? 1 : 0;
            }
            $i++;
            next;
        }
        $i++;
    }

    push @errors, "閉じていない括弧 '" . $_->[0] . "' (line " . $_->[1] . ")" for @stack;
    push @errors, "閉じていない文字列" if $in_string;
    push @errors, "閉じていないブロックコメント" if $block_comment;

    if (@errors) {
        $failures++;
        print "NG $path\n";
        print "   - $_\n" for @errors;
    }
}

if ($failures) {
    print "\nswift structure check: $failures / $checked files failed\n";
    exit 1;
}
print "swift structure check: OK ($checked files)\n";
exit 0;
