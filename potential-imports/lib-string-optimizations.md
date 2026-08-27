# Potential Import: lib/string optimizations (memcpy/memset/memmove/memcmp)

**Date:** 2026-07-07
**Source:** Danda420/kernel_xiaomi_sm8250 + kvsnr113/xiaomi_sm8250_kernel
**Commits:** `6c4c9c5fda7d`, `41342b8bfe06`, `b814c3406d77`, `2efb0e7ddeb6`
**Status:** RESEARCHED — not yet imported

---

## What it does

Optimizes generic (non-arch-specific) memcpy, memset, memmove, and memcmp with word-at-a-time copy, aligned writes, and improved comparison logic.

**Benchmark (RISC-V):**
- memcpy: 75 → 114 MB/s (+52%)
- memset: 140 → 241 MB/s (+72%)

**Impact:** MEDIUM — these are the generic fallbacks; ARM64 has arch-specific versions. But some code paths use the generic versions.

**Risk:** LOW — well-tested upstream-quality optimizations.

---

## Files affected

- `lib/string.c` (memcpy, memset, memmove, memcmp)

---

## Backport feasibility

**HIGH** — generic C code, no API dependencies. Drop-in replacement.

---

## PR strategy

Single PR: `import/lib-string-optimizations`

One commit, one file change. Bundle all 4 optimizations together.
