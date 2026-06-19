# Frontend

macOS menu bar app (**dxFilters**) under `menubar/`:

| File | Role |
|------|------|
| `JiraAlertMenuBar.swift` | Status item, polling, notifications |
| `MenuPanelView.swift` | Panel UI |
| `build.sh` | Compile `dxFilters.app` |
| `install.sh` | Build, install to `~/Applications/`, open app |

From the repository root:

```bash
./frontend/menubar/install.sh
```
