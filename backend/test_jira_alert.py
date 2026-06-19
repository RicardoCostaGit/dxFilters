#!/usr/bin/env python3
"""Runnable checks for backend install path and PAT persistence."""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "backend" / "jira_alert.py"
REQUIREMENTS = ROOT / "backend" / "requirements.txt"


def _python() -> str:
    venv = ROOT / "backend" / ".venv" / "bin" / "python3"
    if venv.is_file() and os.access(venv, os.X_OK):
        return str(venv)
    return sys.executable


def _run(
    *args: str,
    home: Path,
    extra_env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["PYTHONWARNINGS"] = "ignore"
    for key in list(env):
        if key.startswith("JIRA_"):
            del env[key]
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [_python(), str(SCRIPT), *args],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )


class JiraAlertCliTests(unittest.TestCase):
    def test_import_requests(self) -> None:
        proc = subprocess.run(
            [_python(), "-c", "import requests; print(requests.__version__)"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(proc.stdout.strip())

    def test_credentials_status_empty(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            proc = _run("--credentials-status", home=Path(tmp))
            self.assertEqual(proc.returncode, 0, proc.stderr)
            data = json.loads(proc.stdout)
            self.assertFalse(data["configured"])
            self.assertFalse(data["has_pat"])

    def test_save_credentials_json_persists_pat(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            payload = json.dumps(
                {
                    "jira_base_url": "https://jira.example.com",
                    "jira_pat": "test-pat-token",
                }
            )
            proc = _run("--save-credentials-json", payload, home=home)
            self.assertEqual(proc.returncode, 0, proc.stderr or proc.stdout)
            data = json.loads(proc.stdout)
            self.assertTrue(data["configured"])
            self.assertEqual(data["jira_base_url"], "https://jira.example.com")

            creds = home / ".config" / "jira-alert" / "credentials.env"
            self.assertTrue(creds.is_file())
            text = creds.read_text(encoding="utf-8")
            self.assertIn("JIRA_PAT=test-pat-token", text)
            self.assertNotIn("test-pat-token", proc.stderr)

            mode = creds.stat().st_mode
            self.assertEqual(mode & stat.S_IRWXG, 0)
            self.assertEqual(mode & stat.S_IRWXO, 0)

            status = _run("--credentials-status", home=home)
            self.assertEqual(status.returncode, 0, status.stderr)
            self.assertTrue(json.loads(status.stdout)["configured"])

    def test_save_credentials_json_rejects_missing_pat(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = json.dumps({"jira_base_url": "https://jira.example.com", "jira_pat": ""})
            proc = _run("--save-credentials-json", payload, home=Path(tmp))
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("JIRA_PAT", proc.stderr)

    def test_check_json_without_credentials_is_not_import_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            proc = _run("--check-json", home=Path(tmp))
            self.assertEqual(proc.returncode, 1, proc.stdout)
            combined = f"{proc.stdout}\n{proc.stderr}".lower()
            self.assertNotIn("modulenotfounderror", combined)
            data = json.loads(proc.stdout)
            self.assertTrue(data.get("error"))

    def test_check_json_after_save_does_not_import_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            payload = json.dumps(
                {"jira_base_url": "https://jira.example.com", "jira_pat": "test-pat-token"}
            )
            save = _run("--save-credentials-json", payload, home=home)
            self.assertEqual(save.returncode, 0, save.stderr)

            proc = _run("--check-json", home=home)
            combined = f"{proc.stdout}\n{proc.stderr}".lower()
            self.assertNotIn("modulenotfounderror", combined)
            data = json.loads(proc.stdout)
            # Network may fail; we only require Python backend is wired up.
            self.assertNotIn("no module named 'requests'", combined)


class VenvBootstrapTests(unittest.TestCase):
    """Mirrors frontend/menubar/build.sh venv setup on a clean tree."""

    def test_fresh_venv_can_run_save_credentials(self) -> None:
        if not REQUIREMENTS.is_file():
            self.skipTest("requirements.txt missing")

        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            backend = work / "backend"
            backend.mkdir()
            for name in ("jira_alert.py", "requirements.txt"):
                (backend / name).write_bytes((ROOT / "backend" / name).read_bytes())

            venv_py = backend / ".venv" / "bin" / "python3"
            bootstrap = subprocess.run(
                ["python3", "-m", "venv", str(backend / ".venv")],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(bootstrap.returncode, 0, bootstrap.stderr)

            pip = subprocess.run(
                [str(venv_py), "-m", "pip", "install", "-q", "-r", str(backend / "requirements.txt")],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(pip.returncode, 0, pip.stderr)

            import_check = subprocess.run(
                [str(venv_py), "-c", "import requests"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(import_check.returncode, 0, import_check.stderr)

            home = work / "home"
            home.mkdir()
            env = os.environ.copy()
            env["HOME"] = str(home)
            for key in list(env):
                if key.startswith("JIRA_"):
                    del env[key]
            payload = json.dumps(
                {"jira_base_url": "https://jira.example.com", "jira_pat": "bootstrap-pat"}
            )
            proc = subprocess.run(
                [str(venv_py), str(backend / "jira_alert.py"), "--save-credentials-json", payload],
                cwd=work,
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr or proc.stdout)
            combined = f"{proc.stdout}\n{proc.stderr}".lower()
            self.assertNotIn("modulenotfounderror", combined)
            self.assertTrue(json.loads(proc.stdout)["configured"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
