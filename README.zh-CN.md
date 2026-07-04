# Listening Clip Pipe

[English](README.md) | **中文**

> 把你没听懂的那几秒钟抓下来——一个快捷键，直接进笔记。

Listening Clip Pipe 是一个为**雅思听力训练**（以及一切认真的语言听力学习）设计的 macOS 菜单栏工具。按 **⌥Z** 进入**捕获模式**——空格键变成全局录音键。听到连读、弱读、吞音听不懂时，敲一下**空格**开始录制系统音频，再敲一下**空格**停止——片段自动保存到本地并写入剪贴板，切到飞书 / Notion / 任意文档 **Cmd+V**，音频就落在你正在写笔记的位置。想录几段录几段，练完再按 **⌥Z** 退出捕获模式，空格立刻恢复原有功能。

从 **1.0 版本**起步——完整的「捕获 → 保存 → 粘贴」流水线，刻意保持极简。

## 它解决什么问题

传统流程里，雅思听力有 3 秒没听懂想留档：找到音频文件、拖进度条定位、剪出片段、导出、上传到笔记、再写错因——3 秒的音频要 5 分钟的操作。摩擦太大，所以没人真的做，听不懂的地方永远不会被复习到。

Listening Clip Pipe 把这一切压缩成两次按键：

- **🎧 录的是你耳朵里的声音，不是麦克风。** 直接捕获 macOS 系统音频输出（Core Audio Process Tap），戴耳机也能录，零环境噪音。
- **⚡ 空格就是录音键，零切换成本。** ⌥Z 进入捕获模式后，敲一下空格开始/停止——对"没听懂"的反应速度快到极致，全程不离开播放器和笔记。空格只在模式开启期间被独占（用的是同一个免权限的 Carbon 热键 API），⌥Z 退出后立刻恢复。
- **🔴 录音状态绝不会看漏。** 录制期间屏幕右上角悬浮一个置顶的 ● REC 计时器——全屏 App 之上也可见，鼠标事件穿透，不挡任何操作。可选：菜单里的 **Show On-Screen REC Indicator** 可随时开关。
- **📋 停止即可粘贴。** 片段以文件形式进入剪贴板，Cmd+V 直接插到你写错因分析的位置。
- **🤖 为 AI / 脚本批处理而设计。** 每段音频有唯一 ID、结构化文本锚点、独立 metadata JSON 和总索引——之后你（或一个 LLM agent）可以批量处理你的"听不懂合集"：转写、标注连读/弱读类型、生成复习计划。
- **🔒 完全本地，权限极简。** 无云端、无账号、无数据上报。只需要「仅录制系统音频」一项权限——不要麦克风、不要屏幕录制、不要辅助功能。

## 环境要求

- macOS 14.4+（Apple Silicon 或 Intel）
- Xcode Command Line Tools（从源码构建用）

## 安装

```bash
git clone https://github.com/wanglikai121666-stack/listening-clip-pipe.git
cd listening-clip-pipe
./build_app.sh
cp -R build/ListeningClipPipe.app /Applications/
open /Applications/ListeningClipPipe.app
```

菜单栏出现波形图标。首次按 ⌥Z 时 macOS 会请求授权：**系统设置 → 隐私与安全性 → 屏幕与系统音频录制 → 仅录制系统音频**，允许后再按一次 ⌥Z 即可。

## 使用方法

1. 播放雅思听力 / 播客 / 课程音频，按 **⌥Z** 进入捕获模式（菜单栏图标变橙色；此时空格是录音键，其他 App 收不到空格）。
2. 听到听不懂的地方 → 敲 **空格**（图标变红，屏幕右上角出现悬浮 ● REC 计时器）。
3. 这一小段放完 → 再敲 **空格**，收到通知 *Clip copied*。
4. 切到笔记 **Cmd+V**，在音频旁边写下听错了什么、为什么听错。重复 2–4，想录几段录几段。
5. 这次精听结束 → 按 **⌥Z** 退出捕获模式（空格恢复正常）。

菜单栏菜单还提供：**Start/Stop Recording**（纯鼠标操作的备选）、**Copy Last Clip + Anchor**、**Copy Last Clip**、**Copy Last Anchor**（粘贴失败时补救用）、**Show On-Screen REC Indicator**（悬浮 REC 计时器开关）、**Open Clips Folder**。

## 数据结构

所有数据在 `~/Documents/ListeningClipPipe/` 下：

```
~/Documents/ListeningClipPipe/
├── clips/
│   ├── LC_20260626_213522.wav    # 音频片段（16-bit PCM WAV）
│   └── LC_20260626_213522.json   # 单条元数据
└── clips_index.json              # 总索引，供批量整理
```

每段音频的文本锚点（用于在文档里语义定位这段音频）：

```
🎧 AUDIO_CLIP_ID: LC_20260626_213522
duration: 8.4s
local_file: LC_20260626_213522.wav
source: system_audio
note:
```

## 粘贴兼容性说明

剪贴板采用 *composite* 模式：同一个剪贴板条目同时携带文件 URL 和文本锚点，多数编辑器会取文件。如果目标 App 只粘出其中一种，用菜单里的 **Copy Last Clip** / **Copy Last Anchor** 分开复制兜底。

## 1.0 版本范围与路线图

1.0 只做捕获、存储、剪贴板，这是刻意的。暂不包含：自动转写、飞书 API 同步（接口已在 `FeishuSyncService.swift` 预留）、原文匹配、回放/复习 UI、间隔复习计划、Anki 导出。得益于结构化的本地数据，这些都可以在不改动捕获流水线的前提下往上叠。

## 常见问题

- **`swift build` 失败 / `import Foundation` 报 `SwiftBridging` 重复定义**：部分新旧混装的 Command Line Tools 会残留一个旧的 `module.modulemap`。`build_app.sh` 直接用 `swiftc` 编译并自动应用 VFS overlay 绕过；永久修复：`sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap{,.bak}`。
- **重新构建后又弹权限**：构建使用 ad-hoc 签名，每次重建签名都会变化。日常使用建议固定用 `/Applications` 里的那份。
- **按 ⌥Z 没反应**：确认菜单栏图标在（App 在运行），且 ⌥Z 没有被其他 App 注册为全局快捷键。
- **空格打不出空格了**：你还在捕获模式里（菜单栏图标是橙色/红色）——按 ⌥Z 退出，空格立刻恢复。

## 许可证

[MIT](LICENSE)
