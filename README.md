# supercode

Run multiple [Claude Code](https://claude.ai/code) sessions in parallel — each in its own git worktree, all in one tmux window.

![Bash](https://img.shields.io/badge/Bash-4.0%2B-green)
![License](https://img.shields.io/badge/License-MIT-blue)

![supercode in action](screenshot.png)

## What it does

- Spawns N parallel Claude Code agents, each working in an isolated git worktree off your current HEAD
- Arranges them in a single tmux window with a tiled pane layout
- Includes a **Brain** pane — an orchestrator agent that coordinates the workers, dispatches tasks, and monitors progress
- Provides commands to peek at agent screens, send messages, broadcast to all, save/merge work, and roll back

## Requirements

- **Bash 4.0+** (macOS ships 3.x — `brew install bash`)
- **git**
- **tmux** (`brew install tmux` on macOS)
- **[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)** (`claude` must be in your PATH)

## Install

```bash
git clone https://github.com/Haro321/supercode.git
cd supercode
./install.sh
```

Or manually copy the `supercode` script to somewhere in your `$PATH`:

```bash
cp supercode ~/.local/bin/supercode
chmod +x ~/.local/bin/supercode
```

## Usage

```bash
# Launch 5 workers + brain, describe your project interactively
supercode

# Launch with tasks — brain coordinates and dispatches
supercode "build the auth API" "create the React frontend" "write integration tests"

# Legacy direct mode: one agent per task, no brain
supercode --direct "fix login bug" "add rate limiting"

# Interactive: prompts for agent count and tasks
supercode -i

# Read tasks from a file (one per line)
supercode -f tasks.txt
```

## Commands

| Command | Description |
|---|---|
| `supercode` | Launch 5 workers + brain (asks what to build) |
| `supercode "task1" "task2" ...` | Launch and dispatch tasks via brain |
| `supercode --direct "t1" ... "tN"` | One pane per task, no brain |
| `supercode attach` | Reattach to the running tmux session |
| `supercode list` | Show worktrees and session status |
| `supercode peek <N\|all>` | View an agent's screen (or all agents) |
| `supercode tell <N> "msg"` | Send a message to agent N |
| `supercode broadcast "msg"` | Send a message to every agent |
| `supercode brain` | Add a brain pane to an existing session |
| `supercode save` | Commit + merge all agents into your branch |
| `supercode unsave` | Undo the last save |
| `supercode rollback` | Rewind to pre-launch state |
| `supercode kill` | Kill the tmux session (worktrees kept) |
| `supercode clean` | Kill session + remove worktrees |
| `supercode label set <N> "text"` | Set a short label on agent N's border |
| `supercode label auto` | Auto-derive labels from pane titles |
| `supercode label list` | Show current labels and accent colors |

## How it works

1. Each agent gets its own git worktree branched from your current HEAD
2. Worktrees live in `~/.supercode/<repo>/agent-N/`
3. Branch names follow `supercode/agent-N-<timestamp>`
4. The brain agent coordinates work — it reads agent screens, dispatches tasks, and keeps agents from conflicting
5. `supercode save` auto-commits pending changes in each worktree, then merges all agent branches into your current branch with `--no-ff` merge commits

## tmux tips

| Keys | Action |
|---|---|
| `Ctrl-b` + arrow | Switch pane |
| `Ctrl-b z` | Zoom/fullscreen current pane |
| `Ctrl-b d` | Detach (leave running) |
| `Ctrl-b [` | Scroll mode (`q` to exit) |
| Click a pane | Focus it (mouse mode enabled) |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `SUPERCODE_HOME` | `~/.supercode` | Where worktrees are created |
| `SUPERCODE_BOOT_DELAY` | `3` | Seconds to wait for Claude to boot before sending tasks |

## License

MIT
