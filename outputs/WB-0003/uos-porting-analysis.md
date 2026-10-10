# DSH Desktop UOS 移植分析

> 工单：WB-0003（P1）　产出：`outputs/WB-0003/uos-porting-analysis.md`
> 分析对象：本机官方安装 `D:/Program Files/DSH Desktop`（只读分析，未改动安装目录）
> 版本基线：`dsh-plugin-desktop` **2.0.15**；上游内核 `@deepseek-ai/dsh` **0.1.7-rc.2**；Electron peer **44.0.0**
> 证据规则：本文所有结论均来自实际读取的安装目录文件，关键结论附 `文件路径:行号`。源码中查不到的项一律标注「**源码未体现，待补**」，不作推测。
> 编制日期：2026-10-08

---

## 0. 样本与证据基线

### 0.1 安装形态（重要事实）

| 项 | 实测值 | 证据 |
|---|---|---|
| 安装根 | `D:/Program Files/DSH Desktop/` | 目录列举 |
| 应用代码位置 | **`resources/app/`（解包目录，非 `app.asar`）** | `resources/` 下仅有 `app/`、`app-update.yml`、`elevate.exe`，无 `app.asar` |
| 更新配置 | `resources/app-update.yml` 存在 | 见 §3 |
| 卸载器 | `Uninstall DSH Desktop.exe` | 根目录 |
| 提权助手 | `resources/elevate.exe` | NSIS 安装器特征 |

> 说明：本机这一构建把应用以**解包目录** `resources/app/` 分发（未打 `app.asar`）。但代码内部仍保留完整 asar 处理逻辑（`lib/asar-archive-policy-*.js`、`lib/packaged-runtime-path-*.js`、多处 `app.asar` → `app.asar.unpacked` 路径替换，如 `lib/profile-B8k_aHEa.js:1022`、`lib/packaged-runtime-smoke.js:58`）。移植时不应假设「一定无 asar」，需按打包配置确认。

### 0.2 核心清单（`resources/app/package.json`）

- `name: dsh-plugin-desktop`，`version: 2.0.15`，`type: module`，`main: lib/main.js`
- **桌面即 Cordis 插件**：`dsh.bundle.patch: ./cordis.patch.yml`；`dsh.client.platform: web`，`dsh.client.inject` 注入 7 个 `@deepseek-ai/dsh-client-ui-*` 客户端包
- `bin`: `dsh-desktop` / `dsh-plugin-desktop` → `lib/bin.js`
- 子能力导出（各自的 Cordis 插件入口）：`./webserver`、`./windows-pwsh-sandbox`、`./terminal`、`./pnpm`、`./profile-service`、`./desktop-plugins`、`./profiles`、`./diagnostics`、`./notifications`、`./updates`
- 关键依赖：`@deepseek-ai/dsh@0.1.7-rc.2`、`@agents-anywhere/dsh-bridge-next`（`file:../vendor/...tgz`）、`koffi@3.1.5`（Win32 FFI）、`pnpm@11.8.0`、`selfsigned@5.5.0`、`adm-zip`、`fs-ext`、`semver`、`yaml`
- `peerDependencies.electron: 44.0.0`；`engines.node: ^22.19.0 || >=24.0.0`

---

## 1. 架构

### 1.1 进程与职责分层

```
┌──────────────────────────────────────────────────────────────┐
│ Electron 主进程  lib/main.js                                   │
│  · 单实例锁、crashReporter、生命周期、启动恢复窗口              │
│  · 生成 native shell generation（BrowserWindow / Tray / 菜单）  │
│  · utilityProcess.fork(host-process-entry.js) → DSH Host        │
└───────────────┬──────────────────────────────────────────────┘
                │ utilityProcess（stdio pipe + postMessage RPC）
┌───────────────▼──────────────────────────────────────────────┐
│ DSH Host（独立 Utility Process）lib/host-process-entry.js       │
│  · 不 import 任何 Electron API                                 │
│  · boot() 挂载上游 Cordis 插件树 + 桌面侧服务                   │
│  · 提供 desktopRuntime / desktopBrowserAccess / desktopLanHttps │
│  · 承载上游 Web 服务器（loopback HTTP）+ LAN HTTPS 边缘          │
└───────────────┬──────────────────────────────────────────────┘
                │ 子进程（ELECTRON_RUN_AS_NODE=1 + Electron 可执行体）
┌───────────────▼──────────────────────────────────────────────┐
│ pnpm / dsh CLI / 终端 / 沙箱 runner 等短生命周期子进程           │
└──────────────────────────────────────────────────────────────┘
                ▲
                │ http://127.0.0.1:<port>/
┌───────────────┴──────────────────────────────────────────────┐
│ 渲染进程 BrowserWindow（加载上游 Web UI）                       │
│  + native-ui（原生对话框/Setup 向导/恢复页，独立 HTML）          │
└──────────────────────────────────────────────────────────────┘
```

**证据**

