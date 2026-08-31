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

**Deployment target: TBD.** No hosting provider is configured in this
repository yet — see `POS_IMPLEMENTATION_PLAN.md` §8 for the options under
consideration. Deployment steps will be documented here once a target is
chosen.
