#!/usr/bin/env python3
"""Publica el digest diario de noticias de IA y tecnología.

Pensado para correr por cron en el servidor propio (el mismo que hospeda
Ollama). Recorre feeds públicos, deja que un modelo local seleccione, traduzca
y redacte, y publica el resultado llamando al RPC `publish_news_digest` de
Supabase.

Se eligió el servidor propio y no un agente en la nube porque el sandbox de
las routines aplica una política de egress que bloquea el dominio de Supabase
(CONNECT 403 en el proxy), y eso no es configurable desde el código.

Solo usa la librería estándar: el servidor no necesita `pip install` nada.

Configuración por variables de entorno (ver news_digest.env.example):
  NEWS_PUBLISH_TOKEN  (obligatoria)  token del RPC
  SUPABASE_URL        base del proyecto Supabase
  OLLAMA_URL          base de Ollama
  OLLAMA_MODEL        modelo a usar
  NEWS_DRY_RUN=1      imprime el digest y NO publica
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

SUPABASE_URL = os.environ.get(
    "SUPABASE_URL", "https://vhtorhsyqszoaeshlnjs.supabase.co"
).rstrip("/")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", "")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
# qwen3:14b y no gemma4:26b pese a ser más pequeño: el 26b degenera tokens en
# español ("peligroaloso", "de la de la") en lotes largos. Si se cambia el
# modelo, revisar la prosa de un dry-run antes de dejarlo en el cron.
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen3:14b")
PUBLISH_TOKEN = os.environ.get("NEWS_PUBLISH_TOKEN", "")
DRY_RUN = os.environ.get("NEWS_DRY_RUN") == "1"

# Ventana de recogida. Son 30h y no 24 a propósito: el cron corre a hora fija y
# una noticia publicada justo antes del corte de ayer se perdería para siempre.
# El solapamiento se paga con algún repetido, que el modelo descarta.
WINDOW_HOURS = 30

# Máximo de titulares que se le pasan al modelo. Un lote mayor no mejora la
# selección y sí desborda el contexto de los modelos locales.
MAX_CANDIDATES = int(os.environ.get("NEWS_MAX_CANDIDATES", "50"))

VALID_CATEGORIES = ("ia", "dev", "startups", "papers")

# (nombre, url, ventana en horas). La ventana por feed existe porque los
# medios publican a diario pero arXiv y los blogs oficiales van a tirones: con
# 30h para todos, las categorías `papers` y los anuncios de laboratorio salían
# vacías casi cada día.
FEEDS = [
    ("TechCrunch", "https://techcrunch.com/category/artificial-intelligence/feed/", None),
    ("The Verge", "https://www.theverge.com/rss/index.xml", None),
    ("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", None),
    ("OpenAI", "https://openai.com/blog/rss.xml", 96),
    ("Google DeepMind", "https://deepmind.google/blog/rss.xml", 96),
    ("Simon Willison", "https://simonwillison.net/atom/everything/", None),
    # https obligatorio: por http, export.arxiv.org devuelve un cuerpo vacío.
    ("arXiv cs.AI", "https://export.arxiv.org/api/query?search_query=cat:cs.AI"
                    "&sortBy=submittedDate&sortOrder=descending&max_results=25", 72),
    ("arXiv cs.LG", "https://export.arxiv.org/api/query?search_query=cat:cs.LG"
                    "&sortBy=submittedDate&sortOrder=descending&max_results=25", 72),
]

HN_URL = ("https://hn.algolia.com/api/v1/search_by_date"
          "?tags=story&numericFilters=points%3E120,created_at_i%3E{since}")

USER_AGENT = "SistemDaily-NewsDigest/1.0"


def log(msg: str) -> None:
    print(f"[{datetime.now(timezone.utc):%Y-%m-%d %H:%M:%S}] {msg}", flush=True)


def fetch(url: str, timeout: int = 25) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def parse_date(raw: str | None) -> datetime | None:
    if not raw:
        return None
    raw = raw.strip()
    # RFC 822 (RSS) y ISO 8601 (Atom) conviven entre feeds; se prueban ambos en
    # vez de asumir uno.
    try:
        dt = parsedate_to_datetime(raw)
        if dt is not None:
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        pass
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def strip_tags(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", text or "")).strip()


def parse_feed(source: str, xml_bytes: bytes, cutoff: datetime) -> list[dict]:
    """Extrae entradas recientes de un feed RSS o Atom."""
    items: list[dict] = []
    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError as exc:
        log(f"  ! {source}: XML inválido ({exc})")
        return items

    ns = {"atom": "http://www.w3.org/2005/Atom"}

    # RSS 2.0
    for node in root.iter("item"):
        published = parse_date(
            (node.findtext("pubDate") or node.findtext("{http://purl.org/dc/elements/1.1/}date"))
        )
        if published and published < cutoff:
            continue
        items.append({
            "source": source,
            "title": strip_tags(node.findtext("title") or ""),
            "url": (node.findtext("link") or "").strip(),
            "summary": strip_tags(node.findtext("description") or "")[:400],
            "published": published.isoformat() if published else None,
        })

    # Atom
    for node in root.iter("{http://www.w3.org/2005/Atom}entry"):
        published = parse_date(
            node.findtext("atom:published", namespaces=ns)
            or node.findtext("atom:updated", namespaces=ns)
        )
        if published and published < cutoff:
            continue
        link = ""
        for link_node in node.findall("atom:link", namespaces=ns):
            if link_node.get("rel") in (None, "alternate"):
                link = link_node.get("href", "")
                break
        items.append({
            "source": source,
            "title": strip_tags(node.findtext("atom:title", namespaces=ns) or ""),
            "url": link.strip(),
            "summary": strip_tags(
                node.findtext("atom:summary", namespaces=ns)
                or node.findtext("atom:content", namespaces=ns)
                or ""
            )[:400],
            "published": published.isoformat() if published else None,
        })

    return [i for i in items if i["title"] and i["url"]]


def fetch_hackernews(cutoff: datetime) -> list[dict]:
    url = HN_URL.format(since=int(cutoff.timestamp()))
    try:
        data = json.loads(fetch(url))
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as exc:
        log(f"  ! Hacker News: {exc}")
        return []
    items = []
    for hit in data.get("hits", []):
        link = hit.get("url") or f"https://news.ycombinator.com/item?id={hit.get('objectID')}"
        items.append({
            "source": "Hacker News",
            "title": strip_tags(hit.get("title") or ""),
            "url": link,
            "summary": f"{hit.get('points', 0)} puntos en Hacker News.",
            "published": hit.get("created_at"),
        })
    return [i for i in items if i["title"] and i["url"]]


def normalize_title(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", title.lower()).strip()


def collect(now: datetime, cutoff: datetime) -> list[dict]:
    seen: set[str] = set()
    collected: list[dict] = []

    for source, url, window in FEEDS:
        feed_cutoff = cutoff if window is None else now - timedelta(hours=window)
        try:
            raw = fetch(url)
        except (urllib.error.URLError, TimeoutError) as exc:
            # Un feed caído no puede tumbar el digest completo.
            log(f"  ! {source}: {exc}")
            continue
        found = parse_feed(source, raw, feed_cutoff)
        log(f"  · {source}: {len(found)}")
        collected.extend(found)

    hn = fetch_hackernews(cutoff)
    log(f"  · Hacker News: {len(hn)}")
    collected.extend(hn)

    unique = []
    for item in collected:
        key = normalize_title(item["title"])
        if not key or key in seen:
            continue
        seen.add(key)
        unique.append(item)

    # Los más recientes primero: si hay que recortar, se recorta lo viejo.
    unique.sort(key=lambda i: i["published"] or "", reverse=True)
    return unique[:MAX_CANDIDATES]


PROMPT = """Eres el editor de "Sistem Daily", un periódico personal diario sobre inteligencia artificial y tecnología, escrito en español para alguien que construye software con IA.

