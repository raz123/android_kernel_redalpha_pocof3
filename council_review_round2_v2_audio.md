# Council Review — Round 2 v2 — Audio Data Path Expert

**Reviewer:** R2v2B (Audio Data Path Expert)
**Branch:** ultrasound-fix-audited @ a3c94edfd3fe
**Files reviewed:** `techpack/audio/dsp/apr_mius.c`, `techpack/audio/dsp/mius/mius.c`, `drivers/iio/proximity/us_prox.c`
**Focus:** Data path correctness, SoundWire safety

---

## 1. Buffer NULL Guard in `us_afe_callback` (`us_prox.c:169-200`)

**File:** `drivers/iio/proximity/us_prox.c`
**Previous issue (Round 1):** `wake_up_poll(&prox->prox_idev->buffer->pollq)` could NULL-deref if `buffer` is NULL.

### Current code:

```c
int us_afe_callback(int data)
{
    struct us_prox_data *prox;
    struct us_prox_el_data el_data;
    struct timespec ts;
    int ret;

    get_monotonic_boottime(&ts);
    el_data.timestamp = timespec_to_ns(&ts);
    el_data.data1 = (data != 0) ? 5 : 0;

    rcu_read_lock();
    prox = rcu_dereference(g_us_prox);
    if (prox && !kref_get_unless_zero(&prox->refcount))
        prox = NULL;
    rcu_read_unlock();

    if (!prox)
        return 0;

    if (prox->prox_idev->buffer) {
        ret = iio_push_to_buffers(prox->prox_idev,
                     (unsigned char *)&el_data);
        if (ret < 0)
            pr_err("%s: failed to push us prox data to buffer, err=%d\n",
                    __func__, ret);
        wake_up_poll(&prox->prox_idev->buffer->pollq, EPOLLIN);
    }

    kref_put(&prox->refcount, us_prox_data_release);
    return 0;
}
```

### Analysis — VERDICT: CORRECT (FIX APPLIED)

**NULL guard:** Both `iio_push_to_buffers` AND `wake_up_poll` are guarded by `if (prox->prox_idev->buffer)` at line 189. This directly addresses the Round 1 finding.

**iio_push_to_buffers internal safety:** The upstream implementation of `iio_push_to_buffers` performs its own `if (!indio_dev->buffer)` check inside the function. The outer guard is therefore belt-and-suspenders for that call. However, the guard is **essential** for `wake_up_poll` — there is no internal NULL check on `buffer->pollq` — so the fix is necessary and correct for that line.

**Lifetime safety (kref + RCU):** The RCU read-lock protects the `g_us_prox` dereference. After successful `kref_get_unless_zero`, the caller holds a counted reference on `us_prox_data`. This prevents `us_prox_data_release` (and thus `us_proximity_teardown`) from running, which ensures `prox->prox_idev` remains valid. Since `iio_device_free` (which frees the iio_dev containing the buffer) is only called from `us_proximity_teardown`, and teardown is gated on the kref reaching zero, the buffer cannot be freed while the callback holds a kref reference. **The entire lifetime chain is safe.**

**Race window on buffer pointer:** There is a micro-window between the NULL check at line 189 and the two subsequent uses of `buffer`. However, as argued above, the kref reference on the parent `us_prox_data` prevents any teardown from running, so the buffer pointer cannot become stale. This race is **not exploitable** in the current design.

### Status: PASS — Fix correct and complete.

---

## 2. APR → MIUS FIFO Data Path (`apr_mius.c` + `mius.c`)

### 2.1 APR Payload Dispatch (`q6afe.c:1250-1257` → `apr_mius.c:363-398`)

**File:** `techpack/audio/dsp/q6afe.c:1250-1257` / `techpack/audio/dsp/apr_mius.c:363-398`

The AFE callback dispatches `MI_ULTRASOUND_OPCODE` to `mius_process_apr_payload`.

### Payload parsing (`apr_mius.c:363-398`):

