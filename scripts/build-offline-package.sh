#!/bin/bash
# 组装 DSH Desktop UOS 离线一体化安装包
#
# 产出两个文件（都在 /home/xuhk/dsh-dist/out/）：
#   A. DSH-Desktop-2.0.17-uos-amd64.deb   标准 deb，UOS 双击/一条命令安装
#      —— 依赖在 UOS 桌面版均为系统基线（已实测 dpkg --dry-run 通过）
#   B. DSH-Desktop-2.0.17-uos-offline-amd64.run  自解压一体化包，零联网
#      —— 内嵌"系统确实缺失"的依赖，最小化系统也能装
#
# 【内嵌策略 —— 血泪教训，勿改】
#   只内嵌 WHITELIST 里的包。原因：DSH 主程序 9 个 Depends 均无版本约束，
#   UOS 桌面版已自带且健康。若把 libgtk-3-0 / libuuid1 这类系统基线组件一并内嵌，
#   会因内嵌版本高于系统而引发版本倒挂（如内嵌 gtk 3.24.41-1deepin8 要求
#   libgtk-3-common>=1deepin8，而系统只有 1deepin6），连锁导致一堆包无法配置、
#   主程序也装不上。实测踩过一次（见 outputs/WB-0008-offline-verify-r2.txt）。
#
# 用法: bash build-offline-package.sh
set -e

WORK=/home/xuhk/dsh-dist/build
DEPS=/home/xuhk/dsh-dist/deps
MAIN=/home/xuhk/dsh-build/repo/dsh-plugin-desktop/dist/DSH-Desktop-2.0.17-amd64.deb
OUTDIR=/home/xuhk/dsh-dist/out

# 仅内嵌这些"系统缺失"的包（apt 源里由 ayatana 系列替代已废弃的 libappindicator3-1）
WHITELIST="libayatana-appindicator3-1 libayatana-indicator3-7 libayatana-ido3-0.4-0"

rm -rf "$WORK" "$OUTDIR"
mkdir -p "$WORK/payload/deps" "$OUTDIR"

echo "=== 1. 校验输入 ==="
[ -f "$MAIN" ] || { echo "FAIL: 主包不存在 $MAIN"; exit 1; }
echo "主包 : $MAIN ($(stat -c%s "$MAIN") bytes)"

for p in $WHITELIST; do
  f=$(ls "$DEPS"/${p}_*.deb 2>/dev/null | head -1)
  [ -n "$f" ] || { echo "FAIL: 白名单依赖缺失 $p"; exit 1; }
done
echo "内嵌 : $(echo $WHITELIST | wc -w) 个（白名单）"

echo
echo "=== 2. 准备 payload ==="
for p in $WHITELIST; do
  cp "$DEPS"/${p}_*.deb "$WORK/payload/deps/"
done
cp "$MAIN" "$WORK/payload/DSH-Desktop-2.0.17-amd64.deb"
(cd "$WORK/payload/deps" && sha256sum *.deb > "$WORK/payload/deps-SHA256SUMS.txt")
ls -1 "$WORK/payload/deps/"

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

info "检查主程序依赖是否已由系统满足..."
# 主程序 Depends 无版本约束，只要包处于已配置状态即可满足
UNMET=""
for p in $(dpkg-deb -f DSH-Desktop-2.0.17-amd64.deb Depends | tr ',' ' '); do
  p=${p%%|*}; p=$(echo "$p" | tr -d ' ')
  [ -n "$p" ] || continue
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || UNMET="$UNMET $p"
done
if [ -n "$UNMET" ]; then
  warn "系统缺少这些依赖:$UNMET"
  warn "本离线包未内嵌它们（属 UOS 桌面版基线组件，请确认您使用的是完整桌面版）"
else
  info "系统依赖已全部满足"
fi

info "安装可选的托盘依赖（系统缺失时才装）..."
# ayatana 系列是 Recommends 的可选依赖；系统已有同名包时一律跳过，绝不用内嵌版本覆盖系统
INSTALLED_ANY=0
for d in deps/*.deb; do
  pkg=$(dpkg-deb -f "$d" Package 2>/dev/null) || continue
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    info "  跳过已装: $pkg"
    continue
  fi
  info "  安装: $pkg"
  dpkg -i "$d" >/dev/null 2>&1 || true
  INSTALLED_ANY=1
done
[ "$INSTALLED_ANY" = "1" ] && { dpkg --configure -a >/dev/null 2>&1 || true; }

info "安装 DSH Desktop 主程序..."
dpkg -i DSH-Desktop-2.0.17-amd64.deb >/dev/null 2>&1 || true
dpkg --configure -a >/dev/null 2>&1 || true

if dpkg-query -W -f='${Status}' dsh-desktop 2>/dev/null | grep -q "install ok installed"; then
  V=$(dpkg-query -W -f='${Version}' dsh-desktop)
  echo
  info "=========================================="
  info "安装成功  DSH Desktop 版本: $V"
  info "=========================================="
  info "启动方式: 应用菜单搜索「DSH Desktop」/ 桌面快捷方式 / 终端 dsh-desktop"
  echo
else
  echo
  fail "安装失败，请检查上方信息（当前状态: $(dpkg-query -W -f='${Status}' dsh-desktop 2>/dev/null || echo 未安装)）"
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
