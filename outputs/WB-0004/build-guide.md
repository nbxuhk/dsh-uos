# DSH Desktop · Linux / 统信 UOS 构建命令清单

- 工单：WB-0004　产出：`outputs/WB-0004/build-guide.md`
- 基线：`dsh-plugin-desktop` 2.0.17（桌面仓库 HEAD `a1ff68b`）
- 适用：x86_64 统信 UOS / 同族 Debian 系 Linux
- 编制日期：2026-10-08

> **前提声明**：本清单**未在本机执行过**（本机为 Windows，WSL 被安全策略拦截，无 Docker，无可 SSH 的 Linux 主机，见 `uos-dev-plan.md` §6）。清单中的每条命令均来自对仓库脚本的实际读取（`scripts/package-linux.ts`、根 `package.json`、`dsh-plugin-desktop/package.json`、`.yarnrc.yml`），**不是**经过实机验证的运行记录。凡属推断的步骤均以「**需实测**」标注。

---

## 0. 构建机硬性门禁（来自 `scripts/package-linux.ts:103-118`）

打包脚本 `assertLinuxPackageHost()` 会主动拒绝以下情况，请先自查：

| 门禁 | 要求 | 违反后的报错 |
|---|---|---|
| 主机平台 | **必须是原生 Linux**（`process.platform === 'linux'`） | `Linux artifacts must be built on a native Linux host` |
| Node 架构 | **必须 x64**（`process.arch === 'x64'`） | `Linux artifacts require x64 Node; received <arch>` |
| Node 版本 | **22.19+ 或 24.x**（带 corepack） | `Linux artifacts require Node 22.19+ or Node 24.x with bundled Corepack; received <version>` |

自查命令：

```bash
uname -m                     # 期望 x86_64
node -v                      # 期望 v22.19+ 或 v24.x
corepack -v                  # 期望有输出（0.34.x 量级）
```

---

## 1. 构建机系统依赖（一次性）

```bash
# Debian/UOS 系；UOS 有 zsh/zh 本地化，命令本身不受影响
sudo apt-get update
sudo apt-get install -y \
  build-essential python3 make g++ pkg-config \
  fakeroot dpkg libarchive-tools xz-utils \
  libgtk-3-0 libnss3 libasound2 libgbm1 libxtst6 libxss1 libatspi2.0-0 \
  bubblewrap
```

说明：

- `build-essential python3 make g++`：`scripts/prepare-fs-ext.ts` 会用 `node-gyp rebuild --runtime=electron --target=<electron版本> --dist-url=https://electronjs.org/headers --arch=x64` 编译 `fs-ext@2.1.1` 的 Electron ABI 绑定（源码已核实，非推断）。
- `fakeroot dpkg libarchive-tools`：electron-builder 产出 `.deb` 所需。
- `libgtk-3-0` 等为 Electron 运行/打包期前置。
- `bubblewrap`：**不是构建必需，是运行必需**。上游 Linux 沙箱链为 `bwrap → Landlock`（`packages/sandbox/sandbox-local/README.zh.md:71`），两者都不可用时沙箱会以 `SANDBOX_UNAVAILABLE` 失败关闭。

---

## 2. 阶段 A：在有外网的准备机上产出离线物料

> 目的：把「运行时依赖」全部落到文件系统，供内网构建机零外网使用。

```bash
# A1. 取源码（含 vendored 运行时 tarball）
cd /path/to/work
git clone <桌面仓库地址> deepseek-harness-desktop
cd deepseek-harness-desktop
git checkout a1ff68b2960753ab1f6c90565bf3d9e3f3b7ae91

# A2. 施加 UOS 适配补丁（本工单产出）
git apply /path/to/patches/0001-uos-linux-platform-adaptation.patch

# A3. 启用 corepack 并安装工作区依赖
corepack enable
yarn install --immutable

# A4. 把 Electron / electron-builder / node-gyp 的下载缓存预热到本地
#     （仓库 .yarnrc.yml 为 enableScripts: false，Electron 二进制不在 yarn install 时下载，
#       而是在 electron-builder 打包时下载 —— 因此必须显式预热缓存）
export ELECTRON_CACHE="$PWD/.offline-cache/electron"
export ELECTRON_BUILDER_CACHE="$PWD/.offline-cache/electron-builder"
mkdir -p "$ELECTRON_CACHE" "$ELECTRON_BUILDER_CACHE"
# 触发 Electron 与 app-builder 二进制下载（首次会走网络）
yarn workspace dsh-plugin-desktop exec electron-builder --version

# A5. 预置 node-gyp 的 Electron headers 缓存（供 prepare-fs-ext 离线编译）
#     默认目录为 ~/.node-gyp 或 ~/.electron-gyp；亦可下一步用 npm_config_devdir 显式指定。
#     需实测：确认 fs-ext 的 Electron ABI 编译在无网条件下命中缓存。
ls -la ~/.node-gyp 2>/dev/null || true
ls -la ~/.electron-gyp 2>/dev/null || true

# A6. 打离线物料包
tar -czf /tmp/dsh-offline-materials.tgz \
  node_modules .yarn .offline-cache ~/.node-gyp ~/.electron-gyp \
  vendor patches package.json yarn.lock .yarnrc.yml upstream.json
```