Abajo tienes los titulares recogidos hoy de varias fuentes. Selecciona entre 6 y 10 que de verdad importen y redacta el digest.

Criterios:
- Prefiere una noticia sustancial a tres triviales. Si solo hay cinco cosas que importan, devuelve cinco.
- Si varios titulares cubren el mismo hecho, quédate con uno solo (el de la fuente más primaria).
- Descarta publicidad, listicles, opinión sin noticia y contenido promocional.
- Reparte: no llenes el digest con una sola categoría. Si en la lista hay algún paper de arXiv o alguna noticia de financiación o adquisición que merezca la pena, incluye al menos uno de cada. Si no lo hay, no fuerces ninguno.
- Traduce los titulares al español. No dejes títulos en inglés.
- Cada "summary" son 2 o 3 frases que digan qué pasó y por qué importa. No repitas el titular con otras palabras.
- "relevance" es un entero 0-10: 8-10 si cambia cómo se construye software con IA; 5-7 si es relevante pero no urgente; 2-4 si es una curiosidad.
- "category" debe ser exactamente una de: ia, dev, startups, papers.
- "id" es el NÚMERO del titular en la lista de abajo. No escribas URLs: el enlace lo resuelve el sistema a partir del número.
- "editorial" es un párrafo de 2 a 4 frases sobre qué es lo importante del día y qué hilo conecta las noticias.

Responde SOLO con un objeto JSON con esta forma, sin texto alrededor:
{"editorial": "...", "items": [{"id": 12, "title": "...", "summary": "...", "category": "ia", "relevance": 8}]}

