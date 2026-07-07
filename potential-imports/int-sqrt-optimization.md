# Potential Import: int_sqrt optimization

**Date:** 2026-07-07
**Source:** Danda420/kernel_xiaomi_sm8250 + kvsnr113/xiaomi_sm8250_kernel
**Commits:** `5d801d03da6d`, `e1e236a758dd`
**Status:** RESEARCHED — not yet imported

---

## What it does

Optimizes the integer square root function used in scheduler capacity calculations and other kernel math.

**Impact:** LOW-MEDIUM — int_sqrt is called in scheduler hot paths.

**Risk:** LOW — well-tested optimization, 3x faster on some architectures.

---

## Files affected

- `lib/int_sqrt.c`

---

## Backport feasibility

**HIGH** — pure math function, no API dependencies.

---

## PR strategy

Single PR: `import/int-sqrt-optimization`

One commit, one file change.
