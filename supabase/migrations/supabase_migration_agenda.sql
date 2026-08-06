-- =====================================================================
-- Agenda → sistema de planeación nocturna
-- =====================================================================
-- Aditiva: no borra ni reescribe nada existente. Se puede correr varias
-- veces sin efecto (todo lleva IF NOT EXISTS / DO $$ ... $$).

-- ---------------------------------------------------------------------
-- 1. Columnas nuevas en tasks
-- ---------------------------------------------------------------------
alter table public.tasks
  -- Liga un bloque de agenda con un hábito. ON DELETE SET NULL: borrar el
  -- hábito no debe borrar el histórico de lo que sí planeaste ese día.
  add column if not exists habit_id uuid references public.habits(id) on delete set null,
  add column if not exists block_type text not null default 'task',
  -- Parte de la intención de implementación: "haré X a las HH:MM EN [lugar]".
  add column if not exists location text,
  -- Uno de los 3 grandes del día (regla de Ivy Lee).
  add column if not exists is_mit boolean not null default false,
  -- Cuándo se planeó el bloque, no cuándo ocurre. Sirve para distinguir lo
  -- planeado la noche anterior de lo improvisado sobre la marcha.
  add column if not exists planned_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'tasks_block_type_check'
  ) then
    alter table public.tasks
      add constraint tasks_block_type_check
      check (block_type in ('task', 'habit', 'deep', 'admin', 'rest', 'personal'));
  end if;
end $$;

create index if not exists tasks_habit_idx on public.tasks (habit_id, due_date);

-- ---------------------------------------------------------------------
-- 2. day_plans: una fila por día planeado
-- ---------------------------------------------------------------------
create table if not exists public.day_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  -- El día que se PLANEA (normalmente mañana), no la noche en que se planeó.
  plan_date date not null,
  intention text,
  reflection text,
  mood smallint check (mood between 1 and 5),
  ritual_completed boolean not null default false,
  planned_at timestamptz not null default timezone('utc'::text, now()),
  created_at timestamptz not null default timezone('utc'::text, now()),
  unique (user_id, plan_date)
);

create index if not exists day_plans_user_date_idx on public.day_plans (user_id, plan_date desc);

alter table public.day_plans enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'day_plans' and policyname = 'day_plans_select_own') then
    create policy day_plans_select_own on public.day_plans for select using (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'day_plans' and policyname = 'day_plans_insert_own') then
    create policy day_plans_insert_own on public.day_plans for insert with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'day_plans' and policyname = 'day_plans_update_own') then
    create policy day_plans_update_own on public.day_plans for update using (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'day_plans' and policyname = 'day_plans_delete_own') then
    create policy day_plans_delete_own on public.day_plans for delete using (auth.uid() = user_id);
  end if;
end $$;
