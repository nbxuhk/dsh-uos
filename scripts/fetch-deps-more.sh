#!/bin/sh
# 补齐离线包缺失的依赖（基于 full-closure.sh 的结果）
set -e
OUT=/home/xuhk/dsh-dist/deps
mkdir -p "$OUT"
cd "$OUT"

PKGS="libayatana-appindicator3-1 libayatana-indicator3-7 libayatana-ido3-0.4-0 libdbusmenu-glib4 libdbusmenu-gtk3-4 lsb-base fonts-croscore fonts-dejavu-mono fonts-freefont-otf fonts-freefont-ttf fonts-texgyre"

for p in $PKGS; do
  if ls ${p}_*.deb >/dev/null 2>&1; then
    echo "SKIP  $p"
    continue
  fi
  echo "GET   $p"
  apt-get download "$p" 2>&1 | tail -1 || echo "  !! $p 下载失败"
done

echo
echo "=== 依赖目录现状 ==="
ls -1 "$OUT"/*.deb | wc -l
du -sh "$OUT"
echo
echo "=== 逐个校验 ==="
for f in "$OUT"/*.deb; do
  dpkg-deb -I "$f" >/dev/null 2>&1 && echo "OK   $(basename $f)" || echo "BAD  $(basename $f)"
done
