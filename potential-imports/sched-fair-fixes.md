# Potential Import: sched/fair fixes (vruntime overflow, wakeup_preempt, delayed dequeue)

**Date:** 2026-07-07
**Source:** kvsnr113/xiaomi_sm8250_kernel_e404 + GustavoMends/kernel_xiaomi_aliooth
**Commits:** `a45d4dc13bcd`, `1bb660a657da`, `62bfaf0066cf`, `b75142eb5ea5`
**Status:** RESEARCHED — not yet imported

---

## What it does

Collection of scheduler correctness fixes:
1. Fix overflow in vruntime_eligible() using __int128 (`a45d4dc13bcd`)
2. Fix wakeup_preempt_fair() crash when cfs_rq empty (`1bb660a657da`)
3. Fix wakeup_preempt_fair() vs delayed dequeue (`62bfaf0066cf`)
4. Avoid overflow in enqueue_entity() (`b75142eb5ea5`)

**Impact:** HIGH — fixes kernel panics and scheduler bugs.

**Risk:** MEDIUM — scheduler changes need thorough testing.

---

## Files affected

- `kernel/sched/fair.c`

---

## Backport feasibility

**MEDIUM** — scheduler code has evolved; need to verify our WALT tree compatibility.

---

## PR strategy

Single PR: `import/sched-fair-fixes`

One commit per fix for easy revert.
