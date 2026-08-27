# Potential Import: zram fixes (NULL deref, disksize restoration, race conditions)

**Date:** 2026-07-07
**Source:** Danda420/kernel_xiaomi_sm8250 + kvsnr113/xiaomi_sm8250_kernel_e404
**Commits:** `b90b475c21c5`, `f20ff6cfaed9`, `0225a3697b9c`, `425038a582cd`
**Status:** RESEARCHED — not yet imported

---

## What it does

Collection of zram bug fixes:
1. Fix NULL pointer dereference on OOM (`b90b475c21c5`)
2. Restore userspace disksize configuration (`f20ff6cfaed9`)
3. Fix slot write race condition (`0225a3697b9c`)
4. Fix race condition in slot write (`425038a582cd`)

**Impact:** HIGH — fixes crashes and data corruption in zram.

**Risk:** LOW — each fix is small and well-scoped.

---

## Files affected

- `drivers/block/zram/zram_drv.c`

---

## Backport feasibility

**HIGH** — single file, each fix is independent.

---

## PR strategy

Single PR: `import/zram-bugfixes`

One commit per fix for easy revert, or bundle if they're closely related.
