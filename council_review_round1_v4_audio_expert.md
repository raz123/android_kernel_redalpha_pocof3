# Council Review: Round 1 Attempt 4 — Audio/IIO Integration Expert

**Reviewer:** R1v4Audio (Audio/IIO Integration Engineer)  
**Branch:** ultrasound-fix-audited @ 4370e0fa7d59  
**Files reviewed:** 6 (us_prox.c, industrialio-buffer.c, iio.h, apr_mius.c, swr-mstr-ctrl.c, mius.c)  
**Date:** 2026-07-03

---

## Criteria Ratings

| Criterion | Rating |
|-----------|--------|
| Compilation correctness | **FAIL** — apr_mius.c: `break`/`default` outside switch |
| Bounds safety | **PASS** — with one latent note |
| `wake_up_poll` in AFE callback | **PASS** |
| SoundWire timeout propagation | **PASS** |
| SoundWire mutex balance | **PASS** |
| `g_us_prox` NULL/lifetime | **PASS** (remove side); **NOTE** (probe side) |
| Keepalive workqueue gating | **PASS** |
| MIUS diagnostics | **PASS** (no behavioral impact) |

---

## Detailed Findings

### Finding 1: `apr_mius.c` — CRITICAL: `break;`/`default:` outside switch (COMPILATION ERROR)

**File:** `techpack/audio/dsp/apr_mius.c`  
**Function:** `mius_process_apr_payload` (line 364)  
**Severity: HIGH — Renders file uncompilable.**

#### Issue

The APR OOB bounds fix (introduced in `bd8082a61f32`) restructured `#if 0` blocks around old ENGINE_DATA dead code. The fix added a premature `#endif` at line 440 (new file line numbering), which prematurely closes the `#if 0` that wraps the old ENGINE_DATA handler. This **exposes `break;` (line 441) and `default:` (line 442) outside any switch statement**.

Preprocessed output confirms the problem:

```c
if (true) {
    payload_size = payload[2] & 0xFFFF;
    {                                   // bounded copy block — added by fix
        uint32_t max_copy;
        payload_size = payload[2] & 0xFFFF;
        max_copy = min(payload_size, MIUS_MSG_BUF_SIZE);
        if (max_copy > 0) {
            ret = mius_data_push(MIUS_ALL_DEVICES,
                (const char *)&payload[3],
                max_copy,
                MIUS_DATA_PUSH_FROM_KERNEL);
        }
        if (ret != 0) { ... return ret; }
        ret = max_copy;
    }
    break;                              // ERROR: 'break' not in switch/loop
    default:                            // ERROR: 'default' label not in switch
} else {
```

**Root cause:** In the original code (`f2fs-fix-ksu`), ALL of the ENGINE_DATA body (including `us_afe_callback` calls), plus `break;`, `default:`, and the inner `}` were inside a single `#if 0` block. The fix added the new bounded-copy block OUTSIDE `#if 0`, then added a NEW `#endif` at line 440 that closes the `#if 0` wrapping the old `us_afe_callback` code — but left `break;` and `default:` outside it.

**How to fix:** The `break;` and `default:` labels must be placed back inside the `#if 0`. Either:
1. Extend the `#if 0` block to cover `break;` and `default:` as well (consolidating with the second `#if 0` that wraps the inner `default: { ... } break; }`), OR
2. Remove the second `#endif` and let the original single `#if 0` block wrap all dead code including `break;` and `default:`.

Recommended consolidation:

```c
            ret = max_copy;
            }
#if 0
            printk(KERN_DEBUG ...);
            if (payload[3] == 0 || payload[3] == 1) {
                ...
            } else {
                ups_event = ups_event ^ 1;
                ...
            }
            if (ret != 0) { ... return ret; }
            ret = payload_size;
            break;
        default:
            {
                pr_err("[MIUS] : mius_process_apr_payload, Illegal paramId:%u", payload[1]);
            }
            break;
        }
#endif
    } else {
```

#### OOB bounds check itself

The `min(payload_size, MIUS_MSG_BUF_SIZE)` clamp at line 412-413 is **correct**. It bounds the copy against the local MIUS buffer, preventing an OOB read when ADSP sends a truncated or malicious packet with an oversized `payload_size` field. The `payload_size = payload[2] & 0xFFFF` extraction (masking to 16 bits) is also correct.

#### Payload minimum size

