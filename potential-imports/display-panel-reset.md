# Potential Import: Display panel reset sequence (alioth)

**Date:** 2026-07-07
**Source:** PocoF3Releases/kernel_xiaomi_sm8250 (RvKernel)
**Commits:** `c7ae90b7`, `43c4f16b`, `1afeab3a`
**Status:** RESEARCHED — not yet imported

---

## What it does

Updates display panel reset sequence and timing for alioth (K11A) panel. Reduces dimming speed setting to 16 frames.

**Impact:** MEDIUM — display quality improvement.

**Risk:** LOW — DTS-only changes, well-scoped.

---

## Files affected

- `arch/arm64/boot/dts/vendor/qcom/` (alioth panel DTS)

---

## Backport feasibility

**HIGH** — DTS changes are portable.

---

## PR strategy

Single PR: `import/display-panel-reset`

One commit, DTS changes only.
