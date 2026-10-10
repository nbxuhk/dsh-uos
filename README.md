# DSH Desktop · 统信 UOS 版

把 [DSH Desktop](https://github.com/anywhere-labs/deepseek-harness-desktop)（DeepSeek Harness 的 Electron 桌面客户端）移植到**统信 UOS / Deepin**，并产出**离线一体化安装包**。

本项目为**移植工程**，不 fork 上游代码：以上游仓库为基线，叠加一层 UOS 平台适配补丁（15 个文件），复用其自带的 `dist:linux` 构建链产出 deb 与 AppImage。

---

## 交付物

| 文件 | 体积 | 说明 |
|---|---|---|
| `DSH-Desktop-2.0.17-uos-amd64.deb` | 228 MB | 标准 deb，UOS 双击即装 |
| `DSH-Desktop-2.0.17-uos-offline-amd64.run` | 228 MB | 自解压一体化包，内嵌缺失依赖，**零联网**可用 |

> 安装包体积过大，不入 git 仓库，通过 **Release 附件**分发。
>
> 离线包内嵌的是 **3 个系统确实缺失的依赖**（`libayatana-appindicator3-1` 及其两个传递依赖），
> 用于替代已废弃的 `libappindicator3-1`（UOS 源中无候选）。其余 9 个主程序依赖在 UOS 桌面版
> 均为系统基线，**刻意不内嵌** —— 内嵌系统基线组件会因其版本高于系统而引发版本倒挂，
> 连锁导致主程序无法配置（详见下方「依赖策略」）。

---

## 快速开始

### 安装（联网环境）

```bash
sudo dpkg -i DSH-Desktop-2.0.17-uos-amd64.deb
```

9 个运行时依赖在 UOS 桌面版均为**系统基线**（实测 `dpkg --dry-run -i` 直接通过）。

### 安装（内网离线环境）

```bash
sudo bash DSH-Desktop-2.0.17-uos-offline-amd64.run
```

自解压后依次执行：校验内嵌依赖 SHA256 → 检查主程序依赖是否已由系统满足 →
仅安装系统缺失的可选依赖（已装的一律跳过，绝不覆盖）→ 安装主程序 → 复核安装状态。
全程零联网。断网实测通过（见 `outputs/WB-0008-offline-verify-r3.txt`）。

### 启动

- 应用菜单搜索「DSH Desktop」
- 桌面快捷方式
- 终端执行 `dsh-desktop`

---

## 依赖策略（重要）

DSH 主程序声明的依赖**均无版本约束**，且在 UOS 桌面版上全部已装且健康：

```
Depends:    libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6,
            xdg-utils, libatspi2.0-0, libuuid1, libsecret-1-0
Recommends: libappindicator3-1
```

`libappindicator3-1` 在 Deepin/UOS 源中**无候选版本**，由 ayatana 系列替代，
而该系列默认未预装 —— 这才是离线包真正需要补的东西：

| 内嵌包 | 原因 |
|---|---|
| `libayatana-appindicator3-1` | 源中替代 `libappindicator3-1`，系统缺失 |
| `libayatana-indicator3-7` | 上述包的传递依赖 |
| `libayatana-ido3-0.4-0` | 上述包的传递依赖 |

**不要**把 `libgtk-3-0`、`libuuid1` 等系统基线组件打进离线包。实测教训：
内嵌的 `libgtk-3-0 3.24.41-1deepin8` 要求 `libgtk-3-common >= 1deepin8`，
而系统为 `1deepin6`，dpkg 因版本倒挂拒绝配置，连锁导致
`libgtk-3-0` → `libayatana-*` → `dsh-desktop` 共 5 个包全部停在 unpacked，主程序装不上。
（完整现场见 `outputs/WB-0008-offline-verify-r2.txt`）

---

## 适配内容

针对 UOS / Linux 的 15 处改造（详见 `outputs/WB-0004/patches/`）：

| 模块 | 改动 |
|---|---|
| 内置终端 | 新增 `LINUX_TERMINAL_LAUNCHERS`，优先 `deepin-terminal` |
| 目录选择器 | `canPickDirectory: true`（Linux 原生支持） |
| dsh 命令 shim | 新增 `posixDshShim`，生成 POSIX shell 包装脚本（0700） |
| 平台门控 | `main.ts` 放开 win32 独占条件至 win32 \|\| linux |
| 打包配置 | 补 `StartupWMClass` 与 `zh_CN` 本地化字段 |

**沙箱无需改造**：上游已内置 Linux 沙箱链（`dsh-bash-sandbox`：bwrap → Landlock），win32 分支天然跳过。

---

## 实测结论（UOS 实机）

| 验证项 | 结果 |
|---|---|
| deb 安装 | PASS（9 个依赖系统自带，零联网） |
| 程序启动 | PASS（窗口渲染、DDE 托盘 StatusNotifier 注册成功） |
| 沙箱 | PASS（bwrap 0.11.0 + Landlock ABI=3，内核 6.6.143） |
| dsh 命令 shim | PASS（`dsh --version` → 0.2.0-rc.2） |
| 中文本地化 | PASS |
| 全链路 | PASS（构建 → 安装 → 登录 → 对话界面可用） |
| 离线包断网安装 | PASS（删默认路由 → 安装 → 零未配置包 → 复核通过） |

完整报告见 `outputs/WB-0006/p2-verification-report.md`，离线包复验记录见
`outputs/WB-0008-offline-verify-r3.txt`。

**已知限制**见 `outputs/WB-0004/known-limitations.md`，要点：

- 自动更新无 Linux 端点（内网场景建议禁用，走离线包分发）
- Wayland（treeland）会话未实测，当前基于 X11 验证
- 托盘「终端」按钮与目录选择器依赖 GUI 交互，留人工确认

---

## 仓库结构

```
├── outputs/
│   ├── WB-0002/  源码简报（上游仓库分析）
│   ├── WB-0003/  UOS 移植差异分析（15 项改造点）
│   ├── WB-0004/  开发方案 + 适配补丁 + 构建指南 + 已知限制
│   ├── WB-0005/  构建记录（deb / AppImage 产出）
│   ├── WB-0006/  P2 实机验证报告 + 桌面快捷方式部署 + 截图
│   ├── WB-0007/  GitHub Release 说明与附件
│   └── WB-0008-offline-verify-r*.txt  离线包三轮断网复验记录
├── scripts/
│   ├── vm.py                     虚拟机 SSH 操作助手
│   ├── vm-run.sh                 本地凭据包装器（不入库）
│   ├── env.sh                    VM 构建环境变量（镜像源适配）
│   ├── dep-closure.sh            依赖闭包解析
│   ├── full-closure.sh           递归展开闭包，区分已装/待外带
│   ├── analyze-deps.py           依赖满足性分析
│   ├── fetch-deps.sh             依赖 deb 批量下载
│   ├── fetch-deps-more.sh        补齐遗漏依赖
│   ├── build-offline-package.sh  离线一体化包组装（白名单内嵌）
│   ├── offline-verify.sh         断网安装自包含验证任务
│   ├── install-desktop-shortcut.py  桌面快捷方式部署
│   ├── push-via-api.py           经 Git Data API 推送（绕开镜像代理 push 限制）
│   ├── make-release.py           创建 Release 并上传附件
│   └── sandbox-probe.py          bwrap / Landlock 能力探测
└── .workbuddy/memory/            项目工作日志
```

---

## 构建方法

见 `outputs/WB-0004/build-guide.md`。核心要点：

**硬性门禁**（上游 `scripts/package-linux.ts` 强制校验）：

- 必须**原生 Linux 主机**（不支持交叉编译）
- **x64 Node**，版本 **22.19+** 或 24.x（带 corepack）

**国内网络适配**（`scripts/env.sh` 已固化）：

```bash
export COREPACK_NPM_REGISTRY=https://registry.npmmirror.com
export ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
export ELECTRON_BUILDER_BINARIES_MIRROR=https://npmmirror.com/mirrors/electron-builder-binaries/
export npm_config_disturl=https://cdn.npmmirror.com/binaries/node
export CC=clang CXX=clang++   # GCC 12.3 编 V8 头文件报错，必须用 clang
```

**构建命令**：

```bash
yarn install
yarn dist:linux    # 产出 deb + AppImage
```

---

## 上游基线

| 仓库 | 版本 / commit |
|---|---|
| [anywhere-labs/deepseek-harness-desktop](https://github.com/anywhere-labs/deepseek-harness-desktop) | HEAD `a1ff68b`，`dsh-plugin-desktop` 2.0.17 |
| [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) | v0.2.1-alpha.1（MIT） |

两仓库均为 MIT 许可。本项目仅叠加适配补丁，未修改上游核心逻辑。

---

## 许可

本项目为移植适配层，遵循上游 MIT 许可。
