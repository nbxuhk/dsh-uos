# DSH Desktop · 统信 UOS 版

把 [DSH Desktop](https://github.com/anywhere-labs/deepseek-harness-desktop)（DeepSeek Harness 的 Electron 桌面客户端）移植到**统信 UOS / Deepin**，并产出**离线一体化安装包**。

本项目为**移植工程**，不 fork 上游代码：以上游仓库为基线，叠加一层 UOS 平台适配补丁（15 个文件），复用其自带的 `dist:linux` 构建链产出 deb 与 AppImage。

---

## 交付物

| 文件 | 体积 | 说明 |
|---|---|---|
| `DSH-Desktop-2.0.17-uos-amd64.deb` | 228 MB | 标准 deb，UOS 双击即装 |
| `DSH-Desktop-2.0.17-uos-offline-amd64.run` | 232 MB | 自解压一体化包，内嵌 10 个依赖 deb，**零联网**可用 |

> 安装包体积过大，不入 git 仓库，通过 **Release 附件**分发。

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

内嵌全部依赖，自动跳过已装项，无需任何网络。

### 启动

- 应用菜单搜索「DSH Desktop」
- 桌面快捷方式
- 终端执行 `dsh-desktop`

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

完整报告见 `outputs/WB-0006/p2-verification-report.md`。

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
│   └── WB-0006/  P2 实机验证报告 + 桌面快捷方式部署 + 截图
├── scripts/
│   ├── vm.py                     虚拟机 SSH 操作助手
│   ├── env.sh                    VM 构建环境变量（镜像源适配）
│   ├── dep-closure.sh            依赖闭包解析
│   ├── analyze-deps.py           依赖满足性分析
│   ├── fetch-deps.sh             依赖 deb 批量下载
│   ├── build-offline-package.sh  离线一体化包组装
│   ├── install-desktop-shortcut.py  桌面快捷方式部署
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
