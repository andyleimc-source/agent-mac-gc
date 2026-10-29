# agent-mac-gc

**Zero-config macOS garbage collector & process reaper built specifically for AI Agent / Vibe Coding workloads (Claude Code, Codex Desktop, Cursor, Antigravity, and MCP servers).**

> **中文简介**：专为 **Claude Code / Codex / Cursor / Antigravity / MCP** 重度用户设计的 macOS 自动巡检与垃圾回收工具（零外部依赖，纯 Python 标准库 + LaunchAgent）。解决传统清理工具（CleanMyMac、Mole 等）完全看不见的「AI 编程特有病灶」：**断连 MCP 僵尸进程堆积、Codex 桌面端跨会话泄漏上百个 MCP 子树、`uvx` 孤儿虚拟环境暴涨 60GB+、多 git worktree 编译导致的 150GB+ `DerivedData` 与 Spotlight (`mds_stores`) 偷跑几十小时 CPU、以及长待机 Mac 上 120GB+ 的 Chrome `code_sign_clone` 残留**。

---

## Why Traditional Mac Cleaners Miss 80% of Vibe Coding Bloat

Generic Mac cleaners (`Mole`, `mac-cleanup-py`, `CleanMyMac`) only wipe standard folders like `~/Library/Caches` or blindly delete `DerivedData`. When you run multiple AI coding agents and MCP servers all day on a Mac with weeks of uptime, four invisible failure modes slow your machine to a crawl:

| Failure Mode | What Happens Under the Hood | Real-World Impact | How `agent-mac-gc` Fixes It |
| :--- | :--- | :--- | :--- |
| **1. Orphaned MCP Stdio Daemons & Codex Thread Leaks** | When agent sessions exit or new threads open in ChatGPT/Codex Desktop (`codex app-server`), `npx`/`uvx` MCP stdio processes (`*-mcp*`, `workspace-mcp`, `email-mcp`, `SkyComputerUseClient`, etc.) are left behind with broken pipes or duplicated across dozens of idle threads. | **150–250+ zombie Node/Python processes**, **10–25 GB Swap** exhaustion. | Inspects `lsof` file descriptors (`0,1`) for peerless pipes on `PPID=1` tools and reaps `codex app-server` MCP subtrees older than 2 hours—without touching active sessions. |
| **2. Multi-Worktree `DerivedData` + Spotlight CPU Drain** | Agents spin up isolated git worktrees to build/test iOS/macOS apps. Each worktree leaves a `1–5 GB` `<Project>-<hash>` folder in `Xcode/DerivedData` after the worktree is removed. Worse, macOS Spotlight (`mds_stores`) indexes `DerivedData` nonstop. | **80–150 GB** disk bloat + **30+ hours of cumulative `mds_stores` CPU time**. | Automatically migrates `DerivedData` to `DerivedData.noindex` via symlink (stopping Spotlight permanently), parses each folder's `info.plist` (`:WorkspacePath`), and immediately deletes caches whose worktree no longer exists (while ignoring background `WebDriverAgent` runner processes). |
| **3. `uv` / `uvx` Ephemeral Virtualenv Explosion** | Running Python MCP servers via `uvx` creates isolated environments in `~/.cache/uv/archive-v0` that accumulate across package updates. | **20–60+ GB** hidden in `~/.cache/uv`. | Checks active `ps` arguments for mounted `archive-v0` hashes and prunes unreferenced environments idle for >3 days. |
| **4. Chrome `code_sign_clone` Leftovers on Long-Uptime Macs** | On Macs that go weeks without rebooting, Chrome's background updater clones the entire 2.1 GB app bundle into `/private/var/folders/.../X/com.google.Chrome.code_sign_clone/code_sign_clone.*` and fails to delete old clones. | **50–130+ GB** hidden in `/private/var/folders`. | Queries `lsof` for the currently mapped Chrome clone and removes all inactive clones older than 12 hours. |
| **5. Stale Agent Artifacts & Dev Servers** | Old `~/.codex/packages/standalone/releases`, abandoned `~/.codex/worktrees`, `~/.gemini/*/browser_recordings`, idle `GradleDaemon`/`KotlinCompileDaemon`, and forgotten `python -m http.server` / `next dev` processes running for weeks. | **15–40 GB** disk + **1.5–3 GB RAM**. | Automatically reaps orphaned temporary dev servers (>24h), idle Gradle daemons (>2h), old Codex releases/worktrees (>3d), and old iOS `DeviceSupport` symbols (>30d). |

---

## Quick Start

### 1. One-Line Install

```bash
git clone https://github.com/andyleimc-source/agent-mac-gc.git ~/.agent-mac-gc
~/.agent-mac-gc/bin/agent-mac-gc status
```

Or add `bin/agent-mac-gc` to your `~/.local/bin`:

```bash
ln -sf ~/.agent-mac-gc/bin/agent-mac-gc ~/.local/bin/agent-mac-gc
```

### 2. Audit What Can Be Reclaimed (Safe Dry-Run)

```bash
agent-mac-gc status
```

### 3. Execute Immediate Cleanup

```bash
# Run both process reaper and cache garbage collection
agent-mac-gc run --apply

# Or run only the fast process + Chrome clone reaper
agent-mac-gc run --apply --mode session

# Or run only the build/agent cache garbage collector
agent-mac-gc run --apply --mode caches
```

### 4. Enable Automatic Two-Tier Background Protection (`launchd`)

```bash
agent-mac-gc install
```

This installs and loads two lightweight per-user `LaunchAgents` in `~/Library/LaunchAgents`:
- **`io.github.agent-mac-gc.session`** (runs every **15 minutes**): Reaps disconnected MCP stdio processes, stale Codex `app-server` MCP subtrees (>2h), orphaned temporary dev servers (>24h), idle Gradle daemons (>2h), and inactive Chrome `code_sign_clone` bundles.
- **`io.github.agent-mac-gc.daily`** (runs daily at **04:00 AM**): Enforces the `DerivedData -> DerivedData.noindex` Spotlight guard, cleans orphaned git-worktree Xcode build caches, prunes unused `uv/archive-v0` environments, removes old Codex releases/worktrees and Antigravity browser recordings (>3d), and cleans unavailable iOS simulators & unused `iOS DeviceSupport` (>30d).

To remove the background agents at any time:

```bash
agent-mac-gc uninstall
```

---

## Safety Guarantees

1. **Dry-Run by Default**: `agent-mac-gc` and `agent-mac-gc status` never modify processes or files unless `run --apply` is explicitly passed.
2. **Process Identity Verification**: Before sending `SIGTERM` to any orphaned process tree, `agent-mac-gc` re-verifies `(pid, ppid, lstart, comm)` and checks `lsof` file descriptors so active MCP pipes or `launchd`-managed services are never killed.
3. **Active Build Guard**: Xcode `DerivedData` cleanup is automatically skipped if a real `xcodebuild` is running (while properly ignoring `iphone-use` / `WebDriverAgent` `test-without-building` daemons).
4. **Zero Dependencies**: Written in 100% standard-library Python 3 for macOS. No `pip install` or root (`sudo`) required.

---

## License

MIT
