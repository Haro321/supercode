#!/usr/bin/env bash
# Role definitions, presets, and role-aware prompt generation.

declare -gA ROLE_DESCRIPTIONS=(
  [architect]="Design system architecture, define API contracts, data models, shared types, and file ownership. You do NOT write implementation code — you write specs and contracts that other agents follow."
  [backend]="Implement server-side logic: API routes, services, middleware, authentication, and business logic. Follow the contracts and data models defined by the architect."
  [frontend]="Build UI components, pages, forms, client-side state, and routing. Follow the component structure and API contracts defined by the architect."
  [database]="Create database schemas, migrations, seeds, and query helpers. Define the data layer that backend and other agents depend on."
  [qa]="Write comprehensive tests (unit, integration, e2e) and run the project's build/test/lint/typecheck commands. Report failures to the Brain with the agent most likely responsible."
  [security]="Audit for security vulnerabilities: injection, XSS, CSRF, auth bypass, secrets exposure, insecure dependencies, and permission issues. Produce findings as actionable items."
  [reviewer]="Review all agent diffs for correctness, consistency, style, and adherence to the spec and contracts. Write a structured review report. Do NOT modify code — only review and report."
  [docs]="Write and update documentation: README, API docs, inline doc comments, .env.example, CHANGELOG, and setup guides. Ensure docs match the implementation."
  [devops]="Handle CI/CD pipelines, Dockerfiles, deployment configs, environment setup, and infrastructure-as-code. Ensure the project builds and deploys correctly."
  [refactor]="Refactor existing code for clarity, performance, and maintainability. Preserve all existing behavior and ensure backward compatibility."
  [reproducer]="Reproduce the reported bug with a minimal test case. Create a failing test that demonstrates the issue. Do NOT fix the bug — only reproduce it."
  [debugger]="Investigate the root cause of the bug through code analysis, tracing call paths, and reading logs. Identify the exact location and cause. Report findings to the Brain."
  [fixer]="Implement a targeted fix for the identified bug. Keep changes minimal and focused. Add a regression test for the fix."
  [ux]="Audit and improve user experience: interaction flows, error states, loading states, empty states, and user feedback. Focus on usability, not visual design."
  [accessibility]="Ensure accessibility compliance: WCAG AA, semantic HTML, ARIA labels, keyboard navigation, screen reader support, color contrast, and focus management."
  [mapper]="Map the codebase: dependencies, call graphs, module boundaries, and impact analysis for planned changes. Produce a clear map that other agents can use."
  [compatibility]="Ensure backward compatibility during refactoring: API stability, migration paths, deprecation warnings, and feature flags where needed."
  [reverser]="Reverse engineer binaries using Ghidra (static analysis, decompilation via GhidraMCP) and x64dbg/gdb (dynamic analysis, debugging). Analyze executables, shared libraries, firmware, and protocols. Identify functions, recover data structures, trace control flow, find vulnerabilities, and document findings."
  [selfmod]="Modify and improve the supercode tool itself. You are editing the tool that launched you. Supercode lives at ~/.local/bin/supercode (main entry point) and ~/.local/share/supercode/lib/ (all library modules). Read and understand the existing code before making changes. Test your changes by running 'supercode doctor' and 'supercode --help' after edits."
  [api]="Design API contracts across REST, GraphQL, and gRPC: resource schemas, versioning, authentication, pagination, error formats, and rate limits. Publish the contract so backend and frontend agents implement against the same shapes."
  [mobile]="Build mobile apps (iOS, Android, React Native, Flutter): screens, navigation, offline storage, push notifications, and deep links. Handle platform differences and the app lifecycle."
  [data]="Build data pipelines: ETL/ELT, warehouses, streaming, and schema evolution. Define data models, transformations, and quality checks that downstream consumers depend on."
  [ml]="Build and operate ML systems: model training, inference, evaluation, deployment, and drift monitoring. Define datasets, metrics, and reproducible training/eval pipelines."
  [prompt]="Design prompts and LLM pipelines: prompt templates, evals, structured output schemas, and cost/latency tuning. Build measurable, regression-tested prompt suites for LLM apps."
  [performance]="Profile and optimize performance: CPU, memory, latency, bundle size, and battery. Measure first, fix the real bottleneck, and prove the win with before/after benchmarks."
  [sre]="Own reliability: define SLIs/SLOs and error budgets, add observability (metrics, logs, traces), write runbooks, and lead incident response. Make failures detectable and recoverable."
  [legacy]="Modernize legacy code with gradual, low-risk migrations: characterization tests, strangler-fig wrappers, and parallel-run validation. Never break existing behavior."
)

