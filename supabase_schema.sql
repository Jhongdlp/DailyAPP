-- Habilitar extensión pgvector para el Segundo Cerebro (Búsqueda Semántica)
create extension if not exists vector;

-- 1. TABLA DE PERFILES DE USUARIO
create table public.profiles (
  id uuid references auth.users on delete cascade primary key,
  updated_at timestamp with time zone,
  username text unique,
  full_name text,
  avatar_url text,
  constraint username_length check (char_length(username) >= 3)
);

-- Habilitar RLS en perfiles
alter table public.profiles enable row level security;

-- Políticas de seguridad para perfiles
create policy "Los usuarios pueden ver cualquier perfil" 
  on public.profiles for select 
  to authenticated 
  using (true);

create policy "Los usuarios pueden editar su propio perfil" 
  on public.profiles for update 
  to authenticated 
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- Trigger para crear perfil automáticamente cuando se registra un usuario
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, full_name, avatar_url)
  values (new.id, split_part(new.email, '@', 1), new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'avatar_url');
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- 2. TABLA DE HÁBITOS
create table public.habits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  name text not null,
  icon text not null default '✅', -- Emoji representativo del hábito
  color text not null default '#758BFD', -- Color hex para tarjeta/heatmap
  category text not null default 'general'
    check (category in ('health','mind','productivity','learning','social','general')),
  days_of_week integer[] not null default '{1,2,3,4,5,6,7}', -- Días activos/esperados (1=Lunes..7=Domingo)
  archived boolean not null default false,
  goal_value numeric, -- Meta numérica opcional (ej. 2 litros, 30 minutos, 8000 pasos)
  goal_unit text, -- Unidad de la meta (ej. 'L', 'min', 'pasos')
  reminder_hour integer check (reminder_hour between 0 and 23), -- Hora del recordatorio diario (null = sin recordatorio)
  reminder_minute integer check (reminder_minute between 0 and 59),
  reminder_times text[] not null default '{}'::text[], -- Múltiples horas de recordatorios en formato hh:mm
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Habilitar RLS en hábitos
alter table public.habits enable row level security;

-- Políticas de seguridad para hábitos
create policy "Usuarios pueden ver sus propios hábitos"
  on public.habits for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden insertar sus propios hábitos"
  on public.habits for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden actualizar sus propios hábitos"
  on public.habits for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden eliminar sus propios hábitos"
  on public.habits for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- 2.1 LOGS DE HÁBITOS (una fila por día completado, ahora soporta meta numérica con progress_value)
create table public.habit_logs (
  id uuid primary key default gen_random_uuid(),
  habit_id uuid references public.habits on delete cascade not null,
  user_id uuid references auth.users on delete cascade not null,
  completed_on date not null,
  progress_value numeric not null default 0,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  unique (habit_id, completed_on)
);

create index habit_logs_habit_idx on public.habit_logs (habit_id, completed_on desc);

alter table public.habit_logs enable row level security;

create policy "Usuarios pueden ver sus propios logs de hábitos"
  on public.habit_logs for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden crear sus propios logs de hábitos"
  on public.habit_logs for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden eliminar sus propios logs de hábitos"
  on public.habit_logs for delete
  to authenticated
  using ((select auth.uid()) = user_id);