- 主进程 fork Host：`lib/main.js:73`（`utilityProcess.fork(fileURLToPath(new URL("./host-process-entry.js", ...)))`）
- Host 入口不引 Electron：`lib/host-process-entry.js:210`（注释「No BrowserWindow or Electron main APIs are imported here」）；`:212` 校验 `process.parentPort`
- Host 内 boot 上游插件树：`lib/host-process-entry.js:67`（`await boot(DESKTOP_PACKAGE_NAME, prepared.rootConfig, prepared.patches, ...)`）
- 服务注入：`lib/host-process-entry.js:77-80`（`desktopBrowserAccess` / `desktopLanHttps` / `desktopRuntime` / `desktopPnpmBootstrap`）
- 渲染进程 URL：`lib/index.js:271-279`（`http://127.0.0.1:${port}/`，带 `dsh-desktop-mode/platform/version/material` 查询参数）
- native-ui 资产：`resources/app/lib/native-ui/`（`compatibility-chrome.html`、`desktop-dialog.html`、`profile-create.html`、`profile-selector.html`、`recovery.html`、`setup-wizard.html`）

### 1.2 「desktop 本身作为插件」的挂接方式

`dsh-plugin-desktop` 以**上游 bundle 之上的一层补丁**接入，而不是替换上游：

`resources/app/cordis.patch.yml`
```yaml
- insert:
    - id: desktop-shell        name: dsh-plugin-desktop            config: {mode: compatibility}
    - id: desktop-terminal     name: dsh-plugin-desktop/terminal   disabled: !!js process.platform === 'linux'
    - id: desktop-diagnostics  name: dsh-plugin-desktop/diagnostics
    - id: desktop-notifications name: dsh-plugin-desktop/notifications
    - id: desktop-pnpm         name: dsh-plugin-desktop/pnpm
    - id: desktop-profiles     name: dsh-plugin-desktop/profiles
    - id: desktop-updates      name: dsh-plugin-desktop/updates
- id: web-runtime
  config: {openBrowser: false, printUrl: false, surfaceContext: true, trustedHosts: []}
```

- 插件名 `desktop-shell`、注入依赖清单：`lib/index.js:242-251`（`inject: ["webServer","webRuntime","appExit","settings","connection"]`）
- `desktopRuntime` 是**探测而非必需**：`lib/index.js:286-290`（缺失时打印「requires the desktop launcher (desktopRuntime)」并返回，即普通 DSH boot 下桌面行静默失效）
- 三种外壳模式：`compatibility`（默认，保留上游浏览器载体）/ `extended` / `advanced`（`lib/settings-bridge-CKOtrHLn.js:400-404`）

> **关键点**：桌面外壳以「Web 载体的宿主操作层」身份插入，上游 Web UI 与插件系统保持**未改动**。这对移植非常有利——桌面层是可剥离、可替换的壳。

### 1.3 端口分配机制（对应任务重点项）

| 端口 | 分配方式 | 证据 |
|---|---|---|
| 主 Web 端口 | 默认固定 **43120**，可在设置中改为 `0..65535`；`0` 即交操作系统分配 | 常量 `lib/desktop-port-DWrq-_UM.js:4`；默认值 `lib/settings-bridge-CKOtrHLn.js:388`；schema 允许 `min(0)` `:388` |
| 主 Web 端口传递 | Host 启动时以命令行注入：`provideCmdline(ctx, {args:["--port", String(prepared.port)]})` | `lib/host-process-entry.js:191-194` |
| 实际绑定 | 上游 `dsh-host-webserver` 绑定 `config.port`；`config.port=0` 时读回 OS 分配值 | `node_modules/@deepseek-ai/dsh-host-webserver/lib/index.js:143,163-164,297,302` |
| LAN HTTPS 边缘端口 | **恒为 `requestedPort: 0`（系统分配）** | `lib/host-process-entry.js:263`、`lib/main.js:4605`；落位读回 `lib/lan-https-runtime-6lVFk32q.js:241-245` |
| Web 绑定地址 | `loopback` → `127.0.0.1`；`lan` → 由 `desktopWebServerHost(networkExposure)` 决定 | `lib/index.js:298`、`lib/settings-bridge-CKOtrHLn.js`、默认 `networkExposure: "loopback"`（`settings-bridge:390`） |

> 结论：任务描述中「v0.2.1 已改系统分配端口」在**本样本**中体现为：主 Web 端口默认仍是固定 43120（可配 0），**LAN HTTPS 边缘恒定走系统分配端口**（`requestedPort: 0`）。主端口是否已默认改为系统分配，源码未体现，待补。

---

## 2. 平台绑定点清单（重点）

下表逐项列出与 Windows 强绑定的实现点。E = 证据（`file:line`）。

### 2.1 Windows PowerShell 沙箱（最高优先级绑定点）

