#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用 GitHub Git Data API 把本地仓库推送到远端。

背景：本机 git 走镜像代理（127.0.0.1:17890），该代理只支持 clone/fetch，
push 会挂起；直连 github.com 被网络层重置。但 api.github.com 直连完全正常
（实测 HTTP 200/201），因此改用 REST API 完成推送。

流程（等价于一次 git push）：
  1. 取远端当前 HEAD（可能为空）
  2. 为本仓库所有入库文件创建 blob
  3. 构造 tree（继承远端已有内容，叠加本次文件）
  4. 创建 commit
  5. 更新 refs/heads/main

用法：
  python push-via-api.py [--repo nbxuhk/dsh-uos] [--branch main] [--dry-run]
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# 令牌只从环境变量读取，严禁硬编码（GitHub Secret Scanning 会拦截含令牌的提交）
TOKEN = os.environ.get("GITHUB_TOKEN", "")
API = "https://api.github.com"

if not TOKEN:
    print("错误：未设置 GITHUB_TOKEN 环境变量。", file=sys.stderr)
    print("用法：GITHUB_TOKEN=<your_token> python push-via-api.py", file=sys.stderr)
    sys.exit(2)

# 沙箱代理会干扰，强制直连
PROXY_HANDLER = urllib.request.ProxyHandler({})
OPENER = urllib.request.build_opener(PROXY_HANDLER)


def api(method, path, payload=None, raw=False):
    url = f"{API}{path}"
    data = None
    headers = {
        "Authorization": f"token {TOKEN}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "dsh-uos-push",
    }
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with OPENER.open(req, timeout=120) as resp:
            body = resp.read()
            return resp.status, (body if raw else json.loads(body or b"{}"))
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            parsed = json.loads(body or b"{}")
        except Exception:
            parsed = {"raw": body.decode("utf-8", "replace")[:400]}
        return e.code, parsed


def git(*args):
    r = subprocess.run(["git", "-C", REPO_DIR, *args],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} 失败: {r.stderr.strip()}")
    return r.stdout


def list_tracked():
    """返回 [(相对路径, 绝对路径, blob 模式)]，取自 git 索引（已遵循 .gitignore）。"""
    out = git("ls-files", "-s")
    files = []
    for line in out.splitlines():
        if not line.strip():
            continue
        meta, path = line.split("\t", 1)
        mode = meta.split()[0]
        abspath = os.path.join(REPO_DIR, path)
        if not os.path.isfile(abspath):
            continue
        # git 里 100755 表示可执行
        files.append((path, abspath, "100755" if mode == "100755" else "100644"))
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="nbxuhk/dsh-uos")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--message", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    files = list_tracked()
    print(f"待上传文件: {len(files)} 个")
    total = sum(os.path.getsize(p) for _, p, _ in files)
    print(f"总体积: {total/1048576:.2f} MB")

    if args.dry_run:
        for path, _, mode in files:
            print(f"  {mode}  {path}")
        return 0

    # 1. 远端 HEAD
    base_tree = None
    st, info = api("GET", f"/repos/{args.repo}/git/ref/heads/{args.branch}")
    if st == 200:
        base_sha = info["object"]["sha"]
        st2, commit = api("GET", f"/repos/{args.repo}/git/commits/{base_sha}")
        base_tree = commit["tree"]["sha"]
        parents = [base_sha]
        print(f"远端当前 HEAD: {base_sha[:10]}")
    else:
        parents = []
        print("远端无分支，将创建首个提交")

    # 2. 创建 blobs
    tree_items = []
    for i, (path, abspath, mode) in enumerate(files, 1):
        with open(abspath, "rb") as f:
            content = f.read()
        st, res = api("POST", f"/repos/{args.repo}/git/blobs", {
            "content": base64.b64encode(content).decode("ascii"),
            "encoding": "base64",
        })
        if st not in (200, 201):
            print(f"  !! blob 失败 {path}: {st} {res}")
            return 1
        tree_items.append({"path": path, "mode": mode, "type": "blob", "sha": res["sha"]})
        print(f"  [{i}/{len(files)}] {path}")

    # 3. tree
    tree_payload = {"tree": tree_items}
    if base_tree:
        tree_payload["base_tree"] = base_tree
    st, tree = api("POST", f"/repos/{args.repo}/git/trees", tree_payload)
    if st not in (200, 201):
        print(f"!! tree 创建失败: {st} {tree}")
        return 1
    print(f"tree: {tree['sha'][:10]}")

    # 4. commit
    msg = args.message or git("log", "-1", "--pretty=%B").strip()
    st, commit = api("POST", f"/repos/{args.repo}/git/commits", {
        "message": msg,
        "tree": tree["sha"],
        "parents": parents,
    })
    if st not in (200, 201):
        print(f"!! commit 创建失败: {st} {commit}")
        return 1
    print(f"commit: {commit['sha'][:10]}")

    # 5. 更新 ref
    if parents:
        st, ref = api("PATCH", f"/repos/{args.repo}/git/refs/heads/{args.branch}",
                      {"sha": commit["sha"], "force": False})
    else:
        st, ref = api("POST", f"/repos/{args.repo}/git/refs",
                      {"ref": f"refs/heads/{args.branch}", "sha": commit["sha"]})
    if st not in (200, 201):
        print(f"!! ref 更新失败: {st} {ref}")
        return 1

    print()
    print("推送完成")
    print(f"  提交: https://github.com/{args.repo}/commit/{commit['sha']}")
    print(f"  仓库: https://github.com/{args.repo}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
