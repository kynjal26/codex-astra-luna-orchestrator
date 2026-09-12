#!/bin/sh

set -eu

source_root=$1
plan=$2
codex_home=${CODEX_HOME:-"$HOME/.codex"}
skills_home=${AGENTS_HOME:-"$HOME/.agents"}
profile_dir=$source_root/profiles/$plan

confirm() {
    prompt=$1
    default_yes=$2
    if [ "$default_yes" = yes ]; then suffix='[Y/n]'; else suffix='[y/N]'; fi
    while :; do
        printf '%s %s ' "$prompt" "$suffix"
        if ! IFS= read -r answer; then
            printf '\nSetup cancelled: input ended before setup was complete.\n' >&2
            exit 1
        fi
        case "$answer" in
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No) return 1 ;;
            '') [ "$default_yes" = yes ] && return 0 || return 1 ;;
            *) printf '%s\n' 'Please answer yes or no.' ;;
        esac
    done
}

linked_component() {
    base=$1
    target=$2
    current=$base

    if [ -L "$current" ]; then
        printf '%s\n' "$current"
        return 0
    fi
    case "$target" in
        "$base") return 1 ;;
        "$base"/*) remainder=${target#"$base"/} ;;
        *) return 1 ;;
    esac
    while [ -n "$remainder" ]; do
        component=${remainder%%/*}
        current=$current/$component
        if [ -L "$current" ]; then
            printf '%s\n' "$current"
            return 0
        fi
        case "$remainder" in
            */*) remainder=${remainder#*/} ;;
            *) remainder= ;;
        esac
    done
    return 1
}