| 项 | 说明 | 证据 |
|---|---|---|
| 桌面适配器 | `DecoratorWindowsPwshSandbox` 继承上游 `@deepseek-ai/dsh-pwsh-sandbox` 的 `SandboxPwshExecutor` | `lib/windows-pwsh-sandbox.js:79` |
| pwsh 可执行体探测 | **仅 win32**：先在 `ProgramFiles\PowerShell\7\pwsh.exe`，再退到 `SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe` | `lib/windows-pwsh-sandbox.js:11-16` |
| 只在 Windows+Electron 生效 | `adaptWindowsAclExecution` 首行即 `if (adaptation.platform !== "win32" \|\| !adaptation.electron ...) return {spec, argv}` | `lib/windows-pwsh-sandbox.js:58` |
| ACL runner 蹦床 | 用 Electron 可执行体以 `ELECTRON_RUN_AS_NODE=1` 拉起 `windows-acl-runner.js`，再 import 上游 `@deepseek-ai/dsh-sandbox-windows-acl/runner` | `lib/windows-pwsh-sandbox.js:7,56-77`；`lib/windows-acl-runner.js:42-54` |
| Win32 控制台 | 用 `koffi` 载入 `kernel32.dll`/`user32.dll`，`AllocConsole` + `ShowWindow(SW_HIDE)` | `lib/windows-acl-runner.js:6-16,25-32` |
| 行替换时机 | Windows profile 组装时把上游 `pwsh-sandbox` 行替换为 `dsh-plugin-desktop/windows-pwsh-sandbox`（**仅 `platform === "win32"` 分支**） | `lib/profile-B8k_aHEa.js:1083,1096-1107` |
| 底座平台门 | 上游基础包中 pwsh 沙箱行本身就是 `disabled: !!js process.platform !== 'win32'` | `node_modules/@deepseek-ai/dsh-base/cordis.patch.yml:240-242` |

### 2.2 Windows 路径 / 数据目录 / 环境

| 项 | 绑定内容 | 证据 |
|---|---|---|
| Electron userData | `%APPDATA%\DSH Desktop`；macOS 为 `~/Library/Application Support/...`；其余（Linux）为 `$XDG_CONFIG_HOME` 或 `~/.config/DSH Desktop` | `lib/bin.js:175-185` |
| Harness home | `.dsh`（beta 版 `.dsh-beta`） | `lib/bin.js:108,115` |
| PATH 分隔符/大小写 | win32 用 `;` 且键名不区分大小写（`key.toUpperCase() === "PATH"`） | `lib/desktop-runtime-environment-BCd9iEvr.js:336-361`；`lib/main.js:2758-2761` |
| 生成 shim | Windows 生成 `.cmd`（含 `chcp 65001` 代码页前导/尾随），POSIX 生成 `#!/bin/sh` | `lib/desktop-runtime-environment-BCd9iEvr.js:223-333` |
| 已生成的 `dsh` 命令 | **`installDesktopDshRuntime` 仅 win32**，产出 `bin/dsh.cmd`；非 win32 直接返回 `void 0` | `lib/desktop-runtime-environment-BCd9iEvr.js:384-385`；`lib/main.js:4556-4564` |
| pnpm 运行时 | 支持 darwin/linux/win32（有 posix shim：`posixPnpmShim`/`posixNodeShim`） | `lib/desktop-runtime-environment-BCd9iEvr.js:411-412,234-266` |
| 打包后 cwd 修正 | `app.isPackaged && process.cwd() === "/"` 时 chdir 到 home（**POSIX 专用判断**） | `lib/main.js:3978` |

### 2.3 注册表 / 自启动 / 登录项

- **源码未体现**：全量检索 `lib/` 未发现 `setLoginItemSettings`、`getLoginItemSettings`、`openAtLogin`、`shell:startup`、`.lnk`、开机自启/自启相关实现。
- 唯一与注册表相关的表述是**代理探测交还给 Chromium**（Chromium 自己读 Windows 注册表 / macOS 网络偏好），桌面代码不直接读写注册表：`lib/main.js:3582`（注释）。
- 「手机连接/远程控制」相关提示文案存在（`lib/electron-runtime-Bq738q05.js:26`），但无对应系统自启/注册表写入实现。
- **待补**：Windows 开机自启、NSIS 快捷方式/注册表项，应在打包配置或安装器脚本中，**不在安装包内**。

### 2.4 自动更新通道

| 项 | 内容 | 证据 |
|---|---|---|
| 更新源文件 | `app-update.yml`：`provider: github`、`owner: anywhere-labs`、`repo: deepseek-harness-desktop`、`updaterCacheDirName: dsh-plugin-desktop-updater` | `resources/app-update.yml` |
| 版本探测端点 | `https://www.dshdesktop.cn/api/desktop/version`（带 `X-DSH-Desktop-Version`/`-Channel`/`-Installation-Id` 头） | `lib/update-checker-D_YsqGce.js:8,113,115-117` |
| 下载端点 | `darwin: /api/downloads/mac`、`win32: /api/downloads/windows`（**无 linux**） | `lib/update-download-gLk3DU6C.js:9-11` |
| 平台限制 | 下载/安装仅 darwin/win32；其他平台直接返回 | `lib/update-download-gLk3DU6C.js:192`；`lib/electron-runtime-Bq738q05.js:3922,3951` |
| 制品校验 | SHA256 校验、原子落盘、保留期清理 | `lib/update-download-gLk3DU6C.js:120-138`；`lib/electron-runtime-Bq738q05.js:3869-3877` |
| 安装方式 | Windows：spawn NSIS 安装器 `["--updated","--force-run"]` 后退出；macOS：`shell.openPath(.dmg)` | `lib/electron-runtime-Bq738q05.js:3872,3889-3919,3968-3994` |
| 通道 | `stable` / `beta` / `next`；文件名 `DSH-Desktop-<ver>-windows.exe` / `-mac.dmg` | `lib/update-download-gLk3DU6C.js:140-144` |
| **Linux** | `LinuxPlatformStrategy.updateDownloadPlatform = void 0` → 更新不可用 | `lib/electron-runtime-Bq738q05.js:2509-2518,3865` |

