# 统信 UOS 版 DSH Desktop 开发实施方案

- 工单：WB-0004（P1）　产出：`outputs/WB-0004/uos-dev-plan.md`
- 前置：WB-0002（源码就位）、WB-0003（移植差异分析）
- 基线：`anywhere-labs/deepseek-harness-desktop` HEAD `a1ff68b2960753ab1f6c90565bf3d9e3f3b7ae91`（2026-10-03），`dsh-plugin-desktop` **2.0.17**
- 上游核心：`deepseek-ai/deepseek-harness` `dsh-v0.2.1-alpha.1`（HEAD `5badb15`），`vendor/dsh-runtime/0.2.1-alpha.1/` 内置 322 个运行时 tgz
- 许可：MIT（Anywhere Labs / DeepSeek），改造仅落在桌面外壳层 `dsh-plugin-desktop`
- 编制日期：2026-10-08

> **证据规则**：本方案所有「已实现」的代码改动均实际落在 `D:/Workbuddy/DSH统信/src/deepseek-harness-desktop/` 工作树内，并已导出为 `patches/0001-uos-linux-platform-adaptation.patch`（已通过 `git apply --reverse --check` 校验与工作树一致）。所有「需实测」「待确认」项一律标注，未以推测填充。**本轮未执行任何 Linux 构建**（原因见 §6）。

---

## 1. 目标与范围

**目标**：在 x86_64 统信 UOS 上交付可安装、可离线部署的 DSH Desktop，产物形态为 `.deb`（主）+ AppImage（备），并以 MIT 许可保留上游版权声明。

**在范围内**

1. 按 WB-0003 差异清单，把桌面外壳层的 Linux 等价实现补齐（内置终端、目录选择器、`dsh` POSIX shim、打包元数据）。
2. Electron Linux 构建链复用 + UOS 适配叠加。
3. 离线内网可部署方案（依赖全量缓存）。
4. 可安装包 + 构建文档 + 已知限制清单。

**不在范围内（明确排除）**

1. **不修改** `@deepseek-ai/dsh` 核心包及其 `apps/desktop`：核心侧 Linux 沙箱（`dsh-bash-sandbox` / `dsh-sandbox-local`）与 bash 工具链上游已具备，本方案只做「外壳编排」。
2. 不自建自动更新服务端（`dshdesktop.cn` 无 Linux 端点），UOS 走离线包更新。
3. 不承诺 loongarch 产物（见 §5.3 与 known-limitations）。

---

## 2. 架构决策

### 决策 1：复用上游 Linux 构建链，不另造打包器

- **依据（WB-0002 已复核）**：桌面仓库自带 `dist:linux` → `dsh-plugin-desktop/scripts/package-linux.ts`，`electron-builder` 的 `build.linux` 已声明 `AppImage + deb`（x64），脚本头注释即「Build an unsigned Linux x64 AppImage and Debian package on a native Linux host」，且带 `verify-linux-artifacts.ts` 产物校验。
- **决策**：沿用该链路，UOS 适配以「配置叠加 + 外壳代码补丁」形式实现，不替换打包器。
- **被否备选**：从零写 `electron-builder.yml`、或改走 Tauri（WB-0003 §5.1 的 Tauri 版是另一套技术栈，迁移成本与本工单目标不符，仅作经验参照）。

### 决策 2：沙箱「零改造」——沿用上游 Linux 沙箱链

- **依据**：上游 `packages/sandbox/sandbox-local` 在 Linux 的 runner 链为 **`bwrap` → Landlock**（`README.zh.md:71`），无可用 runner 时以 `SANDBOX_UNAVAILABLE` **失败关闭**；上游基础组合 `dsh-base/cordis.patch.yml` 中 `bash-sandbox`/`tool-bash` 在非 Windows 启用、`pwsh-sandbox`/`tool-pwsh` 在非 Windows 禁用。
- **决策**：桌面层现有 win32 条件分支天然跳过 Windows ACL 适配器，**Linux 不需要新增沙箱代码**。
- **风险转嫁为运维前置**：UOS 目标机必须能被上游 runner 链探测到（`bwrap` 已安装，或内核支持 Landlock）。见 known-limitations 第 1 条。

### 决策 3：平台能力开关「按能力放开」，不整体解除 Linux 限制

WB-0003 §2.5 列的 Linux 平台策略有 4 个能力开关。逐项决策：

