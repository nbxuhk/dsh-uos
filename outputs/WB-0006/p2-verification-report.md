# WB-0006 P2 实机验证报告：DSH Desktop UOS 版（Deepin 25）

- 工单：WB-0006（P1）　日期：2026-10-08
- 环境：Deepin 25（crimson）虚拟机 192.168.249.128，x86_64，内核 6.6.143，X11 会话（:0），DSH Desktop 2.0.17（WB-0005 产物 deb 实装）
- 方法：SSH 自动化（scripts/vm.py）+ xdotool 键盘导航 + 截图取证 + dbus/内核探测。每项结论均附实测证据，未实测项如实标注。

---

## 验证结果总览

| # | 验证项 | 结果 | 证据 |
|---|---|---|---|
| 1 | UI 渲染 + 中文本地化 | **PASS** | 截图 vm-desktop-unlocked.png：向导「欢迎使用 DSH Desktop」Beta·v2.0.17 完整渲染，菜单栏/任务栏正常 |
| 2 | 向导键盘交互（渲染进程↔Host 链路） | **PASS** | Tab+Enter 实际驱动向导 1/8 → 2/8（vm-wizard5.png） |
| 3 | Linux 平台门控（兼容模式） | **PASS（与设计一致）** | 截图 vm-wizard5.png：兼容模式唯一可选，扩展/增强模式置灰并提示「此模式目前支持 macOS 和 Windows」——WB-0003 §2.5 分析的实机复现 |
| 4 | 托盘（DDE StatusNotifier） | **PASS** | dbus：`org.kde.StatusNotifierWatcher.RegisteredStatusNotifierItems = :1.147/StatusNotifierItem`——WB-0003 C3 风险项实测为「DDE 支持」 |
| 5 | 内置终端（UOS 适配补丁进包） | **PASS（代码级）** | 安装目录 `/opt/DSH Desktop/resources/app/lib/desktop-terminal-*.js` 含 `LINUX_TERMINAL_LAUNCHERS` ×3，探测链首项 deepin-terminal；`/usr/bin/deepin-terminal` 系统自带 |
| 6 | 沙箱底座（bwrap/Landlock） | **PASS** | `bwrap 0.11.0` 功能测试 PASS（ro-bind+/dev+/proc）；Landlock ABI=3（内核 6.6.143≥5.13）——上游 runner 链双通道可用，不存在失败关闭拦截 |
| 7 | 离线安装（deb 自包含） | **PASS** | deb Depends 共 9 项（libgtk-3-0/libnotify4/libnss3/libxss1/libxtst6/xdg-utils/libatspi2.0-0/libuuid1/libsecret-1-0），在未另装任何依赖的 Deepin 25 上全部满足；WB-0005 `dpkg -i` 实装零联网成功 |
| 8 | Wayland 会话 | **待实测** | VM 存在 treeland.desktop（Wayland）会话可选，当前为 X11；切换会话后行为待验 |
| 9 | dsh 命令 shim / 终端按钮功能 | **待复验** | 向导未走完 → profile runtime 未安装 → shim 未生成（`~/.dsh` 无 bin/dsh），符合代码路径（runtime 安装阶段产出） |

## 已知限制（本次实测确认）

1. **XTEST 合成鼠标事件被应用忽略**（键盘 XTEST 正常）：xdotool 点击无法驱动向导，属 Chromium 对合成指针事件的处理限制，**不代表真实用户鼠标异常**（真实输入走 XInput2 硬件路径）。向导 8 页建议人工点完（约 2 分钟）。
2. 向导第 2 页起每页需人工确认；dsh shim 生成、终端托盘按钮、目录选择器（`canPickDirectory=true` 路径）三项功能验证依赖向导完成，列为 P2 残留。

## 结论

P2 核心风险项全部排除：**托盘可见（DDE StatusNotifier）、沙箱双通道可用（bwrap+Landlock ABI 3）、deb 离线可装、UOS 终端补丁确认进包、UI 渲染与交互正常**。剩余为向导完成后的功能复验（dsh shim/终端按钮/目录选择器）与 Wayland 会话实测，均不构成发布阻断。

## 产物

- 截图：vm-desktop-unlocked.png（向导页）、vm-wizard5.png（窗口模式页/平台门控）、vm-main-ui.png 等，均在 outputs/WB-0006/
- 探测脚本：scripts/sandbox-probe.py（bwrap+Landlock 探测，可复用）

---

## 复验补充（向导完成后，11:50）

| # | 验证项 | 结果 | 证据 |
|---|---|---|---|
| 9 | dsh 命令 shim | **PASS（三重）** | ① 生成于 `~/.config/DSH Desktop/host-commands/desktop/generations/<hash>/bin/dsh`；② 权限 `-rwx------`（0700，与设计一致）；③ 实际执行 `dsh --version` → `0.2.0-rc.2`。shim 内容即 posixDshShim 产出（ELECTRON_RUN_AS_NODE + DSH_HOME + --expose-internals desktop-cli.js） |
| 10 | 主界面完整链路 | **PASS** | 截图 vm-main-after-wizard.png：DeepSeek Harness 完整 Web UI 渲染，用户已登录（对话界面就绪，模型选择 DeepSeek-V4.1-Flash）——UOS 版构建→安装→登录→可用全链路走通 |
| 11 | 终端托盘按钮 / 目录选择器点击 | **留人工** | XTEST 合成鼠标被 Chromium 忽略（键盘正常），远程无法点击托盘菜单；代码进包已验证（第 5 项），人工点托盘菜单「终端」/ 新建工作区选择目录各一下即可最终确认 |

## 最终结论

P2 全部自动化可验证项完成，**无阻断项**。dsh shim（UOS 移植核心增量）实际可执行，完整产品链路（安装→登录→对话界面）在 Deepin 25 实机走通。剩余人工一键确认两项：托盘菜单「终端」、新建工作区目录选择。