**关于子模块**：`deepseek-harness/` 子模块在浅克隆下为空。经核实 **`dist:linux` 链路不需要它**——它只被根 `upstream:install` / `upstream:build:official` / `upstream:pack:dsh` 使用，而 Linux 打包走的是 `vendor/dsh-runtime/0.2.1-alpha.1/` 中**已内置的 322 个运行时 tgz**（根 `package.json` 的 `resolutions` 对 `0.2.1-alpha.1` 有 642 条 `file:vendor/dsh-runtime/0.2.1-alpha.1/...` 映射）。若确实需要从子模块重建内核，再执行：

```bash
git submodule update --init --recursive
yarn upstream:prepare-runtime   # = upstream:install + upstream:build:official + upstream:pack:dsh
```

---

## 3. 阶段 B：把物料搬运进内网

```bash
# 介质准备（U 盘/内网文件服务），搬运清单：
#   1) dsh-offline-materials.tgz
#   2) 源码树（不含 node_modules 亦可，运行期会用 1) 覆盖）
#   3) 本工单 patches/0001-uos-linux-platform-adaptation.patch
```

在构建机上解包（示例）：

```bash
mkdir -p /opt/dsh-build && cd /opt/dsh-build
tar -xzf /media/usb/dsh-offline-materials.tgz
```

---

## 4. 阶段 C：在 UOS / Linux 构建机上打包

```bash
cd /opt/dsh-build/deepseek-harness-desktop

# C0. 离线环境变量（关键）
export ELECTRON_CACHE=/opt/dsh-build/.offline-cache/electron
export ELECTRON_BUILDER_CACHE=/opt/dsh-build/.offline-cache/electron-builder
export npm_config_devdir=/opt/dsh-build/.node-gyp      # node-gyp / Electron headers 离线目录
export npm_config_offline=true

# C1. 先单独跑一次包门禁，失败信息最清晰（可选）
corepack yarn workspace dsh-plugin-desktop check:linux-package

# C2. 完整打包（一条命令跑完 preflight + 原生依赖 + electron-builder + 产物校验）
corepack yarn dist:linux
```

`dist:linux` 实际展开为（根 `package.json`，已核实）：

```bash
node scripts/prepare-dsh-market.mjs                       # market:prepare
node scripts/prepare-agents-anywhere-release.mjs          # aa:prepare-release
yarn workspace dsh-community-market build
node dsh-plugin-desktop/scripts/package-linux.ts          # ← 真正的打包主体
```

而 `package-linux.ts` 内部还会依次执行（`package-linux.ts:120-163`）：

```bash
# 1) 平台/架构/Node 门禁，并剥离全部签名变量（产出未签名产物）
# 2) 预检包门禁（可用 DSH_PACKAGE_CHECK_ALREADY_RAN=1 跳过）
corepack yarn workspace dsh-plugin-desktop check:linux-package
# 3) 准备 Electron ABI 的 fs-ext 原生绑定
#    （prepareFsExtForElectron({ platform:'linux', arch:'x64' })）
# 4) electron-builder
node <electron-builder/cli.js> --linux AppImage deb --x64 \
  --publish never --config.npmRebuild=false \
  --config.electronFuses.onlyLoadAppFromAsar=false
# 5) 产物校验
node dsh-plugin-desktop/scripts/verify-linux-artifacts.ts
```

### 4.1 只看命令、不跑全流程（调试用）

