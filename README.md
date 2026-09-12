# Codex Sol Orchestrator + Luna Subagents

A configurable Codex setup where GPT-5.6 Sol is the root/orchestrator and reviewer, while GPT-5.6 Luna is the default and pinned model for execution subagents.

The installer asks which Codex plan you are on. Pro uses GPT-5.6 Sol at medium reasoning to orchestrate and GPT-5.6 Luna at high reasoning for execution subagents. Plus uses GPT-5.6 Luna at max reasoning to orchestrate and medium reasoning for execution subagents. Both plans retain the separate GPT-5.6 Sol reviewer at low reasoning.

## Layout

```text
.
├── profiles/
│   ├── pro/
│   │   ├── codex/           (config.toml and agents/*.toml)
│   │   └── agents/          (skills/sol-orchestrator/SKILL.md)
│   └── plus/
│       ├── codex/           (config.toml and agents/*.toml)
│       └── agents/          (skills/sol-orchestrator/SKILL.md)
├── guides/
│   ├── fast-iteration.md
│   ├── complex-repo-work.md
│   ├── routine-coding.md
│   ├── full-orchestration.md
│   ├── plus-plan.md
│   └── token-usage.md
├── scripts/
│   ├── setup_global.sh
│   └── token_usage.py
├── AGENTS.md
├── setup.sh
├── setup.ps1
└── LICENSE
```

## Current Plus and Pro configuration

| Role or setting | Plus | Pro |
|---|---|---|
| Orchestrator | GPT-5.6 Luna - max | GPT-5.6 Sol - medium |
| Explorer, worker, tester, researcher | GPT-5.6 Luna - medium | GPT-5.6 Luna - high |
| Default subagent | GPT-5.6 Luna - medium | GPT-5.6 Luna - high |
| Independent reviewer | GPT-5.6 Sol - low | GPT-5.6 Sol - low |
| Concurrent subagent limit | 4 | 4 |

### Pro - `profiles/pro/codex/config.toml`

```toml
model = "gpt-5.6-sol"
model_reasoning_effort = "medium"

approval_policy = "on-request"
sandbox_mode = "workspace-write"

[agents]
enabled = true
max_concurrent_threads_per_session = 4
default_subagent_model = "gpt-5.6-luna"
default_subagent_reasoning_effort = "high"
```

### Plus - `profiles/plus/codex/config.toml`

```toml
model = "gpt-5.6-luna"
model_reasoning_effort = "max"

approval_policy = "on-request"
sandbox_mode = "workspace-write"

[agents]
enabled = true
max_concurrent_threads_per_session = 4
default_subagent_model = "gpt-5.6-luna"
default_subagent_reasoning_effort = "medium"
```

Project setup copies `profiles/<plan>/codex` to `.codex` and
`profiles/<plan>/agents` to `.agents` in the target repository. Personal/global
setup installs only this package's five agents and one skill, then surgically
merges the selected model and `[agents]` defaults into the existing global
configuration.

Each role file is explicitly pinned to its intended model: Luna for explorer, worker, tester, and researcher; Sol for reviewer. This means changing only `default_subagent_model` will affect generic spawned agents, but not the named roles.

The four Luna role files explicitly set `model_reasoning_effort = "high"` in the Pro profile and `"medium"` in the Plus profile. The reviewer keeps its explicit `low` effort in both.

When updating an existing installation, copy the role files along with `config.toml` from the selected profile. Replace `<plan>` below with `pro` or `plus`.

If you want all named roles, including the reviewer, to follow the `[agents]` defaults, remove both the `model` and `model_reasoning_effort` overrides from their role files.

## Setup

Clone this repository:

```bash
git clone https://github.com/donvito/codex-astra-luna-orchestrator.git
cd codex-astra-luna-orchestrator
```

### macOS and Linux

Run the shell installer:

```bash
./setup.sh
```

### Windows

Run the PowerShell installer from Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

With PowerShell 7, you can use:

```powershell
pwsh -File .\setup.ps1
```

### Installer prompts

Choose the installation scope first:

```text
Installation scope:
  1) Personal/global - available in every project for this user
  2) Project - install into one repository
Select scope [1/2] (default 1):
```

Personal/global is the default. It installs into `~/.codex` and
`~/.agents/skills`, so new Codex sessions inherit the setup regardless of the
repository you open. Project scope retains the original per-repository flow and
asks for the target repository path after plan selection.

Then choose your Codex plan:

```text
Codex plan:
  1) Pro  - GPT-5.6 Sol orchestrates, GPT-5.6 Luna executes, GPT-5.6 Sol reviews
  2) Plus - GPT-5.6 Luna (max reasoning) orchestrates, GPT-5.6 Luna executes, GPT-5.6 Sol reviews
Select plan [1/2] (default 1):
```

The selected configuration sets both the root and default subagent reasoning.
Agent role files are shared between plans: explorer, worker, tester, and
researcher use Luna at the plan's default effort; the reviewer uses Sol at low
effort on both plans.

For project scope, the installer asks whether to install each component:

