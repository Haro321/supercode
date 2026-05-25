#!/usr/bin/env bash
# Brain pane creation and prompt generation.

_create_brain_pane() {
  local session=$1
  local existing
  existing=$(_brain_pane_id "$session")
  if [[ -n "$existing" ]] \
     && tmux list-panes -t "$session:0" -F '#{pane_id}' | grep -qx "$existing"; then
    printf '%s' "$existing"
    return 1
  fi
  tmux split-window -t "$session:0" -v -f -c "$REPO_ROOT"
  local brain_idx brain_id
  brain_idx=$(tmux list-panes -t "$session:0" -F '#{pane_index}' | sort -n | tail -1)
  brain_id=$(tmux list-panes -t "$session:0" -F '#{pane_index} #{pane_id}' \
    | awk -v i="$brain_idx" '$1==i {print $2; exit}')
  tmux set-option -wq -t "$session:0" "@brain-pane" "$brain_id"
  tmux select-pane -t "$brain_id" -T "brain"
  local win_h
  win_h=$(tmux display-message -t "$session:0" -p '#{window_height}')
  tmux resize-pane -t "$brain_id" -y "$(( win_h * 44 / 100 ))"
  tmux send-keys -t "$brain_id" "clear && claude ${SUPERCODE_CLAUDE_ARGS:-}" Enter
  printf '%s' "$brain_id"
}

_build_dispatch_prompt() {
  local n=$1 task_count=$2
  shift 2
  local tasks=("$@")
  local prompt
  prompt="You are the Brain -- orchestrator of this supercode session. The user wants $n parallel Claude agents to work together on a shared project. Your job RIGHT NOW is to dispatch a coordinated task to each agent so they understand each other and don't conflict."$'\n\n'
  prompt+="STEPS:"$'\n'
  prompt+="1. Read the tasks below carefully. Identify the shared project (these are almost certainly parts of one system -- figure out which one)."$'\n'
  prompt+="2. In 1-2 sentences, summarize the overall project and the shared elements: module structure, file paths, naming conventions, data types/interfaces that more than one agent will touch."$'\n'
  prompt+="3. For each agent K (1..$n), compose a coordinated task message and dispatch it with:"$'\n'
  prompt+="     supercode tell K \"composed message\""$'\n'
  prompt+="   Each composed message should include: (a) the agent's specific work, (b) one sentence of project context, (c) brief note on what OTHER agents are building (so this agent doesn't duplicate or conflict), (d) any shared conventions/interfaces to follow."$'\n'
  if (( task_count < n )); then
    prompt+="   The user gave only $task_count tasks but you have $n agents -- assign useful complementary work (tests, docs, code review, etc.) to the spare agents."$'\n'
  elif (( task_count > n )); then
    prompt+="   The user gave $task_count tasks but you have only $n agents -- combine related tasks where it makes sense."$'\n'
  fi
  prompt+="4. After all $n agents are dispatched, say \"all $n agents launched\" and wait for the user's next message. From then on you coordinate -- use 'supercode peek all' to check progress, 'supercode tell K ...' to follow up, 'supercode broadcast ...' to notify everyone."$'\n\n'
  prompt+="AGENTS: 1..$n  (worktrees at $WORKTREE_BASE/agent-K)"$'\n\n'
  prompt+="TASKS THE USER GAVE:"$'\n'
  local k=1
  for t in "${tasks[@]}"; do
    prompt+="  $k. $t"$'\n'
    ((k++))
  done
  prompt+=$'\n'"Begin."
  printf '%s' "$prompt"
}

_build_idle_prompt() {
  local n=$1
  local prompt
  prompt="You are the Brain -- orchestrator of this supercode session. There are $n parallel Claude agents (agent-1 .. agent-$n) booted in worktrees at $WORKTREE_BASE/agent-K, sitting idle and waiting for instructions."$'\n\n'
  prompt+="The user hasn't told you what to build yet. Your job:"$'\n'
  prompt+="1. Greet them in one short sentence and ask what they want to build (a project, a feature, a change to an existing codebase, etc.). Stay concise -- one or two questions."$'\n'
  prompt+="2. Once you understand the goal, design how to split the work across up to $n agents. Identify shared elements (modules, file paths, conventions, data types) that more than one agent will touch."$'\n'
  prompt+="3. Dispatch a coordinated task to each agent with:"$'\n'
  prompt+="     supercode tell K \"composed message\""$'\n'
  prompt+="   Each message should include: (a) the agent's specific work, (b) one sentence of project context, (c) brief note on what OTHER agents are doing, (d) shared conventions/interfaces to follow."$'\n'
  prompt+="4. After dispatching, stay interactive. Use 'supercode peek all' to check progress, 'supercode tell K ...' for follow-ups, 'supercode broadcast ...' for everyone."$'\n\n'
  prompt+="You coordinate; you do not write code yourself. Begin by greeting the user and asking what they want to build."
  printf '%s' "$prompt"
}