### 2.5 系统托盘 / 终端 / 窗口外壳

| 项 | 绑定内容 | 证据 |
|---|---|---|
| 托盘 | `new Tray(prepareTrayIcon(...))`；macOS 用模板图并 `setTemplateImage(true)`，其余用蓝色品牌图 | `lib/electron-runtime-Bq738q05.js:2041-2045,962-982` |
| 托盘项注册 | 桌面运行时的通用能力 `registerTrayItem`，被 terminal/diagnostics/updates/profiles 复用 | `lib/electron-runtime-Bq738q05.js:3521`；`lib/terminal.js:13-21`；`lib/updates.js:37-43` |
| 内置终端（TUI） | **只支持 macOS/Windows**：`prepareDesktopTerminalFiles` 在非 darwin/win32 抛错；`terminal.js` 对 linux 直接抛错；cordis patch 中该行 `disabled: !!js platform === 'linux'` | `lib/desktop-terminal-CSXxo5CR.js:289,338`；`lib/terminal.js:12`；`resources/app/cordis.patch.yml:8` |
| 终端 shim | macOS 生成 `dsh`/`pnpm`/`node` + `.zshrc`/`bashrc`/`welcome.command`；Windows 生成 `.cmd`/`welcome.ps1`/`welcome.cmd` | `lib/desktop-terminal-CSXxo5CR.js:304-337` |
| 窗口外壳 | 平台策略：`WindowsPlatformStrategy` / `MacPlatformStrategy` / `LinuxPlatformStrategy` | `lib/electron-runtime-Bq738q05.js:2477-2525` |
| Linux 外壳能力 | `canPickDirectory:false`、`canToggleShellMode:false`、`hidesWindowOnClose:false`、`updateDownloadPlatform:undefined`，`configureWindow` 为空 | `lib/electron-runtime-Bq738q05.js:2509-2518` |
| Linux 强制兼容模式 | 前端把 linux 的 mode 强制为 `compatibility`；UI 上 extended/advanced 置灰并给出「unavailableOnLinux」文案 | `lib/client.js:10554,10671-10704,12808-12820` |
| 自定义 chrome | macOS/Windows 走自定义标题栏；Linux 走原生 fallback | `lib/electron-runtime-Bq738q05.js:457-520` |
| 主题源 | 非 linux 才设置 `nativeTheme.themeSource` | `lib/electron-runtime-Bq738q05.js:1726`；`lib/index.js:444-446` |
| 渲染进程隔离 | `isolated = mode !== "advanced" && platform !== "linux"` | `lib/electron-runtime-Bq738q05.js:1741` |
| AppUserModelId | **仅 win32** 调用 `app.setAppUserModelId` | `lib/main.js:3977` |
| 窗口闪烁提醒 | win32 用 `flashFrame(true)` | `lib/electron-runtime-Bq738q05.js:2199,2253` |

### 2.6 登录 Shell 环境捕获（Linux 已具备）

- `resolveDesktopShellEnvironment` 明确支持 `linux`：非打包回退、win32 回退、`darwin|linux` 走「捕获登录 shell 导出的环境」。仅捕获白名单键（`PATH` + 一组工具链变量）。使用 **POSIX 语义**（`/usr/bin/printf`、`/usr/bin/env -0`、`zsh -ilc` / `bash -ilc` / `fish --login --interactive --command`）。
- 证据：`lib/main.js:330-340`（支持的 shell）、`:423-430`（POSIX 捕获命令）、`:550-578`（`platform === "linux"` 支持）。
- **含义**：Linux 下的「GUI 应用 PATH 不含用户 shell 环境」问题，桌面层**已经解决**，UOS 上可直接复用。

### 2.7 目录选择器 / 工作区

- 上游目录选择器在 win32 上被替换为「browse 后端 + browse 表面」两行；**仅 win32 分支**：`lib/profile-B8k_aHEa.js:1083-1095`。
- 桌面仅注册 native 目录选择器路由（`DESKTOP_DIRECTORY_PICKER_PATH` / `DESKTOP_DIRECTORY_VALIDATOR_PATH`）在 win32：`lib/index.js:378-399`。
- 前端 native picker 桥也仅 win32：`lib/client.js:15268`。
- 与 `LinuxPlatformStrategy.canPickDirectory = false`（`electron-runtime:2512`）一致。

