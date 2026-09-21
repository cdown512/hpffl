# HPFFL Archives — Supabase backend

The site is still a static page on GitHub Pages. Nothing about the repo layout
changes; it just fetches its data from Supabase instead of reading a JS file.

## Files

- `schema.sql` — tables, views, and read-only row-level security. Run once.
- `seed.sql` — every row currently in `hpffl-data.js` and `photos.js`, as
  idempotent upserts. Re-running it updates rather than duplicating.
- `../site/hpffl-config.js` — your project URL and anon key. **Edit this.**
- `../site/hpffl-db.js` — the data layer. Reads the tables over Supabase's
  REST endpoint and sets `window.HPFFL_DATA` / `window.HPFFL_PHOTOS`, the same
  globals the app already used, then fires an `hpffl-data` event so the page
  re-renders. No SDK, no build step.

## Setup

1. Create a project at supabase.com (free tier is plenty — this is ~100KB).
2. SQL Editor → paste `schema.sql` → Run.
3. SQL Editor → paste `seed.sql` → Run.
4. Storage → New bucket named `photos`, **public**. Upload everything from
   `site/photos/` into it, keeping the filenames exactly as they are.
5. Settings → API → copy the Project URL and the `anon` public key into
   `site/hpffl-config.js`.
6. Commit and push. Load the site and check the console: no `[HPFFL]` error
   means it is reading from the database.

The anon key is publishable. Every table is `select`-only for `anon`, so the
worst anyone can do with it is read data the site already displays. Never put
the `service_role` key in this repo.

## Editing data

Supabase table editor. The tables the site reads today:

| Table | What it holds |
| --- | --- |
| `franchises` | One row per team. `owners`, `former_owners`, `former_names` are text arrays. |
| `league_seasons` | One row per year, including that year's champion. |
| `seasons` | One row per franchise per year — the W/L/T, PF/PA, playoff and prize totals. |
| `photos` + `photo_franchises` | Gallery photos and their team tags. |

Add a photo: upload the file to the `photos` bucket, insert a `photos` row
with that filename, then add one `photo_franchises` row per tagged team
(`sort = 0` is the Gallery's click target).

## Built for later (empty for now)

These tables exist so the weekly scrape and the pages you described have
somewhere to write. The site ignores them until we build those views.

| Table / view | For |
| --- | --- |
| `matchups` | Game-by-game results: year, week, both teams, both scores. |
| `v_franchise_weeks` | Each matchup as two team-shaped rows — the base for weekly records. |
| `v_head_to_head` | All-time head-to-head W/L/T and points between any two teams. |
| `weekly_prizes` | POTW / TOTW per week, with `share = 0.5` for shared weeks and an optional payout. |
| `transactions` | Free agent moves, waivers, trades, each with its fee. |
| `ledger_entries` + `v_franchise_ledger` | Dues, fees, payouts, and each franchise's balance per season. |

Once `matchups` is populated, `seasons` can be recomputed from it rather than
maintained by hand — that's the right moment to add a database function so the
weekly scrape only ever writes matchups.

Note on row limits: `hpffl-db.js` asks for `limit=5000`, but PostgREST caps
responses at 1000 rows by default (Settings → API → Max rows). Fine for the 382
season rows today; once `matchups` is populated it will need either a raised
max-rows or paged requests.

## For the weekly ESPN scrape

Have it write with the `service_role` key (keep it in the skill's environment,
never in this repo) and upsert:

- `matchups` on `(year, week, home_franchise_id, away_franchise_id)`
- `weekly_prizes` — insert one row per prize per week
- `transactions` — insert one row per move
- `seasons` on `(franchise_id, year)` for the rolled-up totals

Franchise ids are stable UUIDs and carried over from the old data file, so the
scrape can resolve a team by name once and cache the id.
