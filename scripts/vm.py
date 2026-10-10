#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""DSH UOS 构建：虚拟机 SSH 操作助手。

用法：
  python vm.py exec "<shell 命令>"            # 远程执行命令（超时 VM_EXEC_TIMEOUT，默认 600s）
  python vm.py put  <本地路径> <远程路径>      # 上传文件/目录
  python vm.py get  <远程路径> <本地路径>      # 下载文件

凭据必须通过环境变量传入（不设默认值，避免凭据入库）：
  VM_HOST / VM_USER / VM_PASS / VM_PORT
"""
import os
import posixpath
import sys

import paramiko

HOST = os.environ.get("VM_HOST", "")
USER = os.environ.get("VM_USER", "")
PASS = os.environ.get("VM_PASS", "")
PORT = int(os.environ.get("VM_PORT", "22"))

if not HOST or not USER:
    print("错误：需设置 VM_HOST 与 VM_USER 环境变量。", file=sys.stderr)
    print("示例：VM_HOST=192.168.1.10 VM_USER=user VM_PASS=pass python vm.py exec 'hostname'",
          file=sys.stderr)
    sys.exit(2)


def connect():
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, port=PORT, username=USER, password=PASS,
              timeout=20, banner_timeout=20, auth_timeout=20,
              look_for_keys=False, allow_agent=False)
    return c


def exec_cmd(client, cmd, timeout=600):
    timeout = float(os.environ.get("VM_EXEC_TIMEOUT", timeout))
    chan = client.get_transport().open_session()
    chan.settimeout(timeout)
    chan.exec_command(cmd)
    out, err = b"", b""
    while True:
        if chan.recv_ready():
            out += chan.recv(65536)
        if chan.recv_stderr_ready():
            err += chan.recv_stderr(65536)
        if chan.exit_status_ready() and not chan.recv_ready() and not chan.recv_stderr_ready():
            break
    rc = chan.recv_exit_status()
    return rc, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")


def put(sftp, local, remote):
    if os.path.isdir(local):
        try:
            sftp.mkdir(remote)
        except IOError:
            pass
        for name in sorted(os.listdir(local)):
            if name == ".git" or name == "node_modules":
                continue
            put(sftp, os.path.join(local, name), posixpath.join(remote, name))
    else:
        sftp.put(local, remote)
        print(f"  put {local} -> {remote} ({os.path.getsize(local)} bytes)")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    action = sys.argv[1]
    c = connect()
    try:
        if action == "exec":
            rc, out, err = exec_cmd(c, sys.argv[2])
            if out:
                print(out, end="")
            if err:
                print("[stderr]", err, end="", file=sys.stderr)
            return rc
        sftp = c.open_sftp()
        if action == "put":
            put(sftp, sys.argv[2], sys.argv[3])
        elif action == "get":
            sftp.get(sys.argv[2], sys.argv[3])
            print(f"  get {sys.argv[2]} -> {sys.argv[3]}")
        else:
            print("unknown action:", action)
            return 2
        return 0
    finally:
        c.close()


if __name__ == "__main__":
    sys.exit(main())
