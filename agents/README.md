# agents/ — per-role skill files

Each `<role>.md` here is a domain-specific skill the role's agent reads at
dispatch time, in addition to its short bash description from `lib/roles.sh`.
The skill files give concrete patterns, checklists, and examples so each
agent works to a higher standard than the one-liner alone allows.

## How loading works

At dispatch time, `_build_role_prompt()` in `lib/roles.sh` checks for
`$SUPERCODE_AGENTS/<role>.md` and appends its content to the agent's prompt
under a `DOMAIN SKILL` heading. Roles without a matching file fall back
silently to the bash description.

`SUPERCODE_AGENTS` is resolved by the `supercode` script in this order:
1. `$SUPERCODE_AGENTS` (env override)
2. `<script_dir>/agents/` (dev/checkout path)
3. `~/.local/share/supercode/agents/` (installed path)

## Where these files come from

All current files are mirrored from
[`affaan-m/ecc`](https://github.com/affaan-m/ecc) (MIT-licensed) and renamed
to match supercode's role names. Each row notes how closely the upstream
skill matches the role; weak fits are kept because they're still useful but
narrower than the role itself.

| supercode role | source skill (ecc) | fit |
|---|---|---|
| `api` | `api-design` | strong |
| `backend` | `backend-patterns` | strong |
| `frontend` | `frontend-patterns` | strong |
| `qa` | `tdd-workflow` | strong |
| `security` | `security-review` | strong |
| `ml` | `mle-workflow` | strong |
| `reviewer` | `verification-loop` | weak — covers self-verification before PR, not reviewing other agents' diffs |
| `prompt` | `eval-harness` | weak — covers evals only, not prompt design as a whole |

Roles without a skill file here (architect, database, devops, refactor,
mobile, performance, data, sre, debugger, mapper, docs, ux, accessibility,
compatibility, reproducer, fixer, legacy, reverser) fall back to their
bash description in `lib/roles.sh`. `reverser` additionally has an inline
Ghidra/gdb prompt block in `lib/roles.sh`.

## Adding more

Drop a `<role>.md` here for any role in `lib/roles.sh`. The file can be any
markdown; YAML frontmatter is allowed and ignored by supercode. Keep them
focused on concrete patterns, decision rules, and checklists — not generic
"you are a senior X" boilerplate (the runtime already establishes that).
