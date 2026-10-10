#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""解析 DSH deb 的完整依赖闭包，并判断哪些在目标系统上已满足。

输出三张表：
  A. 直接 Depends 满足情况
  B. 未满足依赖的完整传递闭包（需要外带的包）
  C. 每个待外带包的体积与来源

用法：python analyze-deps.py <deb路径>
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vm import connect, exec_cmd  # noqa: E402

DEB = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/dsh-build/repo/dsh-plugin-desktop/dist/DSH-Desktop-2.0.17-amd64.deb"
)

REMOTE = r'''
set -u
DEB="__DEB__"

echo "########## 0. 包控制信息 ##########"
dpkg-deb -f "$DEB" Package Version Architecture Depends Recommends 2>/dev/null

echo
echo "########## 1. 直接依赖满足情况 ##########"
DEPS=$(dpkg-deb -f "$DEB" Depends 2>/dev/null | tr ',' '\n' | sed 's/([^)]*)//g' | sed 's/^ *//;s/ *$//' | grep -v '^$')
MISSING=""
for p in $DEPS; do
  v=$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null)
  if [ -n "$v" ]; then
    echo "SATISFIED  $p = $v"
  else
    echo "MISSING    $p"
    MISSING="$MISSING $p"
  fi
done

echo
echo "########## 2. 未满足依赖的传递闭包 ##########"
if [ -z "$MISSING" ]; then
  echo "(无——所有直接依赖已满足)"
else
  echo "待解析种子:$MISSING"
  # apt-rdepends 若可用则用，否则用 apt-cache depends 递归
  if command -v apt-rdepends >/dev/null 2>&1; then
    apt-rdepends $MISSING 2>/dev/null | grep -v '^ ' | sort -u
  else
    # 手工 BFS
    VISITED=""
    QUEUE="$MISSING"
    while [ -n "$QUEUE" ]; do
      NEXT=""
      for p in $QUEUE; do
        case " $VISITED " in *" $p "*) continue ;; esac
        VISITED="$VISITED $p"
        echo "CLOSURE $p"
        for d in $(apt-cache depends --no-recommends --no-suggests --no-conflicts \
                     --no-breaks --no-replaces --no-enhances "$p" 2>/dev/null \
                   | grep -E '^ +Depends:' | sed 's/^ *Depends: *//' | sed 's/([^)]*)//g' | sed 's/<[^>]*>//g'); do
          NEXT="$NEXT $d"
        done
      done
      QUEUE="$NEXT"
    done
  fi
fi

echo
echo "########## 3. 各包体积与可用版本 ##########"
for p in $MISSING; do
  apt-cache show "$p" 2>/dev/null | grep -E '^(Package|Version|Size|Filename):' | head -4
  echo "---"
done
'''

script = REMOTE.replace("__DEB__", DEB)


def main():
    c = connect()
    try:
        rc, out, err = exec_cmd(c, script, timeout=300)
        if out:
            print(out, end="")
        if err:
            print("[stderr]", err, end="", file=sys.stderr)
        return rc
    finally:
        c.close()


if __name__ == "__main__":
    sys.exit(main())