| 开关 | 原值 | UOS 值 | 决策理由 |
|---|---|---|---|
| `canPickDirectory` | `false` | **`true`** | Electron `dialog.showOpenDialog` 在 Linux 的 X11/Wayland 门户下可用，且上游 `dsh-host-directory-picker-auto` 在 Linux 上依赖 `zenity`/`kdialog` 存在才走 native，否则退化为 in-app browse。改为桌面自带路由可**去掉这个外部二进制依赖**，对离线内网镜像更稳。（patch 已改） |
| `updateDownloadPlatform` | `undefined` | **保持 `undefined`** | `dshdesktop.cn` 只有 `/api/downloads/mac` 与 `/api/downloads/windows` 两个端点，**没有 Linux 端点**。伪造端点属于编造，故保持禁用，UOS 走离线包更新。（patch 仅补注释说明） |
| `canToggleShellMode` | `false` | **保持 `false`** | extended/advanced 需要自定义 chrome 与窗口材质，Linux 前端已强制 `compatibility` 并置灰这两档（`client/DesktopSettingsSection.tsx:754,762`）。放开需要先补 Linux 自定义标题栏，属独立的 UI 工程量，本工单不做。 |
| `hidesWindowOnClose` | `false` | **保持 `false`** | 上游注释已给出正确理由：Linux 桌面不保证有状态区（托盘），隐藏窗口会导致不可达。保持「关闭即最小化」是 UOS 上的正确行为。 |

### 决策 4：内置终端按「POSIX shim 复用 + 平台化 welcome + 终端模拟器探测」实现

- 上游 macOS 分支已经产出纯 POSIX 的 `#!/bin/sh` shim（`dsh` / `pnpm` / `node`）与 bash/zsh rc 注入，Linux 可直接复用；差异只在 **welcome 脚本**（macOS 用 `/usr/bin/open -a Terminal`，Linux 需拉起终端模拟器）与 **默认登录 shell**（macOS 兜底 `/bin/zsh`，UOS 兜底 `/bin/bash`）。
- 终端模拟器按优先级探测 PATH：**`deepin-terminal`（UOS/DDE 默认）→ `x-terminal-emulator`（Debian alternatives）→ `gnome-terminal` → `konsole` / `xfce4-terminal` / `mate-terminal` / `tilix` / `alacritty` / `xterm`**，参数前缀分别 `-e` / `--`。
- **被否备选**：硬编码单一终端（UOS 上可用但移植到麒麟/Ubuntu 会挂）；依赖 `x-terminal-emulator` 单一点（UOS 不一定维护该 alternatives 链接）。

### 决策 5：`dsh` 命令走「内容寻址的 POSIX 生成目录」，与现有 pnpm 运行时同机制

- 上游 `installDesktopDshRuntime` **仅 win32**（非 win32 直接返回 `void 0`），导致 Linux 的 Host 子进程 PATH 里没有 `dsh`。
- 决策：把该函数从「Windows-only」扩为「Windows + POSIX」，复用同仓库已有的 `posixNodeShim`/`posixPnpmShim` 风格与同一套 `installRuntimeGeneration` 内容寻址/原子落盘/可回收 PATH 机制，新增 `posixDshShim`（`#!/bin/sh`，注入 `ELECTRON_RUN_AS_NODE=1` / `DSH_DESKTOP_DEFAULT_PROFILE` / `DSH_HOME`，`--expose-internals` 引导）。
- macOS 保持只走「每终端 shim」，不额外注入 Host PATH（不改变现有 mac 行为）。

### 决策 6：UOS 桌面入口补齐 `StartupWMClass`

- Electron 从根 `desktopName` 推导窗口 `WM_CLASS`；`syncDesktopName: true` 负责把安装项命名对齐。补 `StartupWMClass: dsh-desktop` 与中文 `Comment[zh_CN]` / `GenericName[zh_CN]`，让 DDE/GNOME 能把运行中的窗口绑定到启动项（否则任务栏/图标分组丢失）。属低风险增量配置。

---

## 3. 改造清单（逐项落地状态）

对应 WB-0003 §4 的 15 项改造点。

