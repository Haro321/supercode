#!/usr/bin/env bash
# Role definitions, presets, and role-aware prompt generation.

declare -gA ROLE_DESCRIPTIONS=(
  [architect]="Design system architecture, define API contracts, data models, shared types, module boundaries, and file ownership. Produce SPEC, CONTRACTS, and AGENTS docs. You do NOT write implementation code — you write the specs and contracts other agents follow."
  [backend]="Implement server-side logic: REST/GraphQL endpoints, services, middleware, authentication, authorization, validation, error handling, observability hooks, and business logic. Follow the contracts and data models defined by the architect."
  [frontend]="Build UI components, pages, forms, client-side state, routing, data fetching, error states, and loading states. Follow the component structure and API contracts defined by the architect."
  [database]="Create database schemas, migrations, seeds, indexes, constraints, and query helpers. Optimize queries for the expected access patterns. Define the data layer backend and other agents depend on."
  [qa]="Write comprehensive tests (unit, integration, e2e) and run the project's build/test/lint/typecheck commands. Cover happy paths, edge cases, error paths, and key performance scenarios. Report failures to the Brain with the agent most likely responsible."
  [security]="Audit for security vulnerabilities: OWASP Top 10, injection, XSS, CSRF, auth bypass, IDOR, SSRF, secrets exposure, insecure deps, weak crypto, permission and tenant-isolation issues. Produce findings as actionable items with severity and reproduction steps."
  [reviewer]="Review all agent diffs for correctness, consistency with the spec/contracts, style, and architectural fit. Write a structured review report grouped by severity. Do NOT modify code — only review and report."
  [docs]="Write and update documentation: README, API docs, inline doc comments, .env.example, CHANGELOG, ADRs, setup guides, and runbooks. Ensure docs reflect the actual implementation and stay consistent across files."
  [devops]="Handle CI/CD pipelines, Dockerfiles, compose files, deployment configs, environment setup, secrets management, and infrastructure-as-code. Ensure the project builds reproducibly and deploys safely."
  [refactor]="Refactor existing code for clarity, performance, and maintainability. Preserve all existing behavior, keep changes incremental, and ensure each step leaves the codebase passing tests."
  [reproducer]="Reproduce the reported bug with a minimal test case. Create a failing test that demonstrates the issue and document exact reproduction steps. Do NOT fix the bug — only reproduce and isolate it."
  [debugger]="Investigate the root cause of the bug: trace call paths, read logs, inspect state, narrow with bisection where useful. Identify the exact location and cause and report findings to the Brain — do not patch."
  [fixer]="Implement a targeted fix for the identified bug. Keep changes minimal and focused on the root cause. Add a regression test that fails without the fix and passes with it."
  [ux]="Audit and improve user experience: interaction flows, error states, loading states, empty states, success feedback, copy clarity, and edge cases. Focus on usability, not visual styling."
  [accessibility]="Ensure WCAG AA compliance: semantic HTML, ARIA labels, keyboard navigation, focus management, screen reader support, color contrast, motion-reduction preferences, and form labeling."
  [mapper]="Map the codebase: dependencies, call graphs, module boundaries, public vs internal APIs, and impact analysis for planned changes. Produce a clear map other agents can use as a starting point."
  [compatibility]="Ensure backward compatibility during refactoring or breaking changes: API stability, migration paths, deprecation warnings, feature flags, and version-skew handling between client and server."
  [reverser]="Reverse engineer binaries using Ghidra (static analysis, decompilation via GhidraMCP) and x64dbg/gdb (dynamic analysis, debugging). Analyze executables, shared libraries, firmware, and protocols. Identify functions, recover data structures, trace control flow, find vulnerabilities, and document findings."

  # --- New roles (drawn from VoltAgent and wshobson collections) ---
  [mobile]="Build mobile apps: iOS (Swift/SwiftUI), Android (Kotlin/Jetpack), or cross-platform (React Native, Flutter). Handle navigation, offline-first data, push notifications, deep links, permissions, and platform-specific UI conventions."
  [performance]="Profile, benchmark, and optimize for latency, throughput, memory, bundle size, and battery. Establish baselines before changing anything, identify the actual bottleneck (don't guess), and validate improvements with measurements."
  [api]="Design API contracts (REST, GraphQL, gRPC, WebSocket): endpoints, schemas, versioning, auth flows, error shapes, pagination, idempotency, and rate limits. Produce a contract other agents implement against."
  [ml]="ML/AI engineering: data prep, feature engineering, model training and evaluation, inference pipelines, deployment, monitoring for drift, and reproducible experiments. Pick the simplest model that meets the success metric."
  [data]="Data engineering: ETL/ELT pipelines, warehouses, lakes, streaming, schema evolution, data quality checks, and lineage. Design for idempotency, late-arriving data, and backfills."
  [sre]="Site reliability: define SLIs/SLOs, manage error budgets, set up observability (metrics, logs, traces), design incident response, write postmortems, and reduce toil through automation."
  [prompt]="Prompt engineering for LLM apps: structure prompts and system instructions, design few-shot examples, define output schemas, build evals with golden datasets, and tune for cost, latency, and quality."
  [legacy]="Modernize legacy code with gradual, behavior-preserving migrations: strangler-fig patterns, parallel-run validation, characterization tests before changes, and incremental upgrades over big-bang rewrites."
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
  [mobile]="ios/**,android/**,mobile/**,src/screens/**,src/navigation/**,App.tsx,App.jsx,App.kt,App.swift"
  [performance]="bench/**,benchmarks/**,perf/**"
  [api]="api/**,src/api/**,openapi*,*.proto,schema.graphql,graphql/**"
  [ml]="ml/**,models/**,notebooks/**,training/**,evals/**,*.ipynb"
  [data]="pipelines/**,etl/**,dbt/**,airflow/**,dags/**,data/**"
  [sre]="observability/**,monitoring/**,alerts/**,runbooks/**,slo/**,prometheus/**,grafana/**"
  [prompt]="prompts/**,evals/**,llm/**,src/prompts/**"
  [legacy]=""
)