- `profiles/<plan>/codex` contains the root configuration and agent role profiles, installed as `.codex`.
- `profiles/<plan>/agents` contains the `sol-orchestrator` skill, installed as `.agents`.
- `AGENTS.md` gives Codex the project-level orchestration instructions. If it
  already exists, setup appends the instructions and preserves its contents.
  Re-running setup skips the append when the same instructions are already
  present. Symbolic links and incompatible targets are skipped.

Press Enter or answer `y` to install a component; answer `n` to skip it. All
three components are selected by default.

If a component already exists, the installer lists the exact paths that would
be overwritten and asks again before making changes:

```text
WARNING: the following existing files will be overwritten:
  - .codex/config.toml
Update .codex? New files will be added; only paths listed above will be replaced. [y/N]
```

Existing-file updates default to `n`. If approved, missing files are added and
only the listed paths are replaced. Other files already present in the target
component remain untouched.

After project setup, launch Codex from the target repository. Project-scoped
`.codex` configuration is loaded only for trusted projects.

See `guides/` for model presets and the Sol + Luna topology.

## Personal/global safety

Global setup preserves unrelated agents, skills, plugins, MCP servers,
providers, permissions, trust entries, desktop settings, comments, and other
configuration. It changes only the selected root model and reasoning level plus
the four orchestrator-owned `[agents]` defaults. Existing files with different
contents require confirmation and receive timestamped backups.

Automatic config merging accepts conventional Codex TOML with single-line bare
key assignments and table headers. It leaves the config unchanged and requests
a manual merge when it finds multiline strings, dotted or quoted assignment
keys, multiline values, or table syntax it cannot classify safely.

The installer refuses linked global config and instruction files, plus linked
agent or skill destinations and intermediate directories inside those install
trees. If `~/.codex/AGENTS.md` is managed by Home Manager, set its declarative
source for that run:

```bash
CODEX_MANAGED_AGENTS_SOURCE="$HOME/.dotfiles/home/AGENTS.md" ./setup.sh
```

Without that variable, setup leaves the managed link untouched and prints the
exact instruction block to add. A non-empty `~/.codex/AGENTS.override.md` is
also reported because it shadows the normal global instructions.

Set `CODEX_HOME` or `AGENTS_HOME` before running setup when you use non-default
personal locations. Restart Codex after installation because the instruction
chain is loaded at the beginning of a session.

## Using the skill

Codex may select the skill automatically when the task matches its description.

You can also invoke it explicitly from Codex CLI or the IDE extension with:

```text
$sol-orchestrator
```

Example prompt:

```text
$sol-orchestrator

Implement the new invoice export endpoint.
Have explorer map the existing invoice/export path first.
Use workers for bounded implementation, tester for verification,
and reviewer for an independent final review.
```

## Suggested topology

```text
                 GPT-5.6 Sol
             root / orchestrator
                      |
      +---------------+---------------+
      |               |               |
   explorer          worker         researcher
     Luna             Luna             Luna
      |               |
      +-------+-------+
              |
           tester
            Luna
              |
          reviewer
           Sol
              |
              v
         GPT-5.6 Sol
      integrate + verify
```

## Tuning

For cheaper/faster runs:
- lower Pro's Sol reasoning from `medium` to `low`
- set Luna reasoning to `low` or `medium`
- use 3-4 concurrent threads

For larger codebases:
- consider raising Pro's Sol reasoning to `high`
- start with your plan's Luna default and adjust based on results
- use 6-8 concurrent threads, only when tasks are actually independent

For strict parent/child separation:
- keep explorer/reviewer/researcher read-only
- keep worker/tester workspace-write
- leave the root in workspace-write so it can integrate changes

## Token usage

Orchestration is not free: the root stays in the loop for the whole task and
every subagent carries its own context. Usage depends on repository size and
task shape, so there is no single number. `scripts/token_usage.py` reads the
rollout logs Codex already writes under `~/.codex/sessions` and reports usage
per thread, role, and model, plus the change in your 5-hour and 7-day rate
limit windows:

```bash
scripts/token_usage.py --list --date 2026-09-07
scripts/token_usage.py --latest --date 2026-09-07
```

See [`guides/token-usage.md`](guides/token-usage.md) for a measurement
protocol, one sample run with real numbers, and tips for reducing usage.

Plus users: the root thread is the largest line item, so running it on Luna
saves the most. Selecting `Plus` in the installer does this for you; for a
manual or global setup see [`guides/plus-plan.md`](guides/plus-plan.md):

```toml
# Root
model = "gpt-5.6-luna"
model_reasoning_effort = "max"
```

## Important behavior

Explicit model choices during a spawn override `[agents]` defaults. Custom agent files that specify `model` or `model_reasoning_effort` also take precedence over inherited defaults.

The execution role files are pinned to Luna intentionally, while the reviewer is pinned to Sol for independent final review. Sol remains the orchestrator unless you deliberately change the role configuration.

## License

Licensed under the [Apache License 2.0](LICENSE).
