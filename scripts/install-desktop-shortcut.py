#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""给 UOS 虚拟机安装 DSH Desktop 桌面快捷方式。

做的事（幂等，可重复跑）：
  1. 校验 /usr/share/applications/dsh-desktop.desktop 存在且 desktop-file-validate 通过
  2. 在 $(xdg-user-dir DESKTOP) 建软链指向上面那个系统 desktop 文件
  3. 打 metadata::trusted 标记（DDE 桌面需要）
  4. 列出桌面目录复核

用法：
  python install-desktop-shortcut.py
环境变量同 vm.py（VM_HOST / VM_USER / VM_PASS / VM_PORT）。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vm import connect, exec_cmd  # noqa: E402

APP_DESKTOP = "/usr/share/applications/dsh-desktop.desktop"

SCRIPT = r'''
set -e
DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
mkdir -p "$DESKTOP_DIR"
echo "DESKTOP_DIR=$DESKTOP_DIR"

# 1. 系统 desktop 文件校验
if [ ! -f "__APP__" ]; then
  echo "FAIL: __APP__ 不存在（DSH Desktop 是否已 dpkg -i 安装？）"
  exit 1
fi
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "__APP__" && echo "OK: desktop 文件校验通过"
fi

# 2. 桌面软链
ln -sfn "__APP__" "$DESKTOP_DIR/dsh-desktop.desktop"
echo "OK: 软链已建 $DESKTOP_DIR/dsh-desktop.desktop -> __APP__"

# 3. 可信标记（DDE 桌面需要，否则可能不渲染/不可双击）
export DISPLAY=:0
if command -v gio >/dev/null 2>&1; then
  gio set "$DESKTOP_DIR/dsh-desktop.desktop" metadata::trusted true 2>/dev/null || true
  gio info "$DESKTOP_DIR/dsh-desktop.desktop" 2>/dev/null | grep -i trusted || echo "WARN: 未读到 trusted 标记"
fi

# 4. 复核
echo "=== 桌面内容 ==="
ls -la "$DESKTOP_DIR"
'''.replace("__APP__", APP_DESKTOP)


def main():
    c = connect()
    try:
        rc, out, err = exec_cmd(c, SCRIPT)
        if out:
            print(out, end="")
        if err:
            print("[stderr]", err, end="", file=sys.stderr)
        return rc
    finally:
        c.close()


if __name__ == "__main__":
    sys.exit(main())
