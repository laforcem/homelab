# Karakeep Migration Design

**Date:** 2026-05-01
**Status:** Approved

## Overview

Migrate from Raindrop.io to a self-hosted Karakeep instance on vm101. Karakeep provides AI-powered auto-tagging via a local Ollama instance, full-page archiving (deferred until RAID storage is ready), and native iOS/Android apps. The organization system uses six coarse lists and a semantic tag vocabulary, optimized for reference lookup via search.

---

## 1. Organization System

### Lists

| List | Purpose |
|---|---|
| `Software` | GitHub repos, open source projects, proprietary software worth endorsing |
| `Tools & Services` | Web tools, utilities, SaaS |
| `Articles` | Curated long-form reads |
| `Videos` | YouTube and other video saves |
| `Reference` | Wikis, legal resources, databases, documentation |
| `Personal` | Gaming, theology, fitness, music, hobbies — everything else |

Philosophy: lists are coarse and durable. Tags do the fine-grained work. Collections should never require a hard filing decision.

### Seed Tag Vocabulary

**Domain tags:** `gaming` · `theology` · `fitness` · `music` · `self-hosting` · `android` · `linux` · `privacy` · `copyright` · `ai` · `networking` · `bookbinding`

**Type tags:** `tool` · `wiki` · `documentation` · `legal`

These seed the vocabulary. Ollama will extend it automatically as new bookmarks are saved. New tags should be lowercase; avoid near-duplicates (e.g. `linux` and `linux-tools` coexisting).

Each bookmark should receive **2–5 tags**. Fewer than 2 is too narrow for useful search; more than 5 dilutes the vocabulary into noise. This range is encoded in the Ollama custom prompt.

Date-based tags (`8/23/2025`, `9/25/2025`) from Raindrop are retired. Those research sessions are retagged semantically:
- `8/23/2025` batch (DMCA/copyright law) → `copyright` + `legal`
- `9/25/2025` batch (Bible rebinding services) → `bookbinding`

---

## 2. Infrastructure

### Deployment

Karakeep and Ollama run as Docker containers in **vm101**, added to the existing Docker Compose stack alongside Immich, Plex, Invidious, etc. Karakeep is proxied through the existing Caddy instance.

**vm101 RAM context:**
- 11.5GB allocated, ~3.8GB in active use, 7.4GB available
- Adding Ollama (`qwen3:4b` at ~2.5GB) brings active use to ~6.3GB — comfortable headroom for Immich ML spikes
- Recommended: trim vm101 allocation from 11.5GB to 8GB in Proxmox to free ~3.5GB back to the host

### Ollama

- **Model:** `qwen3:4b`
- **Why:** Current-generation Qwen3 architecture punches above its weight on instruction following; rivals older 7B models at 2.5GB RAM. Sufficient for tag generation.
- **Keep-alive:** `OLLAMA_KEEP_ALIVE=5m` — model unloads after 5 minutes idle, freeing RAM for other workloads. Set to `0` if Immich ML conflicts arise.
- **Run as:** Standalone Docker container (not a Karakeep sidecar) so other future services can share it.

### Karakeep AI Configuration

In Karakeep → Settings → AI → Custom Prompt, prepend `/no_think` to the prompt.

**This is critical.** Qwen3 defaults to "thinking mode" (silent chain-of-thought reasoning) before responding. For a tag generation task this adds 10–30 seconds of latency with zero quality benefit. `/no_think` disables it and gets direct, fast responses.

### Archiving

Archiving is **disabled at initial deployment** to conserve disk space on the 500GB HDD.

When the 6TB RAID array is operational, enable Karakeep's built-in archiving — it will backfill existing bookmarks.

In the meantime, install the [SingleFile browser extension](https://github.com/gildas-lormeau/SingleFile) and configure it to push full HTML archives directly to Karakeep for pages worth preserving on demand. This provides Wayback Machine-style single-file HTML snapshots.

---

## 3. Raindrop Cleanup (Pre-Migration)

Before exporting from Raindrop, reorganize in place so the import lands cleanly.

### Step 1 — Rename/restructure collections to match new list names

Current Raindrop collections map to new lists as follows:

| Current Raindrop Collection | New List |
|---|---|
| Open Source Repos | Software |
| Favorite Articles | Articles |
| YouTube | Videos |
| Self-hosting | Software (tag: `self-hosting`) |
| AI projects | Software |
| Product Research | Reference |
| Theology Resources | Personal |
| Fitness | Personal |
| Games / Pokemon Emerald Legacy | Personal |

### Step 2 — File the 63 Unsorted items

Key groups in Unsorted:

| Group | Destination | Tags |
|---|---|---|
| Retrogaming resources (hacks.guide, Vimm's Lair, redump.org, etc.) | Personal | `gaming` |
| DMCA/copyright law research (18 items, tagged `8/23/2025`) | Reference | `copyright` `legal` |
| Bible rebinding services (7 items, tagged `9/25/2025`) | Personal | `bookbinding` |
| Pokemon Emerald Legacy docs | Personal | `gaming` |
| Video game music (VGMdb, Sitting on Clouds) | Personal | `music` |
| Web tools (SimplePDF, CamelCamelCamel) | Tools & Services | `tool` |
| Fitness (Hybrid Calisthenics) | Personal | `fitness` |
| Consumer rights wiki | Reference | `wiki` |
| Remaining miscellaneous (music discovery, photography, random tools) | Personal or Tools & Services | per item |

### Step 3 — Retire date tags

Replace `8/23/2025` → `copyright` + `legal`
Replace `9/25/2025` → `bookbinding`

---

## 4. Migration Steps

1. Complete Raindrop cleanup (Step 1–3 above) via Raindrop MCP
2. Export Raindrop as Netscape HTML
3. Deploy Karakeep + Ollama via Docker Compose on vm101
4. Configure Karakeep: point at Ollama, set `/no_think` custom prompt, disable archiving
5. Pull `qwen3:4b`: `ollama pull qwen3:4b`
6. Import Netscape HTML into Karakeep
7. Trigger bulk AI re-tagging; review and prune noise
8. Install Karakeep browser extension on desktop browsers
9. Install Karakeep mobile app on iPhone 14 and Pixel 4a
10. Install SingleFile extension on desktop browsers, configure to push to Karakeep
11. Trim vm101 RAM allocation from 11.5GB to 8GB in Proxmox

---

## 5. Future: Oracle VPS Ollama (mrgutsy)

Tracked separately in [homelab issue #25](https://github.com/laforcem/homelab/issues/25).

Add a standalone Ollama instance to the Oracle A1 VPS running `qwen3:14b` (~9GB RAM), exposed via Caddy with bearer token auth. For personal/general-purpose LLM use — not for Karakeep tagging. Karakeep uses the local vm101 instance to avoid internet dependency.
