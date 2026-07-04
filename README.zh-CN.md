# Obsidian-Clipper-AutoTrigger

[English](README.md) · [中文](README.zh-CN.md)

> 从命令行驱动 Obsidian Web Clipper Chrome 扩展。
> 一个 URL、一整份阅读清单、甚至一个 AI Agent 的请求
> → 直接解析成 Markdown，落进你的 Obsidian vault，全自动。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: macOS · Windows](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-blue)
![Requires: PowerShell 7+ on Windows](https://img.shields.io/badge/pwsh-7%2B-informational)

同时支持 **macOS**（AppleScript + 可选 Shortcuts）和 **Windows**（Chrome
DevTools 协议 + AutoHotkey / SendKeys）。两个平台使用相同的 CLI 契约。
macOS 默认通过 AppleScript 直接注入键盘，不再需要手动建 macOS
Shortcut。

```console
$ scripts/clip_webpages.sh "https://example.com/article"
[2026-07-04 17:00:00] Loaded config: config/clipper.conf
[2026-07-04 17:00:00] Vault path: /Users/me/Obsidian Vault
[2026-07-04 17:00:01] Opening Chrome for: https://example.com/article
[2026-07-04 17:00:03] Page loaded: Example Article — example.com
[2026-07-04 17:00:04] Triggering clipper via direct keystroke 'Shift+Option+S' (attempt 1/3)...
[2026-07-04 17:00:06] Markdown detected: /Users/me/Obsidian Vault/Inbox/Clippings/Example Article.md
[2026-07-04 17:00:06] Result: SUCCEEDED
```

---

## 特性

- 一条命令批量剪辑 —— 阅读清单一次搞定，不用逐个点扩展图标。
- 跨平台（macOS + Windows），共用同一套 CLI 契约。
- 复用你现有的 Obsidian Web Clipper —— 不重新解析、不改变格式。
- **跨平台登录墙检测。** 页面加载完成后，脚本会通过 Chrome DevTools
  协议（Windows）或 Chrome AppleScript `execute javascript`（macOS）
  探测 URL、DOM 和正文文本（中英文）。命中就在触发 Web Clipper
  **之前**以 `SUSPECTED_LOGIN_WALL` 中止，不再默默剪出"请登录"垃圾
  内容。可用 `LOGIN_WALL_CHECK=0` 关掉。macOS 需要开一次 Chrome 权限，
  见[已知限制](#已知限制)。
- 自动重试 + 自适应轮询；失败留下的 `Untitled*.md` 会被自动清理。
- 作为可安装的 **AI Agent skill**（OpenClaw / Claude Code / Codex）分发，
  Agent 可以代你采集网页内容。

---

## 首次运行检查清单

在这台机器上首次成功剪辑之前，请确认**全部 4 条**：

1. **扩展已装**在本 skill 驱动的那个 Chrome profile 里。
   Windows 上首次运行会创建一个专属 `--user-data-dir` profile ——
   **不是**你日常用的那个 Chrome profile。
2. **手动按快捷键能弹出 Web Clipper。** 在那个 Chrome 里随便打开一个页面，
   自己按一下快捷键，确认 Web Clipper 弹窗出现。没反应就去
   `chrome://extensions/shortcuts` 绑定。
3. **配置和 Chrome 一致。** 配置文件里的 `CLIP_SHORTCUT` 必须等于你在
   Chrome 里实际绑定的按键组合。
4. **目标网站你已经在被驱动的 Chrome profile 里登录了。** 两个平台的
   脚本层都会在页面加载后跑登录墙探针（Windows 通过 CDP，macOS 通过
   AppleScript），命中就以 `SUSPECTED_LOGIN_WALL` 中止该 URL（见
   "特性"节）。macOS 需要一次性打开 Chrome 的"允许 Apple 事件中的
   JavaScript"，否则探针会打印提示并让剪辑继续跑（此时没有安全网）。

   两个平台都建议：剪辑已知需要登录的 URL（Medium 会员文章、微信订阅号、
   私密 Notion 页面、Twitter/X 主页、企业 SSO 等）之前，**先在被驱动的
   Chrome profile 里登录该网站**。

### ⚠️ 全新机器的首次运行注定失败

首次运行会启动一个**没装任何扩展**的全新 Chrome profile，三次重试全部
失败后脚本会退出。这属于**预期行为**。此时**不要关掉那个 Chrome 窗口**，
按下面步骤操作：

1. 在这个新 profile 里安装 [Obsidian Web Clipper][Obsidian Web Clipper] 扩展。
2. 打开扩展设置，把"Save to"目录设成和你 `CLIP_OUTPUT_DIR` 一致的路径。
3. 到 `chrome://extensions/shortcuts` 绑定快捷键。
4. 重新跑一次 —— 第一次尝试就会成功。

macOS 完整流程（含可选的 Shortcut 路径）见
[`references/usage.md`](references/usage.md)，
Windows 见 [`references/usage-windows.md`](references/usage-windows.md)。

---

## 环境要求

- **Google Chrome**，并安装了 [Obsidian Web Clipper] 扩展。
- 本地文件系统上的 **Obsidian vault**。
- **macOS**：macOS 13+、Shortcuts App、命令行 `shortcuts` CLI。
- **Windows**：PowerShell 7+（`winget install Microsoft.PowerShell`）；
  可选 AutoHotkey v2（`winget install AutoHotkey.AutoHotkey`）。
  没装 AHK 时会自动回退到 `SendKeys` 驱动。

[Obsidian Web Clipper]: https://chromewebstore.google.com/detail/obsidian-web-clipper/cnjifjpddelmedmihgijeibhnjfabmlf

---

## 快速开始

### macOS

```bash
git clone https://github.com/CharlotteLiii/obsidian-clipper-autotrigger.git
cd obsidian-clipper-autotrigger
cp config/clipper.conf.example config/clipper.conf
# 编辑 VAULT_PATH、CLIP_OUTPUT_DIR、CLIP_SHORTCUT 匹配你的环境。
scripts/install.sh
scripts/clip_webpages.sh --dry-run "https://example.com"
```

### Windows（PowerShell 7+）

```powershell
git clone https://github.com/CharlotteLiii/obsidian-clipper-autotrigger.git
cd obsidian-clipper-autotrigger
Copy-Item config\clipper.win.conf.example config\clipper.win.conf
# 编辑 VAULT_PATH、CLIP_OUTPUT_DIR、CLIP_SHORTCUT 匹配你的环境。
pwsh -NoProfile -File scripts\install.ps1
pwsh -NoProfile -File scripts\clip_webpages.ps1 -DryRun "https://example.com"
```

<details>
<summary><b>更喜欢 Agent 一行安装？</b>（curl / iwr）</summary>

告诉你的 AI Agent（OpenClaw / Codex / Claude 等）：

> "把 https://github.com/CharlotteLiii/obsidian-clipper-autotrigger 装成 skill"

或者自己跑一条 bootstrap：

```bash
# macOS / Linux
bash <(curl -fsSL https://raw.githubusercontent.com/CharlotteLiii/obsidian-clipper-autotrigger/main/bootstrap.sh)
```

```powershell
# Windows
iwr -useb https://raw.githubusercontent.com/CharlotteLiii/obsidian-clipper-autotrigger/main/bootstrap.ps1 | iex
```

bootstrap 会：自动识别你的 Agent skills 目录（OpenClaw → Claude Code
→ Codex 优先级）、`git clone` 到该目录、运行对应平台的 installer、
打印一份"还需要你填这些字段"的清单。装完记得重启 Agent，让它重新
扫描 skills。

在把脚本喂进 shell 之前，建议先看一眼源代码 —— 两个 bootstrap 都很短，
只做了 `git clone` + 调用仓库自带的 installer，别的什么都没做。

</details>

---

## 配置

`config/clipper.conf`（macOS）和 `config/clipper.win.conf`（Windows）都在
`.gitignore` 里。从 `*.example` 模板复制一份，编辑下表这些字段即可，其余
参数都有安全的默认值。

| Key                    | 作用                                                                                                                       | 默认值                             |
|------------------------|----------------------------------------------------------------------------------------------------------------------------|------------------------------------|
| `VAULT_PATH`           | Obsidian vault 的绝对路径，必须存在。                                                                                       | *（必填）*                         |
| `CLIP_OUTPUT_DIR`      | vault 里 Web Clipper 保存 Markdown 的相对目录，需和扩展"Save to"设置一致。留空则扫描整个 vault。                            | `""`（整个 vault）                 |
| `CLIP_SHORTCUT`        | 你在 `chrome://extensions/shortcuts` 里为 Obsidian Web Clipper 绑定的按键组合，必须和 Chrome 里完全一致。                    | `Shift+Option+S` / `Shift+Alt+S`   |
| `SHORTCUT_NAME`        | *（仅 macOS，可选）* 用来触发扩展的 macOS Shortcut 名称。留空则使用 AppleScript 直接注入键盘（默认）。模板见 `references/usage.md`。 | *（空）*                          |
| `TRIGGER_DRIVER`       | *（仅 Windows）* `ahk`（AutoHotkey v2）或 `sendkeys`。                                                                       | `sendkeys`                         |
| `CHROME_USER_DATA_DIR` | *（仅 Windows）* 可选，用于指定驱动的 Chrome profile。留空则在 `%LOCALAPPDATA%` 下创建一个专属 profile。                     | `""`                               |
| `LOGIN_WALL_CHECK`     | `1` 启用页面加载后的登录墙探针（Windows 走 CDP，macOS 走 AppleScript），命中则中止该 URL；`0` 关闭探针（等同旧版行为）。       | `1`                                |
| `LOGIN_WALL_MIN_TEXT`  | 正文可见文本短于该阈值 + 命中弱信号时视为可疑。如果你经常剪辑合理的短页面，调高该值。                                        | `300`                              |

计时相关参数——`PAGE_LOAD_TIMEOUT`、`RENDER_GRACE_SECONDS`、
`CLIP_TIMEOUT`、`MAX_RETRIES`、`POLL_INTERVAL`——一般不用改，
详见 `.example` 文件里的注释。

---

## 使用

```bash
# macOS
scripts/clip_webpages.sh "https://example.com/article"
scripts/clip_webpages.sh "https://a.com" "https://b.com" "https://c.com"
scripts/clip_webpages.sh --dry-run "https://example.com"
scripts/clip_webpages.sh --config /absolute/path/to/clipper.conf "https://example.com"
```

```powershell
# Windows
pwsh -NoProfile -File scripts\clip_webpages.ps1 "https://example.com"
pwsh -NoProfile -File scripts\clip_webpages.ps1 -DryRun "https://a.com" "https://b.com"
pwsh -NoProfile -File scripts\clip_webpages.ps1 -Config "D:\my.conf" "https://x.com"
```

或者直接告诉 AI Agent：*"用 Obsidian-Clipper-AutoTrigger 把
&lt;URL&gt; 存到 Obsidian 里。"*

退出码：`0` 全部剪辑成功；`1` 有 URL 失败（含 `SUSPECTED_LOGIN_WALL`
中止）；`2` 配置或参数错误。

---

## 故障排查

> **当脚本报 `Result: FAILED` 时，登录墙是头号嫌疑。**
> 先在日志里找 `ERROR: SUSPECTED_LOGIN_WALL: <reason>` —— 两个平台的
> 探针都会把命中的原因直接写出来，不用猜。只有探针被关掉、或 macOS 上
> Chrome 的"允许 Apple 事件中的 JavaScript"没打开时，脚本才会分不清
> 登录重定向和其他失败，只看到"重试 N 次都没新 Markdown"。
> 在怀疑扩展、快捷键、超时之前，先在**被驱动的**那个 Chrome profile 里
> 手动打开那个 URL，看页面到底渲染出了什么。如果看到登录表单、
> "请登录后阅读"回横、或付费墙，那就是原因。在那个 profile 里登录后
> 重跑即可。

| 现象                                        | 常见原因                                                                                                                      |
|---------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|
| `ERROR: SUSPECTED_LOGIN_WALL: <原因>`（两个平台） | 页面加载后的探针命中了登录 / 付费墙信号。在被驱动的 Chrome profile 里登录该网站后重跑。                                        |
| 每次都失败，vault 里没生成任何 Markdown     | **先看上面的提示：这个 URL 是不是需要登录？** 如果不是，再排查：被驱动的 profile 里没装扩展，或快捷键没绑。                     |
| Web Clipper 弹窗有，但没 `.md` 生成         | `CLIP_OUTPUT_DIR` 和扩展"Save to"目录对不上。                                                                                 |
| 剪出来的 Markdown 只有"请登录"字样            | 该 URL 需要登录，但探针被关掉或漏过了。先在被驱动的 Chrome profile 里登录该网站，然后重跑；macOS 请顺便确认 Chrome 已开启"允许 Apple 事件中的 JavaScript"。 |
| `SUSPECTED_LOGIN_WALL` 误报                   | 调高 `LOGIN_WALL_MIN_TEXT`，或者在配置里设 `LOGIN_WALL_CHECK=0` 关掉探针（macOS 改 `clipper.conf`，Windows 改 `clipper.win.conf`）。 |
| Windows：找不到 `pwsh`                       | `winget install Microsoft.PowerShell`。                                                                                       |
| Windows：`SendKeys` 把键发到别的窗口去了    | 有别的窗口抢焦点。改用 `TRIGGER_DRIVER=ahk` + AutoHotkey v2，比 SendKeys 稳。                                                  |
| macOS：`shortcuts list` 什么都不返回        | 到*系统设置 → 隐私与安全性 → 自动化*里给 Shortcuts 授权。                                                                     |

需要深入排查时跑 `scripts/preflight.sh` / `scripts\preflight.ps1` ——
它会探测 Chrome CDP、列出驱动 profile 里装了哪些扩展、验证 vault 路径。

---

## 已知限制

- **登录墙探针是启发式的**，不完美。它综合使用 URL 路径正则、DOM 探测、
  和正文短语匹配（中英文）。合法的短页面 + 认证风格 URL 依然可能踩坑。
  遇到误报时：调高 `LOGIN_WALL_MIN_TEXT`、扩展短语列表（Windows 在
  `Test-CdpLoginWall`，macOS 在 `chrome_login_wall_probe.scpt`）、
  或者用 `LOGIN_WALL_CHECK=0` 关闭探针。
- **macOS 探针需要 Chrome 手动授权一次。** 到 *显示 → 开发者 → 允许
  Apple 事件中的 JavaScript* 打开开关。未开启时探针会记录提示并让
  剪辑继续跑，但没有安全网。
- **只查同源。** 探针跑在目标标签页的主 frame 里，跨域 iframe 里的
  登录墙不会被检查到。

---

## 给 AI Agent 用的入口

AI Agent（OpenClaw / Claude Code / Codex）安装或运行本 skill 时，读
**[`AGENT_INSTALL.md`](AGENT_INSTALL.md)** —— 这份文件是 `clone →
configure → link → verify` 的机器可读契约。Agent 运行时加载的入口是
[`SKILL.md`](SKILL.md)。`SKILL.md` 里还定义了一个**每次剪辑前必跑的
登录检查**（Workflow 里的 Step 0）—— 脚本层的探针是安全网，
不能替代 agent 主动询问用户"你是否已经在被驱动的 profile 里登录了
这个已知需要登录的网站"。

---

## 仓库结构

```
Obsidian-Clipper-AutoTrigger/
├── SKILL.md                          # Agent 运行时入口
├── AGENT_INSTALL.md                  # 面向 AI Agent 的安装契约
├── README.md                         # 本文件
├── CHANGELOG.md · CONTRIBUTING.md · LICENSE
├── bootstrap.sh · bootstrap.ps1      # Agent 一行安装脚本
├── config/
│   ├── clipper.conf.example          # macOS 配置模板
│   ├── clipper.win.conf.example      # Windows 配置模板
│   └── clipper.conf                  # 本地生成，已在 .gitignore
├── scripts/
│   ├── clip_webpages.sh              # macOS 入口（含登录墙探针）
│   ├── clip_webpages.ps1             # Windows 入口（含登录墙探针）
│   ├── install.sh · install.ps1      # 平台 installer
│   ├── preflight.sh · preflight.ps1  # 环境自检
│   ├── lib/Cdp.psm1                  # Windows CDP 客户端 + Test-CdpLoginWall
│   └── trigger/                      # Windows 按键驱动
├── applescripts/                     # macOS Chrome / Shortcut 胶水层（含登录墙探针）
├── references/                       # 详细使用文档
└── agents/                           # Agent 相关元数据
```

---

## 隐私

`config/clipper.conf` 和 `config/clipper.win.conf` 都在 `.gitignore` 里
—— 它们含有 vault 的绝对路径，绝对不能提交到仓库。仓库里只有 `*.example`
模板文件。

## Changelog & 贡献

- [`CHANGELOG.md`](CHANGELOG.md) —— 版本记录，遵循 SemVer。
- [`CONTRIBUTING.md`](CONTRIBUTING.md) —— 如何提交改动。

## License

[MIT](LICENSE) © Charlotte Li
