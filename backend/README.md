# Backend

- `jira_alert.py` — Jira filter polling, state, notifications, JSON API for the menu bar app
- `requirements.txt` — Python dependencies (`requests`)

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
pip install -r requirements.txt
```

Credentials: open the dxFilters panel and use the **key** icon to set Jira URL (`https://<BASE_URL>`) + PAT (saved to `~/.config/jira-alert/credentials.env`).

For CLI use, copy `../.env.example` to `../.env` and replace `<BASE_URL>` with your Jira host.

Install the menu bar app from the repo root: `./frontend/menubar/install.sh`.

### Optional: background polling (launchd)

Generates `~/Library/LaunchAgents/com.dxfilters.plist` with paths for **this clone** (no hardcoded home directory):

```bash
chmod +x run-jira-alert.sh install-launchagent.sh
./install-launchagent.sh
```

`run-jira-alert.sh` resolves the repo and venv from its own location. Re-run `install-launchagent.sh` after moving the repository.