### 2.8 上游基础包中的平台门（对移植的直接影响）

`resources/app/node_modules/@deepseek-ai/dsh-base/cordis.patch.yml`（基础组合包，全平台共享）：

| 行 | 包 | 平台门 | 行号 |
|---|---|---|---|
| `bash-sandbox` | `@deepseek-ai/dsh-bash-sandbox` | `disabled: !!js process.platform === 'win32'`（**非 Windows 启用**） | `:234-238` |
| `pwsh-sandbox` | `@deepseek-ai/dsh-pwsh-sandbox` | `disabled: !!js process.platform !== 'win32'` | `:240-242` |
| `tool-bash` | `@deepseek-ai/dsh-tool-bash` | `disabled: !!js process.platform === 'win32'` | `:266-268` |
| `tool-pwsh` | `@deepseek-ai/dsh-tool-pwsh` | `disabled: !!js process.platform !== 'win32'` | `:270-272` |
| `deepseek-account` | `.../platform` | `desktopPlatform` 仅 `['darwin','win32']` 时非 null | `:112-115` |

> **极其重要的移植利好**：上游 DSH **已内置 Linux 侧沙箱与 bash 工具链**（`bash-sandbox` + `tool-bash` 在非 Windows 启用）。桌面层需要改的只是「把 Windows 专属适配器换成使用现成 bash 沙箱」的**编排层**，而不是从零造沙箱。

---

## 3. 打包链

### 3.1 结论：electron-builder（NSIS + DMG）

| 证据 | 内容 |
|---|---|
| `resources/app-update.yml` | `provider: github` + `owner/repo` + `updaterCacheDirName` → 标准 **electron-builder** 生成物 |
| `lib/bin.js:118-119` | 注释明确：「Stable release-channel identities that must stay aligned with **electron-builder**」 |
| `lib/bin.js:102-125` | 稳定版 `appId: ai.deepseek.dsh.desktop`、beta 版 `ai.deepseek.dsh.desktop.beta`；产品名 `DSH Desktop` / `DSH Desktop Beta` |
| 根目录 `Uninstall DSH Desktop.exe` + `resources/elevate.exe` | **NSIS** 安装器特征（卸载器 + 提权助手） |
| `LICENSE.electron.txt` / `LICENSES.chromium.html` | Electron 打包标准产物 |
| 安装器退出握手 | `isDesktopInstallerQuitRequest`：`platform === "win32" && argv.includes("--dsh-installer-quit")` |
| 更新安装 | spawn NSIS：`["--updated","--force-run"]`，随后当前进程退出 |
| Linux 线索 | `package.json` 的 `desktopName: "dsh-desktop.desktop"` 是 **electron-builder Linux** 字段（桌面入口名）；`LinuxPlatformStrategy` 已存在 |

- 证据：`lib/main.js:158-160`；`lib/electron-runtime-Bq738q05.js:3968-3994`；`resources/app/package.json`（`desktopName`）。

### 3.2 vendor tgz 依赖的处理方式

- `package.json` 中：`"@agents-anywhere/dsh-bridge-next": "file:../vendor/agents-anywhere/agents-anywhere-dsh-bridge-next-0.1.0-dev.0.desktop.c125aab0a5f30.r1188e1a1.tgz"`
- 实际落盘：`resources/app/node_modules/@agents-anywhere/dsh-bridge-next/`，`package.json` 版本号即文件名中的长版本 `0.1.0-dev.0.desktop.c125aab0a5f30.r1188e1a1`
- 该包自带 Cordis bundle patch：`dsh-bridge-next/cordis.patch.yml`（插入 `agents-anywhere-bridge-next` 行）
- 自带 **Python Connector**：`dsh-bridge-next/lib/bundled-connector/`（`pyproject.toml` + `connector/`）；桌面侧在 profile 组装时校验其存在：`lib/profile-B8k_aHEa.js:1022-1023`
- 运行时用 `@dataiku/uv@0.12.0` 管理 Python 环境，按 `@dataiku/uv-${process.platform}-${process.arch}` 解析 uv 二进制：`dsh-bridge-next/lib/index.js:871-872`

> **含义**：vendor tgz 是**源码仓库内的本地打包依赖**（`file:../vendor/...`），安装时被 pnpm 落进 `node_modules`；它**不是**运行时可写目录。移植时 vendor 目录需随源码仓库一起取出。AA Connector 引入 **Python + uv 双运行时**，是 UOS 移植的真实增量依赖。

### 3.3 打包配置本体

- **源码未体现，待补**：安装包内**不含** `electron-builder.yml`/`electron-builder.json5`、NSIS 脚本、`build/` 下的图标源（`build/` 仅有运行时需要的 `app-icon.ico/png`、`tray-icon*.png`）。`package.json.files` 中声明的 `build/icons/**`、`build/app-icon.icns`、`docs/**` 在安装包内**不存在**。
- 结论：`electron-builder` 配置与 NSIS 定制脚本位于**源码仓库**（`anywhere-labs/deepseek-harness-desktop`，子目录 `dsh-plugin-desktop`），需另行获取才能完整评估打包改造面。