`mius_process_apr_payload` does not receive a `payload_size` parameter from the caller. It reads `payload[0]` through `payload[3]` without verifying the APR message has at least 16 bytes. This is a pre-existing issue (not introduced by this fix) — the caller in `q6afe.c` only checks `data->payload != NULL`, not minimum payload length. The caller passes `data->payload` without `data->payload_size`, making bounds-checking against the actual APR message impossible. **Not a regression, but noted for robustness.**

---

### Finding 2: `us_prox.c` — `g_us_prox` race window in probe (pre-existing, low severity)

**File:** `drivers/iio/proximity/us_prox.c`  
**Lines:** 339, 272, 343  

In `us_prox_probe()`, `g_us_prox = us_prox` is set at line 339, THEN `us_proximity_iio_setup(us_prox)` is called at line 343. Inside `us_proximity_iio_setup()`, `data->prox_idev = idev` is set at line 272 — AFTER `g_us_prox` is globally visible.

**Race:** If the ADSP callback (`us_afe_callback`) fires between line 339 (`g_us_prox = us_prox`) and line 272 (`data->prox_idev = idev`), the callback checks `g_us_prox` (non-NULL) but `prox_idev` is NULL → NULL dereference.

**Practical risk:** The ADSP subsystem (audio DSP) initializes later than platform device probes in a typical boot sequence, so this race is extremely unlikely in practice. The remove path was correctly fixed in v3 (NULL before cancel/teardown/free). The probe-side ordering issue remains but is low severity.

**Recommendation:** Move `g_us_prox = us_prox` to after `us_proximity_iio_setup(us_prox)` completes successfully.

---

### Finding 3: `us_prox.c` — Keepalive workqueue gating — CORRECT

**File:** `drivers/iio/proximity/us_prox.c`  

- `us_buffer_postenable`: Sets `keepalive_active = 1`, then `schedule_delayed_work` (lines 117-119). **Correct.**
- `us_buffer_predisable`: Sets `keepalive_active = 0`, then `cancel_delayed_work_sync`. Double `cancel_delayed_work` after sync is harmless no-op (lines 134-136). **Correct.**
- `us_prox_keepalive_work`: Pushes data, checks `keepalive_active` before re-scheduling (lines 254-257). If race where work is already running: work checks flag AFTER push, sees 0, does NOT re-schedule. `cancel_delayed_work_sync` returns after work finishes. **Correct.**
- **Result:** No keepalive re-schedule past `cancel_delayed_work_sync`.

---

### Finding 4: `us_prox.c` — `wake_up_poll` in AFE callback — SAFE

**File:** `drivers/iio/proximity/us_prox.c`, line 175  

```c
wake_up_poll(&g_us_prox->prox_idev->buffer->pollq, EPOLLIN);
```

- **Calling context:** `us_afe_callback` is called from ADSP APR callback path in `mius_process_apr_payload`/`q6afe.c`. This runs in kernel workqueue context (not hard IRQ).
- **`wake_up_poll` semantics:** Macro expands to `__wake_up(q, TASK_NORMAL, 1, poll_to_key(EPOLLIN))`. It takes only the waitqueue's embedded spinlock with `spin_lock_irqsave`. Safe in process, softirq, and timer contexts.
- **Lock ordering:** No locks held by caller. No inversion risk.
- **NULL safety:** `g_us_prox` checked at line 169. `prox_idev` and `buffer` are established during probe and remain valid until teardown (gated by `g_us_prox = NULL` in remove).
- **Redundancy:** `iio_push_to_buffers()` internally calls `wake_up(&buf->pollq)` via `__iio_buffer_poll()` (in `industrialio-buffer.c`). The explicit `wake_up_poll` with `EPOLLIN` key provides an additional wakeup with the poll key, which helps ensure `poll()` returns `EPOLLIN` even if `stufftoread` hasn't been set by the internal path.
- **Verdict: Safe and effective.**

---

### Finding 5: `us_prox.c` — Trigger cleanup NULL check — CORRECT

**File:** `drivers/iio/proximity/us_prox.c`, lines 300-304, 316-319  

`us_setup_trigger_sensor()` is now a no-op (returns 0, no trigger allocation). Both error cleanup paths (`us_proximity_iio_setup` and `us_proximity_teardown`) guard trigger cleanup with `if (idev->trig)` check. This prevents NULL-deref when no trigger was allocated. **Correct.**

---

