# Digest diario de noticias

Genera y publica el digest que consume la sección **Noticias** de la app.

Corre por cron en el servidor propio (el mismo que hospeda Ollama). No usa
librerías externas: basta `python3` y `curl` no hace falta.

## Por qué aquí y no en un agente en la nube

El primer montaje usaba una routine (agente programado de Claude Code). Falló
dos días seguidos: el sandbox aplica una política de egress que bloquea el
dominio de Supabase, y el proxy corta con `CONNECT tunnel failed, response 403`
antes de que la petición salga. No es configurable desde el código, así que la
tarea se movió a un servidor sin esa restricción.

## Flujo

```
cron 6:00  →  news_digest.py
                ├─ descarga feeds RSS/Atom + Hacker News
                ├─ deduplica por título normalizado
                ├─ qwen3:14b selecciona, traduce y redacta  (Ollama local)
                ├─ valida y descarta lo que no cuadre
                └─ POST → RPC publish_news_digest  (Supabase)

app Flutter  →  select de news_digests
```

La app solo lee. La única vía de escritura es el RPC, que exige token y valida
el payload otra vez del lado del servidor.

## Instalación

```bash
# 1. Copiar el script
scp tools/news_digest/news_digest.py usuario@servidor:~/news_digest.py

# 2. Crear la configuración a partir del ejemplo
scp tools/news_digest/news_digest.env.example usuario@servidor:~/news_digest.env
ssh usuario@servidor
nano ~/news_digest.env          # rellenar NEWS_PUBLISH_TOKEN y SUPABASE_ANON_KEY
chmod 600 ~/news_digest.env

# 3. Probar sin publicar
set -a; . ~/news_digest.env; set +a
NEWS_DRY_RUN=1 python3 ~/news_digest.py

# 4. Programar a las 6:00 hora de Guayaquil (11:00 UTC)
crontab -e
```

Línea de cron:

```cron
0 11 * * * set -a; . $HOME/news_digest.env; set +a; /usr/bin/python3 $HOME/news_digest.py >> $HOME/news_digest.log 2>&1
```

Si el servidor ya está en `America/Guayaquil`, usar `0 6 * * *`. Comprobar con
`date` antes de decidir.

## Verificar

```bash
tail -20 ~/news_digest.log
```

Una ejecución correcta termina con:

```
[...] Publicado: {'ok': True, 'date': '2026-08-01', 'count': 9}
```

Cualquier fallo empieza por `FALLO:` y devuelve código de salida 1, así que el
log distingue "no corrió" de "corrió y falló" — que es justo lo que no se podía
saber con la routine.

## Ajustes

| Variable | Para qué |
|---|---|
| `OLLAMA_MODEL` | Modelo que redacta. `qwen3:14b` por defecto. |
| `NEWS_MAX_CANDIDATES` | Titulares que ve el modelo (50). |
| `NEWS_DRY_RUN=1` | Imprime el digest y no publica. |

**Al cambiar de modelo, revisar la prosa de un dry-run antes de dejarlo en el
cron.** `gemma4:26b` parecía la opción obvia por tamaño y degeneraba tokens en
español ("peligroaloso", "de la de la") con lotes largos.

Las fuentes y sus ventanas temporales están en la constante `FEEDS`. Los medios
usan la ventana general (30h); arXiv y los blogs oficiales tienen ventanas más
largas porque publican a tirones y si no la categoría `papers` sale vacía casi
todos los días.
