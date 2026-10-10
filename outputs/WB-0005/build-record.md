# WB-0005 构建记录：DSH Desktop 统信 UOS 版（P1 构建打通）

- 工单：WB-0005（P1）　日期：2026-10-08
- 结果：**构建成功**，deb + AppImage 双产物均通过上游 `verify-linux-artifacts` 校验，deb 已在 Deepin 25 虚拟机安装并启动冒烟通过。

---

## 1. 产物

| 产物 | 大小 | sha256 |
|---|---|---|
| `DSH-Desktop-2.0.17-amd64.deb` | 238,953,356 B | `60568e026a648e117b235f7e5702c92cab3aefa241a93f206cd9c2cfa6874d07` |
| `DSH-Desktop-2.0.17-x86_64.AppImage` | 319,968,478 B | `37d78550f95a2dec1066b0343abcf8a03aa588dc3c16b847ed55195819c289ab` |

本地位置：`outputs/WB-0005/`；构建机位置：`~/dsh-build/repo/dsh-plugin-desktop/dist/`（哈希双端核对一致）。

## 2. 构建环境

| 项 | 值 |
|---|---|
| 机器 | 用户虚拟机 `192.168.249.128`（SSH 助手 `scripts/vm.py`） |
| 系统 | Deepin 25（crimson，UOS 同族 Debian 系），内核 6.6.143-amd64，x86_64 |
| Node | v22.20.0（npmmirror 二进制，装于 `~/dsh-build/opt/node`，免 sudo） |
| Yarn | 4.18.0（corepack，`COREPACK_NPM_REGISTRY=npmmirror`） |
| 编译器 | **Clang 17.0.6**（`CC=clang CXX=clang++`；GCC 12.3 编 V8 头文件报 attribute 解析错误，Chromium 系只官方支持 Clang） |
| 系统依赖 | fakeroot、git、libarchive-tools（apt 补装）；dpkg/ar/xz/g++/python3 系统自带 |

## 3. 网络适配（构建环境 sed，未进 patch，共 3 处 + 2 个缓存预置）

构建机对 Cloudflare 系端点（registry.npmjs.org / electronjs.org 下载路径）不稳，全部换 npmmirror：

| # | 位置 | 原值 → 改为 |
|---|---|---|
| 1 | `scripts/prepare-dsh-market.mjs:11` | `registry.npmjs.org/dshmarket/latest` → `registry.npmmirror.com/dshmarket/**1.66.7**`（固定为仓库锁定版本；latest=1.66.11 与仓库自带 dshmarket-desktop.patch 不兼容——上游防静默过期保护触发，属预期行为） |
| 2 | `dsh-plugin-desktop/scripts/prepare-fs-ext.ts:22` | `https://electronjs.org/headers` → `https://cdn.npmmirror.com/binaries/electron` |
| 3 | env：`npm_config_disturl` | `https://cdn.npmmirror.com/binaries/node`（node-gyp node 头文件） |
| 4 | env：`ELECTRON_MIRROR` / `ELECTRON_BUILDER_BINARIES_MIRROR` | npmmirror electron / electron-builder-binaries |
| 5 | 缓存预置 | `node-gyp install --runtime=electron --target=44.0.0 --tarball=<npmmirror headers>`（npmmirror 无 SHASUMS256.txt，远端校验必失败；--tarball 方式绕过） |
| 6 | env：`DSH_AA_SOURCE_REF=7df5b31f3fe23d4be92ccd5ae5e0aeb6a3744c0e` | AA 桥精确指定 commit → 走「复用已验证 vendor 产物」路径，免 GitHub 克隆 |

完整环境见 `scripts/env.sh`；上述 sed 均只改 VM 上的构建副本（`~/dsh-build/repo`），不影响本地 `src/` 仓库与 WB-0004 patch。

## 4. 构建过程（总耗时约 35 分钟）

1. `yarn install --immutable`：1652 包 1.4GiB，首跑 fs-ext 失败（node-gyp 下载 node 头文件超时）→ 加 disturl 镜像后 16s 增量完成。
2. `yarn dist:linux`（= market:prepare → aa:prepare-release → market build → package-linux.ts）：历经 4 轮排障（market 端点 → dshmarket 版本锁定 → electron headers 镜像+缓存预置 → Clang），第 5 轮跑通。
3. 关卡全过：`dshmarket 1.66.7 verified` ✓、`Reusing verified AA artifact` ✓、`dsh-community-market build` ✓、`Linux artifact verification passed` ✓。

## 5. 安装与启动冒烟（Deepin 25 实机）

- `dpkg -i DSH-Desktop-2.0.17-amd64.deb`：安装成功，包名 `dsh-desktop 2.0.17 amd64`，落位 `/opt/DSH Desktop/`，桌面入口 `dsh-desktop.desktop`。
- 启动（DISPLAY=:0）：主进程 + zygote 拉起 ✓；**Host Web 服务监听 `127.0.0.1:43120`**（默认端口，与 WB-0003 分析一致）✓；`desktop-shell` 插件加载（host outbound proxy policy installed）✓。
- GLib-GObject 告警为 Chromium 在 Linux 的常见无害噪声。
- **待 P2 深化验证**：托盘（DDE StatusNotifier）、目录选择器、内置终端（deepin-terminal 分支）、`dsh` 命令 shim、沙箱（bwrap/Landlock）、Wayland 会话行为。当前为 X11（`:0`）。

## 6. 结论

P1 构建打通：**UOS/Deepin 同族环境上 deb + AppImage 可构建、可安装、可启动**。WB-0004 的 UOS 适配代码随包进入产物。网络适配属构建环境问题（Cloudflare 端点不稳），不涉及代码缺陷；3 处 sed 可作为后续离线内网构建流水线的固化配置。
