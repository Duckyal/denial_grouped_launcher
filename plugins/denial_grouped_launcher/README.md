# denial_grouped_launcher

KDE 风格分组应用启动器，替代 Denial 内置 App Launcher（两者都提供 `ShellLauncher`，只能启用其一）。

- 左侧分组栏：全部 / 自定义分组（含应用数）/ 未分组 / 新建分组
- 按 `.desktop` 的 `Categories=` 自动分组，可重命名或恢复默认名
- 顶栏当前用户 + 设置入口 + 电源下拉（关机/重启/休眠/挂起/锁定/熄屏/注销，破坏性操作需确认）
- “全部”视图：搜索栏下方固定一行四个最近启动，其下为应用网格
- 右键应用磁贴：移动到分组、移出分组、新建分组并移入
- 右键分组名：重命名、删除（删除只解除归属，不删应用）
- 右键 desktop 应用：编辑/恢复启动命令
- 右键应用磁贴"从启动器移除"（二次点击确认）：用户目录（`~/.local/share/applications`）下的 desktop 文件直接删除（宿主监听该目录，重扫后自动消失）；系统目录条目无权删除，仅本地隐藏并记入 `hiddenApps`。有隐藏项时侧栏出现"已移除"视图，右键其磁贴可恢复。适合清理已卸载软件残留的失效图标
- 侧栏"添加应用"：输入 AppImage 或任意位置的 `.desktop` 文件路径（支持 `~/` 前缀），在 `~/.local/share/applications` 生成/复制条目，宿主自动重扫出现磁贴。AppImage 会自动补 `chmod u+x` 并按文件名推导显示名（去版本号/架构后缀）；生成的条目无图标，可手动编辑该 `.desktop` 文件加 `Icon=`
- 搜索跨全部分组；当前分组在关闭后记忆
- 分组数据存于 `$XDG_CONFIG_HOME/denial/grouped-launcher.json`，插件独立维护，不依赖合成器改动
- Super 键（裸按）默认打开本启动器：插件直接沿用内置启动器的动作 id `denial_launcher.openApplications`。合成器（deniald Rust 侧 `wayland_frontend::input`）把裸 Super 硬编码路由到这个 id，且要求该 id 出现在发布的动作目录里才派发；`shortcuts.json` 无法声明 modifier-only 的 "Super"，所以必须复用同一 id。两个插件都提供 `ShellLauncher`（zeroOrOne）不会同时启用，此 id 不会被占用。对外只暴露这一个"打开应用列表（分组）"入口
- 关机/重启/休眠/挂起由插件直连 `org.freedesktop.login1` 逐个 verb 读取，不受 SDK 会话电源快照影响；锁定/注销仍走 `sessionPowerProvider`，熄屏走 `screenPowerServiceProvider`

## 安装

```sh
denial-plugins add --local <本目录绝对路径>
denial-plugins enable denial_grouped_launcher
denial-plugins remove denial_launcher   # 避免 ShellLauncher 冲突
denial-plugins apply   # 或 plan -> build ID -> activate ID
```

## 回退

```sh
denial-plugins remove denial_grouped_launcher
denial-plugins enable denial_launcher
denial-plugins apply
```

## 开发

`pubspec_overrides.yaml` 指向当前 build-kit 的 runtime packages；Denial 升级后需更新其中的 build-kit 哈希。修改代码后 `plan -> build -> activate`（build-kit 会直接读取本目录源文件）。
