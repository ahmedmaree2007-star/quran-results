-- انسخ هذا الملف كاملًا في Supabase > SQL Editor ثم Run
-- تحذير: يمسح جدول المتسابقين ويعيد إنشاءه (استخدمه قبل إدخال بيانات حقيقية)

drop table if exists contestants cascade;
create table contestants (
  id uuid primary key default gen_random_uuid(),
  number text unique not null,
  name text not null,
  branch text not null check (branch in ('القرآن كامل','نصف القرآن','ربع القرآن','خمسة أجزاء')),
  hifz numeric not null check (hifz >= 0 and hifz <= 70),
  tajweed numeric not null check (tajweed >= 0 and tajweed <= 30),
  score numeric generated always as (hifz + tajweed) stored,
  created_at timestamptz default now()
);

create table if not exists settings (
  id int primary key default 1 check (id = 1),
  pass_score numeric not null default 50,
  show_top boolean not null default false,
  top_count int not null default 3
);
insert into settings (id) values (1) on conflict do nothing;
update settings set pass_score = 50 where id = 1;

alter table contestants enable row level security;
alter table settings enable row level security;
drop policy if exists "admin all contestants" on contestants;
drop policy if exists "admin all settings" on settings;
create policy "admin all contestants" on contestants for all to authenticated using (true) with check (true);
create policy "admin all settings" on settings for all to authenticated using (true) with check (true);

create or replace function get_result(p_number text)
returns json language sql security definer set search_path = public as $$
  with r as (
    select c.*, rank() over (partition by branch order by score desc) as rk
    from contestants c
  )
  select json_build_object(
    'number', r.number, 'name', r.name, 'branch', r.branch,
    'hifz', r.hifz, 'tajweed', r.tajweed,
    'score', r.score, 'rank', r.rk,
    'passed', r.score >= (select pass_score from settings where id = 1)
  )
  from r where r.number = trim(p_number);
$$;

create or replace function get_top()
returns table (branch text, rk bigint, name text, score numeric)
language sql security definer set search_path = public as $$
  select t.branch, t.rk, t.name, t.score from (
    select c.branch, c.name, c.score,
           rank() over (partition by c.branch order by c.score desc) as rk
    from contestants c
  ) t, settings s
  where s.id = 1 and s.show_top and t.rk <= s.top_count
  order by t.branch, t.rk;
$$;

revoke all on function get_result(text), get_top() from public;
grant execute on function get_result(text), get_top() to anon, authenticated;
