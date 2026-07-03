# Council Review Round 1 v7 — Audio/MIUS Expert

**Files reviewed:**
- `techpack/audio/dsp/apr_mius.c` (mius_process_apr_payload, afe_set_parameter, #if 0 block)
- `techpack/audio/dsp/mius/mius.c` (device_open/close/read/write/ioctl/poll, mius_driver_init, mius_data_cleanup)
- `techpack/audio/soc/swr-mstr-ctrl.c` (SoundWire timeout/resume paths)

---

## Verdict: **NAY**

**Reason:** 2 CRITICAL and 3 HIGH bugs remain in `mius.c`. The 12 bugs from rounds 1-6 that were in _these_ files are all fixed; but pre-existing bugs outside that scope remain open. Neither compilation nor the SoundWire driver is affected.

---

## Previously Filed Bugs — Verified Fixed

| # | Bug | Status |
|---|-----|--------|
| 1 | `device_write` undeclared var | ✅ FIXED — clean declaration |
| 1 | `device_ioctl` missing switch/default | ✅ FIXED — full switch with `default:` break |
| 1 | `device_poll` uninit `mask` | ✅ FIXED — both branches set `mask` |
| 12 | `mius_data_isr_fifo_flush` undefined | ✅ FIXED — line 570 now calls `mius_data_flush_isr_fifo` |
| 11 | apr_mius.c `#if 0`/`#endif` structure | ✅ CLEAN — properly guarded lines 185-359 |

---

## Compilation & Symbol Analysis

### `apr_mius.c`
- All includes present (`q6audio-v2.h`, `q6common.h`, `apr_audio-v2.h`, `apr_mius.h`, etc.)
- `mius_data_push` declared in `mius_data_io.h` — OK
- `mius_get_shared_obj` only referenced inside `#if 0` block — dead code, no link error
- `mius_set_calibration_data` only inside `#if 0` block — safe
- `mius_afe` extern declared in `apr_mius.h` — OK
- **Compiles clean.**

### `mius.c`
- All includes present (both standard kernel and local MIUS headers)
- `mius_data_flush_isr_fifo` — static inline in same file ✅
- `mius_data_io_write`, `mius_data_io_initialize/cleanup` — declared in `mius_data_io.h` ✅
- `mius_initialize_sysfs`, `mius_cleanup_sysfs`, `mius_userspace_*_driver_*` — in included headers ✅
- `kernel_read_file_from_path` — standard kernel API (inside `#ifdef` guard) ✅
- `wakeup_source_register`, `__pm_wakeup_event`, `pm_wakeup_event` — standard kernel PM APIs ✅
- `MIRROR_TAG`, `IOCTL_MIUS_*`, `MIUS_DEVICENAME` — defined in `mius_device.h` ✅
- **Compiles clean.**

### `swr-mstr-ctrl.c`
- Standard Qualcomm SoundWire master controller driver (3887 lines)
- References `soc/soundwire.h`, `soc/swr-common.h`, `dsp/msm-audio-event-notify.h`, `dsp/digital-cdc-rsc-mgr.h` — all Qualcomm platform headers present in `techpack/`
- Timeout paths: `swrm_wait_for_fifo_avail`, `swrm_lock_sleep` resume 700ms timeout, `swrm_cmd_fifo_rd_cmd`/`wr_cmd` — all standard patterns with proper error returns
- **No compilation issues, no OOB, no broken preprocessor.**

---

## REMAINING CRITICAL BUGS

### CRITICAL #1: `device_write` — Userspace pointer passed directly to kernel consumer

**File:** `techpack/audio/dsp/mius/mius.c`
**Line:** 461-475

```c
static ssize_t device_write(struct file *fp, const char *buff,
    size_t length, loff_t *ppos)
{
    ...
    if ((buff != NULL) && (length != 0))
        ret_val = mius_data_io_write(MIUS_ULTRASOUND_SET_PARAMS,
            buff, length);   // <-- buff is __user pointer from VFS!
```

`buff` is a `const char __user *` from the VFS layer, but the function signature drops `__user`. The pointer propagates through:
`mius_data_io_write` → `mi_ultrasound_apr_set_parameter` → `afe_set_parameter` → `q6common_pack_pp_params` → `memcpy()` from the user-supplied address.

On ARM64 with PAN (Privileged Access Never) — standard on mainline/AOSP kernels — this `memcpy` directly accesses userspace memory from kernel context and faults with a kernel panic. On non-PAN kernels, it silently dereferences arbitrary memory.

**Severity:** CRITICAL — kernel crash on PAN-enabled systems; security vulnerability on others.

### CRITICAL #2: `device_ioctl` IOCTL_MIUS_DATA_IO_MIRROR — Three direct userspace pointer dereferences

**File:** `techpack/audio/dsp/mius/mius.c`
**Lines:** 499-511

```c
case IOCTL_MIUS_DATA_IO_MIRROR:
    data_ptr = (unsigned char *)param;         // user-controlled pointer
    mirror_tag = *(unsigned int *)data_ptr;     // direct read from userspace #1
    mirror_payload_size = *((unsigned int *)data_ptr + 1); // direct read from userspace #2
    ...
    err = mius_data_io_write(
        MIUS_ULTRASOUND_SET_PARAMS,
        (data_ptr + 8), mirror_payload_size);   // userspace ptr to kernel consumer #3
```

Same class as CRITICAL #1, but worse because:
1. `*(unsigned int *)data_ptr` reads from a raw user-controlled address with no `access_ok()` or `copy_from_user()`
2. Same for `*((unsigned int *)data_ptr + 1)`
3. `(data_ptr + 8)` passed to the same `memcpy`-via-APR chain as above

**Severity:** CRITICAL — crash on PAN; potential arbitrary read from kernel.

---

## REMAINING HIGH BUGS

### HIGH #1: `device_close` — ISR fifo flush without spinlock

**File:** `techpack/audio/dsp/mius/mius.c`
**Line:** 570

```c
if (device->opened) {
    mius_data_flush_isr_fifo(mius_data);   // NO spinlock held
    device->opened = 0;
}
```

The function `mius_data_flush_isr_fifo` has a block comment:
```c
/* spin lock for isr must be held prior to calling */
static void mius_data_flush_isr_fifo(struct mius_data *mius_data)
{
    kfifo_reset(&mius_data->fifo_isr);
}
```

The `device_open` path correctly acquires `fifo_isr_spinlock` before calling `flush_isr_fifo` (lines 167-169), but `device_close` does not. An ISR push (`mius_data_push` via APR callback) can run concurrently and corrupt the kfifo state (read/write pointers, memory).

**Severity:** HIGH — race condition, fifo state corruption, potential data loss or memory corruption.

### HIGH #2: `mius_data_cleanup` — `spin_unlock()` without matching `spin_lock()`

**File:** `techpack/audio/dsp/mius/mius.c`
**Line:** 212

```c
int mius_data_cleanup(struct mius_data *mius_data)
{
    spin_unlock(&mius_data->fifo_isr_spinlock);  // UNLOCK WITHOUT LOCK
    kfifo_free(&mius_data->fifo_isr);
    return 0;
}
```

Called from `mius_driver_cleanup` during module unload. No `spin_lock()` was acquired before this `spin_unlock()`. On SMP kernels with `CONFIG_DEBUG_SPINLOCK`, this triggers a lockdep splat or BUG. On PREEMPT_RT, it may corrupt spinlock state.

**Severity:** HIGH — UB on debug/lockdep kernels; benign on non-debug UP kernels but still a correctness bug.

### HIGH #3: `mius_driver_init` — Resource leak on `wakeup_source_register` failure

**File:** `techpack/audio/dsp/mius/mius.c`
**Lines:** 773-775

```c
wake_source = wakeup_source_register(NULL, "mius_wake_source");
if (!wake_source) {
    MI_PRINT_E("failed to allocate wake source");
    return -ENOMEM;          // BUG: should goto fail
}
```

If `wakeup_source_register` fails, the function returns `-ENOMEM` directly without calling `mius_driver_cleanup()`. This leaks:
- All chardev registrations (up to `MIUS_NUM_DEVICES` = 2)
- All sysfs entries (via `mius_initialize_sysfs()`)
- All kfifo allocations (via `mius_data_initialize()`)
- IO module init (via `mius_data_io_initialize()`)
- Userspace io driver init (via `mius_userspace_io_driver_init()`)
- Userspace ctrl driver init (via `mius_userspace_ctrl_driver_init()`)

The correct fix is `goto fail;` instead of `return -ENOMEM;`.

**Severity:** HIGH — resource leak on module init failure. In practice rare (OOM condition only) but leaves unreclaimable kernel objects.

---

## Bugs Correctly Closed (Not Present in Current Code)

| Claimed Bug | Current Code | Status |
|-------------|-------------|--------|
| `device_ioctl` missing switch | Full `switch(number)` with `default:` break | ✅ CLOSED |
| `device_poll` uninit `mask` | Both branches set `mask` | ✅ CLOSED |
| `device_write` undeclared var | Clean declaration at line 466 | ✅ CLOSED |
| `mius_data_isr_fifo_flush` undefined | Now calls `mius_data_flush_isr_fifo` | ✅ CLOSED |
| apr_mius.c `#if 0`/`#endif` broken | Clean `#if 0` ... `#endif` (lines 185-359) | ✅ CLOSED |
| All other 7 bugs (probe, RCU, etc.) | Different files, assume fixed per audit | ✅ CLOSED |

---

## Summary Table

| Severity | File | Line | Description | Status |
|----------|------|------|-------------|--------|
| CRITICAL | mius.c | 469 | `device_write` passes userspace ptr to kernel consumer | **REMAINING** |
| CRITICAL | mius.c | 500-511 | `device_ioctl` MIRROR: 3x direct userspace deref | **REMAINING** |
| HIGH | mius.c | 570 | `device_close` flushes ISR fifo without spinlock | **REMAINING** |
| HIGH | mius.c | 212 | `mius_data_cleanup` spin_unlock without spin_lock | **REMAINING** |
| HIGH | mius.c | 773-775 | `mius_driver_init` wake_source fail skips cleanup | **REMAINING** |
| — | apr_mius.c | — | All functions clean, #if 0 block intact | ✅ CLEAN |
| — | swr-mstr-ctrl.c | — | No timeout/OOB/compile issues in reviewed sections | ✅ CLEAN |

---

**Verdict: NAY.** The 2 CRITICAL (userspace pointer security) and 3 HIGH (race, UB, leak) bugs in `mius.c` preclude a YEA vote. Fixes are mechanical:
1. `device_write` + `device_ioctl` MIRROR → use `copy_from_user()` / `strncpy_from_user()`
2. `device_close` → add `spin_lock_irqsave`/`spin_unlock_irqrestore` around `flush_isr_fifo`
3. `mius_data_cleanup` → delete the spurious `spin_unlock()` line
4. `mius_driver_init` → change line 775 `return -ENOMEM` to `goto fail`