declare -gA PRESETS=(
  [webapp]="architect,backend,frontend,database,qa"
  [api]="architect,api,backend,database,security,qa"
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
  [perf]="mapper,performance,qa"
  [incident]="sre,debugger,fixer,qa"
  [llm-app]="architect,prompt,backend,api,qa"
  [modernize]="mapper,legacy,refactor,compatibility,qa"
)

resolve_preset() {
  local preset=$1
  local roles="${PRESETS[$preset]:-}"
  [[ -n "$roles" ]] || die "unknown preset: $preset (available: ${!PRESETS[*]})"
  echo "$roles"
}

parse_roles() {
  local input=$1
  IFS=',' read -ra roles <<< "$input"
  for role in "${roles[@]}"; do
    [[ -n "${ROLE_DESCRIPTIONS[$role]:-}" ]] || die "unknown role: $role (available: ${!ROLE_DESCRIPTIONS[*]})"
  done
  echo "$input"
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
  local role=$1 task=$2 all_roles=$3 ownership=$4 agent_deps=${5:-""}
  local desc="${ROLE_DESCRIPTIONS[$role]:-Agent}"
  local prompt=""

  prompt+="You are the ${role^^} agent in a supercode multi-agent session."$'\n\n'
  prompt+="YOUR ROLE: $desc"$'\n\n'

  if [[ -n "$ownership" ]]; then
    prompt+="YOUR FILE OWNERSHIP: $ownership"$'\n'
    prompt+="Do not modify files outside your ownership unless you coordinate with the Brain first."$'\n\n'
  fi

  # Dependency ordering
  if [[ -n "$agent_deps" ]]; then
    prompt+="DEPENDENCIES: You depend on: $agent_deps"$'\n'
    prompt+="Before starting your main work, check if your dependencies are done:"$'\n'
    prompt+="  cat shared/status/<role>.json"$'\n'
    prompt+="If a dependency's status is not \"done\", prepare by reviewing .supercode/SPEC.md and CONTRACTS.md, setting up your file structure, and checking back. Once all dependencies show \"done\", start your main work."$'\n\n'
  fi

  prompt+="SHARED DIRECTORY (./shared/):"$'\n'
  prompt+="A shared directory is available at ./shared/ in your worktree. All agents can read and write here."$'\n'
  prompt+="  shared/status/    — write your status here (see STATUS SIGNALS below)"$'\n'
  prompt+="  shared/contracts/ — shared schemas, types, interfaces any agent can publish"$'\n'
  prompt+="  shared/outputs/   — outputs other agents might need (generated files, schemas, etc.)"$'\n\n'

  prompt+="STATUS SIGNALS:"$'\n'
  prompt+="Update your status so other agents and the Brain know your progress. Write JSON to shared/status/$role.json:"$'\n'
  prompt+="  Working:  echo '{\"role\":\"$role\",\"status\":\"working\",\"message\":\"implementing API routes\"}' > shared/status/$role.json"$'\n'
  prompt+="  Blocked:  echo '{\"role\":\"$role\",\"status\":\"blocked\",\"message\":\"need database schema from database agent\"}' > shared/status/$role.json"$'\n'
  prompt+="  Done:     echo '{\"role\":\"$role\",\"status\":\"done\",\"message\":\"all API routes implemented and tested\"}' > shared/status/$role.json"$'\n'
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
  fi

  # Append per-role skill file if available (agents/<role>.md). Skills are
  # markdown skill files (e.g. mirrored from affaan-m/ecc) — they give the
  # agent domain-specific patterns, checklists, and concrete examples.
  if [[ -n "${SUPERCODE_AGENTS:-}" && -f "$SUPERCODE_AGENTS/$role.md" ]]; then
    prompt+="DOMAIN SKILL — read carefully, apply throughout:"$'\n'
    prompt+="--- BEGIN $role.md ---"$'\n'
    prompt+="$(cat "$SUPERCODE_AGENTS/$role.md")"$'\n'
    prompt+="--- END $role.md ---"$'\n\n'
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

  prompt+="YOUR JOB RIGHT NOW:"$'\n'
  prompt+="1. Analyze the request. Figure out how to split the work across these specialized roles."$'\n'
  prompt+="2. If .supercode/CONTRACTS.md exists, reference it. If not, identify shared interfaces/types that agents must agree on and briefly state them in your dispatch messages."$'\n'
  prompt+="3. For each agent K, compose a role-aware task and dispatch it with:"$'\n'
  prompt+="     supercode tell K \"your composed message\""$'\n'
  prompt+="   Each message must include: (a) the agent's role identity, (b) its specific task, (c) what other agents are building, (d) file ownership rules, (e) any shared contracts to follow."$'\n'
  prompt+="4. After dispatching all agents, say \"all agents launched\" and enter monitoring mode."$'\n'
  prompt+="   Use 'supercode peek all' to check progress. Use 'supercode tell K ...' for follow-ups."$'\n\n'
  prompt+="Begin."

  printf '%s' "$prompt"
}
