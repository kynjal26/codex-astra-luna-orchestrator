# Pro Profile: Sol + Luna Orchestration

Choose this preset when you want Sol to plan, orchestrate, and review while
Luna handles the execution roles. Select Pro in `setup.sh` or `setup.ps1`.
Personal/global setup merges this profile into the user's existing Codex
configuration. Project setup copies `profiles/pro/codex/` to `.codex/` and
`profiles/pro/agents/` to `.agents/` in the target repository.

The topology is:

```text
Sol root (medium)
├── Luna explorer (high)
├── Luna worker (high)
├── Luna tester (high)
├── Luna researcher (high)
└── Sol reviewer (low)
```

Put the root settings in the project-scoped `.codex/config.toml`, or merge
them into `~/.codex/config.toml` for a personal/global setup:

```toml
model = "gpt-5.6-sol"
model_reasoning_effort = "medium"

[agents]
enabled = true
max_concurrent_threads_per_session = 4
default_subagent_model = "gpt-5.6-luna"
default_subagent_reasoning_effort = "high"
```

For the named roles, use these model settings in the corresponding files under
`.codex/agents/`:

```toml
# explorer.toml, worker.toml, tester.toml, researcher.toml
model = "gpt-5.6-luna"
model_reasoning_effort = "high"
```

```toml
# reviewer.toml
model = "gpt-5.6-sol"
model_reasoning_effort = "low"
```

The role files override the inherited `[agents]` defaults. Keep those explicit
overrides when you want the topology above to remain stable. Remove them when
you want all named roles to follow the defaults in `config.toml`.

For the Luna-root configuration, use the [Plus profile](plus-plan.md).