---

## 4. Linux / UOS 改造点

> 难度评级：**低** = 配置/编排即可；**中** = 需要新增平台分支与代码；**高** = 需新造子系统或与上游/外部服务协商。

| # | 绑定点 | Linux/UOS 等价方案 | 难度 | 依据 |
|---|---|---|---|---|
| 1 | **pwsh 沙箱**（Windows ACL 受限令牌） | 直接用上游 `dsh-bash-sandbox`：沙箱提供方 `dsh-sandbox-local` 在 Linux 用 **bwrap → Landlock** runner 链（无 runner 时 `SANDBOX_UNAVAILABLE` 失败关闭）。桌面层只需**不插入** windows-pwsh-sandbox 行（现有 win32 分支天然跳过） | **低** | `dsh-base/cordis.patch.yml:234-242`；`dsh-bash-sandbox/README.zh.md:12,38-39`；`dsh-sandbox-local/README.zh.md:71,75-77` |
| 2 | Windows ACL runner / koffi Win32 FFI | Linux 不需要；`windows-acl-runner.js`、`windows-pwsh-sandbox.js`、`koffi` 仅被 win32 路径引用 | **低** | `lib/windows-acl-runner.js:8-9`；`lib/windows-pwsh-sandbox.js:58` |
| 3 | **内置终端** | 参考 macOS 分支的 `#!/bin/sh` shim（`dsh`/`pnpm`/`node`）与登录 shell rc 注入，新增 linux 分支；终端宿主选 `x-terminal-emulator`/`gnome-terminal` 等 | **中** | `lib/desktop-terminal-CSXxo5CR.js:289,304-337`；`lib/terminal.js:12` |
| 4 | **自动更新** | 新增 linux 下载端点与 AppImage/`.deb` 安装流；`LinuxPlatformStrategy.updateDownloadPlatform` 需从 `undefined` 改为具体值；服务端 `dshdesktop.cn` 需提供 linux 制品 | **中→高** | `lib/electron-runtime-Bq738q05.js:2511,3865`；`lib/update-download-gLk3DU6C.js:9-11,192` |
| 5 | 目录选择器 | Electron 原生 `dialog.showOpenDialog` 在 Linux 可用；当前 `canPickDirectory:false` 且仅 win32 注册路由，需放开 | **中** | `lib/electron-runtime-Bq738q05.js:2512`；`lib/index.js:378-399` |
| 6 | 外壳模式 | Linux 已被强制 `compatibility`、extended/advanced 禁用；若需高级模式须补 Linux 自定义 chrome/材质 | **中** | `lib/client.js:10554,12808-12820`；`lib/electron-runtime-Bq738q05.js:459-465` |
| 7 | 窗口材质/主题 | Linux 材质 schema 已存在（默认 `off`，`transparent` 被归一为 `off`）；`nativeTheme` 已跳过 Linux | **低** | `lib/settings-bridge-CKOtrHLn.js:74-84,387`；`lib/electron-runtime-Bq738q05.js:1726` |
| 8 | 登录 shell 环境捕获 | **已支持 Linux**（zsh/bash/fish，POSIX 捕获）；UOS 默认 shell 若非三者需扩展白名单 | **低** | `lib/main.js:330-340,550-578` |
| 9 | `dsh` 命令注入 PATH | 现仅 win32（`bin/dsh.cmd`）；Linux 需补 posix shim（可直接参考已存在的 `posixPnpmShim`/`posixNodeShim`） | **中** | `lib/desktop-runtime-environment-BCd9iEvr.js:234-266,384-385`；`lib/main.js:4556-4564` |
| 10 | 打包形态 | electron-builder 增 Linux target（AppImage/`.deb`）；`desktopName: dsh-desktop.desktop` 已就绪；需补 Linux 图标集（当前 `build/` 无 `icons/`） | **中** | `resources/app/package.json`（`desktopName`）；`build/` 目录列举 |
| 11 | 单实例锁 / AppUserModelId | Electron 单实例锁跨平台；`setAppUserModelId` 仅 win32，Linux 无需 | **低** | `lib/main.js:3735,3977` |
| 12 | AA Bridge / Connector | `dsh-bridge-next` **已含 Linux 分支**：`xdg-open`、`linuxProcesses`、AppImage 检测、`@dataiku/uv-${platform}-${arch}`。需确保 UOS 架构（x86_64/arm64/loongarch）的 uv 二进制与 `python-build-standalone` 可得 | **低→中** | `node_modules/@agents-anywhere/dsh-bridge-next/lib/index.js:871-872,901,1394,1470`；`package.json:165` |
| 13 | 托盘 | Electron `Tray` 跨平台，Linux 用蓝色品牌图（`build/tray-icon-blue.png`）；但 UOS 需确认 StatusNotifier/AppIndicator 支持 | **低→中** | `lib/electron-runtime-Bq738q05.js:975-982,2041` |
| 14 | 开机自启 / 注册表 | **源码未体现**，UOS 若需要须另做（`~/.config/autostart/*.desktop`） | **待补** | §2.3 |
| 15 | 打包/签名/公证配置 | 安装包内不含 | **待补** | §3.3 |

