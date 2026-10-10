#!/bin/bash
# 组装 DSH Desktop UOS 离线一体化安装包
#
# 产出两个文件（都在 /home/xuhk/dsh-dist/out/）：
#   A. DSH-Desktop-2.0.17-uos-amd64.deb   标准 deb，UOS 双击/一条命令安装
#      —— 依赖在 UOS 桌面版均为系统基线（已实测 dpkg --dry-run 通过）
#   B. DSH-Desktop-2.0.17-uos-offline-amd64.run  自解压一体化包，零联网
#      —— 内嵌 10 个依赖 deb，最小化系统也能装
#
# 用法: bash build-offline-package.sh
set -e

WORK=/home/xuhk/dsh-dist/build
DEPS=/home/xuhk/dsh-dist/deps
MAIN=/home/xuhk/dsh-build/repo/dsh-plugin-desktop/dist/DSH-Desktop-2.0.17-amd64.deb
OUTDIR=/home/xuhk/dsh-dist/out

rm -rf "$WORK" "$OUTDIR"
mkdir -p "$WORK/payload/deps" "$OUTDIR"

echo "=== 1. 校验输入 ==="
[ -f "$MAIN" ] || { echo "FAIL: 主包不存在 $MAIN"; exit 1; }
echo "主包 : $MAIN ($(stat -c%s "$MAIN") bytes)"
echo "依赖 : $(ls -1 "$DEPS"/*.deb | wc -l) 个"

echo
echo "=== 2. 准备 payload ==="
cp "$DEPS"/*.deb "$WORK/payload/deps/"
cp "$MAIN" "$WORK/payload/DSH-Desktop-2.0.17-amd64.deb"
(cd "$DEPS" && sha256sum *.deb > "$WORK/payload/deps-SHA256SUMS.txt")

cat > "$WORK/payload/install.sh" <<'INSTALL_EOF'
#!/bin/bash
# DSH Desktop UOS 离线安装器（零联网）
set -e
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SELF_DIR"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
info() { echo -e "${G}[DSH]${N} $*"; }
warn() { echo -e "${Y}[DSH]${N} $*"; }
fail() { echo -e "${R}[DSH]${N} $*"; exit 1; }

info "DSH Desktop UOS 离线安装程序"

[ "$(dpkg --print-architecture)" = "amd64" ] || fail "本包仅支持 amd64"
if [ "$(id -u)" -ne 0 ]; then
  warn "需要 root 权限，通过 sudo 重新执行..."
  exec sudo -E bash "$0" "$@"
fi

info "校验依赖完整性..."
if [ -f deps-SHA256SUMS.txt ]; then
  (cd deps && sha256sum -c ../deps-SHA256SUMS.txt --quiet) || fail "依赖校验失败，文件可能损坏"
  info "校验通过"
fi

info "安装运行时依赖（已装的自动跳过）..."
MISSING=""
for d in deps/*.deb; do
  pkg=$(dpkg-deb -f "$d" Package 2>/dev/null) || continue
  dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || MISSING="$MISSING $d"
done

if [ -z "$MISSING" ]; then
  info "运行时依赖已全部满足"
else
  info "补装缺失依赖"
  dpkg -i $MISSING || { warn "尝试修复依赖关系..."; apt-get install -f -y --no-download 2>/dev/null || dpkg --configure -a || true; }
fi

info "安装 DSH Desktop 主程序..."
dpkg -i DSH-Desktop-2.0.17-amd64.deb || { warn "尝试修复..."; dpkg --configure -a || true; }

if dpkg-query -W -f='${Status}' dsh-desktop 2>/dev/null | grep -q "install ok installed"; then
  V=$(dpkg-query -W -f='${Version}' dsh-desktop)
  echo
  info "=========================================="
  info "安装成功  DSH Desktop 版本: $V"
  info "=========================================="
  info "启动方式: 应用菜单搜索「DSH Desktop」/ 桌面快捷方式 / 终端 dsh-desktop"
  echo
else
  fail "安装失败，请检查上方信息"
fi
INSTALL_EOF
chmod +x "$WORK/payload/install.sh"

echo
echo "=== 3. 生成自解压一体化包 ==="
OUT="$OUTDIR/DSH-Desktop-2.0.17-uos-offline-amd64.run"
cat > "$OUT" <<'HEADER_EOF'
#!/bin/bash
# DSH Desktop UOS 离线一体化安装包（自解压 + 零联网）
# 用法: sudo bash DSH-Desktop-2.0.17-uos-offline-amd64.run
set -e
PAYLOAD_LINE=$(awk '/^__PAYLOAD_BELOW__$/ {print NR + 1; exit 0; }' "$0")
TMPDIR=$(mktemp -d /tmp/dsh-install.XXXXXX)
trap "rm -rf $TMPDIR" EXIT
tail -n +"$PAYLOAD_LINE" "$0" | tar -xz -C "$TMPDIR"
bash "$TMPDIR/install.sh" "$@"
exit 0
__PAYLOAD_BELOW__
HEADER_EOF
tar -czf - -C "$WORK/payload" . >> "$OUT"
chmod +x "$OUT"

echo
echo "=== 4. 复制标准 deb 到输出目录 ==="
cp "$MAIN" "$OUTDIR/DSH-Desktop-2.0.17-uos-amd64.deb"

echo
echo "=== 5. 校验产物 ==="
for f in "$OUTDIR"/*; do
  SZ=$(stat -c%s "$f")
  printf "%s\n  大小: %s bytes (%.1f MB)\n  sha256: %s\n" \
    "$(basename "$f")" "$SZ" "$(echo "scale=2; $SZ/1048576" | bc)" \
    "$(sha256sum "$f" | cut -d' ' -f1)"
done

echo
echo "=== 6. 校验自解压包结构 ==="
V=$(mktemp -d)
tail -n +$(awk '/^__PAYLOAD_BELOW__$/ {print NR + 1; exit 0; }' "$OUT") "$OUT" | tar -xz -C "$V"
echo "解出内容:"
ls -1 "$V"
echo "内嵌依赖数: $(ls -1 "$V/deps"/*.deb 2>/dev/null | wc -l)"
echo "install.sh 可执行: $([ -x "$V/install.sh" ] && echo yes || echo no)"
rm -rf "$V"
echo
echo "=== 完成 ==="
