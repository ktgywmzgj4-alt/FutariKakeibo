#!/usr/bin/env perl
# レシート辞書（FutariKakeibo/Resources/ReceiptDictionary.json）の書き間違いを見つける。
# アプリは読めない項目を捨てて動き続けるので、壊れていても気づきにくい。ここで先に止める。
use strict; use warnings;
use JSON::PP;

my $path = 'FutariKakeibo/Resources/ReceiptDictionary.json';
open my $fh, '<:raw', $path or die "NG: $path を開けません: $!\n";
my $raw = do { local $/; <$fh> }; close $fh;

my $data = eval { JSON::PP->new->utf8->decode($raw) };
die "NG: $path がJSONとして読めません: $@\n" unless $data;

my %categories = map { $_ => 1 } qw(groceries dining household transportation utilities entertainment health beauty travel other);
my @errors;

push @errors, "chains がありません" unless ref $data->{chains} eq 'ARRAY' && @{ $data->{chains} };
my %seen_alias;
for my $chain (@{ $data->{chains} || [] }) {
    my $name = $chain->{name} // '';
    push @errors, "名前の無いチェーンがあります" if $name eq '';
    push @errors, "$name: 種類 '" . ($chain->{category} // '') . "' は使えません" unless $categories{ $chain->{category} // '' };
    push @errors, "$name: 別名がありません" unless ref $chain->{aliases} eq 'ARRAY' && @{ $chain->{aliases} };
    for my $alias (@{ $chain->{aliases} || [] }) {
        my $key = lc $alias;
        $key =~ s/[\s\x{3000}・'’!！\-－.]//g;
        push @errors, "$name: 別名 '$alias' は '$seen_alias{$key}' と重なっています" if $seen_alias{$key} && $seen_alias{$key} ne $name;
        $seen_alias{$key} = $name;
    }
}
for my $entry (@{ $data->{productNames} || [] }) {
    push @errors, "品名の略し方に名前がありません" if ($entry->{name} // '') eq '';
    push @errors, "$entry->{name}: 略し方がありません" unless ref $entry->{aliases} eq 'ARRAY' && @{ $entry->{aliases} };
}
for my $category (keys %{ $data->{productCategories} || {} }) {
    push @errors, "品の種類 '$category' は使えません" unless $categories{$category};
}
push @errors, "通信先（http/https）が入っています" if $raw =~ m{https?://};

if (@errors) {
    print STDERR "NG: $_\n" for @errors;
    exit 1;
}
printf "receipt dictionary: OK (%d chains, %d product names)\n", scalar @{ $data->{chains} }, scalar @{ $data->{productNames} || [] };
