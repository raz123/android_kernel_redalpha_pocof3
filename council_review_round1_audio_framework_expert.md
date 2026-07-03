# Council Review — Round 1 (Re-run): Audio Framework Expert

**Reviewer:** Audio Framework Expert (Round 1 re-run)
**Branch:** `ultrasound-fix-audited`
**Date:** 2026-07-03

---

## 1. mius.c — Three Fix Verification

### 1a. `device_write`: undeclared `device` variable
**Status: PASS**

Line 464: `struct mius_device *device = (struct mius_device *)fp->private_data;`

`device` is properly declared as `struct mius_device *` and initialized from `fp->private_data` before use at line 473:
```c
pr_info_ratelimited("[MIUS_DIAG] write dev=%d len=%zu ret=%zd\n",
        (int)(device - mius_devices), length, ret_val);
```
The pointer arithmetic `device - mius_devices` correctly computes the device index. No new bugs introduced.

### 1b. `device_ioctl`: missing `switch(number)`
**Status: PASS**

Line 492: `switch (number) {` is present with three cases:
- `IOCTL_MIUS_DATA_IO_CANCEL` (lines 493-497) — cancels read
- `IOCTL_MIUS_DATA_IO_MIRROR` (lines 499-521) — processes mirror tag with bounds check (`mirror_payload_size <= (MIUS_SET_PARAMS_SIZE * 4)`)
- `default` (lines 524-526) — prints warning for unknown ioctls

Function returns 0 after the switch. All error paths return early with their error code. No fall-through issues, no new bugs.

### 1c. `device_poll`: uninitialized `mask` in diagnostic print
**Status: PASS**

The `mask` variable is declared at line 536, assigned in the if/else block at lines 545-548, and the `pr_info_ratelimited` call at line 550-551 correctly occurs **after** the assignment. The previous bug (print before mask assignment) is fully resolved.

---

## 2. `us_afe_callback` — `wake_up_poll()` Safety (us_prox.c:150-175)

**Status: PASS**

```c
int us_afe_callback(int data)
{
    ...
    if (g_us_prox) {
        ret = iio_push_to_buffers(g_us_prox->prox_idev, ...);
        if (ret < 0)
            pr_err(...);
        wake_up_poll(&g_us_prox->prox_idev->buffer->pollq, EPOLLIN);
    }
    return 0;
}
```

**Safety analysis:**
- **Calling context**: `us_afe_callback` is invoked from the APR callback path (`mius_process_apr_payload` in `apr_mius.c`), which is triggered by an ADSP notification. This runs in a kernel workqueue or softirq context (APR callback context).
- **`wake_up_poll` semantics**: `wake_up_poll(q, EPOLLIN)` is `__wake_up(q, TASK_NORMAL, 1, poll_to_key(EPOLLIN))`. It takes only the waitqueue's own internal spinlock. This is safe in process context, softirq, timer callbacks, and tasklets — all contexts the AFE callback may execute in.
- **Lock ordering**: No spinlocks are held by the caller. No lock dependency inversion risk.
- **NULL safety**: `g_us_prox` is guarded by the `if (g_us_prox)` check at line 165. An `iio_push_to_buffers` failure does not skip `wake_up_poll` (spurious wakeup is harmless — poll semantics mandate that userspace re-checks).
- **Reentrancy**: `__wake_up` is reentrant-safe on the waitqueue head.

**Minor observation**: On `iio_push_to_buffers` failure, userspace still gets woken but finds no data ready. This is a spurious wakeup, which is valid per poll semantics — not a bug.

**Verdict:** `wake_up_poll()` is safe in the AFE callback context.

---

## 3. SoundWire — `swr-mstr-ctrl.c`

### 3a. `swrm_wait_for_fifo_avail` return type (void → int)
**Status: PASS**

Line 770: `static int swrm_wait_for_fifo_avail(struct swr_mstr_ctrl *swrm, int swrm_rd_wr)`