### 4.1 关键判断

1. **沙箱不是移植难点**。上游已有 Linux 沙箱（bwrap/Landlock）与 bash 工具链，桌面层的 Windows 适配器是「可选增强」，在 Linux 上自动不插入（`lib/profile-B8k_aHEa.js:1083` 的 win32 条件）。
2. **真正的改造面集中在 4 处**：① 内置终端（无 Linux 分支）② 自动更新（无 Linux 制品与端点）③ 目录选择器与高级外壳（被 Linux 策略关闭）④ 打包产物（AppImage/`.deb`）与 `dsh` posix shim。
3. **新增依赖**：AA Bridge 的 Python Connector 需要 Linux 版 `uv` + Python 运行时，离线内网场景需一并打包。
4. **端口与登录环境**基本无需改造。

---

## 5. 可参考的先行项目

### 5.1 主参考：`dsh-tauri/deepseek-harness-desktop`（Tauri 版，已支持 Linux）

来源：GitHub `dsh-tauri/deepseek-harness-desktop` README（英文版，commit `9d2c97f`）与检索汇总。

| 维度 | 该项目的做法 |
|---|---|
| 技术栈 | **Tauri 2（Rust）+ React 19 WebView**，非 Electron；安装包约 5–8MB，内存更低 |
| 平台 | Windows 10+ / macOS 12+ / **Linux（AppImage / `.deb`）**；macOS 另有 Homebrew tap |
| 架构 | WebView 加载 `http://127.0.0.1:3080` 内嵌上游 Web UI；Rust 后端服务：`service/download`、`service/core`、`service/profile`、`service/plugin`、`service/cli`(shim+PATH)、`service/update`、`service/workflow`(dsh 进程生命周期)、`task`(健康检查) |
| 运行时策略 | 首次启动下载 Node 运行时（**v22.22.0**）与 Harness 内核（`dependencies/dsh/`）；若本机已有全局 `dsh` 则优先复用；内核包由配套仓库 **`deepseek-harness-pkg`** 构建 |
| 离线场景 | Release 提供 `Deepseek.Harness.Desktop_Bundle_<ver>` 离线包（内网/白名单环境）；Linux 离线包在 `.deb` 内，`/usr/lib` 只读，root 安装后需修正内核目录权限 |
| 端口/主页 | 固定 `--host 127.0.0.1 --port 3080`，`DSH_HOME=~/.dsh` |
| CLI 集成 | 安装时注册 `dsh` 命令 shim，不覆盖用户既有 shell 配置 |
| 更新 | 应用内自更新 + 每次启动比对最新内核发行版；GitHub 不可达时保留本地版本 |
| 内置插件 | `dsh-tauri`（与 Tauri 壳通信、重写桌面载体两个鉴权门以让跨源沙箱 WebView 访问 loopback）、`dsh-tauri-ui`、`-worktree`、`-extension`、`-scheduler`、`-archive`、`-pet`、`-rightclick`、`-model` |
| 许可 | MIT **+ 非商用附加条款**（商用需注意） |
| **Linux 已知坑** | ① Wayland 下 AppImage 可能崩溃/黑屏（WebKitGTK）：优先 `.deb`，或 `WEBKIT_DISABLE_COMPOSITING_MODE=1 WEBKIT_DISABLE_DMABUF_RENDERER=1 GDK_BACKEND=x11`；② 滚动发行版（Arch/CachyOS/Fedora）旧 AppImage 捆绑 Ubuntu 22.04 显示栈库导致 `WebKitWebProcess` abort——新版构建已剥离这些库，或 `LD_PRELOAD=/usr/lib/libwayland-client.so.0`；③ 图标缺失时把 hicolor 图标拷到 `~/.local/share/icons` 并 `update-desktop-database` |

### 5.2 其他社区分支（旁证，非官方）

- `web-casa/DeepSeek-Harness-Desktop`：Windows/macOS 原生打包，无 Node 依赖安装。
- `AleCyriaco/deepseek-harness-desktop`：Rust + Tauri v2 跨平台壳。
- `gitboyzcf/deepseek-harness-desktop`：Windows/macOS/Linux（`.AppImage`），内置 Node + dsh、内核自动更新、客户端自动更新流水线。
- 上游官方：`deepseek-ai/deepseek-harness`（Linux 走 npm）；本样本对应 `anywhere-labs/deepseek-harness-desktop`（Electron，Windows x64 + macOS Universal）。
- **以上均非 DeepSeek 官方，未经官方背书**，引用仅作技术路线参照。

### 5.3 对 UOS 移植的可复用经验

