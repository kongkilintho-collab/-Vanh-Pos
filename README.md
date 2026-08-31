# Beauty Clinic POS

A production-track POS for beauty clinics, spas, and salons. Flutter
(Material 3, web/desktop-first) on top of Supabase (Postgres + Auth + RLS).

See [POS_IMPLEMENTATION_PLAN.md](POS_IMPLEMENTATION_PLAN.md) for
architecture, database schema, RLS/permission strategy, and the day-by-day
build status — that document is kept current as each part lands, so it's
the source of truth, not this file.

## Running locally

1. Copy `env.example.json` to `env.json` and fill in your Supabase project
   URL and anon/publishable key (Supabase Dashboard → Settings → API).
   `env.json` is gitignored — never commit it.
2. Apply the database schema: paste `supabase/bootstrap_all.sql` into the
   Supabase Dashboard's SQL Editor and run it once (or use the Supabase
   CLI — see section 9 of the implementation plan).
3. Run:

   ```
   flutter pub get
   flutter run --dart-define-from-file=env.json -d chrome
   ```

## Quality gates

```
flutter analyze
flutter test
```

Both must pass before a change is considered done.

## Production build

Verified build command:

```
flutter build web --dart-define-from-file=env.json
```

This produces a static `build/web` artifact — no server-side rendering;
secrets are injected at build time via `--dart-define-from-file`, the same
mechanism used for `flutter run` above.

Required environment variables (set in `env.json`):

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

`env.json` is local and gitignored; `env.example.json` is the committed
template. Never commit `env.json` or any file containing these values.

## Cloudflare Pages deployment

**Deployment target: Cloudflare Pages**, Git-connected build (Cloudflare
builds and deploys directly from this repository on push — no local
artifact upload).

- **Output directory:** `build/web`
- **Flutter toolchain:** Cloudflare Pages' build image does not ship
  Flutter, so the build command clones the pinned Flutter SDK (3.44.1)
  as its first step, shallow and disposable — no Docker image, no
  repository config file, nothing committed.
- **Build command** (paste into the Cloudflare Pages project's *Build
  command* field):

  ```
  git clone https://github.com/flutter/flutter.git -b 3.44.1 --depth 1 _flutter && export PATH="$PWD/_flutter/bin:$PATH" && flutter config --enable-web && flutter pub get && flutter build web --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
  ```

- **Environment variables:** `SUPABASE_URL` and `SUPABASE_ANON_KEY` must
  be set as *build-time* environment variables in the Cloudflare Pages
  project settings (Settings → Environment variables) — not committed
  anywhere, and not read at runtime. Flutter web reads them via
  `String.fromEnvironment` (`lib/config/env.dart`), so they must be
  passed as `--dart-define` values at build time, which the build
  command above does directly from the shell environment Cloudflare
  injects — no generated `env.json` needed. Only the public anon key and
  project URL go here; never set `SUPABASE_SERVICE_ROLE_KEY` or any
  other privileged credential in this or any client-build context.
- **SPA fallback:** not required. The app uses `go_router` without
  `usePathUrlStrategy()`, so it runs under Flutter's default hash-based
  URL strategy (`/#/...`) — every route resolves through `index.html` at
  `/`, with routing handled entirely client-side after load.

This section documents the configuration; the actual Cloudflare project
creation, environment variable entry, and first deploy are owner actions
performed in the Cloudflare dashboard, not part of this repository.
