-- HPFFL Archives — Supabase schema
-- Run this once in the Supabase SQL editor, then run seed.sql.
-- Read-only for the public (anon) role; all writes go through the Supabase
-- table editor / service role. Per-franchise logins can be added later by
-- granting insert/update policies keyed on auth.uid() — see the note at the end.

create extension if not exists "pgcrypto";

-- ───────────────────────── reference ─────────────────────────

create table if not exists eras (
  id    text primary key,          -- 'paper' | 'fanstar' | 'espn'
  label text not null,
  sort  int  not null default 0
);

insert into eras (id, label, sort) values
  ('paper',   'Paper era',   1),
  ('fanstar', 'Fanstar era', 2),
  ('espn',    'ESPN era',    3),
  ('strike',  'Strike year', 0)
on conflict (id) do nothing;

-- ───────────────────────── core ─────────────────────────

create table if not exists franchises (
  id             uuid primary key default gen_random_uuid(),
  name           text not null unique,
  active         boolean not null default true,
  first_season   int,
  last_season    int,                       -- null while active
  league_seasons int,                       -- seasons the franchise was in the league
  era            text references eras(id),  -- era the franchise debuted in
  owners         text[] not null default '{}',
  former_owners  text[] not null default '{}',
  former_names   text[] not null default '{}',
  notes          text,
  created_at     timestamptz not null default now()
);

create table if not exists league_seasons (
  year               int primary key,
  era                text references eras(id),
  teams              int,
  games              int,
  champ_franchise_id uuid references franchises(id) on delete set null,
  note               text
);

-- One row per franchise per season: the season totals the site renders today.
create table if not exists seasons (
  id           uuid primary key default gen_random_uuid(),
  franchise_id uuid not null references franchises(id) on delete cascade,
  year         int  not null references league_seasons(year) on delete restrict,
  era          text references eras(id),
  w            int not null default 0,
  l            int not null default 0,
  t            int not null default 0,
  pw           int not null default 0,      -- playoff wins
  pg           int not null default 0,      -- playoff games
  champ        boolean not null default false,
  conf         boolean not null default false,  -- conference title
  div          boolean not null default false,  -- division title
  dw           int not null default 0,      -- division record
  dl           int not null default 0,
  dt           int not null default 0,
  pf           numeric(8,1),                -- regular season points for / against
  pa           numeric(8,1),
  ppf          numeric(8,1),                -- playoff points for / against
  ppa          numeric(8,1),
  potw         numeric(5,1) not null default 0,  -- Player of the Week (halves = shared)
  totw         numeric(5,1) not null default 0,  -- Team of the Week
  mlw          int not null default 0,      -- Miss Lilly Bowl won / attempted
  mla          int not null default 0,
  cbl          int not null default 0,      -- Chihuahua Bowl lost / attempted
  cba          int not null default 0,
  updated_at   timestamptz not null default now(),
  unique (franchise_id, year)
);

create index if not exists seasons_year_idx on seasons (year);
create index if not exists seasons_franchise_idx on seasons (franchise_id);

-- ───────────────────────── weekly detail ─────────────────────────
-- Not used by the site yet. These are the tables the weekly ESPN scrape
-- writes into; season totals above can then be recomputed from them.

create table if not exists matchups (
  id                uuid primary key default gen_random_uuid(),
  year              int  not null references league_seasons(year) on delete cascade,
  week              int  not null,
  kind              text not null default 'regular'
                      check (kind in ('regular','playoff','consolation','bowl')),
  home_franchise_id uuid references franchises(id) on delete set null,
  away_franchise_id uuid references franchises(id) on delete set null,
  home_points       numeric(6,2),
  away_points       numeric(6,2),
  note              text,
  created_at        timestamptz not null default now(),
  unique (year, week, home_franchise_id, away_franchise_id)
);

create index if not exists matchups_year_week_idx on matchups (year, week);

-- Every matchup as two franchise-shaped rows — the base for weekly records,
-- head-to-head and streaks.
create or replace view v_franchise_weeks as
  select m.id as matchup_id, m.year, m.week, m.kind,
         m.home_franchise_id as franchise_id, m.away_franchise_id as opponent_id,
         m.home_points as points, m.away_points as opp_points
    from matchups m
   where m.home_franchise_id is not null
  union all
  select m.id, m.year, m.week, m.kind,
         m.away_franchise_id, m.home_franchise_id,
         m.away_points, m.home_points
    from matchups m
   where m.away_franchise_id is not null;