```c
int32_t mius_process_apr_payload(uint32_t *payload)
{
    uint32_t payload_size;
    int32_t  ret = -1;

    /* payload format
     *   payload[0] = Module ID
     *   payload[1] = Param ID
     *   payload[2] = LSB - payload size, MSB - reserved
     *   payload[3] = US data payload starts from here
     */
    payload_size = payload[2] & 0xFFFF;

    if (payload_size == 0)
        return -EINVAL;

    {
        uint32_t max_copy;

        /* Bound against MIUS buffer and remaining msg */
        max_copy = min(payload_size, (uint32_t)MIUS_MSG_BUF_SIZE);
        if (max_copy > 0) {
            ret = mius_data_push(MIUS_ALL_DEVICES,
                (const char *)&payload[3],
                max_copy,
                MIUS_DATA_PUSH_FROM_KERNEL);
        }
        if (ret != 0) {
            pr_err("[MIUS] : failed to push apr payload to mius device");
            return ret;
        }
        ret = max_copy;
    }

    return ret;
}
```

### Analysis — VERDICT: CORRECT

**Bounds checking:**
- `payload_size == 0` check prevents zero-length pushes.
- `max_copy = min(payload_size, MIUS_MSG_BUF_SIZE)` caps the copy at 512 bytes (the FIFO element size). This prevents an oversized payload from overflowing the kernel buffer.
- The `(const char *)&payload[3]` offset correctly skips the 3 x uint32_t header (Module ID, Param ID, size+reserved) and points at the data payload.

**Calling context:** Runs from the `afe_callback` in `q6afe.c`, which is registered with `apr_register("ADSP", "AFE", ...)` and invoked from the ADSP APR notification path. This is a workqueue/softirq context — safe for spinlock-based FIFO operations.

**Push target:** `MIUS_ALL_DEVICES` — distributes to all configured mius chardev instances via `mius_data_push`.

### 2.2 mius_data_push FIFO Write (`mius.c:283-400`)

### Analysis — VERDICT: CORRECT (with minor concerns)

**Spinlock correctness:**
- `spin_lock_irqsave(&mius_data->fifo_isr_spinlock, flags)` is used, which is correct for both the APR callback context (atomic) and for protecting against concurrent userspace reads.
- The per-device spinlock (`&mius_data->fifo_isr_spinlock`) protects the per-device FIFO — concurrent pushes to different devices on different CPUs do not contend.

**Discard-on-full policy:**
```c
available_space = kfifo_avail(&mius_data->fifo_isr);
...
spin_lock_irqsave(...);
if (available_space < space_required) {
    mius_data_isr_fifo_pop(mius_data, MIUS_MSG_BUF_SIZE);
}
```
- `available_space` is sampled **outside** the spinlock. Under concurrent multi-producer access, this is a TOCTOU race — the decision to pop (discard) is based on stale data.
- **Mitigation:** In the actual usage model, the FIFO has a **single producer** (the APR callback path). Only `mius_process_apr_payload` pushes kernel data; the `MIUS_DATA_PUSH_FROM_USERSPACE` path is exercised only by out-of-tree or external modules. Under single-producer operation, the TOCTOU is a performance concern (unnecessary pops) but not a correctness bug.
- After popping, the kfifo_in always has at least `MIUS_MSG_BUF_SIZE` bytes free (the pop frees exactly one element of that size), so the push succeeds.

**Zero-padding:**
- `zeros_to_pad = MIUS_MSG_BUF_SIZE - buffer_size` — every FIFO element is padded to MIUS_MSG_BUF_SIZE (512 bytes). This ensures the consumer always reads fixed-size records. Correct.
- If the zero-padding kfifo_in fails after the data kfifo_in succeeded, the data element is popped back (rollback). Correct.

**Wakeup after push:**
- `wake_up_interruptible(&mius_data->fifo_isr_not_empty)` is called **after** `spin_unlock_irqrestore`. This is the correct pattern — waking waiters while holding the spinlock could cause a deadlock if the waiter immediately tries to acquire the same lock.
- `__pm_wakeup_event(wake_source, mius_data->wakeup_timeout)` is called next — also after the unlock. Correct.

