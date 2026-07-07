# Potential Import: zram LZ4 dictionary compression

**Date:** 2026-07-07
**Source:** GustavoMends/kernel_xiaomi_alioth
**Commit:** `b932abea`
**Status:** RESEARCHED — not yet imported

---

## What it does

Optimizes LZ4 compression in zram by using a template stream for dictionary compression. Significant compression performance improvement.

**Impact:** MEDIUM — faster zram compression/decompression, better memory utilization.

**Risk:** LOW — well-tested upstream pattern.

---

## Files affected

- `drivers/block/zram/zram_drv.c`

---

## Backport feasibility

**HIGH** — single file change, uses existing LZ4 API.

---

## PR strategy

Single PR: `import/zram-lz4-dictionary`

One commit, one file change.
