# WB-0002 开源 DSH 源码拉取简报

- 工单：WB-0002（P1）拉取开源 DSH 源码（deepseek-harness 核心 + desktop 桌面壳）
- 产出时间：2026-10-08
- 落盘位置：`D:/Workbuddy/DSH统信/src/`
  - 核心：`src/deepseek-harness/`
  - 桌面：`src/deepseek-harness-desktop/`
- 复核人：主代理（人工）
- 说明：本简报全部数据来自克隆后对仓库文件的**实际读取核验**（`git log` / `package.json` / `README` / `grep`），未凭记忆描述；未安装依赖、未构建。

---

## 0. 拉取过程与通道

| 项 | 结果 |
| --- | --- |
| 直连 GitHub | 失败（`git clone https://github.com/...` 120 秒超时，SIGTERM） |
| 镜像通道 | 成功，使用 `https://gh-proxy.com/` 前缀镜像 |
| 克隆方式 | 浅克隆 `--depth 1` |
| 核心仓库 | `https://gh-proxy.com/https://github.com/deepseek-ai/deepseek-harness.git` |
| 桌面仓库 | `https://gh-proxy.com/https://github.com/anywhere-labs/deepseek-harness-desktop.git` |
| 核验落地文件数 | 核心 14208 个 / 桌面 3771 个（`git ls-files` 计数） |

> 按技能 `github-mirror-failover` 的处置：直连失败后未反复重试，直接切镜像一次成功。

---

## 1. 仓库 A：DSH 核心（deepseek-harness）

### 1.1 版本标识

| 项 | 值 |
| --- | --- |
| 上游 | `https://github.com/deepseek-ai/deepseek-harness` |
| 根包名 | `@deepseek-ai/dsh-root`（`private: true`） |
| **版本号** | **0.2.1-alpha.1** |
| Git tag | `dsh-v0.2.1-alpha.1` |
| 本地 HEAD commit | `5badb15009ae1756c3afe0ae0cef1faafc290ccc` |
| HEAD 提交时间 | 2026-10-03 11:48:13 +0800 |
| HEAD 主题 | `Merge pull request #5648 ... worktree/release-dsh-0.2.1-alpha.1` |
| 许可证 | MIT（Copyright (c) 2026 DeepSeek） |
| 包管理器 | `pnpm@11.7.0`（`packageManager` 字段） |
| Node 引擎 | `^22.19.0 || >=24.0.0` |

### 1.2 顶层目录结构

```
.agents/  .claude/  .github/  .gitlab-ci.yml
apps/          # 产品装配层：cli, desktop, desktop-host, web
packages/      # 能力包层，60+ 分组（acp/api/core/llm/mcp/sandbox/session/skill/...）
native/        # 原生系统层（native/system 及其子包）
python/        # Python SDK / 单可执行文件部署根
vendor/        # 内置第三方（cosmokit, schemastery 等）
benchmarks/  scripts/  docs/  website/  snapshots/  patches/
Makefile  package.json  pnpm-workspace.yaml  pnpm-lock.yaml
tsconfig*.json  tsdown.config.ts  vitest*.config.ts
AGENTS.md  CLAUDE.md  CONTRIBUTING.md  SAFETY.md  BENCHMARK.md
README.md  README.zh.md  LICENSE  THIRD_PARTY_NOTICES.md
```

工作区声明（`pnpm-workspace.yaml`）：`vendor/*`、`packages/*/*`、`native/system`、`native/system/packages/*`、`apps/*`、`benchmarks`、`website`、`python/sdk-runtime`。

### 1.3 apps 应用层版本

| 目录 | 包名 | 版本 |
| --- | --- | --- |
| `apps/cli` | `@deepseek-ai/dsh` | 0.2.1-alpha.1（持有 `dsh` bin） |
| `apps/desktop` | `@deepseek-ai/dsh-desktop` | 0.2.1-alpha.1 |
| `apps/desktop-host` | `@deepseek-ai/dsh-desktop-host` | 0.2.1-alpha.1 |
| `apps/web` | `@deepseek-ai/dsh-web-frontend` | 0.2.1-alpha.1 |

### 1.4 构建入口（根 `package.json` scripts）

