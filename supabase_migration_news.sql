-- Digest diario de noticias.
--
-- Lo publica una routine (agente programado en la nube de Claude Code), que no
-- tiene sesión de usuario ni service key. Escribe a través de
-- publish_news_digest(), que valida un token dedicado guardado como hash en
-- private_config. Ese token solo habilita publicar digests: no lee ni escribe
-- ninguna otra tabla, así que filtrarlo no expone hábitos, notas ni finanzas.
--
-- El token en claro NO vive en este archivo. Se genera con
-- `openssl rand -hex 24`, se guarda en la configuración de la routine y su
-- hash se inserta con la sentencia marcada más abajo.

create table if not exists public.news_digests (
  id uuid primary key default gen_random_uuid(),
  -- Una fila por día: la routine puede reintentar el mismo día sin duplicar.
  digest_date date not null unique,
  editorial text not null default '',
  items jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists news_digests_date_desc
  on public.news_digests (digest_date desc);

alter table public.news_digests enable row level security;

-- El digest es idéntico para cualquier sesión (no hay datos por usuario), así
-- que la lectura es abierta a autenticados. No se crea policy de
-- INSERT/UPDATE/DELETE: la única vía de escritura es la función de abajo.
drop policy if exists "news_digests_read" on public.news_digests;
create policy "news_digests_read"
  on public.news_digests for select
  to authenticated
  using (true);

-- Almacén del token. Sin policies y con los grants revocados, PostgREST no
-- puede leerlo: solo lo alcanza la función SECURITY DEFINER.
create table if not exists public.private_config (
  key text primary key,
  value text not null
);

alter table public.private_config enable row level security;
revoke all on public.private_config from anon, authenticated;

-- Sustituir <TOKEN> por el token generado. Se guarda el hash, no el token:
-- quien lograse leer la tabla no obtendría la credencial.
-- insert into public.private_config (key, value)
-- values ('news_publish_token_sha256',
--         encode(digest('<TOKEN>', 'sha256'), 'hex'))
-- on conflict (key) do update set value = excluded.value;

create or replace function public.publish_news_digest(payload jsonb, token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  expected text;
  incoming text;
  d date;
  item jsonb;
begin
  select value into expected
    from public.private_config
   where key = 'news_publish_token_sha256';

  if expected is null or token is null then
    raise exception 'token no configurado' using errcode = '28000';
  end if;

  incoming := encode(digest(token, 'sha256'), 'hex');

  -- Comparación en tiempo constante sobre los hashes: evita filtrar el token
  -- carácter a carácter por diferencias de latencia.
  if length(incoming) <> length(expected)
     or (select bool_or(substr(incoming, i, 1) <> substr(expected, i, 1))
           from generate_series(1, length(expected)) as g(i)) then
    raise exception 'token invalido' using errcode = '28000';
  end if;

  -- Validación de forma: es preferible rechazar un payload malformado aquí a
  -- que la app se encuentre con una fila que no puede parsear.
  begin
    d := (payload->>'date')::date;
  exception when others then
    raise exception 'campo date ausente o invalido' using errcode = '22007';
  end;

  if jsonb_typeof(payload->'items') is distinct from 'array'
     or jsonb_array_length(payload->'items') = 0 then
    raise exception 'items debe ser un array no vacio' using errcode = '22023';
  end if;

  for item in select * from jsonb_array_elements(payload->'items') loop
    if coalesce(item->>'title', '') = '' or coalesce(item->>'url', '') = '' then
      raise exception 'cada noticia necesita title y url' using errcode = '22023';
    end if;
    if coalesce(item->>'category', '') not in ('ia', 'dev', 'startups', 'papers') then
      raise exception 'category invalida: %', item->>'category' using errcode = '22023';
    end if;
  end loop;

  insert into public.news_digests (digest_date, editorial, items)
  values (d, coalesce(payload->>'editorial', ''), payload->'items')
  on conflict (digest_date) do update
    set editorial = excluded.editorial,
        items = excluded.items,
        updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'date', d,
    'count', jsonb_array_length(payload->'items')
  );
end;
$$;

-- La routine llama con la anon key, así que anon necesita EXECUTE. La función
-- es la frontera de seguridad, no el rol.
revoke all on function public.publish_news_digest(jsonb, text) from public;
grant execute on function public.publish_news_digest(jsonb, text) to anon, authenticated;
