#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""创建 GitHub Release 并上传附件（走 api.github.com 直连，绕过镜像代理）。

用法：
  GITHUB_TOKEN=<token> python make-release.py --upload <文件1> [<文件2> ...]
  GITHUB_TOKEN=<token> python make-release.py --info          # 仅查看已有 release
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = os.environ.get("RELEASE_REPO", "nbxuhk/dsh-uos")
TOKEN = os.environ.get("GITHUB_TOKEN", "")
TAG = os.environ.get("RELEASE_TAG", "v2.0.17-uos")
NAME = os.environ.get("RELEASE_NAME", "DSH Desktop 统信 UOS 版 v2.0.17")
API = "https://api.github.com"
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def api(method, path, payload=None, data=None, content_type=None, timeout=180):
    url = path if path.startswith("http") else f"{API}{path}"
    headers = {
        "Authorization": f"token {TOKEN}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "dsh-uos-release",
    }
    body = data
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    elif content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with OPENER.open(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw or b"{}") if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw or b"{}")
        except Exception:
            return e.code, {"raw": raw.decode("utf-8", "replace")[:300]}


def get_or_create_release():
    st, res = api("GET", f"/repos/{REPO}/releases/tags/{TAG}")
    if st == 200:
        print(f"已存在 Release: {TAG} (id={res['id']})")
        return res
    notes_path = os.path.join(PROJECT_DIR, "outputs", "WB-0007", "release-notes.md")
    with open(notes_path, encoding="utf-8") as f:
        body = f.read()
    st, res = api("POST", f"/repos/{REPO}/releases", {
        "tag_name": TAG, "name": NAME, "body": body,
        "draft": False, "prerelease": False,
    })
    if st not in (200, 201):
        print(f"!! Release 创建失败: {st} {res}")
        return None
    print(f"Release 已创建: {TAG} (id={res['id']})")
    print(f"  {res['html_url']}")
    return res


def upload(rel, filepath):
    """分块上传大文件（GitHub 支持 32MB 分块 + Content-Range 续传）。"""
    name = os.path.basename(filepath)
    size = os.path.getsize(filepath)
    print(f"上传 {name} ({size/1048576:.1f} MB) ...")

    # 已存在同名附件则先删
    for a in rel.get("assets", []):
        if a["name"] == name:
            api("DELETE", f"/repos/{REPO}/releases/assets/{a['id']}")
            print("  (替换同名附件)")

    upload_url = (f"https://uploads.github.com/repos/{REPO}/releases/{rel['id']}"
                  f"/assets?name={urllib.parse.quote(name)}")

    CHUNK = 8 * 1024 * 1024  # 8 MB（网络较慢时小块更稳，避免 inactivity timeout）
    headers = {
        "Authorization": f"token {TOKEN}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "dsh-uos-release",
        "Content-Type": "application/octet-stream",
    }

    if size <= CHUNK:
        with open(filepath, "rb") as f:
            data = f.read()
        req = urllib.request.Request(upload_url, data=data, headers=headers, method="POST")
        st, res = _send(req, timeout=900)
    else:
        # 第一块 + 建资产
        with open(filepath, "rb") as f:
            first = f.read(CHUNK)
        h = dict(headers)
        h["Content-Length"] = str(size)
        req = urllib.request.Request(upload_url, data=first, headers=h, method="POST")
        st, res = _send(req, timeout=600)
        if st not in (200, 201):
            print(f"  !! 首块失败: {st} {res}")
            return False

        asset_id = res["id"]
        put_url = f"https://uploads.github.com/repos/{REPO}/releases/assets/{asset_id}"
        offset = CHUNK
        while offset < size:
            with open(filepath, "rb") as f:
                f.seek(offset)
                chunk = f.read(CHUNK)
            end = offset + len(chunk) - 1
            print(f"  续传 {offset/1048576:.0f}–{end/1048576:.0f} MB")
            h = dict(headers)
            h["Content-Range"] = f"{offset}-{end}"
            req = urllib.request.Request(put_url, data=chunk, headers=h, method="PATCH")
            st, res = _send(req, timeout=600)
            if st not in (200, 201):
                print(f"  !! 分块失败 @{offset}: {st} {res}")
                return False
            offset = end + 1

    if st in (200, 201):
        print(f"  OK  {res.get('browser_download_url','')}")
        return True
    print(f"  !! 失败: {st} {res}")
    return False


def _send(req, timeout=600, retries=4):
    """发送请求，失败自动重试（网络抖动/超时常见）。"""
    last = (0, {})
    for attempt in range(1, retries + 1):
        try:
            with OPENER.open(req, timeout=timeout) as r:
                raw = r.read()
                return r.status, (json.loads(raw or b"{}") if raw else {})
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                parsed = json.loads(raw or b"{}")
            except Exception:
                parsed = {"raw": raw.decode("utf-8", "replace")[:300]}
            last = (e.code, parsed)
            # 4xx（除 408/429）不重试
            if 400 <= e.code < 500 and e.code not in (408, 429):
                return last
        except Exception as e:  # 超时、连接重置等
            last = (0, {"error": str(e)})
        if attempt < retries:
            wait = 3 * attempt
            print(f"    (第 {attempt} 次失败，{wait}s 后重试: {str(last[1])[:80]})")
            time.sleep(wait)
    return last


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload", nargs="*", default=[])
    ap.add_argument("--info", action="store_true")
    args = ap.parse_args()

    if not TOKEN:
        print("错误：需设置 GITHUB_TOKEN", file=sys.stderr)
        return 2

    if args.info:
        st, res = api("GET", f"/repos/{REPO}/releases")
        if st != 200:
            print(f"查询失败: {st} {res}")
            return 1
        for r in res:
            print(f"- {r['tag_name']}  {r['name']}")
            for a in r.get("assets", []):
                print(f"    {a['name']}  {a['size']/1048576:.1f} MB  {a['download_count']} 次下载")
        return 0

    rel = get_or_create_release()
    if not rel:
        return 1
    if args.upload:
        ok = all(upload(rel, f) for f in args.upload)
        if not ok:
            return 1
        st, rel = api("GET", f"/repos/{REPO}/releases/{rel['id']}")
        print()
        print("附件列表:")
        for a in rel.get("assets", []):
            print(f"  {a['name']}  {a['size']/1048576:.1f} MB")
        print(f"\nRelease 页面: {rel['html_url']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