create or replace view v_head_to_head as
  select franchise_id, opponent_id,
         count(*)                                                as games,
         count(*) filter (where points > opp_points)              as w,
         count(*) filter (where points < opp_points)              as l,
         count(*) filter (where points = opp_points)              as t,
         round(sum(points)::numeric, 1)                           as pf,
         round(sum(opp_points)::numeric, 1)                       as pa
    from v_franchise_weeks
   where points is not null and opp_points is not null
   group by franchise_id, opponent_id;

-- Weekly prize board (POTW / TOTW and anything else paid weekly).
create table if not exists weekly_prizes (
  id           uuid primary key default gen_random_uuid(),
  year         int  not null references league_seasons(year) on delete cascade,
  week         int,
  prize        text not null
                 check (prize in ('potw','totw','other')),
  franchise_id uuid references franchises(id) on delete set null,
  share        numeric(4,2) not null default 1,   -- 0.5 when a week is shared
  amount       numeric(8,2),                      -- payout, if tracked
  player       text,                              -- for POTW
  note         text,
  created_at   timestamptz not null default now()
);

create index if not exists weekly_prizes_year_idx on weekly_prizes (year, week);

-- ───────────────────────── league accounting ─────────────────────────

create table if not exists transactions (
  id           uuid primary key default gen_random_uuid(),
  year         int  not null references league_seasons(year) on delete cascade,
  week         int,
  occurred_on  date,
  franchise_id uuid references franchises(id) on delete set null,
  kind         text not null default 'free_agent'
                 check (kind in ('free_agent','waiver','trade','drop','other')),
  player_added text,
  player_drop  text,
  fee          numeric(8,2) not null default 0,
  note         text,
  created_at   timestamptz not null default now()
);

create index if not exists transactions_year_idx on transactions (year, franchise_id);

-- Dues, fees, payouts — one row per money movement.
create table if not exists ledger_entries (
  id           uuid primary key default gen_random_uuid(),
  year         int  not null references league_seasons(year) on delete cascade,
  franchise_id uuid references franchises(id) on delete set null,
  kind         text not null
                 check (kind in ('dues','fa_fee','prize_payout','payout','adjustment','other')),
  amount       numeric(9,2) not null,      -- positive = owed to the league
  occurred_on  date,
  note         text,
  created_at   timestamptz not null default now()
);

create or replace view v_franchise_ledger as
  select year, franchise_id,
         round(sum(amount) filter (where amount > 0), 2) as charges,
         round(-sum(amount) filter (where amount < 0), 2) as credits,
         round(sum(amount), 2)                            as balance
    from ledger_entries
   group by year, franchise_id;

-- ───────────────────────── photos ─────────────────────────

create table if not exists photos (
  id           uuid primary key default gen_random_uuid(),
  file         text not null,               -- original filename
  storage_path text,                        -- path inside the storage bucket; defaults to file
  year         int,                          -- null for undated
  caption      text,
  sort         int not null default 0,
  created_at   timestamptz not null default now(),
  unique (file)
);

create table if not exists photo_franchises (
  photo_id     uuid not null references photos(id) on delete cascade,
  franchise_id uuid not null references franchises(id) on delete cascade,
  sort         int not null default 0,       -- first tag is the Gallery click target
  primary key (photo_id, franchise_id)
);

-- ───────────────────────── derived ─────────────────────────

create or replace view v_champions as
  select ls.year, f.id as franchise_id, f.name as franchise
    from league_seasons ls
    join franchises f on f.id = ls.champ_franchise_id
   order by ls.year;

-- ───────────────────────── row level security ─────────────────────────
-- Public read, no public write. The anon key in the site can only select.

do $$
declare t text;
begin
  foreach t in array array[
    'eras','franchises','league_seasons','seasons','matchups','weekly_prizes',
    'transactions','ledger_entries','photos','photo_franchises'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "public read" on %I', t);
    execute format('create policy "public read" on %I for select to anon, authenticated using (true)', t);
  end loop;
end $$;

-- Later, for per-franchise logins: add a franchise_members(user_id, franchise_id)
-- table and write policies like
--   create policy "own franchise write" on seasons for all to authenticated
--     using (exists (select 1 from franchise_members m
--                     where m.user_id = auth.uid() and m.franchise_id = seasons.franchise_id));
