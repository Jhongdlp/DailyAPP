-- =====================================================================
-- Ejercicio → registro de sesiones + fotos de progreso con IA
-- =====================================================================
-- Aditiva: no borra ni reescribe nada existente. Se puede correr varias
-- veces sin efecto (todo lleva IF NOT EXISTS / DO $$ ... $$).

-- ---------------------------------------------------------------------
-- 1. exercise_logs: una fila por sesión (por ahora solo 'running', pero
--    activity_type + extra jsonb dejan espacio a más tipos sin migrar).
-- ---------------------------------------------------------------------
create table if not exists public.exercise_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  -- Liga la sesión con el hábito de ejercicio. ON DELETE SET NULL: borrar el
  -- hábito no debe borrar el histórico de lo que sí corriste ese día.
  habit_id uuid references public.habits(id) on delete set null,
  activity_type text not null default 'running',
  logged_date date not null,
  distance_km numeric,
  duration_minutes numeric,
  pace_min_per_km numeric,
  notes text,
  extra jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists exercise_logs_user_date_idx on public.exercise_logs (user_id, logged_date desc);

alter table public.exercise_logs enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'exercise_logs' and policyname = 'exercise_logs_select_own') then
    create policy exercise_logs_select_own on public.exercise_logs for select to authenticated using ((select auth.uid()) = user_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'exercise_logs' and policyname = 'exercise_logs_insert_own') then
    create policy exercise_logs_insert_own on public.exercise_logs for insert to authenticated with check ((select auth.uid()) = user_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'exercise_logs' and policyname = 'exercise_logs_update_own') then
    create policy exercise_logs_update_own on public.exercise_logs for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'exercise_logs' and policyname = 'exercise_logs_delete_own') then
    create policy exercise_logs_delete_own on public.exercise_logs for delete to authenticated using ((select auth.uid()) = user_id);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. exercise_photos: 0..5 filas por (user, día). Se insertan durante la
--    captura y luego se actualizan cuando la IA termina de clasificar
--    (por eso necesitan policy de UPDATE, misma lección que habit_logs).
-- ---------------------------------------------------------------------
create table if not exists public.exercise_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  -- Nullable: la foto puede capturarse antes de que exista la sesión
  -- (flujo desde el check del hábito: cámara primero, formulario después).
  exercise_log_id uuid references public.exercise_logs(id) on delete set null,
  logged_date date not null,
  -- Ruta en el bucket 'exercise-photos': "{user_id}/{yyyy-mm-dd}/{uuid}.jpg"
  storage_path text not null,
  classification text,
  classification_status text not null default 'pending',
  taken_at timestamptz not null default timezone('utc'::text, now()),
  created_at timestamptz not null default timezone('utc'::text, now())
);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'exercise_photos_classification_check'
  ) then
    alter table public.exercise_photos
      add constraint exercise_photos_classification_check
      check (classification is null or classification in ('cara', 'cuerpo', 'unknown'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'exercise_photos_classification_status_check'
  ) then
    alter table public.exercise_photos
      add constraint exercise_photos_classification_status_check
      check (classification_status in ('pending', 'classifying', 'done', 'failed'));
  end if;
end $$;

create index if not exists exercise_photos_user_date_idx on public.exercise_photos (user_id, logged_date desc);

alter table public.exercise_photos enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'exercise_photos' and policyname = 'exercise_photos_select_own') then
    create policy exercise_photos_select_own on public.exercise_photos for select to authenticated using ((select auth.uid()) = user_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'exercise_photos' and policyname = 'exercise_photos_insert_own') then
    create policy exercise_photos_insert_own on public.exercise_photos for insert to authenticated with check ((select auth.uid()) = user_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'exercise_photos' and policyname = 'exercise_photos_update_own') then
    create policy exercise_photos_update_own on public.exercise_photos for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'exercise_photos' and policyname = 'exercise_photos_delete_own') then
    create policy exercise_photos_delete_own on public.exercise_photos for delete to authenticated using ((select auth.uid()) = user_id);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. Bucket privado para las fotos (primer uso de Supabase Storage en el
--    proyecto). Nunca público: son fotos del físico del usuario, el
--    acceso debe ir siempre por URL firmada.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('exercise-photos', 'exercise-photos', false)
on conflict (id) do nothing;

-- Ruta: {user_id}/{yyyy-mm-dd}/{uuid}.jpg → storage.foldername(name)[1] es el user_id.
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'objects' and policyname = 'exercise_photos_storage_select_own') then
    create policy exercise_photos_storage_select_own on storage.objects for select to authenticated
      using (bucket_id = 'exercise-photos' and (select auth.uid())::text = (storage.foldername(name))[1]);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'objects' and policyname = 'exercise_photos_storage_insert_own') then
    create policy exercise_photos_storage_insert_own on storage.objects for insert to authenticated
      with check (bucket_id = 'exercise-photos' and (select auth.uid())::text = (storage.foldername(name))[1]);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'objects' and policyname = 'exercise_photos_storage_delete_own') then
    create policy exercise_photos_storage_delete_own on storage.objects for delete to authenticated
      using (bucket_id = 'exercise-photos' and (select auth.uid())::text = (storage.foldername(name))[1]);
  end if;
end $$;