| script | 命令 | 说明 |
| --- | --- | --- |
| `build` | `tsx scripts/build.ts` | 主构建入口 |
| `build:official` | `tsx scripts/build.ts --profile official` | 官方 profile 构建 |
| `build:lib` | `build:lib:host` + `build:lib:client` | 分层库构建（tsc -b + tsdown） |
| `build:web` | `pnpm --filter @deepseek-ai/dsh-web-frontend run build` | Web 前端 |
| `build:desktop` | `pnpm --filter @deepseek-ai/dsh-desktop run build` | 内置桌面应用 |
| `dev:desktop` / `start:desktop` | filter `@deepseek-ai/dsh-desktop` | 桌面开发/启动 |
| `package:desktop:mac:arm64` / `mac:x64` / `win:x64` | filter `@deepseek-ai/dsh-desktop` | **仅 mac / win 打包** |
| `typecheck` / `lint` / `test` | tsc + oxlint + vitest | 质量门 |

构建配置文件位置：`scripts/build.ts`（根）、`tsdown.config.ts`（根）、`apps/desktop/scripts/package-target.ts`（桌面打包目标脚本）。

### 1.5 README 中与 Linux 支持相关的说明

- **核心仓库 `README.md` / `README.zh.md` 中没有任何 Linux 字样**（grep `linux`、`ubuntu`、`统信`、`uos`、`kylin`、`AppImage`、`deb` 均无命中）。
- README 亦无显式的"支持平台"章节（grep `windows`/`macos`/`platform` 亦无命中）；README 定位为 developer preview，明确提示会有破坏性变更。
- 结论：**核心 README 层面不提供 Linux 支持声明**，Linux 能力只能从代码/配置侧证据推断（见 1.6）。

### 1.6 核心仓库中实际存在的 Linux 相关代码证据（代码侧，非 README）

| 证据位置 | 内容 |
| --- | --- |
| `packages/sandbox/README.md` | 沙箱按平台提供后端：**Linux 先 bwrap 后 Landlock**、macOS Seatbelt、Windows 受限令牌 |
| `packages/sandbox/sandbox-local/` | 上述"每平台沙箱后端"的实现包 |
| `packages/experimental/webworker-runtime/src/shell/process/landlock.ts` | Landlock 相关实现 |
| `pnpm-workspace.yaml` → `minimumReleaseAgeExclude` | 列出 Linux 平台原生依赖：`node-addon-require-builtin-linux-*-gnu`、`@anthropic-ai/claude-agent-sdk-linux-*`、`@openai/codex@...linux-*`、`@trycua/cua-driver-linux-*-gnu`、`@deepseek-ai/libreoffice-kit-wasm` 等 |

> 即：核心引擎在**沙箱与原生依赖层面**具备 Linux 适配，但**核心自带的 `apps/desktop` 没有 Linux 打包脚本**（仅有 `package:mac:*` / `package:win:x64`）。

---

## 2. 仓库 B：DSH 桌面版（deepseek-harness-desktop）

### 2.1 版本标识

| 项 | 值 |
| --- | --- |
| 上游 | `https://github.com/anywhere-labs/deepseek-harness-desktop`（社区项目，MIT） |
| 根包 | `deepseek-harness-desktop`（`private: true`） |
| **仓库 HEAD commit** | `a1ff68b2960753ab1f6c90565bf3d9e3f3b7ae91` |
| HEAD 提交时间 | 2026-10-03 17:44:59 +0800 |
| HEAD 主题 | `Merge pull request #1305 ... adapt-dsh-v0.2.1-alpha.1` |
| 许可证 | MIT（Copyright (c) 2026 Anywhere Labs） |
| 包管理器 | `yarn@4.18.0` |
| Node 引擎 | `^22.19.0 || >=24.0.0` |

**子包版本（实际读取）：**

| 目录 | 包名 | 版本 |
| --- | --- | --- |
| `dsh-plugin-desktop` | `dsh-plugin-desktop` | **2.0.17** |
| `dsh-plugin-desktop-beta` | `dsh-plugin-desktop-beta` | 2.0.17-beta.1 |
| `dsh-desktop-next` | `dsh-desktop-next` | 2.0.17-next |