install_files() {
    label=$1
    source_dir=$2
    destination_dir=$3
    destination_root=$4

    if linked_path=$(linked_component "$destination_root" "$destination_dir"); then
        printf 'Skipped %s: destination path contains a symbolic link (%s).\n' \
            "$label" "$linked_path" >&2
        return
    fi
    mkdir -p "$destination_dir"

    find "$source_dir" -type f -print | while IFS= read -r source_file; do
        relative_path=${source_file#"$source_dir"/}
        destination_file=$destination_dir/$relative_path
        destination_parent=$(dirname "$destination_file")

        if linked_path=$(linked_component "$destination_root" "$destination_file"); then
            printf 'Skipped managed path: %s contains symbolic link %s\n' "$destination_file" "$linked_path" >&2
            continue
        fi
        if [ -e "$destination_file" ] && [ ! -f "$destination_file" ]; then
            printf 'Skipped incompatible target: %s\n' "$destination_file" >&2
            continue
        fi
        if [ -f "$destination_file" ] && cmp -s "$source_file" "$destination_file"; then
            printf 'Unchanged %s\n' "$destination_file"
            continue
        fi
        if [ -f "$destination_file" ]; then
            if ! confirm "Update $destination_file? A timestamped backup will be created." no; then
                printf 'Kept existing %s\n' "$destination_file"
                continue
            fi
            cp -p "$destination_file" "$destination_file.backup-$(date -u +%Y%m%dT%H%M%SZ)"
        fi
        mkdir -p "$destination_parent"
        temporary_file=$(mktemp "$destination_parent/.sol-orsetup.XXXXXX")
        cp "$source_file" "$temporary_file"
        chmod 600 "$temporary_file"
        mv "$temporary_file" "$destination_file"
        printf 'Installed %s\n' "$destination_file"
    done
}

archive_legacy_skill() {
    legacy=$skills_home/skills/astra-orchestrator
    if linked_path=$(linked_component "$skills_home" "$legacy"); then
        printf 'Legacy skill path contains a symbolic link and was not changed: %s\n' "$linked_path" >&2
        return
    fi
    if [ ! -e "$legacy" ] && [ ! -L "$legacy" ]; then
        return
    fi
    if [ -L "$legacy" ]; then
        printf 'Legacy skill is managed by a symbolic link and was not changed: %s -> %s\n' \
            "$legacy" "$(readlink "$legacy")" >&2
        return
    fi
    if ! confirm 'Archive the legacy astra-orchestrator skill to prevent duplicate matching?' yes; then
        printf 'Kept legacy skill %s\n' "$legacy"
        return
    fi
    backup=$skills_home/skill-backups/astra-orchestrator-$(date -u +%Y%m%dT%H%M%SZ)
    mkdir -p "$(dirname "$backup")"
    mv "$legacy" "$backup"
    printf 'Archived legacy skill at %s\n' "$backup"
}

merge_config() {
    destination=$codex_home/config.toml
    source_config=$profile_dir/codex/config.toml

    if linked_path=$(linked_component "$codex_home" "$destination"); then
        printf 'Skipped config: destination path contains a symbolic link (%s).\n' "$linked_path" >&2
        printf '%s\n' 'Merge model, model_reasoning_effort, and the [agents] settings from:' "$source_config" >&2
        return
    fi
    if [ -e "$destination" ] && [ ! -f "$destination" ]; then
        printf 'Skipped config: target is not a regular file: %s\n' "$destination" >&2
        return
    fi

    model=$(sed -n 's/^model = /model = /p' "$source_config" | head -1)
    effort=$(sed -n 's/^model_reasoning_effort = /model_reasoning_effort = /p' "$source_config" | head -1)
    enabled=$(sed -n '/^\[agents\]$/,$s/^enabled = /enabled = /p' "$source_config" | head -1)
    max_threads=$(sed -n '/^\[agents\]$/,$s/^max_concurrent_threads_per_session = /max_concurrent_threads_per_session = /p' "$source_config" | head -1)
    subagent_model=$(sed -n '/^\[agents\]$/,$s/^default_subagent_model = /default_subagent_model = /p' "$source_config" | head -1)
    subagent_effort=$(sed -n '/^\[agents\]$/,$s/^default_subagent_reasoning_effort = /default_subagent_reasoning_effort = /p' "$source_config" | head -1)

    mkdir -p "$codex_home"
    if [ ! -e "$destination" ]; then
        temporary_file=$(mktemp "$codex_home/.config.toml.solsetup.XXXXXX")
        printf '%s\n%s\n\n[agents]\n%s\n%s\n%s\n%s\n' \
            "$model" "$effort" "$enabled" "$max_threads" "$subagent_model" "$subagent_effort" > "$temporary_file"
    else
        if ! awk '
            {
                if (index($0, "\"\"\"") || index($0, sprintf("%c%c%c", 39, 39, 39))) exit 43
                line = $0
                sub(/^[[:space:]]*/, "", line)
                if (line == "" || line ~ /^#/) next
                if (line ~ /^\[/) {
                    if (line !~ /^\[\[?[^]]+\]\]?[[:space:]]*(#.*)?$/) exit 43
                    next
                }
                if (line !~ /^[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*=/) exit 43
            }
        ' "$destination"; then
            printf 'Skipped config: unsupported TOML syntax requires a manual merge: %s\n' "$destination" >&2
            return
        fi
        agents_sections=$(awk '/^[[:space:]]*\[[[:space:]]*agents[[:space:]]*\][[:space:]]*(#.*)?$/ { count++ } END { print count + 0 }' "$destination")
        if [ "$agents_sections" -gt 1 ]; then
            printf 'Skipped config: multiple [agents] sections make a safe merge ambiguous: %s\n' "$destination" >&2
            return
        fi
        temporary_file=$(mktemp "$codex_home/.config.toml.solsetup.XXXXXX")
        awk -v model="$model" -v effort="$effort" -v enabled="$enabled" \
            -v max_threads="$max_threads" -v subagent_model="$subagent_model" \
            -v subagent_effort="$subagent_effort" '
            function emit_root_missing() {
                if (!seen_model) print model
                if (!seen_effort) print effort
                root_done = 1
            }
            function emit_agents_missing() {
                if (!seen_enabled) print enabled
                if (!seen_max_threads) print max_threads
                if (!seen_subagent_model) print subagent_model
                if (!seen_subagent_effort) print subagent_effort
                agents_done = 1
            }
            BEGIN { section = "" }
            /^[[:space:]]*\[\[?[^]]+\]\]?[[:space:]]*(#.*)?$/ {
                if (!root_done) emit_root_missing()
                if (section == "agents" && !agents_done) emit_agents_missing()
                section = ($0 ~ /^[[:space:]]*\[[[:space:]]*agents[[:space:]]*\][[:space:]]*(#.*)?$/) ? "agents" : "other"
                if (section == "agents") found_agents = 1
                print
                next
            }
            section == "" && /^[[:space:]]*model[[:space:]]*=/ { if (++seen_model > 1) exit 42; print model; next }
            section == "" && /^[[:space:]]*model_reasoning_effort[[:space:]]*=/ { if (++seen_effort > 1) exit 42; print effort; next }
            section == "agents" && /^[[:space:]]*enabled[[:space:]]*=/ { if (++seen_enabled > 1) exit 42; print enabled; next }
            section == "agents" && /^[[:space:]]*max_concurrent_threads_per_session[[:space:]]*=/ { if (++seen_max_threads > 1) exit 42; print max_threads; next }
            section == "agents" && /^[[:space:]]*default_subagent_model[[:space:]]*=/ { if (++seen_subagent_model > 1) exit 42; print subagent_model; next }
            section == "agents" && /^[[:space:]]*default_subagent_reasoning_effort[[:space:]]*=/ { if (++seen_subagent_effort > 1) exit 42; print subagent_effort; next }
            { print }
            END {
                if (!root_done) emit_root_missing()
                if (section == "agents" && !agents_done) emit_agents_missing()
                if (!found_agents) {
                    print ""
                    print "[agents]"
                    print enabled
                    print max_threads
                    print subagent_model
                    print subagent_effort
                }
            }
        ' "$destination" > "$temporary_file" || {
            status=$?
            rm -f "$temporary_file"
            printf 'Skipped config: duplicate owned keys make a safe merge ambiguous: %s\n' "$destination" >&2
            return "$status"
        }
    fi

    if [ -f "$destination" ] && cmp -s "$temporary_file" "$destination"; then
        rm -f "$temporary_file"
        printf 'Unchanged %s\n' "$destination"
        return
    fi
    if [ -f "$destination" ]; then
        printf 'The global profile will update only model, reasoning, and [agents] defaults in %s.\n' "$destination"
        if ! confirm 'Apply this global Codex profile? A timestamped backup will be created.' yes; then
            rm -f "$temporary_file"
            printf 'Kept existing %s\n' "$destination"
            return
        fi
        cp -p "$destination" "$destination.backup-$(date -u +%Y%m%dT%H%M%SZ)"
    fi
    chmod 600 "$temporary_file"
    mv "$temporary_file" "$destination"
    printf 'Merged %s profile into %s\n' "$plan" "$destination"
}

install_global_instructions() {
    destination=$codex_home/AGENTS.md
    managed_source=${CODEX_MANAGED_AGENTS_SOURCE:-}

    if [ -s "$codex_home/AGENTS.override.md" ]; then
        printf 'Warning: %s is active and shadows AGENTS.md.\n' "$codex_home/AGENTS.override.md" >&2
    fi
    if linked_path=$(linked_component "$codex_home" "$destination"); then
        printf 'Protected managed instructions: destination path contains a symbolic link (%s).\n' "$linked_path" >&2
        if [ -z "$managed_source" ]; then
            printf '%s\n' 'No file was changed. Set CODEX_MANAGED_AGENTS_SOURCE to the declarative source and rerun.' >&2
            printf '%s\n' 'Add this instruction block to that source:' >&2
            sed 's/^/  /' "$source_root/AGENTS.md" >&2
            return
        fi
        destination=$managed_source
    fi
    if [ -L "$destination" ] || { [ -e "$destination" ] && [ ! -f "$destination" ]; }; then
        printf 'Skipped instructions: target must be a regular, unmanaged file: %s\n' "$destination" >&2
        return
    fi
    mkdir -p "$(dirname "$destination")"
    if [ -f "$destination" ] && grep -Fq 'use the `astra-orchestrator` skill' "$destination"; then
        cp -p "$destination" "$destination.backup-$(date -u +%Y%m%dT%H%M%SZ)"
        temporary_file=$(mktemp "$(dirname "$destination")/.AGENTS.md.solsetup.XXXXXX")
        sed 's/astra-orchestrator/sol-orchestrator/g' "$destination" > "$temporary_file"
        mv "$temporary_file" "$destination"
        printf 'Migrated legacy Astra skill references in %s\n' "$destination"
        return
    fi
    if [ -f "$destination" ] && grep -Fq 'use the `sol-orchestrator` skill' "$destination"; then
        printf 'Unchanged %s\n' "$destination"
        return
    fi
    if [ -f "$destination" ]; then
        cp -p "$destination" "$destination.backup-$(date -u +%Y%m%dT%H%M%SZ)"
        printf '\n\n' >> "$destination"
    fi
    cat "$source_root/AGENTS.md" >> "$destination"
    printf 'Installed global instructions in %s\n' "$destination"
}

printf 'Global Codex home: %s\n' "$codex_home"
printf 'Global skills home: %s\n' "$skills_home"

if confirm 'Install or update the five global custom agents?' yes; then
    install_files 'custom agents' "$profile_dir/codex/agents" "$codex_home/agents" "$codex_home"
fi
if confirm 'Install or update the global sol-orchestrator skill?' yes; then
    install_files 'sol-orchestrator skill' "$profile_dir/agents/skills/sol-orchestrator" "$skills_home/skills/sol-orchestrator" "$skills_home"
    archive_legacy_skill
fi
if confirm 'Merge the selected profile into the global Codex config?' yes; then
    merge_config
fi
if confirm 'Add the orchestration policy to global Codex instructions?' yes; then
    install_global_instructions
fi

printf 'Global setup complete (plan: %s). Start a new Codex session to load it.\n' "$plan"
