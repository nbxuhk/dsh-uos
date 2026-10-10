# DSH Desktop（统信 UOS 版）已知限制清单

- 工单：WB-0004　产出：`outputs/WB-0004/known-limitations.md`
- 基线：`dsh-plugin-desktop` 2.0.17（桌面仓库 HEAD `a1ff68b`）+ 本工单 patch `0001-uos-linux-platform-adaptation.patch`
- 编制日期：2026-10-08

> 本清单只列**已由源码/配置证据支撑**的限制，以及**必须实测才能定论**的未决项。凡未实测的，均标注「需实测」，不作通过性断言。

---

## A. 本轮未完成 / 未验证（工单交付边界）

| # | 限制 | 原因 | 影响 | 后续 |
|---|---|---|---|---|
| A1 | **本轮未产出安装包**（无 deb / AppImage） | 本机为 Windows；`package-linux.ts` 硬性拒绝非 Linux 主机；WSL 被安全策略拦截（`wsl.exe` 命中程序黑名单且不可绕过）；无 Docker；技能 `offline-uos-packaging` 不含任何可 SSH 的远端 Linux/UOS 主机信息 | 无法第一时间交付可安装包 | 需一台 x86_64 UOS/Linux 构建机，按 `build-guide.md` 执行 |
| A2 | **改动未经单元测试实跑** | 两仓库均无 `node_modules`、`.yarn/cache` 为空，无法执行 vitest | 代码只过了 `node --experimental-strip-types --check` 语法校验，未过行为测试 | Linux 机上跑 `yarn vitest run tests/desktop-terminal.spec.ts tests/electron-platform.spec.ts tests/desktop-runtime-environment.spec.ts tests/profile.spec.ts tests/electron-runtime.spec.ts` |
| A3 | **UOS 实机零验证** | 无可用 UOS 环境 | 托盘、Wayland、目录选择器、终端、沙箱均为「设计上成立、未实测」 | P2 阶段 |
| A4 | **离线构建链未打通** | 无 Linux 构建机 | `fs-ext` 的 Electron ABI 编译、Electron/app-builder 缓存命中均未验证 | P1 阶段，见 `build-guide.md` §7 |

---

## B. 功能面限制（有意保留，非缺陷）

| # | 限制 | 说明 | 依据 |
|---|---|---|---|
| B1 | **应用内自动更新不可用** | `LinuxPlatformStrategy.updateDownloadPlatform` 保持 `undefined`。更新服务端 `www.dshdesktop.cn` 只有 `/api/downloads/mac` 与 `/api/downloads/windows` 两个端点，**没有 Linux 端点**；伪造端点即编造。UOS 更新一律走**离线包替换**。 | `src/update-download.ts` 的 `DESKTOP_DOWNLOAD_URLS` 只含 darwin/win32；本工单 patch 在 `src/electron-platform.ts` 补注释说明 |
| B2 | **extended / advanced 外壳模式在 Linux 不可用** | 渲染侧对 linux 强制 `compatibility`，并把这两档置灰、给出「unavailableOnLinux」文案。放开需要先补 Linux 自定义标题栏与窗口材质，属独立 UI 工程量。 | `src/client/DesktopSettingsSection.tsx:754,762`；`src/electron-platform.ts` 的 `canToggleShellMode = false` |
| B3 | **窗口材质固定为 `off`** | Linux 下 `transparent` 会被前端归一为 `off`；`nativeTheme.themeSource` 在 Linux 不设置。 | `src/client/environment.ts:57-60`；`src/electron-runtime.ts:299`、`src/electron-shell-generation.ts:302`（均为 `platform !== 'linux'` 才写 `themeSource`） |
| B4 | **关闭窗口走「最小化」而非「隐藏到托盘」** | 有意保留。Linux 不保证有状态区，隐藏窗口会让应用不可达。 | `src/electron-platform.ts:13-21`（上游注释）、`LinuxPlatformStrategy.hidesWindowOnClose = false` |
| B5 | **无开机自启** | 上游源码中没有任何 `setLoginItemSettings` / `openAtLogin` / `~/.config/autostart` 实现（WB-0003 §2.3 全量检索结论）。本轮未新增。若需求确认，需另做（`~/.config/autostart/dsh-desktop.desktop`）。 | 源码检索；需求待确认 |
| B6 | **LoongArch 不支持** | 已核实桌面仓库与 `.yarnrc.yml` 的 `supportedArchitectures` 只有 `x64`/`arm64`；`package-linux.ts` 显式拒绝非 x64。且 Electron 官方不发布 loongarch64 二进制。 | `scripts/package-linux.ts:107-109`；`.yarnrc.yml:12-18` |
| B7 | **Linux arm64 不产物** | `package-linux.ts` 硬编码 x64；上游 `docs/faq.md` 原文亦为「Linux 暂不提供 arm64 产物」。 | 同上 |
| B8 | **未签名产物** | `package-linux.ts` 主动剥离全部签名变量并以 `CSC_IDENTITY_AUTO_DISCOVERY=false` 打包，产出未签名 AppImage/deb。内网安装需在 UOS 上放行（或自行做仓库签名）。 | `scripts/package-linux.ts:10-15,126,155` |