> 记录差异：工单描述"本机安装的 DSH Desktop **v2.0.15**"，而克隆到的 HEAD 中 `dsh-plugin-desktop` 版本为 **2.0.17**。二者版本不一致，推测本机安装版对应更早的 commit/tag（见第 4 节待确认项）。

### 2.2 上游锁定关系（`upstream.json`）

| channel | commit | sourceVersion | runtimePackageVersion | package |
| --- | --- | --- | --- | --- |
| `stable` | `639ed015397290b3745d163aafe02ffee4aa3f84` | 0.2.0-rc.2 | 0.2.0-rc.2 | `dsh-plugin-desktop` |
| **`beta`（activeChannel）** | **`5badb15...ccc`** | **0.2.1-alpha.1** | **0.2.1-alpha.1** | `dsh-plugin-desktop-beta` |

- 桌面仓库通过 git submodule 引用核心：`.gitmodules` → `path = deepseek-harness`，`url = https://github.com/deepseek-ai/deepseek-harness.git`。
- **子模块目录 `deepseek-harness-desktop/deepseek-harness/` 当前为空**（浅克隆不拉子模块）；核心内容由第 1 节的独立克隆提供。
- `vendor/dsh-runtime/` 下同时内置 `0.2.0-rc.2` 与 `0.2.1-alpha.1` 两套运行时 tarball（stable / beta 双通道）。

### 2.3 顶层目录结构

```
.agents/  .github/  .yarn/  .yarnrc.yml  .gitmodules
assets/                # 图标与宣传图
deepseek-harness/      # 核心 submodule（当前未初始化，空目录）
docs/                  # 用户/开发者文档（faq / architecture / user-guide）
dsh-plugin-desktop/    # 正式版桌面插件（electron-builder 打包主体）
dsh-plugin-desktop-beta/  # beta 通道桌面插件
dsh-desktop-next/      # next 通道实验桌面
dsh-community-fabric/  # 插件框架（contract / RFC）
dsh-community-market/  # 插件市场
scripts/               # 仓库级脚本（market:prepare / aa:prepare-release / 图标 / 双语校验 ...）
vendor/                # 内置运行时（dsh-runtime, agents-anywhere）
patches/               # yarn patch 补丁
package.json  yarn.lock  upstream.json
README.md  README.zh.md  README.en.md  LICENSE  PRIVACY.md
```

工作区声明（根 `package.json` workspaces）：`dsh-plugin-desktop`、`dsh-plugin-desktop-beta`、`dsh-desktop-next`、`dsh-community-fabric`、`dsh-community-market`。

### 2.4 构建入口（根 `package.json` scripts）

| script | 命令 | 说明 |
| --- | --- | --- |
| `build` | `yarn market:prepare && workspace build ×4` | 主构建（含插件市场与三条桌面通道） |
| `dev` / `start` | `market:prepare` + workspace `dsh-plugin-desktop` dev/start | 开发/启动正式通道 |
| `dev:beta` / `dev:next` | 对应通道 dev | 其他通道开发 |
| `package:dir` | workspace `dsh-plugin-desktop package:dir` | 免安装目录产物 |
| `dist:win` | `... workspace dsh-plugin-desktop dist:win` | Windows 正式产物 |
| **`dist:linux`** | `yarn market:prepare && yarn aa:prepare-release && yarn workspace dsh-community-market build && yarn workspace dsh-plugin-desktop dist:linux` | **Linux 产物（见 2.6）** |
| `dist:win-portable` | workspace `dist:win-portable` | Windows 便携版 |
| `upstream:prepare-runtime` | 进入子模块 `deepseek-harness` 执行 install + build:official + pack | 准备核心运行时 |
| `check` / `check:layout` / `check:bilingual-docs` / `check:architecture` | 各校验门 | 质量门 |

### 2.5 electron-builder 配置位置与内容

**配置位置：`dsh-plugin-desktop/package.json` 的 `build` 键**（非独立 `electron-builder.yml`）。

`build` 顶层键：`appId`、`productName`、`asar`、`afterPack`、`afterAllArtifactBuild`、`electronFuses`、`directories`、`toolsets`、`files`、`mac`、`win`、`nsis`、`linux`、`deb`、`npmRebuild`、`dmg`。

