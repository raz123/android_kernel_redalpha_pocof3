# Potential Import: RCU boot-only expedited

**Date:** 2026-07-07
**Source:** KopsourcesORG/KosminorKernel-Alioth
**Commit:** `7f1475d6`
**Status:** RESEARCHED — not yet imported

---

## What it does

Restricts RCU expedited grace periods to boot time only. Post-boot, uses normal grace periods which are more power-efficient (no IPI spam).

**Impact:** MEDIUM — reduces CPU wakeups and IPI traffic during normal operation.

**Risk:** LOW — well-established upstream pattern.

---

## Files affected

- `kernel/rcu/tree.c` (or similar RCU file)

---

## Backport feasibility

**HIGH** — single config change or small code modification.

---

## PR strategy

Single PR: `import/rcu-boot-only-expedited`

One commit, one file change.