| # | WB-0003 改造点 | 本轮状态 | 落地位置 |
|---|---|---|---|
| 1 | pwsh 沙箱 → bash 受限执行 | **无需改造**（上游已具备，win32 分支自动跳过） | — |
| 2 | Windows ACL runner / koffi FFI | **无需改造**（仅 win32 路径引用） | — |
| 3 | 内置终端无 Linux 分支 | **已实现** | `src/desktop-terminal.ts`、`src/terminal.ts`、`cordis.patch.yml` |
| 4 | 自动更新无 Linux 端点 | **按离线策略关闭并说明**（不伪造端点） | `src/electron-platform.ts`（注释） |
| 5 | 目录选择器 `canPickDirectory:false` | **已放开** | `src/electron-platform.ts`、`src/index.ts`、`src/client/index.ts`、`src/profile.ts` |
| 6 | 外壳模式 extended/advanced | **保持禁用**（前端已置灰，需独立 UI 工程量） | — |
| 7 | 窗口材质/主题 | **无需改造**（Linux 归一为 `off`，`nativeTheme` 已跳过） | — |
| 8 | 登录 shell 环境捕获 | **无需改造**（上游 zsh/bash/fish POSIX 捕获已支持 Linux） | — |
| 9 | `dsh` 命令注入 PATH | **已实现**（POSIX shim） | `src/desktop-runtime-environment.ts`、`src/main.ts` |
| 10 | 打包形态 AppImage/deb | **已有链路 + 补 UOS 桌面元数据** | `package.json`（`build.linux.desktop.entry`） |
| 11 | 单实例锁 / AppUserModelId | **无需改造**（Linux 不需要 AppUserModelId） | — |
| 12 | AA Bridge / Connector（Python + uv） | **不改代码**，转为离线打包与运维项 | 见 §5.2 |
| 13 | 托盘 | **不改代码**（Electron `Tray` 跨平台），UOS StatusNotifier 支持需实测 | 见 known-limitations 第 4 条 |
| 14 | 开机自启 | **未实现**（源码中上游亦无对应实现） | 见 known-limitations 第 5 条 |
| 15 | 打包/签名/公证配置 | **不需签名**（`package-linux.ts` 明确产出 unsigned 产物） | — |

### 3.1 已落地代码改动明细

patch 文件：`patches/0001-uos-linux-platform-adaptation.patch`（563 行，15 个文件，+266 / −29）

- sha256：`dbf6ff1cdf730b85364dc231f406e0f6b2f9e4a649e14d89dfdda610f888de03`
- 基线提交：`dsh-plugin-desktop` 所在仓库 HEAD `a1ff68b2960753ab1f6c90565bf3d9e3f3b7ae91`
- 施加方式（在桌面仓库根目录，即含 `dsh-plugin-desktop/`、`vendor/` 的目录）：
  `git apply patches/0001-uos-linux-platform-adaptation.patch`（路径前缀为 `a/dsh-plugin-desktop/...`，默认 `-p1` 即可）

**A. 内置终端 Linux 分支**

| 文件 | 改动 |
|---|---|
| `src/desktop-terminal.ts` | `DesktopTerminalPlatform` 增加 `'linux'`；新增 `LINUX_TERMINAL_LAUNCHERS` 优先级表；新增 `linuxWelcome()`（bash 优先、`/bin/bash` 兜底）；新增并导出 `resolveLinuxTerminalLauncher()`（按 PATH 探测 + 明确错误信息）；`prepareDesktopTerminalFiles()` 放开 linux 并复用 POSIX shim，产物 `welcome.sh`；`openDesktopTerminal()` 增加 linux 启动分支 |
| `src/terminal.ts` | 去掉「linux 直接抛错」，改为按 darwin/win32/linux 白名单判定 |
| `cordis.patch.yml` | 移除 `desktop-terminal` 行的 `disabled: !!js process.platform === 'linux'` |

**B. 目录选择器放开**

| 文件 | 改动 |
|---|---|
| `src/electron-platform.ts` | `LinuxPlatformStrategy.canPickDirectory` → `true`（附理由注释） |
| `src/index.ts` | 原生 picker / validator 路由注册条件由 `win32` 扩为 `win32 || linux` |
| `src/client/index.ts` | 渲染侧 picker 桥安装条件同样扩为 `win32 || linux` |
| `src/profile.ts` | profile 组装中「禁用 `directory-picker-auto` + 插入 `directory-picker-browse` 两行」的条件由 `win32` 扩为 `win32 || linux`；**pwsh 沙箱替换仍严格限于 win32** |

**C. `dsh` 命令 POSIX shim**

| 文件 | 改动 |
|---|---|
| `src/desktop-runtime-environment.ts` | 新增 `posixDshShim()`；`installDesktopDshRuntime()` 支持 `darwin`/`linux`（产物 `bin/dsh`，mode `0o700`；Windows 保持 `bin/dsh.cmd`，mode `0o600`） |
| `src/main.ts` | Host 启动时安装 dsh 运行时的平台条件由 `win32` 扩为 `win32 || linux` |

**D. UOS 打包元数据**

| 文件 | 改动 |
|---|---|
| `package.json` | `build.linux.desktop.entry` 增加 `StartupWMClass: dsh-desktop`、中文 `GenericName[zh_CN]` / `Comment[zh_CN]`（**未改动 `build.deb`**，避免破坏既有断言与既有 deb 依赖集） |