_build_posthoc_prompt() {
  local agent_count=$1
  local prompt
  prompt="You are the Brain for this supercode session -- orchestrator of $agent_count parallel Claude agents (agent-1 .. agent-$agent_count) working in worktrees at $WORKTREE_BASE/agent-K. Use these shell helpers: 'supercode peek <N>' to read agent N's screen, 'supercode peek all' for a snapshot of every agent (titles + git status + recent screen), 'supercode tell <N> \"msg\"' to send a message to one agent's Claude prompt, 'supercode broadcast \"msg\"' to send to all. You coordinate; you do not write code yourself. When the user asks how things are going, run 'supercode peek all' first. Reply 'ready' when oriented."
  printf '%s' "$prompt"
}

_build_interactive_brain_prompt() {
  local tasks=("$@")
  local prompt=""

  prompt+="You are the Brain -- the orchestrator of a supercode multi-agent session. No agents are running yet. Your job is to talk to the user, understand what they want to build, and create a plan."$'\n\n'

  if (( ${#tasks[@]} > 0 )); then
    prompt+="THE USER WANTS TO BUILD:"$'\n'
    for t in "${tasks[@]}"; do
      prompt+="  - $t"$'\n'
    done
    prompt+=$'\n'
  fi

  local ptype
  ptype=$(detect_project_type 2>/dev/null || echo "unknown")
  prompt+="PROJECT TYPE DETECTED: $ptype"$'\n\n'

  prompt+="AVAILABLE AGENT ROLES (pick up to 5):"$'\n'
  prompt+="  architect    — system design, API contracts, data models, file ownership"$'\n'
  prompt+="  backend      — server logic, API routes, services, middleware"$'\n'
  prompt+="  frontend     — UI components, pages, forms, client-side logic"$'\n'
  prompt+="  database     — schemas, migrations, seeds, queries"$'\n'
  prompt+="  qa           — tests, build/lint/typecheck verification"$'\n'
  prompt+="  security     — vulnerability auditing, auth, secrets"$'\n'
  prompt+="  reviewer     — code review, spec compliance, quality"$'\n'
  prompt+="  docs         — documentation, README, API docs"$'\n'
  prompt+="  devops       — CI/CD, Docker, deployment configs"$'\n'
  prompt+="  refactor     — refactoring for clarity and performance"$'\n'
  prompt+="  reproducer   — bug reproduction with minimal test cases"$'\n'
  prompt+="  debugger     — root cause investigation"$'\n'
  prompt+="  fixer        — targeted bug fixes"$'\n'
  prompt+="  ux           — user experience, interaction flows"$'\n'
  prompt+="  accessibility — WCAG, ARIA, keyboard nav, screen readers"$'\n'
  prompt+="  mapper       — codebase mapping, dependency analysis"$'\n'
  prompt+="  compatibility — backward compat, migration paths"$'\n'
  prompt+="  reverser     — reverse engineering with Ghidra/GhidraMCP + x64dbg/gdb"$'\n\n'

  prompt+="PRESET SHORTCUTS (for reference):"$'\n'
  prompt+="  webapp     = architect, backend, frontend, database, qa"$'\n'
  prompt+="  api        = architect, backend, database, security, qa"$'\n'
  prompt+="  fullstack  = architect, backend, frontend, database, qa, reviewer"$'\n'
  prompt+="  ui         = architect, frontend, ux, accessibility, qa"$'\n'
  prompt+="  bugfix     = reproducer, debugger, fixer, qa"$'\n'
  prompt+="  refactor   = mapper, refactor, compatibility, qa"$'\n'
  prompt+="  security   = architect, security, backend, qa"$'\n'
  prompt+="  reverse    = reverser, mapper, security, docs"$'\n'
  prompt+="  malware    = reverser, security, mapper, debugger"$'\n\n'

  prompt+="YOUR WORKFLOW:"$'\n'
  if (( ${#tasks[@]} > 0 )); then
    prompt+="1. Analyze the user's request above. Ask clarifying questions if needed (keep it brief — 1-2 questions max)."$'\n'
  else
    prompt+="1. Greet the user in one sentence. Ask what they want to build. Keep it brief."$'\n'
  fi
  prompt+="2. Once you understand the task, decide:"$'\n'
  prompt+="   - Which roles to assign (max 5 agents)"$'\n'
  prompt+="   - What each agent's specific task will be"$'\n'
  prompt+="   - File ownership for each role"$'\n'
  prompt+="3. Inspect the existing codebase (ls, find, cat key files) to understand the project structure."$'\n'
  prompt+="4. Create these files in .supercode/:"$'\n\n'

  prompt+="   .supercode/SPEC.md — requirements, acceptance criteria, out of scope"$'\n'
  prompt+="   .supercode/CONTRACTS.md — shared interfaces, API shapes, types, naming conventions"$'\n'
  prompt+="   .supercode/AGENTS.md — role assignments with specific tasks and file ownership"$'\n'
  prompt+="   .supercode/plan.json — machine-readable plan:"$'\n'
  prompt+='     {"task": "user request", "project_type": "detected", "agents": [{"role": "backend", "task": "specific task", "ownership": ["src/api/**"], "depends_on": []}]}'$'\n\n'

  prompt+="5. Set depends_on in plan.json for agents that need to wait. Example: frontend depends_on: [\"backend\", \"database\"] means frontend waits until backend and database signal done before starting main work."$'\n\n'

  prompt+="6. After creating all plan files, IMMEDIATELY run this command to launch the agents:"$'\n'
  prompt+="     supercode dispatch"$'\n'
  prompt+="   This will create worktrees and spawn agent panes in this tmux session automatically."$'\n'
  prompt+="   Each agent gets a shared/ directory where they can read/write files visible to all agents."$'\n\n'

  prompt+="7. After dispatch completes, enter AUTO-MONITORING MODE. Repeat this loop:"$'\n'
  prompt+="   a) Check agent status signals:  cat shared/status/*.json 2>/dev/null"$'\n'
  prompt+="      (agents write status: working, blocked, done)"$'\n'
  prompt+="   b) If any agent is BLOCKED, read their status message and help them:"$'\n'
  prompt+="      - If they need output from another agent, check shared/outputs/ and relay it"$'\n'
  prompt+="      - If they're stuck on a problem, send guidance: supercode tell K \"...\""$'\n'
  prompt+="   c) If an agent hasn't updated status in a while, peek at them: supercode peek K"$'\n'
  prompt+="   d) When ALL agents report status=done, move to REVIEW PHASE."$'\n\n'

  prompt+="8. REVIEW-FIX CYCLE (when all agents are done):"$'\n'
  prompt+="   a) Review all diffs:  supercode diff all"$'\n'
  prompt+="   b) Read each agent's key changes and compare against .supercode/SPEC.md"$'\n'
  prompt+="   c) CONTRACT VERIFICATION — check that:"$'\n'
  prompt+="      - All API endpoints in CONTRACTS.md are actually implemented"$'\n'
  prompt+="      - Shared types/interfaces match across agents (no mismatched field names or shapes)"$'\n'
  prompt+="      - File ownership was respected (no agent modified files outside its ownership)"$'\n'
  prompt+="   d) For each issue found, send a targeted fix request: supercode tell K \"fix: ...\""$'\n'
  prompt+="      After sending fixes, agents will update status back to 'working' then 'done'"$'\n'
  prompt+="   e) Re-check until all diffs are clean. Then tell the user: \"All agents done. Review complete. Run 'supercode save --dry-run' to preview the merge.\""$'\n\n'

  prompt+="RULES:"$'\n'
  prompt+="- Maximum 5 agents. Pick only the roles that are actually needed."$'\n'
  prompt+="- Do NOT write implementation code. Only planning documents."$'\n'
  prompt+="- Be specific about file paths, function names, and data shapes in contracts."$'\n'
  prompt+="- Inspect the codebase before planning — understand the existing structure."$'\n'
  prompt+="- You MUST run 'supercode dispatch' yourself after creating plan.json. Do not ask the user to do it."$'\n'
  prompt+="- During monitoring, check status signals regularly — don't wait for the user to ask."$'\n'

  if (( ${#tasks[@]} > 0 )); then
    prompt+=$'\n'"The user has already described what they want. Start analyzing and planning."
  else
    prompt+=$'\n'"Begin by greeting the user."
  fi

  printf '%s' "$prompt"
}
