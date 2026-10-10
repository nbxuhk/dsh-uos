# 桌面快捷方式部署记录（UOS 虚拟机）

- 日期：2026-10-08 17:33–17:45
- 环境：统信 UOS（Deepin 25 内核 6.6.143），X11 会话，用户 `xuhk`，桌面目录 `/home/xuhk/Desktop`
- 关联：WB-0006 P2 实机验证后续项

## 1. 用户问题澄清：虚拟机上的 dsh 在哪

| 层级 | 路径 | 说明 |
|---|---|---|
| 已安装程序 | `/opt/DSH Desktop/dsh-desktop` | deb 安装的桌面主程序 |
| 构建产物 | `~/dsh-build/repo/dsh-plugin-desktop/dist/DSH-Desktop-2.0.17-amd64.deb`、`…-x86_64.AppImage` | 构建输出 |
| 命令行 shim | `~/.config/DSH Desktop/host-commands/desktop/generations/<sha256>-<uuid>/bin/dsh` | 权限 0700，桌面端启动时生成 |
| 源码树 | `~/dsh-build/repo` | 含 UOS 适配补丁 |
| 运行数据 | `~/.dsh/`（profiles/sessions/storages）、`~/.config/DSH Desktop/` | |
| Node 工具链 | `~/dsh-build/opt/node/bin/node`（v22.20.0） | 非系统自带 |

shim 内容为：
```sh
#!/bin/sh
ELECTRON_RUN_AS_NODE=1 DSH_DESKTOP_DEFAULT_PROFILE='desktop' DSH_HOME='/home/xuhk/.dsh' \
  exec '/opt/DSH Desktop/dsh-desktop' --expose-internals \
  '/opt/DSH Desktop/resources/lib/desktop-cli.js' "$@"
```
即依赖 `/opt/DSH Desktop` 安装体，非独立 CLI。

## 2. 桌面快捷方式部署

### 做法
```bash
DESKTOP_DIR=$(xdg-user-dir DESKTOP)          # /home/xuhk/Desktop
ln -sfn /usr/share/applications/dsh-desktop.desktop "$DESKTOP_DIR/dsh-desktop.desktop"
gio set "$DESKTOP_DIR/dsh-desktop.desktop" metadata::trusted true
```

用**软链**而非拷贝，与系统既有的 `dde-computer.desktop` / `dde-trash.desktop` 形态一致；
后续 `dpkg -i` 升级时系统 desktop 文件自动更新，桌面快捷方式无需重建。

### 校验结果

| 项 | 结果 |
|---|---|
| `desktop-file-validate` | PASS |
| 图标资源 `/usr/share/icons/hicolor/*/apps/dsh-desktop.png` | 存在（16→1024 全尺寸） |
| `metadata::trusted` | true |
| 桌面渲染 | PASS（截图 vm-desktop-shortcut.png，桌面左侧第 4 位，带专属图标） |
| 启动实测 | PASS（`/opt/DSH Desktop/dsh-desktop` 拉进程 + 窗口映射 + 账号接口 200） |

desktop 文件内容（上游 electron-builder 生成，含中文名与 StartupWMClass）：
```ini
[Desktop Entry]
Name=DSH Desktop
Exec="/opt/DSH Desktop/dsh-desktop" %U
Terminal=false
Type=Application
Icon=dsh-desktop
StartupWMClass=dsh-desktop
GenericName=AI Coding Assistant
GenericName[zh_CN]=AI 编码助手
Comment[zh_CN]=DeepSeek Harness 智能编码桌面客户端
Categories=Development;
```

### 有意未做的事
**未**在 Exec 中注入 `GTK_IM_MODULE` / `QT_IM_MODULE` / `XMODIFIERS`。
Deepin 通过 `im-config`（`/etc/X11/Xsession.d/70im-config_launch`）在图形会话统一注入，
桌面文件硬塞会破坏系统输入法自适应逻辑。

## 3. 过程中的两处坑（重要）

### 3.1 windowkill 文件管理器导致桌面被清空
执行 `xdotool windowkill <dde-file-manager 窗口>` 后，dde-shell 桌面同步把
`~/Desktop/` **全部 6 项**移入回收站。已完整恢复：

- 逐一读 `~/.local/share/Trash/info/*.trashinfo` 取原始 Path（均为 `/home/xuhk/Desktop/`）
- `mv ~/.local/share/Trash/files/<name> ~/Desktop/` 并删除对应 `.trashinfo`
- 校验：`unzip -t m0-offline-validation.zip` OK；目录 17M / 4 项；软链与时间戳完好

**结论：虚拟机上关闭文件管理器窗口不要用 `windowkill`。**

### 3.2 DSH 主窗有强制恢复逻辑
`xdotool windowminimize` 对 DSH 无效；`windowunmap` 后窗口会被应用立即重新映射。
截取纯净桌面必须 `pkill -f '/opt/DSH Desktop/dsh-desktop'` 整个退出应用。

## 4. 沉淀产物

- `scripts/install-desktop-shortcut.py`——幂等的快捷方式安装/校验脚本（已实测连跑无副作用）
- `outputs/WB-0006/screenshots/vm-desktop-shortcut.png`——桌面图标实拍
