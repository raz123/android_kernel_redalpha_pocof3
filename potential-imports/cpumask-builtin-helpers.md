# Potential Import: cpumask builtin helpers

**Date:** 2026-07-06
**Source:** KosminorKernel-Alioth (Sultan Alsawaf)
**Commit:** `4be57bba3973564d2a98e78ca241d8c53cae1bb3`
**Status:** RESEARCHED — not yet imported

---

## What it does

Optimizes cpumask operations when NR_CPUS fits in a single `unsigned long`. On SM8250, NR_CPUS=8 which fits in one long. This means cpumask bit operations can use single-instruction bitwise ops instead of loop-based fallbacks.

**Impact:** Measurable scheduler hot-path wins — cpumask operations execute millions of times per second during task placement and migration.

**Risk:** LOW — well-known optimization, widely tested.

---

## Files affected

- `include/linux/cpumask.h` — add optimized inline helpers
- `kernel/smp.c` — use optimized helpers
- `lib/cpumask.c` — use optimized helpers

---

## Backport feasibility

**MEDIUM** — requires adapting to 4.19 cpumask.h layout. The Kosminor version targets a newer kernel with different include ordering. Need to identify the exact insertion points in our tree.

---

## How to apply

1. Read the Kosminor commit diff
2. Identify equivalent locations in our 4.19 `include/linux/cpumask.h`
3. Add the optimized inline helpers
4. Verify with `grep -n "cpumask_test_and_set\|cpumask_test_and_clear" include/linux/cpumask.h`

---

## PR strategy

Single PR: `import/cpumask-builtin-helpers`

One commit, one file change. Easy to revert if regressions found.
