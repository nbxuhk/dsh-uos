#!/usr/bin/env python3
"""沙箱探测：bwrap 功能测试 + Landlock ABI 查询（在 VM 上跑）。"""
import ctypes
import ctypes.util
import subprocess

# 1. bwrap 功能测试：只读绑定根 + 独立 proc/dev，执行 true
try:
    r = subprocess.run(
        ["bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "true"],
        capture_output=True, text=True, timeout=30)
    print("bwrap_functional:", "PASS" if r.returncode == 0 else f"FAIL rc={r.returncode} {r.stderr[:200]}")
except Exception as e:
    print("bwrap_functional: ERROR", e)

# 2. Landlock ABI 版本探测
libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)
libc.syscall.restype = ctypes.c_long
SYS_landlock_create_ruleset = 444  # x86_64
# LANDLOCK_CREATE_RULESET_VERSION = 1
r = libc.syscall(ctypes.c_long(SYS_landlock_create_ruleset),
                 ctypes.c_void_p(0), ctypes.c_size_t(0), ctypes.c_uint(1))
if r >= 0:
    print("landlock_abi:", r)
else:
    eno = ctypes.get_errno()
    print("landlock_abi: unavailable errno=", eno)