**`build.linux`（关键）：**

```json
{
  "target": [
    { "target": "AppImage", "arch": ["x64"] },
    { "target": "deb",      "arch": ["x64"] }
  ],
  "icon": "build/icons",
  "artifactName": "DSH-Desktop-${version}-${arch}.${ext}",
  "category": "Development",
  "synopsis": "Agentic coding desktop for the DeepSeek Harness",
  "maintainer": "DeepSeek <dsh-desktop@deepseek.com>",
  "executableName": "dsh-desktop",
  "syncDesktopName": true,
  "asar": false
}
```

**`build.win`：** target = `nsis`（x64），icon `build/app-icon.ico`。
**`build.mac`：** target = `dir`，启用 hardened runtime + notarize，entitlements 复用核心 `../deepseek-harness/apps/desktop/scripts/macos-entitlements.plist`。

**linux 打包脚本：** `dsh-plugin-desktop/scripts/package-linux.ts`
- 文件头注释：`Build an unsigned Linux x64 AppImage and Debian package on a native Linux host.`
- 即在**原生 Linux 主机**上产出**未签名**的 Linux x64 AppImage 与 deb。

**linux 相关测试：** `dsh-plugin-desktop/tests/package-linux.spec.ts`、`dsh-plugin-desktop/tests/verify-linux-artifacts.spec.ts`；对应校验脚本 `check:linux-package` / `check:linux-package:platform`。

### 2.6 README / 文档中与 Linux 支持相关的说明（重要）

- **`README.md` / `README.zh.md` 正文中无直接"Linux"字样**（grep 无命中）。
- README 定位（原文）："基于 DeepSeek Harness 构建的 **Windows 和 macOS** 开源桌面客户端"；徽章为 `macOS | Windows`；"下载与安装"表仅列 **Windows x64（NSIS）** 与 **macOS Universal（DMG）** 两项，并注明"当前正式安装包支持 Windows x64 和 macOS Universal"。
- **`docs/faq.md`（第 15–17 行，"支持哪些操作系统？"）给出最明确的平台边界原文：**
  > 当前正式安装包支持 Windows x64 和 universal macOS（Intel 与 Apple Silicon）。**Linux x64 的 AppImage 与 deb 已由 CI 构建，但尚未随任何已发布版本一同发出；在发布说明中看到 Linux 产物之前，不要根据源码中存在跨平台兼容代码推断已经发布了对应安装包。Linux 暂不提供 arm64 产物。**
- `docs/architecture.md`（第 48 行）：平台差异集中在启动时选择一次的 `ElectronPlatformStrategy` seam，**Windows、macOS 与 Linux adapter** 各自声明目录选择、Shell 模式切换与更新下载能力，并负责各自的菜单、Dock 图标与原生材质操作。
- `docs/faq.md`（第 49、57 行）：系统代理由应用读取操作系统代理配置（Windows 的 Internet 选项、macOS 网络设置、**Linux 的桌面设置**）；已知限制——**macOS 与 Linux 上从 Dock/访达启动时不读取 `~/.zshrc`/`~/.bashrc` 内的代理变量**。

### 2.7 综合结论（Linux 支持现状）

| 维度 | 现状 |
| --- | --- |
| 源码侧 Linux 构建能力 | **存在**：electron-builder `linux` 段（AppImage + deb，x64）、`dist:linux` 脚本、`package-linux.ts`、Linux 打包测试与校验门 |
| Linux 平台适配代码 | **存在**：`ElectronPlatformStrategy` 含 Windows/macOS/Linux adapter |
| 官方已发布 Linux 安装包 | **无**：README 与 faq 明确"Linux 产物已由 CI 构建，但尚未随任何已发布版本发出" |
| Linux 架构支持面 | **仅 x64**，明确"暂不提供 arm64 产物" |
| 中文国产 Linux（统信 UOS / 麒麟） | 源码与文档中**均无任何**"统信 / UOS / 麒麟 / Kylin"字样，无针对性适配声明 |

---

## 3. 关键结论（3~5 条）