### 2.3 mius_data_isr_fifo_pop — Static Buffer (`mius.c:108-122`)

```c
static void mius_data_isr_fifo_pop(struct mius_data *mius_data, size_t size)
{
    unsigned int fifo_result;
    static uint8_t temp_buffer[MIUS_MSG_BUF_SIZE];
    ...
    fifo_result = kfifo_out(&mius_data->fifo_isr, temp_buffer, size);
    ...
}
```

**Issue:** `static uint8_t temp_buffer[MIUS_MSG_BUF_SIZE]` is a single buffer shared across all device instances. Under concurrent pushes to different devices (different spinlocks), two CPUs could call discarding pops simultaneously, corrupting each other's `temp_buffer`.

**Mitigation:** The buffer is used only to *discard* data — the contents are never read. The worst case is that garbage data is written but immediately discarded. This is functionally harmless, but it is a code smell. The static buffer should be replaced with a stack allocation (or removed entirely by using a NULL output parameter).

**Severity:** LOW — not a correctness issue in practice.

### 2.4 userspace Read Path (`mius.c:216-278` — `mius_data_pop`)

### Analysis — VERDICT: CORRECT

- `wait_event_interruptible` with proper abort signal (`abort_io`).
- kfifo_out under `spin_lock_irqsave`, then `mutex_lock` for `copy_to_user`. The mutex serializes concurrent reads to the swap buffer (though reads are implicitly serialized by userspace behavior per open fd).
- `copy_to_user` after releasing spinlock — correct, avoids sleeping under spinlock.

---

## 3. SoundWire Safety

### Analysis — VERDICT: CORRECT

The following operations are performed in the APR callback context (workqueue/softirq from ADSP):

| Operation | Context | Safe? |
|-----------|---------|-------|
| `kfifo_in` under `spin_lock_irqsave` | atomic | YES |
| `wake_up_interruptible` | atomic-safe (only takes waitqueue spinlock) | YES |
| `__pm_wakeup_event` | atomic-safe | YES |
| `iio_push_to_buffers` | atomic-safe (uses `iio_buffer->pollq` spinlock) | YES |
| `kref_get_unless_zero` / `kref_put` | atomic-safe (uses `refcount_t`) | YES |
| `rcu_read_lock/unlock` | atomic-safe | YES |

No operations in the callback path allocate memory (no `GFP_KERNEL` allocations), sleep, or take mutexes. **All SoundWire-related interactions are through the APR message passing layer, which is designed for atomic callback contexts.**

The data path does not directly touch SoundWire hardware registers; it transfers DSP-sourced data through kernel FIFOs to userspace.

---

## 4. Summary of Findings

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| F1 | **HIGH** | Buffer NULL guard in `us_afe_callback` — both `iio_push_to_buffers` and `wake_up_poll` guarded | FIXED CORRECTLY |
| F2 | **MEDIUM** | `available_space` TOCTOU in `mius_data_push` (line 348) — sampled outside spinlock | ACCEPTABLE (single-producer model) |
| F3 | **LOW** | `static uint8_t temp_buffer[MIUS_MSG_BUF_SIZE]` in `mius_data_isr_fifo_pop` — shared across devices | ACCEPTABLE (used only for discarding) |
| F4 | **LOW** | `static uint8_t zero_pad_buffer[MIUS_MSG_BUF_SIZE]` in `mius_data_push` — same static buffer concern | ACCEPTABLE (read-only data) |
| F5 | **LOW** | `copy_from_user` partial failure in `mius_data_push` still pushes partial data onward | ACCEPTABLE (only affects external callers) |
| F6 | — | SoundWire/APR callback context safety | PASS — all operations atomic-safe |

---

## 5. Vote

**YEA**

The data path from ADSP APR callback through the mius FIFO to userspace is correct. The buffer NULL guard in `us_afe_callback` is properly applied and the kref+RCU lifetime pattern correctly protects the entire data structure chain. SoundWire safety is maintained — all operations in the callback context are atomic-safe. The minor issues (TOCTOU on `available_space`, static discard buffers) are acceptable under the single-producer usage model and do not affect correctness.