**E. 同步更新的单元测试（保证补丁自洽）**

`tests/desktop-terminal.spec.ts`、`tests/electron-platform.spec.ts`、`tests/electron-runtime.spec.ts`、`tests/profile.spec.ts`、`tests/desktop-runtime-environment.spec.ts`。
- 原断言「linux 抛 `terminal is unsupported on linux`」改为对 `freebsd` 断言（保留「非法平台必须拒绝」的语义）；
- 新增：终端模拟器优先级解析、Linux 全链路（shim + `welcome.sh` + 启动 argv）、Linux 卷选择器可用、POSIX dsh shim 内容与权限位。

> 以上改动**未触碰** `@deepseek-ai/dsh` 核心包，符合工单约束「外壳层做适配」。

---

## 4. 构建流水线设计（三阶段）

本机是 Windows 且无法跑 Linux 构建，故流水线按「**有网准备机 → 离线搬运 → UOS/Linux 构建机**」设计。逐条命令见 `build-guide.md`。

```
阶段 A（联网准备机，任意 x86_64 Linux 或 WSL）
  corepack enable && yarn install --immutable
  → 产出：node_modules 全量树 + .yarn/cache（离线镜像）

阶段 B（离线搬运）
  tar 打包 node_modules / .yarn / 源码树 / vendor/  →  介质进内网
  → DSH 核心运行时无需下载：vendor/dsh-runtime/0.2.1-alpha.1/ 已内置 322 个 tgz

阶段 C（UOS 构建机，x86_64，Node 22.19+）
  yarn market:prepare && yarn aa:prepare-release
  yarn dist:linux          # = node scripts/package-linux.ts
  → AppImage + deb + verify-linux-artifacts 校验
```

### 4.1 硬性前置（来自 `package-linux.ts` 的门禁，非推测）

`assertLinuxPackageHost()` 强制要求：

1. **必须原生 Linux 主机**（`platform !== 'linux'` 直接抛错）；
2. **必须 x64 Node**（`arch !== 'x64'` 抛错）；
3. **Node 22.19+ 或 24.x**（含 corepack）；
4. 打包脚本自身以 `CSC_IDENTITY_AUTO_DISCOVERY=false` 剥离全部签名变量，产出**未签名** AppImage + deb。

### 4.2 构建机系统依赖（Electron + electron-builder + deb 打包）

需要 `dpkg`/`fakeroot`（deb 目标）、`libarchive-tools`、常规 X11/GTK 头（Electron 官方 Linux 前置）、`python3`（Node-gyp 备用路径）。UOS 20/21 默认自带 `dpkg` 与 `fakeroot`，其余按 `build-guide.md` 一次性补齐。

---

## 5. 交付形态与分发

### 5.1 产物

| 产物 | 命名（由 `build.linux.artifactName` 决定） | 用途 |
|---|---|---|
| deb | `DSH-Desktop-<version>-x64.deb` | **UOS 首选**（Wayland 下最稳，见 known-limitations 第 3 条） |
| AppImage | `DSH-Desktop-<version>-x64.AppImage` | 内网便携分发备选 |

### 5.2 离线内网需一并打包的增量依赖

| 依赖 | 来源 | 说明 |
|---|---|---|
| 桌面工作区 npm 依赖 | `yarn install` 产出 | 无 `.yarn/cache`（已核实为零），必须先在联网机装好再搬运 |
| DSH 核心运行时 | `vendor/dsh-runtime/0.2.1-alpha.1/*.tgz` | **已内置 322 个 tgz**，无需外网 |
| AA Bridge（`@agents-anywhere/dsh-bridge-next`） | `vendor/agents-anywhere/*.tgz` | 已内置；其 Python Connector 引入 **Python + uv 双运行时**，`uv` 二进制按 `@dataiku/uv-${platform}-${arch}` 解析，x64 需确认对应包在离线镜像内 |
| Electron 预编译体 | electron npm 包的 install 脚本下载 | 离线机需 `ELECTRON_CACHE` 指向预置缓存，或用 `electron-builder` 的 `electronDownload` 指向内网镜像 |

### 5.3 架构

- **x86_64：本工单目标，链路完整。**
- **arm64：上游 Linux 构建脚本硬编码 x64**（`assertLinuxPackageHost` 拒绝非 x64），且 `docs/faq.md` 原文「Linux 暂不提供 arm64 产物」。本工单**不承诺**。
- **loongarch：不支持。** 已核实整个桌面仓库与 `.yarnrc.yml` 的 `supportedArchitectures` 只有 `x64`/`arm64`，且 Electron 官方不发布 loongarch64 二进制。需要另立工单（自编译 Electron 或换壳）。

