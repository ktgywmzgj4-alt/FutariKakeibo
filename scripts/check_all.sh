#!/usr/bin/env bash
# Macの無い環境でも、CIへ投げる前にここまでは確かめられる。
# 実際にコンパイルするのはCIだけなので、これは「明らかな壊れ」を先に見つけるためのもの。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

files=$(find FutariKakeibo FutariKakeiboTests -name '*.swift' | sort)

perl scripts/check_swift_structure.pl $files
perl scripts/check_swift_escapes.pl $files
perl scripts/check_xcode_project.pl

# アプリのソースから外部への通信先が入り込んでいないか。
if grep -rlE 'https?://' --include='*.swift' FutariKakeibo FutariKakeiboTests >/dev/null 2>&1; then
  echo "NG: Swiftのソースに http/https のURLがあります" >&2
  grep -rnE 'https?://' --include='*.swift' FutariKakeibo FutariKakeiboTests >&2
  exit 1
fi
echo "network URL check: OK"

# 署名まわりのファイルがコミットされていないか。
if git ls-files | grep -qiE '\.(p12|p8|cer|mobileprovision|key)$'; then
  echo "NG: 署名用のファイルがリポジトリに入っています" >&2
  git ls-files | grep -iE '\.(p12|p8|cer|mobileprovision|key)$' >&2
  exit 1
fi
echo "secret file check: OK"

echo
echo "すべて通りました。次はCIでコンパイルとテストを確かめてください。"
