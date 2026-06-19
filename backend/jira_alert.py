#!/usr/bin/env python3
"""
Poll a Jira saved filter and track newly appeared issue keys.

Banners are delivered by the dxFilters menu bar app (UserNotifications), not this CLI.
First run records a baseline. The app notifies only for keys not in the previous snapshot.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import warnings
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

warnings.filterwarnings(
    "ignore",
    message="urllib3 v2 only supports OpenSSL",
    category=Warning,
)

import requests

DEFAULT_STATE_PATH = Path.home() / ".config" / "jira-alert" / "state.json"
FILTERS_CONFIG_PATH = Path.home() / ".config" / "jira-alert" / "filters.json"
CREDENTIALS_PATH = Path.home() / ".config" / "jira-alert" / "credentials.env"
STATES_DIR = Path.home() / ".config" / "jira-alert" / "states"

APP_NOTIFICATION_HINT = (
    "Banners are delivered by the dxFilters menu bar app. "
    "Run ./frontend/menubar/install.sh, open the app, and enable dxFilters "
    "under System Settings → Notifications."
)


@dataclass
class CheckResult:
    baseline: bool
    issue_count: int
    new_issues: list[dict[str, str]] = field(default_factory=list)
    message: str = ""
    error: str | None = None
    jira_base_url: str = ""
    filter_id: str = ""
    filter_name: str = ""
    filter_jira_name: str = ""
    filter_renamed: str = "false"
    filters: list[dict[str, str]] = field(default_factory=list)
    badge_count: int = 0


def default_filter_id() -> str:
    return os.environ.get("JIRA_FILTER_ID", "12345").strip()


def load_filters_config() -> dict[str, Any]:
    if FILTERS_CONFIG_PATH.is_file():
        try:
            data = json.loads(FILTERS_CONFIG_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return data
        except (json.JSONDecodeError, OSError):
            pass
    filter_id = default_filter_id()
    return {
        "active_filter_id": filter_id,
        "filters": [{"id": filter_id, "jira_name": f"Filter {filter_id}"}],
    }


def save_filters_config(data: dict[str, Any]) -> None:
    FILTERS_CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = FILTERS_CONFIG_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    tmp.replace(FILTERS_CONFIG_PATH)


def active_filter_id() -> str:
    data = load_filters_config()
    active = str(data.get("active_filter_id", "")).strip()
    if active:
        return active
    filters = data.get("filters") or []
    if filters and isinstance(filters[0], dict):
        return str(filters[0].get("id", default_filter_id())).strip()
    return default_filter_id()


def filter_jira_name(entry: dict[str, Any]) -> str:
    fid = str(entry.get("id", "")).strip()
    return str(entry.get("jira_name") or entry.get("name") or f"Filter {fid}").strip()


def filter_display_name(entry: dict[str, Any]) -> str:
    fid = str(entry.get("id", "")).strip()
    custom = str(entry.get("display_name", "")).strip()
    if custom:
        return custom
    return filter_jira_name(entry)


def normalize_filter_entry(entry: dict[str, Any]) -> dict[str, Any]:
    if not entry.get("jira_name") and entry.get("name"):
        entry["jira_name"] = str(entry["name"]).strip()
    return entry


def sync_filter_jira_name(filter_id: str, jira_name: str) -> None:
    data = load_filters_config()
    changed = False
    for entry in data.get("filters") or []:
        if not isinstance(entry, dict):
            continue
        if str(entry.get("id", "")).strip() != filter_id:
            continue
        normalize_filter_entry(entry)
        if entry.get("jira_name") != jira_name:
            entry["jira_name"] = jira_name
            changed = True
        break
    if changed:
        save_filters_config(data)


def filters_for_ui() -> list[dict[str, str]]:
    data = load_filters_config()
    active = active_filter_id()
    items: list[dict[str, str]] = []
    for raw in data.get("filters") or []:
        if not isinstance(raw, dict):
            continue
        entry = normalize_filter_entry(dict(raw))
        fid = str(entry.get("id", "")).strip()
        if not fid:
            continue
        jira_name = filter_jira_name(entry)
        display = filter_display_name(entry)
        items.append(
            {
                "id": fid,
                "name": display,
                "jira_name": jira_name,
                "renamed": "true" if display != jira_name else "false",
                "active": "true" if fid == active else "false",
            }
        )
    return items


def add_saved_filter(filter_id: str, name: str | None = None) -> dict[str, Any]:
    filter_id = filter_id.strip()
    if not filter_id:
        raise ValueError("Filter id is required.")
    data = load_filters_config()
    filters = data.get("filters") or []
    for entry in filters:
        if isinstance(entry, dict) and str(entry.get("id", "")).strip() == filter_id:
            normalize_filter_entry(entry)
            if name:
                entry["jira_name"] = name.strip()
                if not str(entry.get("display_name", "")).strip():
                    entry.pop("display_name", None)
            save_filters_config(data)
            return data
    label = (name or f"Filter {filter_id}").strip()
    filters.append({"id": filter_id, "jira_name": label})
    data["filters"] = filters
    if not data.get("active_filter_id"):
        data["active_filter_id"] = filter_id
    save_filters_config(data)
    return data


def rename_saved_filter(filter_id: str, display_name: str) -> dict[str, Any]:
    filter_id = filter_id.strip()
    display_name = display_name.strip()
    if not filter_id:
        raise ValueError("Filter id is required.")
    if not display_name:
        raise ValueError("Display name is required.")
    data = load_filters_config()
    for entry in data.get("filters") or []:
        if not isinstance(entry, dict):
            continue
        if str(entry.get("id", "")).strip() != filter_id:
            continue
        normalize_filter_entry(entry)
        jira_name = filter_jira_name(entry)
        if display_name == jira_name:
            entry.pop("display_name", None)
        else:
            entry["display_name"] = display_name
        save_filters_config(data)
        return data
    raise ValueError(f"Unknown filter id {filter_id}")


def set_active_filter(filter_id: str) -> dict[str, Any]:
    filter_id = filter_id.strip()
    data = load_filters_config()
    known = {
        str(entry.get("id", "")).strip()
        for entry in (data.get("filters") or [])
        if isinstance(entry, dict)
    }
    if filter_id not in known:
        add_saved_filter(filter_id)
        data = load_filters_config()
    data["active_filter_id"] = filter_id
    save_filters_config(data)
    return data


def remove_saved_filter(filter_id: str) -> dict[str, Any]:
    filter_id = filter_id.strip()
    if not filter_id:
        raise ValueError("Filter id is required.")
    data = load_filters_config()
    filters = [entry for entry in (data.get("filters") or []) if isinstance(entry, dict)]
    if len(filters) <= 1:
        raise ValueError("Cannot remove the last saved filter.")
    remaining = [entry for entry in filters if str(entry.get("id", "")).strip() != filter_id]
    if len(remaining) == len(filters):
        raise ValueError(f"Unknown filter id {filter_id}")
    data["filters"] = remaining
    if str(data.get("active_filter_id", "")).strip() == filter_id:
        data["active_filter_id"] = str(remaining[0].get("id", "")).strip()
    save_filters_config(data)
    state_file = STATES_DIR / f"{filter_id}.json"
    if state_file.is_file():
        state_file.unlink()
    return data


def state_path_for_filter(filter_id: str, override: Path | None = None) -> Path:
    if override is not None:
        return override
    STATES_DIR.mkdir(parents=True, exist_ok=True)
    legacy = DEFAULT_STATE_PATH
    per_filter = STATES_DIR / f"{filter_id}.json"
    if legacy.is_file() and not per_filter.is_file() and filter_id == default_filter_id():
        try:
            per_filter.write_text(legacy.read_text(encoding="utf-8"), encoding="utf-8")
        except OSError:
            pass
    return per_filter


def fetch_filter_meta(session: requests.Session, base: str, filter_id: str) -> dict[str, str]:
    for prefix in ("rest/api/3", "rest/api/2"):
        try:
            data = api_get_json(session, base, f"{prefix}/filter/{filter_id}")
            name = data.get("name")
            jql = data.get("jql")
            if isinstance(name, str) and name.strip():
                return {"name": name.strip(), "jql": str(jql or "").strip()}
        except requests.HTTPError as e:
            if e.response is not None and e.response.status_code in (404, 302, 303, 307, 308):
                continue
            if "Non-JSON response" in str(e):
                continue
            raise
    raise RuntimeError(f"Could not load filter metadata for id {filter_id}")


def load_dotenv(path: Path, *, override: bool = False) -> None:
    """Minimal .env loader (no extra dependency)."""
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip().strip('"').strip("'")
        if key and (override or key not in os.environ):
            os.environ[key] = value


def load_env_files(project_root: Path, backend_root: Path) -> None:
    load_dotenv(project_root / ".env")
    load_dotenv(backend_root / ".env")
    load_dotenv(CREDENTIALS_PATH, override=True)


def credentials_status() -> dict[str, Any]:
    base = os.environ.get("JIRA_BASE_URL", "").strip()
    pat = os.environ.get("JIRA_PAT", "").strip()
    email = os.environ.get("JIRA_EMAIL", "").strip()
    api_token = os.environ.get("JIRA_API_TOKEN", "").strip()
    configured = bool(base and (pat or (email and api_token)))
    return {
        "configured": configured,
        "jira_base_url": base,
        "has_pat": bool(pat),
        "has_cloud_auth": bool(email and api_token),
        "credentials_file": str(CREDENTIALS_PATH),
    }


def save_credentials(jira_base_url: str, jira_pat: str) -> dict[str, Any]:
    base = jira_base_url.rstrip("/").strip()
    pat = jira_pat.strip()
    if not base:
        raise ValueError("JIRA_BASE_URL is required.")
    if not pat:
        raise ValueError("JIRA_PAT is required.")
    if not base.startswith(("http://", "https://")):
        raise ValueError("JIRA_BASE_URL must start with http:// or https://")
    CREDENTIALS_PATH.parent.mkdir(parents=True, exist_ok=True)
    CREDENTIALS_PATH.write_text(
        f"JIRA_BASE_URL={base}\nJIRA_PAT={pat}\n",
        encoding="utf-8",
    )
    os.chmod(CREDENTIALS_PATH, 0o600)
    os.environ["JIRA_BASE_URL"] = base
    os.environ["JIRA_PAT"] = pat
    os.environ.pop("JIRA_EMAIL", None)
    os.environ.pop("JIRA_API_TOKEN", None)
    return credentials_status()


def jira_session() -> tuple[requests.Session, str]:
    base = os.environ.get("JIRA_BASE_URL", "").rstrip("/")
    if not base:
        raise RuntimeError("Set JIRA_BASE_URL (e.g. https://<BASE_URL>)")

    session = requests.Session()
    session.headers["Accept"] = "application/json"
    session.headers["Content-Type"] = "application/json"

    email = os.environ.get("JIRA_EMAIL", "").strip()
    token = os.environ.get("JIRA_API_TOKEN", "").strip()
    pat = os.environ.get("JIRA_PAT", "").strip()

    if email and token:
        session.auth = (email, token)
    elif pat:
        session.headers["Authorization"] = f"Bearer {pat}"
    else:
        raise RuntimeError("Set JIRA_BASE_URL and JIRA_PAT.")

    return session, base


def api_get_json(session: requests.Session, base: str, path: str) -> Any:
    url = urljoin(base + "/", path.lstrip("/"))
    r = session.get(url, timeout=60, allow_redirects=False)
    if r.status_code >= 400:
        print(f"GET {url} -> {r.status_code}\n{r.text[:2000]}", file=sys.stderr)
        r.raise_for_status()
    if r.status_code >= 300:
        raise requests.HTTPError(
            f"Unexpected {r.status_code} from {url}",
            response=r,
        )
    try:
        return r.json()
    except requests.exceptions.JSONDecodeError as e:
        ct = r.headers.get("content-type", "")
        raise requests.HTTPError(
            f"Non-JSON response from {url} (content-type={ct})",
            response=r,
        ) from e


def fetch_filter(session: requests.Session, base: str, filter_id: str) -> dict[str, str]:
    """Load filter name + JQL in a single API call."""
    for prefix in ("rest/api/3", "rest/api/2"):
        try:
            data = api_get_json(session, base, f"{prefix}/filter/{filter_id}")
            name = data.get("name")
            jql = data.get("jql")
            if isinstance(jql, str) and jql.strip():
                return {
                    "name": str(name or "").strip(),
                    "jql": jql.strip(),
                }
        except requests.HTTPError as e:
            if e.response is not None and e.response.status_code in (404, 302, 303, 307, 308):
                continue
            if "Non-JSON response" in str(e):
                continue
            raise
    raise RuntimeError(f"Could not load filter id {filter_id}")


def fetch_filter_jql(session: requests.Session, base: str, filter_id: str) -> str:
    return fetch_filter(session, base, filter_id)["jql"]


def search_all_keys(session: requests.Session, base: str, jql: str) -> list[dict[str, str]]:
    """Return list of {key, summary} for all issues matching jql (paginated)."""
    issues: list[dict[str, str]] = []
    page_size = 50

    for prefix in ("rest/api/3", "rest/api/2"):
        start_at = 0
        issues.clear()
        url = urljoin(base + "/", f"{prefix}/search")
        while True:
            params = {
                "jql": jql,
                "startAt": start_at,
                "maxResults": page_size,
                "fields": "summary",
            }
            r = session.get(url, params=params, timeout=60, allow_redirects=False)
            if r.status_code == 404:
                issues.clear()
                break
            if r.status_code >= 300:
                issues.clear()
                break
            if r.status_code >= 400:
                print(f"GET {r.url} -> {r.status_code}\n{r.text[:2000]}", file=sys.stderr)
                r.raise_for_status()
            try:
                data = r.json()
            except requests.exceptions.JSONDecodeError:
                issues.clear()
                break
            batch = data.get("issues") or []
            for it in batch:
                key = it.get("key")
                if not key:
                    continue
                fields = it.get("fields") or {}
                summ = (fields.get("summary") or "").strip()
                issues.append({"key": key, "summary": summ})
            total = data.get("total")
            start_at += len(batch)
            if not batch or (total is not None and start_at >= total):
                return list(issues)
    raise RuntimeError("Could not query Jira search API (tried v3 and v2)")


def read_state(path: Path) -> set[str]:
    if not path.is_file():
        return set()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        keys = data.get("seen_keys")
        if isinstance(keys, list):
            return {str(k) for k in keys}
    except (json.JSONDecodeError, OSError):
        pass
    return set()


def write_state(path: Path, seen: set[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(
        json.dumps({"seen_keys": sorted(seen)}, indent=2) + "\n",
        encoding="utf-8",
    )
    tmp.replace(path)


def perform_check(
    state_path: Path | None = None,
    *,
    reset_baseline: bool,
    dry_run: bool,
    notify: bool = True,
    filter_id: str | None = None,
) -> CheckResult:
    try:
        filter_id = (filter_id or active_filter_id()).strip()
        saved_filters = filters_for_ui()
        resolved_state = state_path_for_filter(filter_id, state_path)
        session, base = jira_session()
        try:
            filter_data = fetch_filter(session, base, filter_id)
            if filter_data.get("name"):
                sync_filter_jira_name(filter_id, filter_data["name"])
                saved_filters = filters_for_ui()
            jql = filter_data["jql"]
        except Exception:
            jql = fetch_filter_jql(session, base, filter_id)
        active_filter = next((f for f in saved_filters if f["id"] == filter_id), None)
        filter_name = active_filter["name"] if active_filter else f"Filter {filter_id}"
        filter_jira_name = active_filter["jira_name"] if active_filter else filter_name
        filter_renamed = active_filter["renamed"] if active_filter else "false"
        issues = search_all_keys(session, base, jql)
        current_keys = {i["key"] for i in issues}
        summary_by_key = {i["key"]: i["summary"] for i in issues}

        prev = read_state(resolved_state)
        if reset_baseline:
            prev = set()

        if not prev:
            if not dry_run:
                write_state(resolved_state, current_keys)
            message = (
                f"Baseline saved ({len(current_keys)} issues). "
                "Future runs will notify when new keys appear."
            )
            return CheckResult(
                baseline=True,
                issue_count=len(current_keys),
                message=message,
                jira_base_url=base,
                filter_id=filter_id,
                filter_name=filter_name,
                filter_jira_name=filter_jira_name,
                filter_renamed=filter_renamed,
                filters=saved_filters,
                badge_count=len(current_keys),
            )

        new_keys = sorted(current_keys - prev)
        new_issues = [
            {"key": key, "summary": summary_by_key.get(key, "")}
            for key in new_keys
        ]
        if not new_keys:
            message = f"No new issues ({len(current_keys)} in filter)."
        else:
            message = f"{len(new_keys)} new issue(s)."
            if notify and not dry_run and new_issues:
                print(APP_NOTIFICATION_HINT, file=sys.stderr)

        if not dry_run:
            write_state(resolved_state, current_keys)

        badge_count = len(new_issues) if new_issues else len(current_keys)
        return CheckResult(
            baseline=False,
            issue_count=len(current_keys),
            new_issues=new_issues,
            message=message,
            jira_base_url=base,
            filter_id=filter_id,
            filter_name=filter_name,
            filter_jira_name=filter_jira_name,
            filter_renamed=filter_renamed,
            filters=saved_filters,
            badge_count=badge_count,
        )
    except Exception as e:
        return CheckResult(
            baseline=False,
            issue_count=0,
            message="Check failed.",
            error=str(e),
            filter_id=filter_id or active_filter_id(),
            filters=filters_for_ui(),
        )


def run_once(
    state_path: Path | None = None,
    *,
    reset_baseline: bool,
    dry_run: bool,
) -> int:
    result = perform_check(
        state_path,
        reset_baseline=reset_baseline,
        dry_run=dry_run,
        notify=False,
    )
    if result.error:
        print(result.error, file=sys.stderr)
        return 1
    print(result.message)
    for issue in result.new_issues:
        print(f"  {issue['key']}  {issue.get('summary', '')}".rstrip())
    return 0


def main() -> int:
    backend_root = Path(__file__).resolve().parent
    project_root = backend_root.parent
    load_env_files(project_root, backend_root)

    parser = argparse.ArgumentParser(
        description="Jira filter polling for dxFilters (notifications are sent by the menu bar app)"
    )
    parser.add_argument(
        "--state",
        type=Path,
        default=DEFAULT_STATE_PATH,
        help=f"Where to store seen issue keys (default: {DEFAULT_STATE_PATH})",
    )
    parser.add_argument(
        "--reset-baseline",
        action="store_true",
        help="Forget previous keys; next run establishes a new baseline with no alerts",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions only; do not write state or show notifications",
    )
    parser.add_argument(
        "--test-notification",
        action="store_true",
        help="Print how to test banners from the dxFilters menu bar app",
    )
    parser.add_argument(
        "--check-json",
        action="store_true",
        help="Machine-readable check result on stdout (for menu bar app)",
    )
    parser.add_argument(
        "--filters-json",
        action="store_true",
        help="Print saved filters configuration as JSON",
    )
    parser.add_argument(
        "--add-filter",
        metavar="ID",
        help="Save a Jira filter id for future use",
    )
    parser.add_argument(
        "--filter-name",
        metavar="NAME",
        help="Optional display name when using --add-filter",
    )
    parser.add_argument(
        "--set-filter",
        metavar="ID",
        help="Switch the active filter id",
    )
    parser.add_argument(
        "--rename-filter",
        metavar="ID",
        help="Set a custom display name for a saved filter",
    )
    parser.add_argument(
        "--remove-filter",
        metavar="ID",
        help="Remove a saved filter and its baseline state",
    )
    parser.add_argument(
        "--credentials-status",
        action="store_true",
        help="Print Jira credentials status as JSON",
    )
    parser.add_argument(
        "--save-credentials-json",
        metavar="JSON",
        help='Save Jira PAT credentials, e.g. {"jira_base_url":"…","jira_pat":"…"}',
    )
    parser.add_argument(
        "--loop",
        action="store_true",
        help="Run forever, sleeping POLL_INTERVAL_SECONDS between checks (default 300)",
    )
    args = parser.parse_args()

    if args.test_notification:
        print(APP_NOTIFICATION_HINT)
        print("In the menu bar panel, use Test Alert after allowing notifications for dxFilters.")
        return 0

    if args.credentials_status:
        print(json.dumps(credentials_status()))
        return 0

    if args.save_credentials_json:
        try:
            data = json.loads(args.save_credentials_json)
            if not isinstance(data, dict):
                raise ValueError("Credentials JSON must be an object.")
            status = save_credentials(
                str(data.get("jira_base_url", "")),
                str(data.get("jira_pat", "")),
            )
            print(json.dumps(status))
            return 0
        except (ValueError, json.JSONDecodeError) as e:
            print(str(e), file=sys.stderr)
            return 1

    if args.add_filter or args.set_filter or args.rename_filter or args.remove_filter:
        try:
            if args.add_filter:
                add_saved_filter(args.add_filter, args.filter_name)
            if args.set_filter:
                set_active_filter(args.set_filter)
            if args.rename_filter:
                if not args.filter_name:
                    print("--filter-name is required with --rename-filter", file=sys.stderr)
                    return 1
                rename_saved_filter(args.rename_filter, args.filter_name)
            if args.remove_filter:
                remove_saved_filter(args.remove_filter)
            print(json.dumps(load_filters_config(), indent=2))
            return 0
        except ValueError as e:
            print(str(e), file=sys.stderr)
            return 1

    if args.filters_json:
        print(json.dumps(load_filters_config(), indent=2))
        return 0

    if args.check_json:
        result = perform_check(
            args.state if args.state != DEFAULT_STATE_PATH else None,
            reset_baseline=args.reset_baseline,
            dry_run=args.dry_run,
            notify=False,
        )
        print(json.dumps(asdict(result)))
        return 1 if result.error else 0

    if args.loop:
        interval = int(os.environ.get("POLL_INTERVAL_SECONDS", "300"))
        print(f"Loop mode: checking every {interval}s. Ctrl+C to stop.")
        while True:
            try:
                run_once(
                    args.state if args.state != DEFAULT_STATE_PATH else None,
                    reset_baseline=False,
                    dry_run=args.dry_run,
                )
            except KeyboardInterrupt:
                raise
            except Exception as e:
                print(f"Error: {e}", file=sys.stderr)
            time.sleep(max(30, interval))
    return run_once(
        args.state if args.state != DEFAULT_STATE_PATH else None,
        reset_baseline=args.reset_baseline,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    raise SystemExit(main())
