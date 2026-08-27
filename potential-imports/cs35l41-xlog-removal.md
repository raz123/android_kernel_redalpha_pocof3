# Potential Import: cs35l41 xlog removal

**Date:** 2026-07-07
**Source:** LineageOS/android_kernel_xiaomi_sm8250
**Commit:** `82ff61e0`
**Status:** RESEARCHED — not yet imported

---

## What it does

Removes Xiaomi proprietary telemetry (xlog) from the cs35l41 audio driver. Deletes `send_data_to_xlog.c/h` and updates Kbuild.

**Impact:** LOW — removes telemetry, no functional change.

**Risk:** LOW — code removal, well-scoped.

---

## Files affected

- `techpack/audio/asoc/codecs/cs35l41/send_data_to_xlog.c` (delete)
- `techpack/audio/asoc/codecs/cs35l41/send_data_to_xlog.h` (delete)
- `techpack/audio/asoc/codecs/cs35l41/Makefile` (update)

---

## Backport feasibility

**HIGH** — code removal, no API dependencies.

---

## PR strategy

Single PR: `import/cs35l41-xlog-removal`

One commit, three file changes.
