# Potential Import: UFS Write Booster Enablement

**Date:** 2026-07-07
**Source:** PocoF3Releases/kernel_xiaomi_sm8250 (RvKernel)
**Commit:** `e36b2363`
**Status:** RESEARCHED — not yet imported

---

## What it does

Reverts Xiaomi's broken `wb_config` changes that prevented UFS Write Booster from activating. Also partially reverts UFS_WB_TYPE check to use UFS_WB_FEATURE instead (some UFS3.0 devices don't report WB_TYPE).

**Tested results (munch/Redmi K40S, SKhynix HN8T15BZGKX016):**
- Continuous Read: 1576 → 1702 MB/s (+8%)
- Continuous Write: 428 → 750 MB/s (+75%)

**Impact:** HIGH — 75% write speed improvement on UFS WB-capable devices.
**Risk:** LOW — reverts broken Xiaomi changes, restores upstream behavior.

---

## Files affected

- `drivers/scsi/ufs/ufshcd.c`
- `drivers/scsi/ufs/ufs-qcom.c`

---

## Backport feasibility

**HIGH** — the UFS subsystem is identical in our tree. The fix reverts Xiaomi-specific changes and restores upstream behavior.

---

## PR strategy

Single PR: `import/ufs-write-booster`

One commit, two file changes. Test with `dd if=/dev/zero of=/data/testfile bs=1M count=1024` before/after.