### Finding 6: `industrialio-buffer.c` / `iio.h` — `IIO_DATA_READY_BIT` — DEAD CODE, HARMLESS

**Files:** `drivers/iio/industrialio-buffer.c` (line +5), `include/linux/iio/iio.h` (+3 lines)

- Added `#define IIO_DATA_READY_BIT 2` and a check in `iio_buffer_poll()` returning `EPOLLIN | EPOLLRDNORM` if the bit is set.
- No code path in `us_prox.c` or any other driver in this tree sets `IIO_DATA_READY_BIT`. The code is harmless but currently dead.
- **Not a regression. Not a correctness concern.**

---

### Finding 7: `swr-mstr-ctrl.c` — SoundWire timeout propagation — CORRECT

**File:** `techpack/audio/soc/swr-mstr-ctrl.c`

Changes from `f2fs-fix-ksu`:

| Change | Rating |
|--------|--------|
| `swrm_wait_for_fifo_avail` return type `void` → `int` | **Correct.** Returns `-ETIMEDOUT` on FIFO underflow/overflow. |
| `swrm_cmd_fifo_rd_cmd` checks return → `mutex_unlock` + `return -ETIMEDOUT` | **Correct.** Prevents proceeding with stale FIFO data. |
| `swrm_cmd_fifo_wr_cmd` checks return → `mutex_unlock` + `return ret` | **Correct.** Prevents write to full FIFO. |
| `swr_master_bulk_write` `int ret = 0;` + `break` on timeout | **Correct.** Propagates error instead of silent success. |
| Write overflow recovery: `swr_master_write(SWRM_CMD_FIFO_CMD, 0x1)` | **Correct.** Flushes FIFO on overflow. |

The spurious `mutex_unlock` issue (lockdep warning) is not visible in the current diff — it was addressed in a prior commit. The current code shows proper mutex locking patterns throughout. **All SoundWire changes are correct.**

---

### Finding 8: `mius.c` — Diagnostic logging — CORRECT (no behavioral change)

**File:** `techpack/audio/dsp/mius/mius.c`

Added `pr_info_ratelimited` diagnostics to:
- `device_read` (line 449): log dev index, requested size, bytes read
- `device_write` (lines 472-473): log dev index, length, return value
- `device_ioctl` (lines 490-491): log dev index, ioctl number, param
- `device_poll` (lines 550-551): log dev index, opened, fifo_len, mask
- `device_close` (line 567): log minor, opened flag
- `mius_data_push` (lines 323, 384): log closed-device skip, push details

The `device - mius_devices` pointers used for indexing are safe:
- `device_open` sets `filp->private_data = &mius_devices[minor]` (always within array)
- VFS guarantees `open()` before `read/write/ioctl/poll/close`

The NULL check removed from `device_close` (old: `if (device == NULL) return -ENODEV`; new: direct cast) is safe due to VFS ordering.

**No behavioral changes. PASS.**

---

## Summary

| # | Area | Finding | Severity |
|---|------|---------|----------|
| 1 | apr_mius.c | **COMPILATION ERROR**: `break;`/`default:` outside switch due to premature `#endif` | **HIGH** |
| 2 | us_prox.c probe | `g_us_prox` set before `prox_idev` assigned — narrow race window | LOW |
| 3 | us_prox.c keepalive | Correct gating | PASS |
| 4 | us_prox.c wake_up_poll | Safe in AFE callback context | PASS |
| 5 | us_prox.c trigger cleanup | Correct NULL guard | PASS |
| 6 | industrialio-buffer.c / iio.h | Dead code, harmless | PASS |
| 7 | swr-mstr-ctrl.c | All changes correct | PASS |
| 8 | mius.c diagnostics | No behavioral impact | PASS |

## Final Vote

**NAY**

Rationale: Finding #1 (compilation error in apr_mius.c) is a blocking issue. The `break;` and `default:` outside any switch statement will cause GCC/Clang to reject the file. While the OOB bounds check itself (`min(payload_size, MIUS_MSG_BUF_SIZE)`) is correctly implemented, the preprocessor structural damage renders the entire APR module uncompilable. This must be fixed before the changes can be approved.

The fix is straightforward: extend the `#if 0` block that wraps the old ENGINE_DATA code to also cover `break;` and `default:` (consolidating with the existing inner `#if 0` for the default label), removing the premature `#endif` that currently exposes these as active code.