-- 2.5 TABLA DE BÓVEDAS DE NOTAS (estilo Obsidian Vault)
create table if not exists public.note_vaults (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  name text not null,
  icon text not null default '📁',
  color text not null default '#758BFD',
  description text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.note_vaults enable row level security;

create policy "Usuarios pueden ver sus propias bóvedas"
  on public.note_vaults for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden crear sus propias bóvedas"
  on public.note_vaults for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden actualizar sus propias bóvedas"
  on public.note_vaults for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden eliminar sus propias bóvedas"
  on public.note_vaults for delete to authenticated
  using ((select auth.uid()) = user_id);


-- 3. TABLA DE NOTAS (SEGUNDO CEREBRO)
create table public.notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  vault_id uuid references public.note_vaults on delete set null, -- Bóveda a la que pertenece (null = sin clasificar)
  title text not null,
  content text not null,
  linked_note_ids uuid[] default '{}'::uuid[] not null,
  embedding vector(1024), -- Vector para búsqueda semántica (bge-m3, 1024 dims)
  priority integer not null default 1 check (priority between 0 and 3), -- 0=baja, 1=normal, 2=alta, 3=urgente
  remind_at timestamptz, -- Recordatorio por notificación (null = sin recordatorio)
  self_destruct boolean not null default false, -- La nota se elimina sola cuando el recordatorio pasa
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Habilitar RLS en notas
alter table public.notes enable row level security;

-- Políticas de seguridad para notas
create policy "Usuarios pueden ver sus propias notas"
  on public.notes for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden crear sus propias notas"
  on public.notes for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden actualizar sus propias notas"
  on public.notes for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden eliminar sus propias notas"
  on public.notes for delete
  to authenticated
  using ((select auth.uid()) = user_id);


-- 4. TABLA DE ALARMAS
create table public.alarms (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  enabled boolean default true not null,
  hour integer not null,
  minute integer not null,
  target_object text not null,
  label text not null default 'Alarma',
  days_of_week integer[] not null default '{1,2,3,4,5,6,7}',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Habilitar RLS en alarmas
alter table public.alarms enable row level security;

-- Políticas de seguridad para alarmas
create policy "Usuarios pueden ver sus propias alarmas"
  on public.alarms for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden crear sus propias alarmas"
  on public.alarms for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden actualizar sus propias alarmas"
  on public.alarms for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden eliminar sus propias alarmas"
  on public.alarms for delete
  to authenticated
  using ((select auth.uid()) = user_id);


-- 5. TABLA DE LOGS DE ALARMAS
create table if not exists public.alarm_logs (
  id uuid primary key default gen_random_uuid(),
  alarm_id uuid references public.alarms on delete cascade not null,
  user_id uuid references auth.users on delete cascade not null,
  triggered_at timestamptz not null default now(),
  dismissed_at timestamptz,
  validated boolean not null default false,
  attempts integer not null default 0
);

alter table public.alarm_logs enable row level security;

create policy "Usuarios pueden ver sus propios logs de alarmas"
  on public.alarm_logs for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden crear sus propios logs de alarmas"
  on public.alarm_logs for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

-- MIGRACIÓN para bases de datos existentes (ejecutar en Supabase SQL editor):
-- alter table public.alarms add column if not exists label text not null default 'Alarma';
-- alter table public.alarms add column if not exists days_of_week integer[] not null default '{1,2,3,4,5,6,7}';
-- alter table public.notes add column if not exists priority integer not null default 1;
-- alter table public.notes add column if not exists remind_at timestamptz;
-- alter table public.notes add column if not exists self_destruct boolean not null default false;
--
-- MIGRACIÓN BÓVEDAS DE NOTAS (ejecutar si ya tienes la tabla notes):
-- create table if not exists public.note_vaults (
--   id uuid primary key default gen_random_uuid(),
--   user_id uuid references auth.users on delete cascade not null,
--   name text not null,
--   icon text not null default '📁',
--   color text not null default '#758BFD',
--   description text,
--   created_at timestamp with time zone default timezone('utc'::text, now()) not null
-- );
-- alter table public.note_vaults enable row level security;
-- create policy "Usuarios pueden ver sus propias bóvedas" on public.note_vaults for select to authenticated using ((select auth.uid()) = user_id);
-- create policy "Usuarios pueden crear sus propias bóvedas" on public.note_vaults for insert to authenticated with check ((select auth.uid()) = user_id);
-- create policy "Usuarios pueden actualizar sus propias bóvedas" on public.note_vaults for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
-- create policy "Usuarios pueden eliminar sus propias bóvedas" on public.note_vaults for delete to authenticated using ((select auth.uid()) = user_id);
-- alter table public.notes add column if not exists vault_id uuid references public.note_vaults on delete set null;

-- MIGRACIÓN de Hábitos (rediseño con racha/heatmap/categorías — ejecutar en orden):
-- alter table public.habits add column if not exists icon text not null default '✅';
-- alter table public.habits add column if not exists color text not null default '#758BFD';
-- alter table public.habits add column if not exists category text not null default 'general'
--   check (category in ('health','mind','productivity','learning','social','general'));
-- alter table public.habits add column if not exists days_of_week integer[] not null default '{1,2,3,4,5,6,7}';
-- alter table public.habits add column if not exists archived boolean not null default false;
-- alter table public.habits add column if not exists reminder_times text[] not null default '{}'::text[];
--
-- create table if not exists public.habit_logs (
--   id uuid primary key default gen_random_uuid(),
--   habit_id uuid references public.habits on delete cascade not null,
--   user_id uuid references auth.users on delete cascade not null,
--   completed_on date not null,
--   progress_value numeric not null default 0,
--   created_at timestamp with time zone default timezone('utc'::text, now()) not null,
--   unique (habit_id, completed_on)
-- );
-- alter table public.habit_logs add column if not exists progress_value numeric not null default 0;
-- create index if not exists habit_logs_habit_idx on public.habit_logs (habit_id, completed_on desc);
-- alter table public.habit_logs enable row level security;
-- create policy "Usuarios pueden ver sus propios logs de hábitos"
--   on public.habit_logs for select to authenticated using ((select auth.uid()) = user_id);
-- create policy "Usuarios pueden crear sus propios logs de hábitos"
--   on public.habit_logs for insert to authenticated with check ((select auth.uid()) = user_id);
-- create policy "Usuarios pueden eliminar sus propios logs de hábitos"
--   on public.habit_logs for delete to authenticated using ((select auth.uid()) = user_id);
--
-- -- Solo si la columna completed_dates todavía existe en tu base:
-- insert into public.habit_logs (habit_id, user_id, completed_on)
-- select h.id, h.user_id, d::date
-- from public.habits h, unnest(h.completed_dates) as d
-- on conflict (habit_id, completed_on) do nothing;
--
-- alter table public.habits drop column if exists completed_dates;

-- 6. MÁQUINA DE CONOCIMIENTO — BÚSQUEDA Y CONEXIONES SEMÁNTICAS (pgvector, bge-m3 1024 dims)

-- Índice HNSW para búsquedas por coseno rápidas
create index if not exists notes_embedding_hnsw_idx
  on public.notes using hnsw (embedding vector_cosine_ops);

-- 6.1 Búsqueda semántica: dado el embedding de una consulta, notas más cercanas
create or replace function match_notes (
  query_embedding vector(1024),
  match_threshold float,
  match_count int,
  exclude_id uuid default null
)
returns table (
  id uuid,
  title text,
  content text,
  similarity float
)
language sql stable
security invoker
set search_path = public
as $$
  select n.id, n.title, n.content,
         1 - (n.embedding <=> query_embedding) as similarity
  from notes n
  where n.user_id = auth.uid()
    and n.embedding is not null
    and (exclude_id is null or n.id <> exclude_id)
    and 1 - (n.embedding <=> query_embedding) > match_threshold
  order by n.embedding <=> query_embedding
  limit match_count;
$$;

-- 6.2 Notas relacionadas a una nota usando su embedding ya almacenado
create or replace function related_notes (
  p_note_id uuid,
  match_threshold float,
  match_count int
)
returns table (id uuid, title text, similarity float)
language sql stable
security invoker
set search_path = public
as $$
  select n.id, n.title, 1 - (n.embedding <=> src.embedding) as similarity
  from notes n,
       (select embedding from notes where id = p_note_id and user_id = auth.uid()) src
  where n.user_id = auth.uid()
    and n.id <> p_note_id
    and n.embedding is not null
    and src.embedding is not null
    and 1 - (n.embedding <=> src.embedding) > match_threshold
  order by n.embedding <=> src.embedding
  limit match_count;
$$;

-- 6.3 Pares de notas similares (aristas semánticas del grafo de conocimiento)
create or replace function semantic_edges (
  match_threshold float,
  max_pairs int
)
returns table (source_id uuid, target_id uuid, similarity float)
language sql stable
security invoker
set search_path = public
as $$
  select a.id, b.id, 1 - (a.embedding <=> b.embedding) as similarity
  from notes a
  join notes b on a.user_id = b.user_id and a.id < b.id
  where a.user_id = auth.uid()
    and a.embedding is not null
    and b.embedding is not null
    and 1 - (a.embedding <=> b.embedding) > match_threshold
  order by similarity desc
  limit max_pairs;
$$;


-- =====================================================
-- 7. GESTOR DE DINERO (Finanzas Personales — moneda USD)
-- =====================================================

-- 7.1 CUENTAS (efectivo, banco, tarjeta, ahorros)
create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  name text not null,
  type text not null default 'cash' check (type in ('cash', 'bank', 'card', 'savings')),
  initial_balance numeric(14,2) not null default 0,
  currency text not null default 'USD',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.accounts enable row level security;

create policy "Usuarios pueden ver sus propias cuentas"
  on public.accounts for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden insertar sus propias cuentas"
  on public.accounts for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden actualizar sus propias cuentas"
  on public.accounts for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden eliminar sus propias cuentas"
  on public.accounts for delete to authenticated
  using ((select auth.uid()) = user_id);

-- 7.2 TRANSACCIONES (ingresos, gastos y transferencias entre cuentas)
create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  account_id uuid references public.accounts on delete cascade not null,
  -- Para transferencias: account_id = origen, transfer_account_id = destino
  transfer_account_id uuid references public.accounts on delete cascade,
  type text not null check (type in ('income', 'expense', 'transfer')),
  amount numeric(14,2) not null check (amount > 0),
  category text not null default 'other',
  description text not null default '',
  occurred_at date not null default current_date,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create index transactions_user_date_idx on public.transactions (user_id, occurred_at desc);

alter table public.transactions enable row level security;

create policy "Usuarios pueden ver sus propias transacciones"
  on public.transactions for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden insertar sus propias transacciones"
  on public.transactions for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden actualizar sus propias transacciones"
  on public.transactions for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden eliminar sus propias transacciones"
  on public.transactions for delete to authenticated
  using ((select auth.uid()) = user_id);


-- =====================================================
-- 8. BÓVEDA SEGURA (Contraseñas y Secretos Encriptados)
-- =====================================================

create table if not exists public.vault_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  
  -- Campos encriptados (almacenados en formato Base64/Hex)
  title_encrypted text not null,       -- Título cifrado (ej. "Mi Cuenta de Banco")
  description_encrypted text,         -- Descripción/Notas cifradas
  payload_encrypted text not null,     -- JSON cifrado con campos dinámicos (username, password, urls, etc.)
  
  -- Configuración de Encriptación
  iv text not null,                   -- Vector de Inicialización único para este registro
  
  -- Metadatos no sensibles
  category text not null default 'password' 
    check (category in ('password', 'note', 'card', 'bank', 'identity', 'other')),
  
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Habilitar RLS
alter table public.vault_items enable row level security;

-- Políticas de RLS
create policy "Usuarios pueden ver sus propios elementos de la bóveda"
  on public.vault_items for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden insertar sus propios elementos de la bóveda"
  on public.vault_items for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden actualizar sus propios elementos de la bóveda"
  on public.vault_items for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden eliminar sus propios elementos de la bóveda"
  on public.vault_items for delete
  to authenticated
  using ((select auth.uid()) = user_id);


-- 8.1 RESPALDO DE CLAVE DE BÓVEDA (recuperación ante reinstalación/cambio de equipo)
-- Guarda el mismo blob que ya se guarda en Secure Storage local: la Vault Key
-- envuelta (cifrada) con la clave derivada de la contraseña maestra (KEK), más
-- la sal y el hash de verificación. Nunca contiene la contraseña ni la Vault
-- Key en texto plano, así que sigue siendo "conocimiento cero" para Supabase.
create table if not exists public.vault_recovery (
  user_id uuid primary key references auth.users on delete cascade,
  salt text not null,
  vault_key_encrypted text not null,
  vault_key_iv text not null,
  master_password_hash text not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.vault_recovery enable row level security;

create policy "Usuarios pueden ver su propio respaldo de bóveda"
  on public.vault_recovery for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden crear su propio respaldo de bóveda"
  on public.vault_recovery for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden actualizar su propio respaldo de bóveda"
  on public.vault_recovery for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden eliminar su propio respaldo de bóveda"
  on public.vault_recovery for delete
  to authenticated
  using ((select auth.uid()) = user_id);



-- 9. CHAT: conversaciones persistentes con memoria
-- El copiloto financiero mantiene el historial completo de cada conversación y
-- el usuario puede tener varias conversaciones en paralelo.
create table if not exists public.chat_conversations (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users on delete cascade not null,
  title text not null default 'Nueva conversación',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create index if not exists chat_conversations_user_updated_idx
  on public.chat_conversations (user_id, updated_at desc);

alter table public.chat_conversations enable row level security;

create policy "Usuarios pueden ver sus propias conversaciones"
  on public.chat_conversations for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden crear sus propias conversaciones"
  on public.chat_conversations for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden actualizar sus propias conversaciones"
  on public.chat_conversations for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden eliminar sus propias conversaciones"
  on public.chat_conversations for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists public.chat_messages (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users on delete cascade not null,
  conversation_id uuid references public.chat_conversations on delete cascade not null,
  role text not null check (role in ('user', 'assistant')),
  content text not null default '',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create index if not exists chat_messages_conversation_idx
  on public.chat_messages (conversation_id, created_at);

alter table public.chat_messages enable row level security;

create policy "Usuarios pueden ver sus propios mensajes"
  on public.chat_messages for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Usuarios pueden crear sus propios mensajes"
  on public.chat_messages for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden actualizar sus propios mensajes"
  on public.chat_messages for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Usuarios pueden eliminar sus propios mensajes"
  on public.chat_messages for delete
  to authenticated
  using ((select auth.uid()) = user_id);
