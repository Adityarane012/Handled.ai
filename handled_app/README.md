<div align="center">

# 📱 handled_app

**The Flutter client for [handled.ai](../README.md)** — one codebase, real
installable app for desktop and web.

![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-Windows%20·%20Web-555)

</div>

---

The app is **screens only** — it holds no business logic. Every button press is a
request to the FastAPI backend, which decides what happens. See the
[root README](../README.md) for the architecture and the safety model.

## Screens

| Route | Screen | What it does |
|---|---|---|
| `/login`, `/signup` | Auth | Sign a company up, log in; JWT stored in `shared_preferences` |
| `/` | Overview | Autonomy analytics from `/ops/stats` — share that ran without a human, pending count, human rejection rate, by-bucket breakdown; first-run explainer for a new company |
| `/ops` | Ops Tools | One card per tool, grouped by autonomy bucket; triggers all 5 endpoints + inventory-doc upload |
| `/approvals` | Approval Queue | Pending drafts with who requested them. PO cards render **blank** quantity/amount fields and keep Approve disabled until a human types real figures; staff see the cards view-only |
| `/history` | History | The full audit trail with bucket/status filters; "Requested by X · Approved by Y" on every row; tap for the full record (agent output, what the human typed, who/when/why) |
| `/team` | Team | Members and their roles; the owner adds department heads and staff |

Routing is `go_router` with an auth redirect; state is `provider`. Permissions
(`can_approve`, `can_manage_team`) come from `/auth/me` — the app never works
them out itself, and the backend enforces them regardless.

## Run it

```bash
flutter pub get
flutter run -d chrome          # or:  flutter run -d windows
```

- The backend must be running at `http://127.0.0.1:8000` (see the root README).
  Change `baseUrl` in [`lib/services/api_service.dart`](lib/services/api_service.dart)
  if yours differs.
- `flutter run -d windows` needs **Windows Developer Mode** on
  (`start ms-settings:developers`) for plugin symlink support. `-d chrome` doesn't.

## Checks

```bash
flutter analyze
flutter test
```

## Project structure

```
lib/
  main.dart                    go_router config + auth redirect
  theme.dart                   dark theme, Inter (vendored in assets/fonts/)
  ops_labels.dart              shared bucket/status/role labels + colours, badges,
                               manualFiguresAreUsable() (the approve-gating rule),
                               formatTimestamp(), trailSummary()
  agent_text.dart              renders the agent's markdown output
  providers/auth_provider.dart JWT lifecycle, /auth/me + permissions
  services/api_service.dart    get / getList / post + friendlyError()
  screens/
    login_screen.dart  signup_screen.dart
    dashboard_shell.dart       sidebar nav + Overview
    ops_tools_screen.dart      the 5 tool launchers
    approval_queue_screen.dart the review queue
    history_screen.dart        audit trail
    action_detail.dart         full record for one action
    team_screen.dart           members + add-member form
test/                          40 tests — approve-gating rule, audit dialog rendering,
                               routing, login flow, error messages, labels
```

> **Note on fonts:** don't add `google_fonts` — its transitive `objective_c`
> native-assets build hook breaks on spaces in the Windows home path. Inter is
> vendored in `assets/fonts/` (four weights + OFL licence) instead.

New to Flutter? [docs.flutter.dev](https://docs.flutter.dev/) has the tutorials
and full API reference.