declare -gA ROLE_DEFAULT_OWNERSHIP=(
  [architect]="*.md,.supercode/**"
  [backend]="src/api/**,src/server/**,src/services/**,src/middleware/**,src/routes/**,app/**,server/**"
  [frontend]="src/components/**,src/pages/**,src/views/**,src/hooks/**,src/styles/**,src/app/**,components/**,pages/**"
  [database]="migrations/**,prisma/**,src/db/**,src/models/**,db/**,schema/**,sql/**"
  [qa]="tests/**,test/**,__tests__/**,**/*.test.*,**/*.spec.*,cypress/**,e2e/**"
  [security]=""
  [reviewer]=""
  [docs]="docs/**,*.md,**/*.md"
  [devops]="Dockerfile*,docker-compose*,.github/**,.gitlab-ci*,Makefile,deploy/**,infra/**,k8s/**"
  [refactor]=""
  [reproducer]="tests/**,test/**"
  [debugger]=""
  [fixer]=""
  [ux]="src/components/**,src/pages/**"
  [accessibility]="src/components/**,src/pages/**"
  [mapper]=""
  [compatibility]=""
  [reverser]="analysis/**,notes/**,scripts/**,*.py,*.java,*.gdt,*.h,*.c"
  [selfmod]="~/.local/bin/supercode,~/.local/share/supercode/lib/**"
  [api]="openapi/**,proto/**,**/*.proto,**/*.graphql,schema/**,api/**"
  [mobile]="ios/**,android/**,mobile/**,lib/**"
  [data]="pipelines/**,etl/**,dbt/**,dags/**,data/**,warehouse/**"
  [ml]="ml/**,models/**,training/**,notebooks/**,**/*.ipynb"
  [prompt]="prompts/**,evals/**"
  [performance]=""
  [sre]="observability/**,runbooks/**,slo/**,monitoring/**,alerts/**"
  [legacy]=""
)

declare -gA PRESETS=(
  [webapp]="architect,backend,frontend,database,qa"
  [api]="architect,backend,database,security,qa"
  [fullstack]="architect,backend,frontend,database,qa,reviewer"
  [ui]="architect,frontend,ux,accessibility,qa"
  [bugfix]="reproducer,debugger,fixer,qa"
  [refactor]="mapper,refactor,compatibility,qa"
  [security]="architect,security,backend,qa"
  [docs]="architect,backend,docs,qa"
  [backend-only]="architect,backend,database,qa"
  [frontend-only]="architect,frontend,ux,qa"
  [reverse]="reverser,mapper,security,docs"
  [malware]="reverser,security,mapper,debugger"
  [mobile-app]="architect,mobile,backend,api,qa"
  [ml-project]="architect,ml,data,backend,qa"
  [llm-app]="architect,prompt,backend,api,qa"
  [modernize]="mapper,legacy,refactor,compatibility,qa"
  [perf]="mapper,performance,qa"
  [incident]="sre,debugger,fixer,qa"
)

resolve_preset() {
  local preset=$1
  local roles="${PRESETS[$preset]:-}"
  [[ -n "$roles" ]] || die "unknown preset: $preset (available: ${!PRESETS[*]})"
  echo "$roles"
}

