# supercode

Run multiple [Claude Code](https://claude.ai/code) sessions in parallel — each in its own git worktree, all inside one tmux window.

![Bash](https://img.shields.io/badge/Bash-4.0%2B-green)
![License](https://img.shields.io/badge/License-MIT-blue)

![supercode in action](screenshot.png)

## Why

A single AI coding agent is powerful. But real projects have multiple independent pieces — an API, a frontend, tests, database migrations, documentation. Doing them one at a time is slow.

**supercode** lets you work on all of them at once. Five Claude Code agents run in parallel, each in an isolated copy of your repo, while a sixth **Brain** agent orchestrates the whole thing. What used to take an hour of sequential back-and-forth now takes minutes.

## The Brain

The Brain is the key difference between supercode and just opening five terminals.

When you launch supercode with tasks, the Brain:

1. **Reads your tasks** and figures out how they relate to each other
2. **Designs a coordination plan** — shared interfaces, naming conventions, file ownership — so agents don't step on each other
3. **Dispatches composed instructions** to each worker, telling them not just *what* to build but *what the other agents are doing* so they stay compatible
4. **Monitors progress** by peeking at agent screens and checking their git status
5. **Follows up** with agents that get stuck or drift off course

Without the Brain, five agents writing code in the same repo would produce five conflicting implementations. The Brain turns them into a coordinated team.

## Install

```bash
git clone https://github.com/Haro321/supercode.git
cd supercode
./install.sh
```

Or just copy the script:

```bash
cp supercode ~/.local/bin/supercode
chmod +x ~/.local/bin/supercode
```

**Requires:** Bash 4+, git, tmux, and the [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude` in your PATH). On macOS, `brew install bash tmux`.

## Usage

```bash
# Just launch — the brain asks what you want to build
supercode

# Give it tasks — the brain coordinates and dispatches
supercode "build the auth API" "create the React frontend" "write integration tests"

# Direct mode: one agent per task, no brain
supercode --direct "fix login bug" "add rate limiting"
```

### Talking to agents

```bash
supercode peek all              # see what every agent is doing
supercode peek 3                # check on agent 3
supercode tell 2 "use JWT"      # send a message to agent 2
supercode broadcast "stop"      # message all agents
```

### Saving the work

```bash
supercode save                  # commit + merge all agent work into your branch
supercode unsave                # undo the last save
supercode rollback              # rewind to the state before supercode launched
```

### Cleanup

```bash
supercode kill                  # kill the tmux session (worktrees stay)
supercode clean                 # kill session + remove worktrees
```

## How it works

1. Snapshots your current branch so you can always roll back
2. Creates a git worktree per agent — isolated copies of your repo that share the same `.git`
3. Opens a tmux session with a 2x3 grid: 5 worker panes + 1 brain pane
4. Each worker runs `claude` in its own worktree. The brain runs in the main repo
5. When you're done, `supercode save` auto-commits each agent's changes and merges them all into your branch

No files conflict because each agent works in its own worktree on its own branch. The brain makes sure they don't *logically* conflict either.

## License

MIT