1. **两仓库版本与锁点已核实**：核心 `deepseek-harness` 根版本 **0.2.1-alpha.1**（tag `dsh-v0.2.1-alpha.1`，HEAD `5badb15`，2026-10-03）；桌面壳 `deepseek-harness-desktop` HEAD `a1ff68b`（2026-10-03），其 `dsh-plugin-desktop` 版本为 **2.0.17**，且 `upstream.json` 的 beta 通道正好锁定核心 `5badb15` / 0.2.1-alpha.1 —— 两侧版本是**配套对齐**的。
2. **桌面壳具备 Linux 构建链，但官方从未发布 Linux 安装包**：`electron-builder` 的 `linux` 段与 `dist:linux`/`package-linux.ts` 一应俱全（AppImage + deb，x64），但 `docs/faq.md` 原文明确"Linux 产物已由 CI 构建，尚未随任何已发布版本发出，且暂不提供 arm64"；README 只承诺 Windows x64 + macOS Universal。
3. **核心 README 完全不含 Linux 声明，Linux 能力只体现在代码层**：核心自带 `apps/desktop` 仅有 mac/win 打包脚本，无 Linux 目标；但核心在沙箱层实装 Linux 后端（`sandbox-local`：**先 bwrap 后 Landlock**）并在 workspace 中登记了 Linux 原生依赖（node-addon、codex、cua-driver、claude-agent-sdk 等的 linux 变体）。
4. **桌面仓库以 git submodule 引用核心，且打包配置集中在插件包内**：核心挂在 `deepseek-harness/` 子模块（当前为空，需自行初始化或用本简报第 1 节的独立克隆）；electron-builder 配置位于 `dsh-plugin-desktop/package.json` 的 `build` 键（非独立 yml），打包主体是工作区包 `dsh-plugin-desktop`。
5. **国产化（统信 UOS/麒麟）适配在源码中零痕迹**：两仓库 README、docs、配置中均无"统信/UOS/麒麟/Kylin"任何字样，也无国产 Linux 发行版专项说明；若目标是在统信上落地，现有可复用资产仅是**上游的 X11/GLib 级 Linux 通道（AppImage/deb x64）**，需自建适配与打包。

---

## 4. 不确定项与待补充（需复核/后续确认）

| # | 待确认项 | 说明 |
| --- | --- | --- |
| 1 | 本机安装版 v2.0.15 与仓库 2.0.17 的对应关系 | 工单称本机安装 DSH Desktop v2.0.15，仓库 HEAD 中 `dsh-plugin-desktop` 为 2.0.17。二者不一致，需确认本机版对应的 commit/tag，或本机是否走 stable（0.2.0-rc.2）通道。本次未读本机安装目录，未做比对。 |
| 2 | 桌面仓库核心 submodule 未初始化 | 浅克隆不拉子模块，`deepseek-harness-desktop/deepseek-harness/` 为空。若需桌面仓库自洽构建，须另行 `git submodule update --init`（或复用本次独立克隆）。本次未执行。 |
| 3 | `vendor/dsh-runtime/` tarball 是否随浅克隆完整 | 已见 `0.2.0-rc.2` 与 `0.2.1-alpha.1` 两目录的引用与文件，但未逐一校验 tarball 完整性/校验和。 |
| 4 | Linux CI 产物的实际可用性 | 文档称 Linux AppImage/deb"已由 CI 构建但未发布"；本次**未构建、未下载 CI 产物**，故无法验证其在 UOS 等国产发行版上的实际可运行性。 |
| 5 | 核心 README 无平台支持章节 | 核心仓库 README 未提供平台支持矩阵，Linux 结论均来自代码/config 推断，属证据强度中等（架构与配置级证据，非官方声明）。 |
| 6 | 未安装依赖、未构建 | 按工单约束执行；两仓库均处于仅源码状态，无 `node_modules`/构建产物。 |

> 数据来源标记：本简报所有版本号、目录、脚本、配置字段均为克隆后实际读取结果；引用 faq/README 的段落为仓库原文（引号内为原文，含"已由 CI 构建""暂不提供 arm64 产物"等表述）。无编造数据、客户名、金额或监管条文。