TITULARES DE HOY:
"""


def build_candidate_list(items: list[dict]) -> str:
    lines = []
    for idx, item in enumerate(items, 1):
        lines.append(
            f'{idx}. [{item["source"]}] {item["title"]}\n'
            f'   url: {item["url"]}\n'
            f'   extracto: {item["summary"][:220]}'
        )
    return "\n".join(lines)


def ask_ollama(candidates: list[dict]) -> dict:
    payload = {
        "model": OLLAMA_MODEL,
        "stream": False,
        # `format: json` obliga a Ollama a emitir JSON sintácticamente válido.
        # No garantiza el esquema, por eso igual se valida después.
        "format": "json",
        "options": {"temperature": 0.4, "num_ctx": 32768},
        "messages": [
            {"role": "user", "content": PROMPT + build_candidate_list(candidates)}
        ],
    }
    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/chat",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(req, timeout=600) as resp:
        body = json.loads(resp.read())
    content = body.get("message", {}).get("content", "")
    if not content:
        raise RuntimeError("Ollama devolvió una respuesta vacía")
    return json.loads(content)


def validate(digest: dict, candidates: list[dict], today: str) -> dict:
    """Normaliza y filtra la salida del modelo.

    Un modelo local se equivoca más que uno frontera: devuelve la relevancia
    como texto, inventa categorías o deja el resumen vacío. Se corrige lo
    corregible y se descarta lo demás, en vez de confiar y publicar basura.

    La URL y la fuente NO salen del modelo: se resuelven por el número de
    titular. Antes se le pedía la URL y se inventaba unas cuantas cada día.
    """
    clean_items = []
    for raw in digest.get("items", []):
        if not isinstance(raw, dict):
            continue

        title = str(raw.get("title", "")).strip()
        try:
            index = int(raw.get("id"))
        except (TypeError, ValueError):
            log(f"  ! descartada (id no numérico): {title[:60]!r}")
            continue
        if not 1 <= index <= len(candidates):
            log(f"  ! descartada (id {index} fuera de rango): {title[:60]!r}")
            continue

        summary = str(raw.get("summary", "")).strip()
        if not title or len(summary) < 40:
            log(f"  ! descartada (sin título o resumen demasiado corto): {title[:60]!r}")
            continue

        category = str(raw.get("category", "")).strip().lower()
        if category not in VALID_CATEGORIES:
            category = "ia"

        try:
            relevance = int(float(raw.get("relevance", 5)))
        except (TypeError, ValueError):
            relevance = 5

        origin = candidates[index - 1]
        clean_items.append({
            "title": title,
            "summary": summary,
            "source": origin["source"],
            "url": origin["url"],
            "category": category,
            "relevance": max(0, min(10, relevance)),
        })

    # Deduplicado por si el modelo repitió una noticia con dos titulares.
    deduped, seen = [], set()
    for item in clean_items:
        if item["url"] in seen:
            continue
        seen.add(item["url"])
        deduped.append(item)

    deduped.sort(key=lambda i: i["relevance"], reverse=True)
    return {
        "date": today,
        "editorial": str(digest.get("editorial", "")).strip(),
        "items": deduped[:10],
    }


def publish(digest: dict) -> dict:
    body = json.dumps({"payload": digest, "token": PUBLISH_TOKEN}).encode("utf-8")
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/rpc/publish_news_digest",
        data=body,
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"Supabase respondió {exc.code}: {detail}") from exc


def main() -> int:
    if not PUBLISH_TOKEN and not DRY_RUN:
        log("FALLO: falta NEWS_PUBLISH_TOKEN")
        return 1
    if not SUPABASE_ANON_KEY and not DRY_RUN:
        log("FALLO: falta SUPABASE_ANON_KEY")
        return 1

    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(hours=WINDOW_HOURS)
    today = now.strftime("%Y-%m-%d")

    log(f"Recogiendo titulares desde {cutoff:%Y-%m-%d %H:%M} UTC")
    candidates = collect(now, cutoff)
    log(f"{len(candidates)} candidatos únicos")
    if len(candidates) < 5:
        log("FALLO: muy pocos candidatos, no se publica nada")
        return 1

    log(f"Redactando con {OLLAMA_MODEL}…")
    try:
        raw_digest = ask_ollama(candidates)
    except (urllib.error.URLError, json.JSONDecodeError, RuntimeError, TimeoutError) as exc:
        log(f"FALLO en Ollama: {exc}")
        return 1

    digest = validate(raw_digest, candidates, today)
    log(f"{len(digest['items'])} noticias tras validar")
    if not digest["items"]:
        log("FALLO: no quedó ninguna noticia válida, no se publica nada")
        return 1

    if DRY_RUN:
        print(json.dumps(digest, ensure_ascii=False, indent=2))
        log("DRY RUN: no se publicó")
        return 0

    try:
        result = publish(digest)
    except (urllib.error.URLError, RuntimeError, TimeoutError) as exc:
        log(f"FALLO al publicar: {exc}")
        return 1

    log(f"Publicado: {result}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