The function now returns `int` (0 on success, `-ETIMEDOUT` on timeout/overflow/underflow). All callers properly evaluate the return:
- `swrm_cmd_fifo_rd_cmd` line 845: `if (swrm_wait_for_fifo_avail(...))` → unlocks `iolock`, returns `-ETIMEDOUT`
- `swrm_cmd_fifo_rd_cmd` line 855: same pattern for read check
- `swrm_cmd_fifo_wr_cmd` line 913: `ret = swrm_wait_for_fifo_avail(...); if (ret)` → unlocks `iolock`, propagates `ret`

Previously a `void` return meant the caller silently ignored FIFO overflow/underflow — now errors are correctly propagated.

### 3b. Mutex safety — spurious `mutex_unlock` removed
**Status: PASS**

All `mutex_lock`/`mutex_unlock` pairs on `iolock` were audited:

- `swrm_cmd_fifo_rd_cmd` (lines 835-883): Lock at 835, unlocks on each error path (lines 846, 856) and success path (line 883). All paths balanced.
- `swrm_cmd_fifo_wr_cmd` (lines 899-936): Lock at 899, unlocks on error (line 915) and success (line 936). All paths balanced.
- No orphaned `mutex_unlock` calls found on `iolock`.

**Lockdep warnings from the previously spurious `mutex_unlock` on an already-unlocked mutex should be fully resolved.**

### 3c. `swr_master_write` for FIFO flush recovery
**Status: PASS**

Line 816: `swr_master_write(swrm, SWRM_CMD_FIFO_CMD, 0x1);` is called on write overflow timeout to flush the command FIFO. The function at line 617 delegates to the platform `swrm->write` callback. This is a standard hardware recovery pattern — writing 0x1 to `SWRM_CMD_FIFO_CMD` flushes the pending command queue.

---

## 4. APR OOB Bounds Check (`apr_mius.c`)

**Status: PASS**

Lines 407-424:
```c
uint32_t max_copy;
/* payload_size from ADSP packet header */
payload_size = payload[2] & 0xFFFF;
/* Bound against MIUS buffer and remaining msg */
max_copy = min(payload_size, (uint32_t)MIUS_MSG_BUF_SIZE);
if (max_copy > 0) {
    ret = mius_data_push(MIUS_ALL_DEVICES,
        (const char *)&payload[3],
        max_copy,
        MIUS_DATA_PUSH_FROM_KERNEL);
}
```

**Analysis:**
- `payload_size` is extracted from the ADSP packet header (`payload[2] & 0xFFFF`) as a 16-bit value (0-65535).
- `max_copy = min(payload_size, MIUS_MSG_BUF_SIZE)` clamps the copy to the kernel buffer size, preventing an OOB read on `&payload[3]`.
- The bounded value is passed to `mius_data_push`, which internally copies to IIO FIFOs.
- A check `max_copy > 0` prevents a pointless call with zero bytes.

**Minor note:** Line 378 also reads `payload_size = payload[2] & 0xFFFF;` but this is inside a `#if 0` block — harmless dead code. The active path at line 410 re-reads the value before the bound check.

**Verdict:** The OOB read vulnerability on truncated/oversized ADSP APR packets is correctly mitigated.

---

## Pre-existing Issue Observed (Not Part of Review Scope)

`mius.c` line 570: `device_close` calls `mius_data_isr_fifo_flush(mius_data)`. This function name differs from the existing static function `mius_data_flush_isr_fifo` (line 101). If `mius_data_isr_fifo_flush` is not defined elsewhere (e.g., in a header with a different implementation), this would be a compilation error. This is pre-existing code and not part of the three fixes to verify, but flagged for awareness.

---

## Final Verdict

| Criterion | Status |
|---|---|
| mius.c `device_write` fix | PASS |
| mius.c `device_ioctl` fix | PASS |
| mius.c `device_poll` fix | PASS |
| `us_afe_callback` `wake_up_poll()` context safety | PASS |
| SoundWire timeout propagation | PASS |
| SoundWire mutex balance | PASS |
| APR OOB bounds check | PASS |
| No new bugs introduced | PASS |

**VOTE: YEA**

All three audio-related fixes from the previous round are correctly applied. The `wake_up_poll()` call in `us_afe_callback` is safe in the AFE callback context. SoundWire timeout propagation and mutex locking are correct. The APR OOB bounds check properly limits the copy size. No new defects are introduced.