---

## 6. 本机执行环境核查（为什么本轮没有构建产物）

| 项 | 实测结果 | 影响 |
|---|---|---|
| 本机平台 | Windows 11（`win32`） | `package-linux.ts` 直接拒绝非 Linux 主机 |
| WSL | **被安全策略拦截**：`wsl.exe` 命中程序黑名单，`Permission denied`，且提示「不可批准或绕过」 | 无法用 WSL 充当 Linux 构建机 |
| Docker | `docker: command not found` | 无法用容器交叉打包 |
| 可 SSH 的 Linux/UOS 主机 | 技能 `offline-uos-packaging` 内容为**离线打包方法论**，未包含任何远端主机地址/凭据；本机亦无其他可用远端 | 无可构建的 Linux 主机 |
| 源码依赖 | 两仓库均无 `node_modules`、`.yarn/cache` 为空 | 连本机 typecheck/vitest 都无法执行 |

**因此**：本轮做到「代码改造落地 + patch 可复现 + 构建命令逐条可执行 + 限制明示」，**未产出安装包，也未声称产出**。所有代码改动以源码树内实际 diff 为证，并已用 `git apply --reverse --check` 证明 patch 与工作树一致。

**已做的等价静态校验**（不能替代构建，仅防低级错误）：对 8 个改动源文件与 5 个改动测试文件执行 `node --experimental-strip-types --check`，全部通过；`package.json` / `cordis.patch.yml` JSON/YAML 结构校验通过。

---

## 7. 分阶段计划（后续批次）

| 阶段 | 内容 | 完成判据 | 依赖 |
|---|---|---|---|
| **P0（本轮，已完成）** | 实施方案 + 代码改造 + patch + 构建文档 + 限制清单 | `outputs/WB-0004/` 四类产物齐备，patch 通过 reverse-check | — |
| **P1 构建打通** | 在 x86_64 UOS（或同族 Linux）执行 `build-guide.md` 全流程，产出 deb + AppImage 并过 `verify-linux-artifacts` | deb 在干净 UOS 上 `dpkg -i` 可装、可启动到主界面 | 需一台 Linux 构建机 |
| **P2 运行验证** | UOS 实机验证：托盘、目录选择器、内置终端、`dsh` 命令、沙箱（bwrap/Landlock）、AA Connector | 各项实测通过或给出精确失败签名 | P1 |
| **P3 内网分发** | 离线包组装（node_modules + electron 缓存 + uv/Python）、内网安装验证、`dsh` 更新策略落定（离线替换包） | 断网 UOS 上可完成安装与首启 | P1/P2 |

---

## 8. 验证方法与判据（供复核人使用）

| 验证项 | 方法 | 预期 |
|---|---|---|
| patch 与工作树一致 | `git apply --reverse --check patches/0001-*.patch` | 退出码 0（本轮已通过） |
| patch 可施加于干净基线 | 在 `a1ff68b` 干净检出上 `git apply patches/0001-*.patch` | 无冲突 |
| 未改核心包 | `git -C src/deepseek-harness status --porcelain` | 空 |
| 改动语法可用 | `node --experimental-strip-types --check <file>` | 全部通过（本轮已通过） |
| 单元测试 | Linux 机上 `yarn vitest run tests/desktop-terminal.spec.ts tests/electron-platform.spec.ts tests/desktop-runtime-environment.spec.ts` | 通过（**需 Linux 机，本轮未执行**） |
| 安装包可用 | UOS 上 `dpkg -i` + 启动 | 主界面可用（**P1/P2 待执行**） |

---

## 9. 待确认项（未以推测填充）

| # | 待确认项 | 归属 |
|---|---|---|
| 1 | UOS 目标版本（20/21/最新版）与内核版本 → 决定 Landlock 可用性、bwrap 是否为必需前置 | 客户/环境 |
| 2 | UOS 目标架构（本方案按 x86_64 设计） | 客户/环境 |
| 3 | UOS 桌面环境（DDE 版本）对 Electron `Tray` 的 StatusNotifier/AppIndicator 支持 | 实测（P2） |
| 4 | 离线镜像内是否有 x64 的 `@dataiku/uv-linux-x64` 与 `python-build-standalone` | 环境 |
| 5 | 本轮改动的 linux 分支需在 Linux 上跑 vitest 复验 | P1 |
| 6 | `StartupWMClass` 在 DDE 下的实际分组效果 | 实测（P2） |
| 7 | 是否需要开机自启（`~/.config/autostart/*.desktop`），上游源码无对应实现 | 需求确认 |
