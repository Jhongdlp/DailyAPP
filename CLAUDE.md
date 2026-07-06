# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

The Flutter SDK is located at `/home/jhon/Documentos/TerminalAgent/sdk/flutter/bin/`. Use the full path:

```bash
# Run the app
/home/jhon/Documentos/TerminalAgent/sdk/flutter/bin/flutter run

# Analyze (lint)
/home/jhon/Documentos/TerminalAgent/sdk/flutter/bin/flutter analyze

# Run tests
/home/jhon/Documentos/TerminalAgent/sdk/flutter/bin/flutter test

# Run a single test file
/home/jhon/Documentos/TerminalAgent/sdk/flutter/bin/flutter test test/widget_test.dart

# Get dependencies
/home/jhon/Documentos/TerminalAgent/sdk/flutter/bin/flutter pub get
```

## Architecture

**SistemDaily** is a Flutter "Life OS" app — a personal second brain with habit tracking, interconnected notes, and anti-procrastination alarms. All AI processing is done locally via Ollama running on a remote server.

### External Services

| Service | Address | Purpose |
|---|---|---|
| Supabase | `https://vhtorhsyqszoaeshlnjs.supabase.co` | Auth, PostgreSQL, Storage |
| Ollama (AI) | `http://63.141.255.7:11434` | Local AI inference |

**Ollama models:**
- `qwen2.5-coder:14b` — text reasoning, chat copilot, note connections
- `qwen3-vl:8b` — vision model for alarm photo validation
- `bge-m3:latest` — embeddings for semantic note search (pgvector)

### State Management

Riverpod (`flutter_riverpod`) is used exclusively. The single global provider is `settingsProvider` (`lib/core/providers/settings_provider.dart`), a `NotifierProvider<SettingsNotifier, AppSettings>` that persists Supabase credentials and AI server config to `SharedPreferences`.

### Navigation / Screen Flow

`main.dart` bootstraps Supabase from saved settings, then routes to one of three entry points:
1. `SetupScreen` — if Supabase is not configured
2. `AuthScreen` — if configured but no active session
3. `DashboardScreen` — if authenticated

`DashboardScreen` hosts a bottom navigation bar with four tabs: Habits, Alarm, Notes, Chat.

### AI Client (`lib/core/network/local_ai_client.dart`)

`LocalAIClient` wraps Ollama's `/api/chat` endpoint and falls back automatically to an OpenAI-compatible endpoint (`/v1/chat/completions`) for servers like LM Studio or vLLM. Vision calls pass images as base64 in the `images` field (Ollama) or as `image_url` content blocks (OpenAI style).

### Theme (`lib/core/theme/bento_theme.dart`)

**Bento UI** — flat, modern, no gradients. Key design tokens:
- `BentoTheme.primaryDark` (`#27187E`) — primary color / text
- `BentoTheme.bgLight` (`#F7F7FF`) — scaffold background
- `BentoTheme.cardBg` (white) + `BentoTheme.borderMuted` (`#EAEBFF`) — card style
- Accent colors: `accentOrange`, `accentBlue`, `accentPurple`
- Font: **Outfit** (Google Fonts)

Reusable widgets: `BentoCard` (bordered container) and `BentoBackground` (scaffold wrapper with safe area).

### Database Schema

Defined in `supabase_schema.sql`. Tables: `profiles`, `habits`, `notes` (with `pgvector` embeddings), `alarms`. All tables use RLS with per-user row policies. A trigger auto-creates a profile on user signup.