```bash
# 分离执行，便于定位失败环节
corepack yarn workspace dsh-community-market build
DSH_PACKAGE_CHECK_ALREADY_RAN=1 corepack yarn workspace dsh-plugin-desktop dist:linux
```

### 4.2 若只想产出免安装目录（快速铺开验证）

```bash
corepack yarn package:dir
```

---

## 5. 产物与校验

```bash
# 产物目录（electron-builder 默认输出目录）
ls -lh dsh-plugin-desktop/dist/ | grep -Ei 'DSH-Desktop.*(deb|AppImage)'

# 期望文件名（由 build.linux.artifactName 决定）
#   DSH-Desktop-<version>-x64.deb
#   DSH-Desktop-<version>-x64.AppImage

# 产物校验脚本（ELF 头、AppImage magic、deb 归档头、可执行位）
corepack yarn workspace dsh-plugin-desktop exec node scripts/verify-linux-artifacts.ts

# deb 元信息与桌面入口自查
dpkg-deb -I dsh-plugin-desktop/dist/DSH-Desktop-*-x64.deb
dpkg-deb -c dsh-plugin-desktop/dist/DSH-Desktop-*-x64.deb | grep -E '\.desktop|icons/|/usr/bin/dsh-desktop'
```

期望在 deb 内容里看到（对应本工单的 `package.json` 改动）：

- `/usr/share/applications/dsh-desktop.desktop`（由根 `desktopName: "dsh-desktop.desktop"` + `syncDesktopName: true` 决定）
- desktop 文件中含 `StartupWMClass=dsh-desktop`、中文 `Comment[zh_CN]` / `GenericName[zh_CN]`
- `/usr/bin/dsh-desktop`（`executableName: "dsh-desktop"`）
- hicolor 图标集（`build/icons/` 下 16→1024 共 8 档，已核实存在）

---

## 6. 安装与首启（UOS 实机）

```bash
# 主分发形态：deb
sudo dpkg -i DSH-Desktop-<version>-x64.deb
sudo apt-get -f install -y          # 若提示缺依赖

# 备选形态：AppImage（便携）
chmod +x DSH-Desktop-<version>-x64.AppImage
./DSH-Desktop-<version>-x64.AppImage --no-sandbox   # --no-sandbox 仅在确有需要时使用

# 首启后核对（P2 验证项）
dsh --dump-config                   # 应解析到 Host 注入的 POSIX shim（bin/dsh）
echo $DSH_HOME                      # 期望 ~/.dsh（beta 通道为 ~/.dsh-beta）
```

---

## 7. 排障速查

| 现象 | 排查方向 |
|---|---|
| `Linux artifacts must be built on a native Linux host` | 在 Windows/macOS 上跑了 `package-linux.ts`。必须换 Linux 主机。 |
| `Linux artifacts require x64 Node` | 构建机是 arm64。本方案只支持 x86_64。 |
| `fs-ext` 编译失败 / node-gyp 报下载超时 | 无外网且 headers 缓存未命中。检查 `npm_config_devdir` 指向的目录是否含对应 Electron 版本 headers。**需实测**。 |
| electron-builder 卡在下载 electron / app-builder | `ELECTRON_CACHE` / `ELECTRON_BUILDER_CACHE` 未指向预置缓存。 |
| 打包成功但窗口/任务栏图标异常 | 检查 `StartupWMClass` 与根 `desktopName` 是否一致（均为 `dsh-desktop`）。 |
| 运行期日志出现 `SANDBOX_UNAVAILABLE` | 目标机既无 `bwrap` 也无 Landlock。`sudo apt-get install -y bubblewrap`。 |
| Wayland 下 AppImage 黑屏/崩溃 | 优先改用 deb；或设 `GDK_BACKEND=x11`（见 known-limitations 第 3 条）。 |
| 托盘图标不出现 | UOS 桌面需支持 StatusNotifier/AppIndicator。**需实测**，见 known-limitations 第 4 条。 |

---

## 8. 复现性记录（请构建时补齐）

| 字段 | 值 |
|---|---|
| 构建机发行版 / 内核 | 待填 |
| `node -v` / `corepack -v` | 待填 |
| 补丁 git hash / patch sha256 | 待填 |
| `dist:linux` 退出码 | 待填 |
| deb / AppImage 文件名 + sha256 | 待填 |
| `verify-linux-artifacts` 结果 | 待填 |
| 首启截图 / 关键日志 | 待填 |
