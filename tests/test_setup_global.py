import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SETUP = ROOT / "setup.sh"


def run_setup(home: pathlib.Path, answers: str) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment["HOME"] = str(home)
    environment.pop("CODEX_HOME", None)
    environment.pop("AGENTS_HOME", None)
    environment.pop("CODEX_MANAGED_AGENTS_SOURCE", None)
    return subprocess.run(
        [str(SETUP)],
        cwd=ROOT,
        env=environment,
        input=answers,
        text=True,
        capture_output=True,
        check=True,
    )


class GlobalSetupTests(unittest.TestCase):
    def test_fresh_pro_and_plus_profiles(self) -> None:
        expectations = {
            "pro": ('model = "gpt-5.6-sol"', 'model_reasoning_effort = "medium"', 'default_subagent_reasoning_effort = "high"'),
            "plus": ('model = "gpt-5.6-luna"', 'model_reasoning_effort = "max"', 'default_subagent_reasoning_effort = "medium"'),
        }
        for plan, expected in expectations.items():
            with self.subTest(plan=plan), tempfile.TemporaryDirectory() as directory:
                home = pathlib.Path(directory)
                plan_answer = "1" if plan == "pro" else "2"
                run_setup(home, f"\n{plan_answer}\n\n\n\n\n")

                config = (home / ".codex/config.toml").read_text()
                for value in expected:
                    self.assertIn(value, config)
                self.assertIn('model = "gpt-5.6-sol"', (home / ".codex/agents/reviewer.toml").read_text())
                self.assertIn('model_reasoning_effort = "low"', (home / ".codex/agents/reviewer.toml").read_text())
                self.assertTrue((home / ".agents/skills/sol-orchestrator/SKILL.md").is_file())
                self.assertFalse((home / ".agents/skills/astra-orchestrator").exists())

    def test_preserves_unrelated_state_and_rerun_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = pathlib.Path(directory)
            codex_home = home / ".codex"
            codex_home.mkdir()
            (codex_home / "agents").mkdir()
            (codex_home / "agents/custom.toml").write_text('name = "custom"\n')
            (codex_home / "config.toml").write_text(
                'notify = ["keep-me"]\n'
                'model = "old"\n'
                'model_reasoning_effort = "low"\n\n'
                '[agents]\n'
                'enabled = false\n'
                'interrupt_message = false\n\n'
                '[plugins.example]\n'
                'enabled = true\n'
            )
            (codex_home / "AGENTS.md").write_text("# Existing\n\n- Keep me.\n")

            run_setup(home, "\n\n\n\n\n\n\n")
            files_before = {
                path.relative_to(home): path.read_bytes()
                for path in home.rglob("*")
                if path.is_file() and ".backup-" not in path.name
            }
            run_setup(home, "\n\n\n\n\n\n\n")
            files_after = {
                path.relative_to(home): path.read_bytes()
                for path in home.rglob("*")
                if path.is_file() and ".backup-" not in path.name
            }

            self.assertEqual(files_before, files_after)
            config = (codex_home / "config.toml").read_text()
            self.assertIn('notify = ["keep-me"]', config)
            self.assertIn("interrupt_message = false", config)
            self.assertIn("[plugins.example]\nenabled = true", config)
            self.assertTrue((codex_home / "agents/custom.toml").is_file())
            self.assertEqual((codex_home / "AGENTS.md").read_text().count("use the `sol-orchestrator` skill"), 1)

    def test_preserves_nested_models_and_recognizes_commented_tables(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = pathlib.Path(directory)
            codex_home = home / ".codex"
            codex_home.mkdir()
            (codex_home / "config.toml").write_text(
                'notify = ["keep-me"]\n\n'
                '[[model_providers]] # valid array table\n'
                'name = "nested"\n'
                'model = "nested-keep"\n\n'
                '[agents] # existing section\n'
                'interrupt_message = false\n\n'
                '["plugins".example] # quoted dotted table\n'
                'enabled = true\n'
            )

            run_setup(home, "\n\n\n\n\n\n\n")

            config = (codex_home / "config.toml").read_text()
            self.assertEqual(config.count('[agents] # existing section'), 1)
            self.assertNotIn('\n[agents]\n', config)
            self.assertIn('model = "gpt-5.6-sol"', config)
            self.assertEqual(config.count('model = "gpt-5.6-sol"'), 1)
            self.assertIn('model = "nested-keep"', config)
            self.assertIn('["plugins".example] # quoted dotted table', config)

    def test_linked_intermediate_install_directories_are_not_modified(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = pathlib.Path(directory)
            codex_home = home / ".codex"
            agents_home = home / ".agents"
            external_agents = home / "external-codex-agents"
            external_skills = home / "external-skills"
            codex_home.mkdir()
            agents_home.mkdir()
            external_agents.mkdir()
            external_skills.mkdir()
            (codex_home / "agents").symlink_to(external_agents, target_is_directory=True)
            (agents_home / "skills").symlink_to(external_skills, target_is_directory=True)

            result = run_setup(home, "\n\n\n\n\n\n")

            self.assertEqual(list(external_agents.iterdir()), [])
            self.assertEqual(list(external_skills.iterdir()), [])
            self.assertIn("destination path contains a symbolic link", result.stderr)

    def test_unsupported_toml_is_left_byte_for_byte_unchanged(self) -> None:
        unsupported_configs = (
            '["provider]name"]\nmodel = "nested-keep"\n',
            'message = """\n[agents]\nenabled = false\n"""\n',
        )
        for original in unsupported_configs:
            with self.subTest(config=original), tempfile.TemporaryDirectory() as directory:
                home = pathlib.Path(directory)
                codex_home = home / ".codex"
                codex_home.mkdir()
                config_path = codex_home / "config.toml"
                config_path.write_text(original)

                result = run_setup(home, "\n\n\n\n\n\n")

                self.assertEqual(config_path.read_text(), original)
                self.assertEqual(list(codex_home.glob("config.toml.backup-*")), [])
                self.assertIn("manual merge", result.stderr)

    def test_managed_config_and_instructions_are_not_modified(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = pathlib.Path(directory)
            codex_home = home / ".codex"
            source = home / "managed"
            codex_home.mkdir()
            source.mkdir()
            source_config = source / "config.toml"
            source_agents = source / "AGENTS.md"
            source_config.write_text('model = "keep-model"\n')
            source_agents.write_text("# Keep managed instructions\n")
            (codex_home / "config.toml").symlink_to(source_config)
            (codex_home / "AGENTS.md").symlink_to(source_agents)

            result = run_setup(home, "\n\n\n\n\n\n")

            self.assertEqual(source_config.read_text(), 'model = "keep-model"\n')
            self.assertEqual(source_agents.read_text(), "# Keep managed instructions\n")
            self.assertIn("Skipped config", result.stderr)
            self.assertIn("Protected managed instructions", result.stderr)

    def test_project_scope_still_installs_selected_profile(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = pathlib.Path(directory) / "home"
            target = pathlib.Path(directory) / "project"
            home.mkdir()
            target.mkdir()

            result = run_setup(home, f"2\n1\n{target}\n\n\n\n")

            self.assertIn("Setup complete", result.stdout)
            self.assertIn('model = "gpt-5.6-sol"', (target / ".codex/config.toml").read_text())
            self.assertIn('model_reasoning_effort = "medium"', (target / ".codex/config.toml").read_text())
            self.assertTrue((target / ".agents/skills/sol-orchestrator/SKILL.md").is_file())

    def test_legacy_astra_skill_and_instruction_are_migrated_recoverably(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = pathlib.Path(directory)
            legacy = home / ".agents/skills/astra-orchestrator"
            legacy.mkdir(parents=True)
            (legacy / "SKILL.md").write_text("legacy skill\n")
            codex_home = home / ".codex"
            codex_home.mkdir()
            (codex_home / "AGENTS.md").write_text(
                "For complex coding tasks, use the `astra-orchestrator` skill when its trigger conditions match.\n"
            )

            run_setup(home, "\n\n\n\n\n\n\n")

            self.assertFalse(legacy.exists())
            self.assertTrue((home / ".agents/skills/sol-orchestrator/SKILL.md").is_file())
            self.assertEqual(len(list((home / ".agents/skill-backups").glob("astra-orchestrator-*"))), 1)
            instructions = (codex_home / "AGENTS.md").read_text()
            self.assertIn("`sol-orchestrator`", instructions)
            self.assertNotIn("`astra-orchestrator`", instructions)


if __name__ == "__main__":
    unittest.main()
