use strict; use warnings;
open my $fh, '<:raw', "FutariKakeibo.xcodeproj/project.pbxproj" or die $!;
my $src = do { local $/; <$fh> }; close $fh;
$src =~ s/\r\n/\n/g;

my %fileref;
while ($src =~ /^\t\t(B\d{23}) \/\* (.+?) \*\/ = \{isa = PBXFileReference;.*? path = ([^;]+);/gm) {
    my ($id, $p) = ($1, $3);
    $p =~ s/^"|"$//g;
    $fileref{$id} = $p;
}
my %buildfile;
while ($src =~ /^\t\t(C\d{23}) \/\* .+? \*\/ = \{isa = PBXBuildFile; fileRef = (B\d{23})/gm) {
    $buildfile{$1} = $2;
}

my @errors;
for my $c (sort keys %buildfile) {
    push @errors, "PBXBuildFile $c points to unknown fileRef $buildfile{$c}" unless exists $fileref{$buildfile{$c}};
}
while ($src =~ /^\t\t\t\t(C\d{23}) \/\* (.+?) in Sources \*\/,$/gm) {
    push @errors, "Sources phase references unknown PBXBuildFile $1 ($2)" unless exists $buildfile{$1};
}
while ($src =~ /^\t\t\t\t(B\d{23}) \/\* (.+?) \*\/,$/gm) {
    push @errors, "Group references unknown fileRef $1 ($2)" unless exists $fileref{$1};
}

my %ondisk;
for my $dir ('FutariKakeibo', 'FutariKakeiboTests') {
    my @stack = ($dir);
    while (my $d = shift @stack) {
        opendir(my $dh, $d) or next;
        for my $e (readdir $dh) {
            next if $e eq '.' || $e eq '..';
            my $full = "$d/$e";
            if (-d $full) { push @stack, $full; }
            elsif ($e =~ /\.swift$/) { $ondisk{$full} = 1; }
        }
        closedir $dh;
    }
}

# テストターゲットのファイル参照IDを、グループの children から特定する。
my %test_ids;
if ($src =~ /A00000000000000000000018 \/\* FutariKakeiboTests \*\/ = \{.*?children = \((.*?)\);/s) {
    my $body = $1;
    $test_ids{$1} = 1 while $body =~ /(B\d{23})/g;
}

my %referenced;
for my $id (keys %fileref) {
    my $p = $fileref{$id};
    next unless $p =~ /\.swift$/;
    my $prefix = $test_ids{$id} ? 'FutariKakeiboTests' : 'FutariKakeibo';
    $referenced{"$prefix/$p"} = 1;
}
for my $f (sort keys %ondisk) {
    push @errors, "disk file not in project: $f" unless $referenced{$f};
}
for my $f (sort keys %referenced) {
    push @errors, "project references missing file: $f" unless $ondisk{$f};
}

my $open_b = () = $src =~ /\{/g; my $close_b = () = $src =~ /\}/g;
push @errors, "unbalanced braces: $open_b vs $close_b" unless $open_b == $close_b;
my $open_p = () = $src =~ /\(/g; my $close_p = () = $src =~ /\)/g;
push @errors, "unbalanced parens: $open_p vs $close_p" unless $open_p == $close_p;

if (@errors) { print "NG\n"; print "  - $_\n" for @errors; exit 1; }
printf "project.pbxproj: OK (%d file refs, %d build files, %d swift files on disk)\n",
    scalar(keys %fileref), scalar(keys %buildfile), scalar(keys %ondisk);
