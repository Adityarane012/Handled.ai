<div align="center">

# 📱 handled_app

**The Flutter client for [handled.ai](../README.md)** — one codebase, real
installable app for desktop and web.

![Flutter](https://img.shields.io/badge/Flutter-3.4+-02569B?logo=flutter&logoColor=white)
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
| `/` | Overview | Live pending-approvals count + quick links |
| `/ops` | Ops Tools | One card per tool, grouped by autonomy bucket; triggers all 5 endpoints + inventory-doc upload |
| `/approvals` | Approval Queue | Pending drafts; PO cards render **blank** quantity/amount fields and keep Approve disabled until a human fills them |

Routing is `go_router` with an auth redirect; state is `provider`.

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
  theme.dart                   dark theme; _fontFamily switch to enable Inter
  providers/auth_provider.dart JWT lifecycle, /auth/me check
  services/api_service.dart    get / getList / post helpers
  screens/
    login_screen.dart  signup_screen.dart
    dashboard_shell.dart       sidebar nav + Overview
    ops_tools_screen.dart      the 5 tool launchers
    approval_queue_screen.dart the review queue
test/
  widget_test.dart             smoke test: unauthenticated launch → login
```

> **Note on fonts:** `google_fonts` was removed — its transitive `objective_c`
> native-assets build hook breaks on spaces in the Windows home path. The theme
> uses the bundled default font; flip `_fontFamily` in `theme.dart` to `'Inter'`
> after vendoring `Inter-*.ttf` into `assets/fonts/`.

New to Flutter? [docs.flutter.dev](https://docs.flutter.dev/) has the tutorials
and full API reference.
