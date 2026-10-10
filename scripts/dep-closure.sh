#!/bin/sh
# 依赖闭包解析（在 VM 上执行）
DEB="${1:-/home/xuhk/dsh-build/repo/dsh-plugin-desktop/dist/DSH-Desktop-2.0.17-amd64.deb}"

echo "########## 0. 包控制信息 ##########"
dpkg-deb -f "$DEB" Package Version Architecture Depends Recommends

echo
echo "########## 1. 直接依赖满足情况 ##########"
DEPS=$(dpkg-deb -f "$DEB" Depends | tr ',' '\n' | sed 's/([^)]*)//g' | sed 's/^ *//;s/ *$//' | grep -v '^$')
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
  echo "(无 - 所有直接依赖已满足)"
else
  echo "种子:$MISSING"
  VISITED=""
  QUEUE="$MISSING"
  for round in 1 2 3 4 5 6; do
    [ -z "$QUEUE" ] && break
    NEXT=""
    for p in $QUEUE; do
      case " $VISITED " in *" $p "*) continue ;; esac
      VISITED="$VISITED $p"
      echo "CLOSURE $p"
      for d in $(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$p" 2>/dev/null | grep -E '^ +Depends:' | sed 's/^ *Depends: *//' | sed 's/([^)]*)//g' | sed 's/<[^>]*>//g'); do
        NEXT="$NEXT $d"
      done
    done
    QUEUE="$NEXT"
  done
fi

echo
echo "########## 3. Recommends 满足情况 ##########"
REC=$(dpkg-deb -f "$DEB" Recommends | tr ',' '\n' | sed 's/([^)]*)//g' | sed 's/^ *//;s/ *$//' | grep -v '^$')
for p in $REC; do
  v=$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null)
  if [ -n "$v" ]; then echo "REC-OK      $p = $v"; else echo "REC-MISSING $p"; fi
done
