#!/bin/sh
# 完整依赖闭包解析：给定一批种子包，递归展开所有未满足的传递依赖。
# 只输出「在当前系统上未安装」的包（已装的无需外带）。
#
# 用法: sh full-closure.sh <包名...>

SEEDS="$*"
[ -z "$SEEDS" ] && { echo "用法: sh full-closure.sh <包名...>"; exit 1; }

is_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# 展开种子自身的依赖（种子可能是未安装的，需要外带）
VISITED=""
QUEUE="$SEEDS"
RESULT=""

for round in 1 2 3 4 5 6 7 8; do
  [ -z "$QUEUE" ] && break
  NEXT=""
  for p in $QUEUE; do
    case " $VISITED " in *" $p "*) continue ;; esac
    VISITED="$VISITED $p"
    # 依赖来自 apt-cache（比读 deb 更方便，能拿到虚拟包解析后的结果）
    deps=$(apt-cache depends --no-recommends --no-suggests --no-conflicts \
             --no-breaks --no-replaces --no-enhances "$p" 2>/dev/null \
           | grep -E '依赖:|Depends:' | sed 's/.*[:：] *//' | sed 's/([^)]*)//g' \
           | grep -v '^<' | tr -d ' ')
    for d in $deps; do
      case " $VISITED " in *" $d "*) continue ;; esac
      NEXT="$NEXT $d"
    done
  done
  QUEUE="$NEXT"
done

echo "=== 闭包全集（含已安装）==="
for p in $VISITED; do
  if is_installed "$p"; then
    echo "  已装   $p"
  else
    echo "  待外带 $p"
  fi
done

echo
echo "=== 需外带的包（不含已安装）==="
NEED=""
for p in $VISITED; do
  if ! is_installed "$p"; then
    # 排除 libc6 等系统核心（绝不该外带）
    case "$p" in
      libc6|libc6-dev|libgcc-s1|base-files|dpkg|apt) echo "  [跳过系统核心] $p"; continue ;;
    esac
    NEED="$NEED $p"
  fi
done
if [ -z "$NEED" ]; then
  echo "  (无)"
else
  echo "$NEED" | tr ' ' '\n' | grep -v '^$' | sort -u
fi
echo
echo "=== 汇总 ==="
echo "需外带包数: $(echo "$NEED" | tr ' ' '\n' | grep -vc '^$')"