1. **Linux 分发形态**：优先 `.deb`（Wayland 更稳），AppImage 作为便携备选；AppImage 需剥离构建机显示栈库以避免滚动发行版 ABI 冲突。
2. **离线/内网**：打包「Node 运行时 + 内核 + 依赖」的离线 bundle；UOS 内网场景必须走离线形态（含 AA 的 Python/uv）。
3. **运行时外置**：把 Node/Harness 内核作为可替换运行时目录，与壳解耦，便于内核升级而不重装壳。
4. **shim + PATH**：用托管 shim 提供 `dsh`/`pnpm`，不污染用户 shell 配置（与本样本 `lib/desktop-runtime-environment-*.js` 思路一致）。
5. **端口固定 + loopback**：`127.0.0.1:3080` 单一固定端口有利于 UOS 桌面防火墙/安全策略；本样本主端口默认 43120。
6. **Wayland/WebKitGTK 兼容**：UOS 若用 Wayland，需预置上述环境变量与 `.deb` 优先策略。

---

## 6. 待补项与不确定项（明确列出，均未以推测填充）

| # | 待补项 | 原因 |
|---|---|---|
| 1 | electron-builder 打包配置、NSIS 定制脚本 | 不在安装包内（§3.3） |
| 2 | Windows 开机自启/快捷方式/注册表项实现 | 源码未体现（§2.3） |
| 3 | 主 Web 端口是否已「默认」改为系统分配 | 本样本默认仍为 43120，仅 LAN 边缘恒 `requestedPort:0`（§1.3） |
| 4 | 稳定版/测试版签名证书与公证流程 | 不在安装包内 |
| 5 | `linuxMaterial` 除 `off` 外是否有计划支持 | schema 接受 `transparent` 但归一为 `off`（`settings-bridge:74-78`） |
| 6 | UOS 目标架构（x86_64 / arm64 / loongarch）与 Electron 44 对应二进制可得性 | 需 UOS 侧确认 |
| 7 | AA Bridge 在 UOS 的 Python/uv 二进制与 `python-build-standalone` 镜像可达性 | 需实测 |
| 8 | UOS 桌面托盘（StatusNotifier/AppIndicator）对 Electron `Tray` 的支持 | 需实测 |
| 9 | `dsh-desktop` 的 `.desktop` 入口、图标主题、MIME 关联具体内容 | 与打包配置同在源码仓库 |
| 10 | `windows-pwsh-sandbox` 之外是否还有其他 win32 专属包被插入 | 仅确认 pwsh 沙箱与目录选择器两处（`profile-B8k_aHEa.js:1083-1107`），其余待全量比对源码仓库 |

---

## 附录 A：本文引用的关键文件清单（均在 `D:/Program Files/DSH Desktop/resources/app/`）

| 文件 | 作用 |
|---|---|
| `package.json` | 插件清单、依赖、`dsh.bundle.patch`、`desktopName` |
| `cordis.patch.yml` | 桌面作为插件插入上游 bundle 的补丁 |
| `lib/main.js` | Electron 主进程（单实例、Host fork、运行时引导、更新与恢复） |
| `lib/host-process-entry.js` | DSH Host（Utility Process）入口，`--port` 注入 |
| `lib/index.js` | `desktop-shell` 插件本体（路由注册、native generation 调度） |
| `lib/desktop-port-*.js` | 默认端口 43120 |
| `lib/settings-bridge-*.js` | 桌面设置 schema（含 `linuxMaterial`、`port`、`networkExposure`） |
| `lib/profile-B8k_aHEa.js` | 桌面 profile 组装（win32 专属行替换） |
| `lib/windows-pwsh-sandbox.js` / `lib/windows-acl-runner.js` | Windows ACL 沙箱 Electron 适配器 |
| `lib/desktop-terminal-*.js` / `lib/terminal.js` | 内置终端（macOS/Windows） |
| `lib/update-checker-*.js` / `lib/update-download-*.js` / `lib/updates.js` | 更新探测与下载 |
| `lib/electron-runtime-*.js` | 平台策略、窗口、托盘、更新安装 |
| `lib/desktop-runtime-environment-*.js` | `dsh`/`pnpm`/`node` shim 与 PATH 注入 |
| `app-update.yml` | 更新源（github/anywhere-labs） |
| `node_modules/@deepseek-ai/dsh-base/cordis.patch.yml` | 上游基础组合（沙箱/bash/pwsh 平台门） |
| `node_modules/@deepseek-ai/dsh-bash-sandbox/README.zh.md` | Linux/macOS 沙箱执行器 |
| `node_modules/@deepseek-ai/dsh-sandbox-local/README.zh.md` | 各平台 runner（bwrap/Landlock/Seatbelt/ACL） |
| `node_modules/@agents-anywhere/dsh-bridge-next/` | vendored AA Bridge（含 Python Connector、uv） |

## 附录 B：合规说明

- 本报告仅对**本机已安装的官方程序**做静态只读分析（Read/Grep/目录列举），未修改安装目录，未收集任何客户信息。
- 第 5 节先行项目信息来自公开网络检索与其公开 README，非官方评测，仅供技术路线参照。
- 全文未编造数据、客户名、金额或监管条文；无法证实的项均标注「源码未体现，待补」或「需实测」。
