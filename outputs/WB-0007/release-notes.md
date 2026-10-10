## DSH Desktop 统信 UOS 版 · v2.0.17

DeepSeek Harness 桌面客户端移植到统信 UOS / Deepin，含**离线一体化安装包**。

### 安装包

| 文件 | 体积 | 适用场景 |
|---|---|---|
| `DSH-Desktop-2.0.17-uos-amd64.deb` | 227.9 MB | 联网环境或依赖已满足，`sudo dpkg -i` 安装 |
| `DSH-Desktop-2.0.17-uos-offline-amd64.run` | 228.0 MB | **内网离线**，自解压 + 零联网，推荐内网使用 |

### 安装

```bash
# 标准 deb
sudo dpkg -i DSH-Desktop-2.0.17-uos-amd64.deb

# 离线一体化包（自动处理缺失依赖）
sudo bash DSH-Desktop-2.0.17-uos-offline-amd64.run
```

离线包执行流程：校验内嵌依赖 SHA256 → 检查主程序依赖是否已由系统满足 →
仅安装系统缺失的可选依赖（已装的一律跳过，**绝不覆盖系统包**）→ 安装主程序 → 复核安装状态。

### 关于依赖（重要）

DSH 主程序声明的 9 个依赖**均无版本约束**，在 UOS 桌面版全部为系统基线。

真正的缺口是 `Recommends: libappindicator3-1` —— 该包在 Deepin/UOS 源中已废弃、无候选，
由 ayatana 系列替代而默认未装。因此离线包**只内嵌 3 个**：

- `libayatana-appindicator3-1`（替代品本体）
- `libayatana-indicator3-7`（传递依赖）
- `libayatana-ido3-0.4-0`（传递依赖）

**不内嵌** `libgtk-3-0`、`libuuid1` 等系统基线组件。内嵌这些会因内嵌版本高于系统而触发
版本倒挂，dpkg 拒绝配置并连锁导致主程序装不上（已实测踩坑并修正）。

### 适配内容（15 处改造）

- 内置终端：新增 `LINUX_TERMINAL_LAUNCHERS`，优先 `deepin-terminal`
- 目录选择器：`canPickDirectory` 放开为 `true`
- dsh 命令 shim：新增 `posixDshShim`，生成 POSIX shell 包装脚本（0700）
- 平台门控：`main.ts` 放开 win32 独占条件至 `win32 || linux`
- 打包配置：补 `StartupWMClass` 与 `zh_CN` 本地化字段

沙箱无需改造——上游已内置 Linux 沙箱链（bwrap → Landlock）。

### 实测结论（UOS 实机，内核 6.6.143）

| 验证项 | 结果 |
|---|---|
| deb 安装 | PASS（9 个依赖系统自带） |
| 离线包断网安装 | PASS（删默认路由 → 安装 → 零未配置包） |
| 程序启动 | PASS（窗口渲染 + DDE 托盘 StatusNotifier 注册） |
| 沙箱 | PASS（bwrap 0.11.0 + Landlock ABI=3） |
| dsh 命令 shim | PASS（`dsh --version` → 0.2.0-rc.2） |
| 中文本地化 | PASS |
| 全链路 | PASS（构建 → 安装 → 登录 → 对话界面） |

离线包复验原始记录见仓库 `outputs/WB-0008-offline-verify-r3.txt`。

### 已知限制

- 自动更新无 Linux 端点（内网建议走离线包分发）
- Wayland（treeland）会话未实测，当前基于 X11 验证
- 托盘「终端」按钮与目录选择器依赖 GUI 交互，留人工确认

### 上游基线

- [anywhere-labs/deepseek-harness-desktop](https://github.com/anywhere-labs/deepseek-harness-desktop) HEAD `a1ff68b`（`dsh-plugin-desktop` 2.0.17）
- [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) v0.2.1-alpha.1

均为 MIT 许可。本项目仅叠加适配补丁。

---

**系统要求**：统信 UOS / Deepin x86_64，内核 5.10+（Landlock 需 5.13+，bwrap 降级可用）
