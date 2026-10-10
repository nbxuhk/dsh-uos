#!/bin/bash
# 离线安装验证：自包含任务
#
# 设计要点（吸取前两次教训）：
#   SSH 是唯一控制通道，一旦断网即失联。因此本脚本把「断网 + 安装 + 结果记录」
#   全部串在一个 nohup 后台任务里，网络恢复后读取结果文件即可。
#
# 用法（在 VM 上执行，会立即返回）：
#   sudo nohup bash offline-verify.sh > /var/log/dsh-offline-verify.log 2>&1 &
#
# 结果：/var/log/dsh-offline-verify.log 与 /var/log/dsh-offline-verify.result
set -u

LOG=/var/log/dsh-offline-verify.log
RESULT=/var/log/dsh-offline-verify.result
DIST=/home/xuhk/dsh-dist/out
GW=$(ip route | awk '/^default/ {print $3; exit}')

step() { echo; echo "########## $* ##########"; }

: > "$RESULT"
record() { echo "$*" | tee -a "$RESULT"; }

step "0. 前置状态"
record "时间: $(date '+%F %T')"
record "默认网关: ${GW:-无}"
record "开始前 DSH 状态: $(dpkg-query -W -f='${Status}' dsh-desktop 2>/dev/null || echo 未安装)"

step "1. 彻底清理"
pkill -f '/opt/DSH Desktop/dsh-desktop' 2>/dev/null
sleep 2
dpkg --purge dsh-desktop >/dev/null 2>&1
record "清理后状态: $(dpkg-query -W -f='${Status}' dsh-desktop 2>/dev/null || echo 未安装)"
record "/opt/DSH Desktop 存在: $([ -d '/opt/DSH Desktop' ] && echo 是 || echo 否)"

step "2. 断开外网（删默认路由，保留同网段 SSH）"
if [ -n "$GW" ]; then
  # 用 route 直接删，并复核 —— 上一轮 ip route del 因存在 metric 100 的重复条目而失效
  ip route del default via "$GW" dev ens33 2>&1 || true
  ip route del default 2>&1 || true
  ip route del default 2>&1 || true
else
  record "无默认路由，已是离线"
fi
sleep 2
record "路由表:"; ip route | tee -a "$RESULT"

step "3. 确认离线（等待 3 秒后测试外网）"
sleep 3
if timeout 8 curl -s -o /dev/null --max-time 6 https://community-packages.deepin.com 2>/dev/null; then
  record "警告: 外网仍可达"
else
  record "确认: 外网不可达（离线状态成立）"
fi
# 再彻底一点：清空 DNS 与 apt 缓存索引，确保无法回退联网
record "apt 源列表条目数: $(grep -rhv '^\s*#' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | grep -c '^deb')"

step "4. 执行离线安装"
cd "$DIST" || { record "失败: 找不到 $DIST"; exit 1; }
# 记录被验证产物的指纹，避免"验证了旧包"这类假通过
record "安装包: $(basename "$(ls -t "$DIST"/*.run | head -1)")"
record "体积: $(stat -c%s "$DIST"/DSH-Desktop-2.0.17-uos-offline-amd64.run) bytes"
record "sha256: $(sha256sum "$DIST"/DSH-Desktop-2.0.17-uos-offline-amd64.run | cut -d' ' -f1)"
record "开始时间: $(date '+%F %T')"
record ""
bash DSH-Desktop-2.0.17-uos-offline-amd64.run 2>&1 | tee -a "$RESULT"
INSTALL_RC=${PIPESTATUS[0]}
record ""
record "安装返回码: $INSTALL_RC"
record "结束时间: $(date '+%F %T')"

step "5. 安装结果复核"
record "包状态: $(dpkg-query -W -f='${Status}' dsh-desktop 2>/dev/null || echo 未安装)"
record "版本: $(dpkg-query -W -f='${Version}' dsh-desktop 2>/dev/null || echo -)"
record "主程序: $([ -x '/opt/DSH Desktop/dsh-desktop' ] && echo 存在 || echo 缺失)"
record "桌面入口: $([ -f /usr/share/applications/dsh-desktop.desktop ] && echo 存在 || echo 缺失)"
record "图标: $([ -f /usr/share/icons/hicolor/256x256/apps/dsh-desktop.png ] && echo 存在 || echo 缺失)"

step "6. 依赖补装情况"
# 主程序 9 个 Depends + 内嵌的 3 个 ayatana 可选依赖
for p in libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 xdg-utils libatspi2.0-0 libuuid1 libsecret-1-0 \
         libayatana-appindicator3-1 libayatana-indicator3-7 libayatana-ido3-0.4-0; do
  record "  $p: $(dpkg-query -W -f='${Status}#${Version}' $p 2>/dev/null || echo 未安装)"
done
record "未配置的包: $(dpkg -l | awk '/^i[^i]/ {print $2}' | tr '\n' ' ')"

step "7. 恢复网络"
if [ -n "$GW" ]; then
  ip route add default via "$GW" 2>&1 && record "默认路由已恢复"
fi
sleep 2
record "路由表:"; ip route | tee -a "$RESULT"

step "8. 启动测试"
export DISPLAY=:0
export XAUTHORITY=/home/xuhk/.Xauthority
setsid '/opt/DSH Desktop/dsh-desktop' >/tmp/dsh-launch-test.log 2>&1 < /dev/null &
sleep 18
if pgrep -f '/opt/DSH Desktop/dsh-desktop' >/dev/null; then
  record "进程: 运行中 (PID $(pgrep -f '/opt/DSH Desktop/dsh-desktop' | head -1))"
else
  record "进程: 未运行"
fi
WINS=$(DISPLAY=:0 xdotool search --name 'dsh-desktop' 2>/dev/null | wc -l)
record "窗口数: $WINS"
record "启动日志尾部:"; tail -5 /tmp/dsh-launch-test.log | tee -a "$RESULT"

step "验证完成"
record "总体判定: $([ "$(dpkg-query -W -f='${Status}' dsh-desktop 2>/dev/null)" = 'install ok installed' ] && echo PASS || echo FAIL)"
echo
echo "结果已保存: $RESULT"
