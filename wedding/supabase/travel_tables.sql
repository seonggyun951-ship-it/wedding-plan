-- 여행 탭 테이블 (웨딩앱 Supabase: wqahhqssawaxynqigwtr)
-- 기존 웨딩 테이블과 같은 방식으로 계정별로만 보인다 (auth.uid() = user_id).
-- 여행을 지우면 딸린 일정·장소·경비·준비물도 함께 지워진다.

create table if not exists trips (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid(),
  title       text not null,
  emoji       text default '✈️',
  origin_code text,            -- 출발 공항 (ICN)
  dest_code   text,            -- 도착 공항 (KIX)
  start_date  date not null,
  end_date    date not null,
  budget      numeric default 0,   -- 원화
  currency    text default 'KRW',  -- 현지 통화
  fx_rate     numeric,             -- 현지 통화 1단위 = 몇 원 (직접 입력)
  created_at  timestamptz default now()
);

create table if not exists trip_places (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid(),
  trip_id     uuid not null references trips(id) on delete cascade,
  name        text not null,
  category    text default 'spot', -- move / stay / food / spot
  address     text,
  lat         double precision,
  lng         double precision,
  place_id    text,                -- 구글 장소 ID
  map_url     text,
  memo        text,
  created_at  timestamptz default now()
);

create table if not exists trip_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid(),
  trip_id     uuid not null references trips(id) on delete cascade,
  day_date    date not null,
  start_time  time,
  end_time    time,
  title       text not null,
  category    text default 'spot',
  place_id    uuid references trip_places(id) on delete set null,
  memo        text,
  created_at  timestamptz default now()
);

create table if not exists trip_expenses (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid(),
  trip_id     uuid not null references trips(id) on delete cascade,
  spent_on    date,
  title       text not null,
  category    text default '기타',
  amount      numeric not null,    -- 입력한 통화 그대로
  currency    text not null,
  amount_krw  numeric not null,    -- 입력 시점 환율로 환산해 저장 (환율을 바꿔도 지난 지출은 그대로)
  created_at  timestamptz default now()
);

create table if not exists trip_packing (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid(),
  trip_id     uuid not null references trips(id) on delete cascade,
  grp         text default '기타',
  text        text not null,
  done        boolean default false,
  created_at  timestamptz default now()
);

create index if not exists trip_places_trip   on trip_places(trip_id);
create index if not exists trip_events_trip   on trip_events(trip_id, day_date);
create index if not exists trip_expenses_trip on trip_expenses(trip_id);
create index if not exists trip_packing_trip  on trip_packing(trip_id);

alter table trips          enable row level security;
alter table trip_places    enable row level security;
alter table trip_events    enable row level security;
alter table trip_expenses  enable row level security;
alter table trip_packing   enable row level security;

drop policy if exists "user own trips"         on trips;
drop policy if exists "user own trip_places"   on trip_places;
drop policy if exists "user own trip_events"   on trip_events;
drop policy if exists "user own trip_expenses" on trip_expenses;
drop policy if exists "user own trip_packing"  on trip_packing;

create policy "user own trips"         on trips         for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user own trip_places"   on trip_places   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user own trip_events"   on trip_events   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user own trip_expenses" on trip_expenses for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user own trip_packing"  on trip_packing  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
