# Potential Import: Power Efficient Workqueue Conversion

**Date:** 2026-07-07
**Source:** KopsourcesORG/KosminorKernel-Alioth
**Commits:** `5ababae6`, `4338103f`, `058bd643`, `c42fcd12`, `e88d10ae`
**Status:** RESEARCHED — not yet imported

---

## What it does

Converts multiple subsystem workqueues to use the system's power-efficient workqueue by default:
- GPU/DRM subsystem
- Block layer
- Power supply/charging
- Allows root control of wq_power_efficient toggle

**Impact:** MEDIUM — reduces CPU wakeups during idle, improving battery life.

**Risk:** LOW — well-established upstream pattern, each subsystem conversion is small.

---

## Files affected

- `drivers/gpu/drm/` (DRM workqueues)
- `block/blk-core.c` (block layer)
- `drivers/power/supply/` (charging)
- `kernel/workqueue.c` (root control)

---

## Backport feasibility

**MEDIUM** — each individual conversion is small, but the blanket conversion touches many files. Need to verify each subsystem's workqueue usage pattern.

---

## PR strategy

One PR per subsystem for easy revert:
- `import/wq-power-efficient-gpu`
- `import/wq-power-efficient-block`
- `import/wq-power-efficient-power`
