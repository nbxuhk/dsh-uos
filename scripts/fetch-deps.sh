#!/bin/sh
# 下载 DSH deb 的全部运行时依赖到 /home/xuhk/dsh-dist/deps/
set -e
OUT=/home/xuhk/dsh-dist/deps
mkdir -p "$OUT"
cd "$OUT"

PKGS="libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 xdg-utils libatspi2.0-0 libuuid1 libsecret-1-0 libappindicator3-1 libayatana-appindicator3-1"

for p in $PKGS; do
  if ls ${p}_*.deb >/dev/null 2>&1; then
    echo "SKIP  $p (已存在)"
    continue
  fi
  echo "GET   $p"
  apt-get download "$p" 2>&1 | tail -2 || echo "  !! $p 下载失败"
done

echo
echo "=== 下载结果 ==="
ls -la "$OUT"/*.deb 2>/dev/null | wc -l
ls -la "$OUT"/*.deb 2>/dev/null
echo
echo "=== 打包体量 ==="
du -sh "$OUT"