---

## C. 运行期依赖与风险（需实测）

| # | 限制 / 风险 | 说明 | 缓解 |
|---|---|---|---|
| C1 | **沙箱依赖 bwrap 或 Landlock，二者皆无则命令全部失败关闭** | 上游 Linux 沙箱 runner 链为 `bwrap` → Landlock；链上全部探测失败时 `confine()` 以 `SANDBOX_UNAVAILABLE` **拒绝执行**（不静默放行）。Landlock 需较新内核（Landlock 自 Linux 5.13 起并入主线），UOS 20 系若为 4.19 内核对 Landlock 不可用。 | 目标机安装 `bubblewrap`；或确认内核 ≥5.13。**需实测**：目标 UOS 上跑一条受限命令，确认报告 `enforcement: full` |
| C2 | **AA Bridge 引入 Python + uv 双运行时** | `@agents-anywhere/dsh-bridge-next` 内置 Python Connector，运行时用 `@dataiku/uv` 按 `@dataiku/uv-${process.platform}-${process.arch}` 解析 uv 二进制。离线内网必须把 x64 的 uv 包与 `python-build-standalone` 一并缓存。 | `build-guide.md` 阶段 A 全量缓存；**需实测**镜像内是否存在 `@dataiku/uv-linux-x64` |
| C3 | **托盘可见性取决于 UOS 桌面实现** | 上游注释明确指出 Linux 上 `new Tray()` 会成功，但桌面可能不显示任何状态区。DDE 需支持 StatusNotifier/AppIndicator 才能看到图标。注意：本轮未把「关闭隐藏到托盘」设为默认（B4），所以即使托盘不可见也不会导致应用不可达。 | **需实测**：UOS DDE 下确认托盘图标与菜单可用 |
| C4 | **Wayland 下 AppImage 有渲染崩溃先例** | 参照 Tauri 版先行项目的已知坑（WB-0003 §5.1）：Wayland 下 AppImage 可能崩溃/黑屏。 | 优先分发 deb；必要时设 `GDK_BACKEND=x11`，或 `WEBKIT_DISABLE_COMPOSITING_MODE=1`（后者为 WebKitGTK 专属，Electron 不适用，故 Electron 侧主要靠 deb + X11 兜底）。**需实测** |
| C5 | **打包后的 `dsh` 命令依赖 `--expose-internals`** | 新增的 POSIX shim 与既有 Windows shim 一样以 `ELECTRON_RUN_AS_NODE=1 <electron> --expose-internals <desktop-cli> ...` 形式运行。Electron 大版本升级若移除 `--expose-internals`，shim 会失效。 | 与 Windows/macOS 一致，属既有约束；升级 Electron 时回归 |
| C6 | **终端模拟器依赖 PATH 中存在受支持的模拟器** | 本轮按 `deepin-terminal → x-terminal-emulator → gnome-terminal → konsole/xfce4-terminal/mate-terminal/tilix/alacritty/xterm` 顺序探测。全部缺失时打开终端会给出明确错误（列出已尝试的名字），而不是静默失败。 | UOS 默认自带 `deepin-terminal`；若为精简镜像需补装任一受支持模拟器 |
| C7 | **代理环境变量在 GUI 启动时可能读不到** | 上游已知限制：macOS 与 Linux 上从 Dock/访达启动时不读取 `~/.zshrc`/`~/.bashrc` 内的代理变量（WB-0002 §2.6 引 `docs/faq.md`）。 | 内网若需代理，走系统级代理配置或桌面设置 |

---

## D. 合规与许可

| # | 项 | 状态 |
|---|---|---|
| D1 | MIT 许可与版权声明保留 | `dsh-plugin-desktop` 携带 `LICENSE`（MIT / Copyright (c) 2026 Anywhere Labs）与 `THIRD_PARTY_NOTICES.md`；corepack 打包链路自带 `verify-licenses.mjs` 校验门，本轮**未修改**许可文件，未删除任何版权声明。 |
| D2 | 不修改 DSH 核心包 | 所有改动仅落在桌面外壳层 `dsh-plugin-desktop`，核心 `@deepseek-ai/dsh` 与 `src/deepseek-harness` 工作树未改动。 |
| D3 | 无客户数据出网 | 本清单与全部产出物不含客户名、账号、金额等敏感信息；构建机如需联外网，仅用于拉取公开 npm/Electron 制品，不涉及行内数据。 |
| D4 | 无编造数据 | 全文限制项均有源码/配置文件行号支撑，或明确标注「需实测」「待确认」。 |

---

## E. 与上游既有行为的一致性声明（避免误判为「移植缺陷」）

以下行为在 Windows/macOS 上**同样存在**，不是 Linux 特有缺陷：

1. 安装包**未签名**（macOS 走独立 `release-mac.ts` 签名流程，未纳入本轮）。
2. 自动更新下载需服务端提供对应平台端点；Linux 侧服务端未提供。
3. extended/advanced 需要平台各自的自定义 chrome 实现（macOS/Windows 已各自实现，Linux 未实现）。
4. 打包配置位于 `dsh-plugin-desktop/package.json` 的 `build` 键，而非独立 `electron-builder.yml`。
