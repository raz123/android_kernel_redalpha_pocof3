# Potential Import: vmscan critical process throttling

**Date:** 2026-07-07
**Source:** EmanuelCN/kernel_xiaomi_sm8250 + kvsnr113/xiaomi_sm8250_kernel_e404
**Commits:** `3c20b9e9d19d`, `0e36eb2f56f0`
**Status:** RESEARCHED — not yet imported

---

## What it does

Prevents critical Android processes (display composer, system_server) from being throttled during memory pressure. Uses OOM scoring to identify critical binder-spawned tasks.

**Impact:** MEDIUM — reduces UI jank during heavy memory pressure.

**Risk:** LOW — targeted fix, not fundamental change. Based on Android common kernel patch.

---

## Files affected

- `mm/vmscan.c`

---

## Backport feasibility

**HIGH** — single file change, uses existing OOM scoring infrastructure.

---

## PR strategy

Single PR: `import/vmscan-critical-process`

One commit, one file change.