parse_roles() {
  local input=$1
  local -a roles clean=()
  local role
  IFS=',' read -ra roles <<< "$input"
  for role in "${roles[@]}"; do
    # strip surrounding whitespace so "backend, frontend" works
    role="${role#"${role%%[![:space:]]*}"}"
    role="${role%"${role##*[![:space:]]}"}"
    [[ -n "$role" ]] || continue
    [[ -n "${ROLE_DESCRIPTIONS[$role]:-}" ]] || die "unknown role: $role (available: ${!ROLE_DESCRIPTIONS[*]})"
    clean+=("$role")
  done
  [[ ${#clean[@]} -gt 0 ]] || die "no valid roles given in: $input"
  (IFS=','; echo "${clean[*]}")
}

list_presets() {
  echo "${C_BOLD}Available presets:${C_RESET}"
  for preset in $(echo "${!PRESETS[@]}" | tr ' ' '\n' | sort); do
    printf "  ${C_BOLD}%-15s${C_RESET} %s\n" "$preset" "${PRESETS[$preset]}"
  done
}

list_roles() {
  echo "${C_BOLD}Available roles:${C_RESET}"
  for role in $(echo "${!ROLE_DESCRIPTIONS[@]}" | tr ' ' '\n' | sort); do
    printf "  ${C_BOLD}%-15s${C_RESET} %s\n" "$role" "${ROLE_DESCRIPTIONS[$role]:0:70}..."
  done
}

_build_role_prompt() {
  local role=$1 task=$2 all_roles=$3 ownership=$4 agent_deps=${5:-""} role_n=${6:-""} agent_n=${7:-"$role_n"}
  local desc="${ROLE_DESCRIPTIONS[$role]:-Agent}"
  local prompt=""

  local signal_key="$role"
  [[ -n "$role_n" ]] && signal_key="${role}_${role_n}"

  prompt+="You are the ${role^^} agent (agent-${agent_n:-?}) in a supercode multi-agent session."$'\n\n'
  prompt+="YOUR ROLE: $desc"$'\n\n'

  if [[ -n "$ownership" ]]; then
    prompt+="YOUR FILE OWNERSHIP: $ownership"$'\n'
    prompt+="Do not modify files outside your ownership unless you coordinate with the Brain first."$'\n\n'
  fi

  # Dependency ordering
  if [[ -n "$agent_deps" ]]; then
    prompt+="DEPENDENCIES: You depend on: $agent_deps"$'\n'
    prompt+="Before starting your main work, check if your dependencies are done:"$'\n'
    prompt+="  cat shared/status/<dep>_*.json"$'\n'
    prompt+="If a dependency's status is not \"done\", prepare by reviewing .supercode/SPEC.md and CONTRACTS.md, setting up your file structure, and checking back. Once all dependencies show \"done\", start your main work."$'\n\n'
  fi

  prompt+="SHARED DIRECTORY (./shared/):"$'\n'
  prompt+="A shared directory is available at ./shared/ in your worktree. All agents can read and write here."$'\n'
  prompt+="  shared/status/    — write your status here (see STATUS SIGNALS below)"$'\n'
  prompt+="  shared/contracts/ — shared schemas, types, interfaces any agent can publish"$'\n'
  prompt+="  shared/outputs/   — outputs other agents might need (generated files, schemas, etc.)"$'\n\n'

  prompt+="STATUS SIGNALS:"$'\n'
  prompt+="Update your status so other agents and the Brain know your progress. Write JSON to shared/status/$signal_key.json:"$'\n'
  prompt+="  Working:  echo '{\"role\":\"$role\",\"status\":\"working\",\"message\":\"implementing API routes\",\"agent\":\"$agent_n\"}' > shared/status/$signal_key.json"$'\n'
  prompt+="  Blocked:  echo '{\"role\":\"$role\",\"status\":\"blocked\",\"message\":\"need database schema from database agent\",\"agent\":\"$agent_n\"}' > shared/status/$signal_key.json"$'\n'
  prompt+="  Done:     echo '{\"role\":\"$role\",\"status\":\"done\",\"message\":\"all API routes implemented and tested\",\"agent\":\"$agent_n\"}' > shared/status/$signal_key.json"$'\n'
  prompt+="IMPORTANT: Always write to shared/status/$signal_key.json — this is YOUR unique status file. Do not write to any other status file."$'\n'
  prompt+="Update your status at key milestones and when you finish."$'\n\n'

  prompt+="COORDINATION RULES:"$'\n'
  prompt+="- If .supercode/CONTRACTS.md exists, follow it for all shared interfaces, types, and API shapes."$'\n'
  prompt+="- If .supercode/SPEC.md exists, your work must satisfy its requirements."$'\n'
  prompt+="- To share something with other agents, write it to shared/contracts/ or shared/outputs/."$'\n'
  prompt+="- To check what other agents have published: ls shared/contracts/ shared/outputs/"$'\n'
  prompt+="- If you need something from another agent, write it in your status message AND describe it aloud."$'\n'
  prompt+="- Do not duplicate work that another agent is responsible for."$'\n\n'

  prompt+="OTHER AGENTS IN THIS SESSION: $all_roles"$'\n\n'

  # Role-specific extended prompts
  if [[ "$role" == "reverser" ]]; then
    prompt+=$(_build_reverser_extended_prompt)
  elif [[ "$role" == "selfmod" ]]; then
    prompt+=$(_build_selfmod_extended_prompt)
  fi

  # Per-role domain skill file (optional). SUPERCODE_SKILLS is resolved and
  # exported by the entry script; if a matching agents/<role>.md exists, append
  # its concrete patterns/checklists to the agent's prompt.
  if [[ -n "${SUPERCODE_SKILLS:-}" && -f "$SUPERCODE_SKILLS/$role.md" ]]; then
    prompt+="DOMAIN SKILL (concrete patterns and checklists for your role):"$'\n'
    prompt+="$(cat "$SUPERCODE_SKILLS/$role.md")"$'\n\n'
  fi

  prompt+="YOUR TASK: $task"

  printf '%s' "$prompt"
}

_build_reverser_extended_prompt() {
  local p=""

  p+="REVERSE ENGINEERING TOOLKIT:"$'\n\n'

  p+="== GHIDRA (Static Analysis) =="$'\n'
  p+="You have access to Ghidra via GhidraMCP. Use these MCP tools to interact with the currently open Ghidra project:"$'\n\n'

  p+="  LISTING & NAVIGATION:"$'\n'
  p+="    ghidra_get_all_functions          — list all functions (name, address, signature)"$'\n'
  p+="    ghidra_get_function_by_address     — get function at a specific address"$'\n'
  p+="    ghidra_search_functions_by_name    — search functions by name pattern"$'\n'
  p+="    ghidra_list_segments               — list memory segments (code, data, bss, etc.)"$'\n'
  p+="    ghidra_get_defined_data            — list defined data labels and types"$'\n'
  p+="    ghidra_list_namespaces             — list namespaces/classes"$'\n'
  p+="    ghidra_list_data_types             — list all data types in the program"$'\n\n'

  p+="  DECOMPILATION & DISASSEMBLY:"$'\n'
  p+="    ghidra_decompile_function          — decompile a function to C (by name or address)"$'\n'
  p+="    ghidra_get_current_address         — get cursor address in Ghidra"$'\n'
  p+="    ghidra_get_current_function        — get function at cursor"$'\n\n'

  p+="  CROSS-REFERENCES:"$'\n'
  p+="    ghidra_get_xrefs_to               — find all references TO an address"$'\n'
  p+="    ghidra_get_xrefs_from             — find all references FROM an address"$'\n'
  p+="    ghidra_get_callees                — functions called by a function"$'\n'
  p+="    ghidra_get_callers                — functions that call a function"$'\n\n'

  p+="  ANNOTATION:"$'\n'
  p+="    ghidra_rename_function             — rename a function"$'\n'
  p+="    ghidra_rename_variable             — rename a variable in decompilation"$'\n'
  p+="    ghidra_retype_variable             — change variable type"$'\n'
  p+="    ghidra_set_decompiler_comment      — add comment to decompiled code"$'\n'
  p+="    ghidra_set_eol_comment             — add end-of-line comment in listing"$'\n'
  p+="    ghidra_set_pre_comment             — add pre-comment in listing"$'\n'
  p+="    ghidra_set_plate_comment           — add plate comment (block header)"$'\n\n'

  p+="  MEMORY & BYTES:"$'\n'
  p+="    ghidra_get_bytes                   — read raw bytes at address"$'\n'
  p+="    ghidra_set_memory_value            — write bytes at address"$'\n\n'

  p+="== DEBUGGER (Dynamic Analysis) =="$'\n'
  p+="Use gdb (Linux) or x64dbg (Windows) via command line for dynamic analysis:"$'\n\n'

  p+="  GDB ESSENTIALS:"$'\n'
  p+="    gdb -q <binary>                   — launch gdb quietly"$'\n'
  p+="    b *0x<addr>  /  b function_name   — set breakpoint"$'\n'
  p+="    r [args]                           — run the program"$'\n'
  p+="    c / si / ni                        — continue / step into / step over (instruction)"$'\n'
  p+="    s / n                              — step into / step over (source line)"$'\n'
  p+="    x/32xb 0x<addr>                   — examine 32 bytes at address"$'\n'
  p+="    x/s 0x<addr>                      — examine as string"$'\n'
  p+="    x/10i \$rip                        — disassemble 10 instructions at RIP"$'\n'
  p+="    info registers                    — show all registers"$'\n'
  p+="    bt                                — backtrace"$'\n'
  p+="    vmmap / info proc mappings        — memory map"$'\n'
  p+="    watch *0x<addr>                   — hardware watchpoint on memory write"$'\n'
  p+="    catch syscall <name>              — break on syscall"$'\n'
  p+="    set follow-fork-mode child        — follow child on fork"$'\n'
  p+="    define hook-stop                  — auto-run commands at each break"$'\n'
  p+="    python / source script.py         — GDB Python scripting"$'\n\n'

  p+="  GDB ENHANCED (pwndbg/GEF if available):"$'\n'
  p+="    checksec                          — check binary protections (NX, PIE, RELRO, etc.)"$'\n'
  p+="    heap / bins / arena               — heap analysis"$'\n'
  p+="    telescope <addr>                  — smart memory dump with pointer derefs"$'\n'
  p+="    cyclic / pattern create/search    — offset finding for buffer overflows"$'\n'
  p+="    rop / ropper                      — ROP gadget search"$'\n\n'

  p+="  X64DBG ESSENTIALS (Windows, via command line / script):"$'\n'
  p+="    bp <addr>                         — set breakpoint"$'\n'
  p+="    run / StepInto / StepOver         — execution control"$'\n'
  p+="    dump <addr>                       — hex dump at address"$'\n'
  p+="    dis.prev/dis.next                 — navigate disassembly"$'\n'
  p+="    mod.main()                        — main module base"$'\n'
  p+="    find <pattern>                    — pattern scan in memory"$'\n'
  p+="    graph                             — control flow graph"$'\n'
  p+="    trace                             — instruction tracing"$'\n\n'

  p+="== ANALYSIS WORKFLOW =="$'\n'
  p+="Follow this structured approach:"$'\n\n'

  p+="1. TRIAGE: Identify the binary format (file, readelf -h, PE header). Check protections (checksec). Identify compiler, language, packing."$'\n'
  p+="2. STRINGS & IMPORTS: Look for interesting strings (strings -n 8), imported functions (readelf -d / objdump -T), and exported symbols."$'\n'
  p+="3. ENTRY POINT: Start from main() or the entry point. Use Ghidra to decompile and understand high-level flow."$'\n'
  p+="4. KEY FUNCTIONS: Identify critical functions — crypto, auth, network, file I/O, anti-debug. Rename them in Ghidra as you go."$'\n'
  p+="5. DATA STRUCTURES: Recover structs, vtables, global state. Create proper types in Ghidra to improve decompilation."$'\n'
  p+="6. DYNAMIC VERIFY: Confirm static analysis findings with the debugger. Set breakpoints on key functions, trace execution, inspect memory."$'\n'
  p+="7. DOCUMENT: Write findings to shared/outputs/ so other agents can use them. Include: function map, data structures, control flow, vulnerabilities."$'\n\n'

  p+="== OUTPUT FORMAT =="$'\n'
  p+="Document your findings in:"$'\n'
  p+="  analysis/FINDINGS.md     — high-level summary, key functions, data flow"$'\n'
  p+="  analysis/functions.md    — renamed functions with purpose"$'\n'
  p+="  analysis/structures.md   — recovered data structures (C struct definitions)"$'\n'
  p+="  analysis/vulns.md        — vulnerabilities found (if any)"$'\n'
  p+="  scripts/                 — any Ghidra scripts or gdb scripts you write"$'\n'
  p+="  shared/outputs/          — key findings for other agents to consume"$'\n\n'

  printf '%s' "$p"
}

_build_selfmod_extended_prompt() {
  local p=""

  p+="SUPERCODE ARCHITECTURE:"$'\n\n'

  p+="== FILE LAYOUT =="$'\n'
  p+="  ~/.local/bin/supercode                  — main entry point (bash script). Parses args, sources libs, dispatches commands."$'\n'
  p+="  ~/.local/share/supercode/lib/           — all library modules:"$'\n'
  p+="    ui.sh           — color codes (C_BOLD, C_RED, etc.), die(), info(), warn(), header(), spinner"$'\n'
  p+="    git.sh          — git helpers: worktree creation/cleanup, snapshot (commit/stash), branch management"$'\n'
  p+="    tmux_helpers.sh — tmux session/pane management, layout tiling, pane labeling"$'\n'
  p+="    agents.sh       — pane label/accent helpers: _agent_accent_color(), _short_label(), _set_pane_label(). Agent LAUNCH (pane splits + 'clear && claude ...') lives in commands/start.sh + commands/dispatch.sh; task delivery uses _send_multiline_to_pane() in tmux_helpers.sh after BOOT_DELAY."$'\n'
  p+="    brain.sh        — Brain orchestrator: plan generation, agent coordination, monitoring loop"$'\n'
  p+="    session.sh      — session state: session name, lock files, state persistence (.supercode/)"$'\n'
  p+="    roles.sh        — role definitions, presets, role-aware prompt generation (THIS FILE — you are here)"$'\n'
  p+="    contracts.sh    — contract/spec generation, project-type detection, file ownership"$'\n'
  p+="    migrations.sh   -- alembic migration-chain audit + linearization helpers"$'\n'
  p+="    signals.sh      — agent status signal reading/writing (working/blocked/done)"$'\n'
  p+="  ~/.local/share/supercode/lib/commands/  — one file per subcommand:"$'\n'
  p+="    start.sh        — cmd_start(): main launch flow (brain or direct mode)"$'\n'
  p+="    attach.sh       — cmd_attach(): reattach to tmux session"$'\n'
  p+="    status.sh       — cmd_status(): show agent status, branches, dirty state"$'\n'
  p+="    save.sh         — cmd_save(): commit + merge all agent work into main branch"$'\n'
  p+="    unsave.sh       — cmd_unsave(): undo the last save"$'\n'
  p+="    rollback.sh     — cmd_rollback(): rewind to pre-launch snapshot"$'\n'
  p+="    clean.sh        — cmd_clean(): kill session + remove worktrees"$'\n'
  p+="    kill.sh         — cmd_kill(): kill tmux session only"$'\n'
  p+="    peek.sh         — cmd_peek(): capture agent screen output"$'\n'
  p+="    tell.sh         — cmd_tell(): send message to specific agent pane"$'\n'
  p+="    broadcast.sh    — cmd_broadcast(): send message to all agents"$'\n'
  p+="    diff.sh         — cmd_diff(): show files changed by each agent"$'\n'
  p+="    logs.sh         — cmd_logs(): view per-agent logs"$'\n'
  p+="    label.sh        — cmd_label(): set/get/clear pane border labels"$'\n'
  p+="    plan.sh         — cmd_plan(): create spec + contracts without coding"$'\n'
  p+="    dispatch.sh     — cmd_dispatch(): launch agents from existing plan"$'\n'
  p+="    review_cmd.sh   — cmd_review(): launch reviewer agent"$'\n'
  p+="    verify.sh       — cmd_verify(): run build/test/lint in worktrees"$'\n'
  p+="    approve.sh      — cmd_approve(): approve an agent's approach"$'\n'
  p+="    claim.sh        — cmd_claim()/cmd_claims()/cmd_conflicts(): file ownership"$'\n'
  p+="    brain_cmd.sh    — cmd_brain_dispatch(): brain subcommands"$'\n'
  p+="    doctor.sh       — cmd_doctor(): dependency/environment checks"$'\n'
  p+="    interactive.sh  — prompt_tasks_interactive(): interactive task input"$'\n'
  p+="    signals_cmd.sh  — cmd_signals(): show agent status signals"$'\n'
  p+="    migrations_cmd.sh -- cmd_migrations(): audit/linearize alembic migration chains"$'\n'
  p+="    rebalance.sh    — cmd_rebalance(): internal rebalance"$'\n\n'

  p+="== KEY CONCEPTS =="$'\n'
  p+="- Each agent runs claude in its own git worktree under \$SUPERCODE_HOME/<repo>/agent-N"$'\n'
  p+="- Brain is agent 0 (pane 0) — it orchestrates other agents via 'supercode tell' and 'supercode peek'"$'\n'
  p+="- Roles define agent specialization: description, file ownership, and extended prompts"$'\n'
  p+="- Presets are named groups of roles (e.g., webapp = architect,backend,frontend,database,qa)"$'\n'
  p+="- Session state lives in .supercode/ directory in the repo root"$'\n'
  p+="- Shared data between agents goes through ./shared/ in each worktree"$'\n'
  p+="- Signals: agents write JSON to shared/status/<role>_<N>.json to coordinate (N = per-role counter, 1 for unique roles)"$'\n\n'

  p+="== EDITING RULES =="$'\n'
  p+="1. ALWAYS read the file you're editing first — understand existing patterns before changing anything."$'\n'
  p+="2. Follow existing bash conventions: set -euo pipefail, quote variables, use local vars in functions."$'\n'
  p+="3. To add a new subcommand: create lib/commands/<name>.sh with cmd_<name>(), add a case to the main script."$'\n'
  p+="4. To add a new role: add to ROLE_DESCRIPTIONS, ROLE_DEFAULT_OWNERSHIP, and optionally a preset."$'\n'
  p+="5. To add an extended prompt: create _build_<role>_extended_prompt() and wire it in _build_role_prompt()."$'\n'
  p+="6. Test after every change: run 'supercode --help', 'supercode doctor', 'supercode roles', 'supercode presets'."$'\n'
  p+="7. Do NOT break the running session you're in — your changes apply to future sessions."$'\n'
  p+="8. Keep the usage() help text in the main script up to date when adding commands."$'\n\n'

  printf '%s' "$p"
}

_build_role_dispatch_prompt() {
  local n=$1 task_description=$2
  shift 2
  local roles=("$@")
  local prompt=""

  prompt+="You are the Brain -- orchestrator of this supercode session with ${#roles[@]} specialized agents."$'\n\n'
  prompt+="THE AGENTS AND THEIR ROLES:"$'\n'
  for ((i=0; i<${#roles[@]}; i++)); do
    local role="${roles[$i]}"
    local desc="${ROLE_DESCRIPTIONS[$role]:-Agent}"
    prompt+="  Agent $((i+1)) ($role): $desc"$'\n'
  done
  prompt+=$'\n'

  prompt+="THE USER'S REQUEST: $task_description"$'\n\n'

  prompt+="IMPORTANT: If the request above is unclear, vague, or missing key details — ASK the user before dispatching agents. Do NOT guess. Say what's unclear, ask 1-3 short questions, and wait for the answer. Dispatching agents with a wrong understanding wastes all their work."$'\n\n'
  prompt+="FORBIDDEN: supercode save, supercode unsave, supercode rollback — only the USER merges or reverts work."$'\n'
  prompt+="SAFE TO USE: tell, broadcast, peek, diff, signals, verify, approve, reject, conflicts, label, dispatch, clean, kill."$'\n\n'

  prompt+="STATUS SIGNALS: Each agent writes to shared/status/ROLE_N.json where N is a per-role counter (1 for unique roles, 2+ for duplicates). Use 'supercode signals' to see all."$'\n\n'

  prompt+="YOUR JOB:"$'\n'
  prompt+="1. Analyze the request. If anything is ambiguous, ask the user to clarify FIRST."$'\n'
  prompt+="2. If .supercode/CONTRACTS.md exists, reference it. If not, identify shared interfaces/types that agents must agree on and state them in your dispatch messages."$'\n'
  prompt+="3. For each agent K, compose a role-aware task and dispatch it with:"$'\n'
  prompt+="     supercode tell K \"your composed message\""$'\n'
  prompt+="   Each message must include: (a) the agent's role identity, (b) its specific task, (c) what other agents are building, (d) file ownership rules, (e) any shared contracts to follow."$'\n'
  prompt+="4. After dispatching, say \"all agents launched\" and enter monitoring mode."$'\n\n'

  prompt+="MONITORING LOOP (repeat every 60-90 seconds after dispatch):"$'\n'
  prompt+="  - Run 'supercode signals' to check status of all agents"$'\n'
  prompt+="  - If any agent is BLOCKED or stale (>3 min no update): 'supercode peek N --history 200' to diagnose"$'\n'
  prompt+="  - Send help: 'supercode tell N \"...\"'"$'\n'
  prompt+="  - If an agent needs output from another: check shared/contracts/ and shared/outputs/, relay it"$'\n'
  prompt+="  - If an agent is in an error loop: give them a different approach"$'\n'
  prompt+="  DO NOT passively wait. Agents cannot message you — YOU must check on THEM."$'\n\n'

  prompt+="REVIEW-FIX CYCLE (when all agents report done):"$'\n'
  prompt+="  1. supercode diff all — review changes"$'\n'
  prompt+="  2. supercode verify — check build/test/lint"$'\n'
  prompt+="  3. supercode conflicts — check ownership violations"$'\n'
  prompt+="  4. For issues: supercode tell K \"fix: ...\" — re-monitor until done again"$'\n'
  prompt+="  5. When clean: tell the user \"All agents done. Run 'supercode save --dry-run' to preview.\""$'\n\n'
  prompt+="CRITICAL: NEVER stop mid-task. If you just read files, reports, or agent output, the next step is to ACT on what you read — not to stop. Reading is a sub-step, not completion. Always continue to the next action (dispatch agents, diagnose issues, send help, write fixes)."$'\n\n'
  prompt+="Begin."

  printf '%s' "$prompt"
}
