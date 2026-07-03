# Council Review Round 1 v4 — Power Expert

**Reviewer:** R1v4Power (IIO Driver Power Engineer)
**File reviewed:** `drivers/iio/proximity/us_prox.c`
**Branch:** ultrasound-fix-audited @ 4370e0fa7d59

---

## Criteria Ratings

### [PASS] 1. keepalive_active flag gates re-schedule properly

**Location:** `us_prox_keepalive_work()` at line 255

```c
us_prox_push_event(data, 0);
if (data->keepalive_active)
    schedule_delayed_work(&data->keepalive_work,
        msecs_to_jiffies(US_PROX_KEEPALIVE_MS));
```

After pushing the dummy event, the flag is checked *before* re-scheduling. If `keepalive_active == 0` (set by `us_buffer_predisable()` or no postenable yet), no re-schedule occurs. The work terminates cleanly without re-arming.

**Race analysis:** Even if the work function is mid-execution when `predisable` clears the flag, the read of `keepalive_active` happens *after* the flag is cleared (store ordered before work check), so the re-schedule is correctly suppressed. The subsequent `cancel_delayed_work_sync()` then waits for full completion.

---

### [PASS] 2. predisable: clear flag + double cancel (sync+async)

**Location:** `us_buffer_predisable()` at lines 134-136

```c
data->keepalive_active = 0;
cancel_delayed_work_sync(&data->keepalive_work);
cancel_delayed_work(&data->keepalive_work);
```

**Clear flag first:** `keepalive_active = 0` is set *before* any cancel call. This prevents the work function (if currently executing) from re-scheduling — the flag is already 0 when it checks. **Correct sequencing.**

**First cancel (sync):** `cancel_delayed_work_sync()` waits for any running instance to finish. If the work was pending (not yet started), it's cancelled. If it was executing, the sync wait ensures it completes, and since the flag is already 0, it won't re-arm.

**Second cancel (async):** This is a harmless no-op after `cancel_delayed_work_sync()`. The work is guaranteed neither pending nor running. Redundant but not buggy — some kernel patterns use double-cancel as defensive belt-and-suspenders. No issue.

---

### [PASS] 3. remove: g_us_prox NULL before cancel (AFE callback protection)

**Location:** `us_prox_remove()` at lines 362-367

```c
if (us_prox) {
    g_us_prox = NULL;                                // line 363
    cancel_delayed_work_sync(&us_prox->keepalive_work); // line 364
    us_proximity_teardown(us_prox);                   // line 365
    kfree(us_prox);                                   // line 366
}
```

**Critical ordering:** `g_us_prox = NULL` is set **before** any cancel, teardown, or free. This means any concurrent `us_afe_callback()` invocation from the audio DSP (which could fire from any CPU at any time) sees `g_us_prox == NULL` at line 169:

```c
if (g_us_prox) {
    ret = iio_push_to_buffers(g_us_prox->prox_idev, ...);
    wake_up_poll(&g_us_prox->prox_idev->buffer->pollq, EPOLLIN);
}
```

This prevents use-after-free of `prox_idev`, `buffer`, and `pollq` during teardown. **Previously broken in v1/v2 (g_us_prox was set NULL after teardown, creating a race window). Now correctly ordered in v4.**

**Keepalive cancel:** After NULLing the global pointer, `cancel_delayed_work_sync()` drains any pending keepalive work. Since the keepalive work's `data` pointer (derived via `container_of`) still points to the live `us_prox` allocation, it's safe to let it finish. After the sync cancel, teardown and free proceed with no concurrent work.

---

### [PASS] 4. postenable: flag set before schedule

**Location:** `us_buffer_postenable()` at lines 117-119

```c
data->keepalive_active = 1;
schedule_delayed_work(&data->keepalive_work,
    msecs_to_jiffies(US_PROX_KEEPALIVE_MS));
```

The flag is set **before** scheduling the work. When the work eventually fires (after 2s delay), it sees `keepalive_active == 1` and re-schedules itself indefinitely. No window where the work can run but see the flag as 0.

---

### [PASS] 5. No wakelock leak, no suspend blocker

This driver does not use any wakelock or suspend-blocker API:
- No `wake_lock` / `wake_unlock`
- No `pm_stay_awake` / `pm_relax`
- No `__pm_stay_awake` / `__pm_relax`

The keepalive workqueue uses standard delayed work (no `WQ_FREEZABLE` or special flags) — it runs when the system is active and is automatically cancelled on buffer disable. Under suspend, the IIO core handles buffer lifecycle appropriately; the driver has no direct power-management hooks that could leak.

**Clean — no wakelock paths to leak.**

---

## Additional Observations

### IIO buffer poll integration (supporting context)

The `iio_buffer_poll()` in `industrialio-buffer.c` (lines 172-190) first checks `IIO_DATA_READY_BIT` (dead code for this driver — nothing sets it), then calls `poll_wait()` on `rb->pollq`, then checks `iio_buffer_ready()`. Both `us_prox_push_event()` and `us_afe_callback()` correctly call `wake_up_poll(&...->buffer->pollq, EPOLLIN)` after pushing data, which wakes the poll waitqueue and triggers a re-check of `iio_buffer_ready()`. **Poll semantics are correct.**

### No null-pointer on buffer access

`us_prox_push_event()` checks `data` and `data->prox_idev` before dereferencing. The keepalive work is only active between `postenable` and `predisable`, so `buffer` is guaranteed valid during its window. `us_afe_callback()` checks `g_us_prox` before accessing. **No null-pointer risk.**

### Double-cancel is harmless

The second `cancel_delayed_work()` after `cancel_delayed_work_sync()` in `predisable` is a no-op. It does not indicate a logic problem.

---

## Final Verdict

| Criterion | Result |
|---|---|
| keepalive_active gates re-schedule | ✅ PASS |
| predisable clear flag + cancel ordering | ✅ PASS |
| remove: g_us_prox NULL before cancel | ✅ PASS |
| postenable flag set before schedule | ✅ PASS |
| No wakelock leak / suspend blocker | ✅ PASS |

**VOTE: YEA**

All 5 power-management criteria pass. The keepalive gating is correctly ordered with proper flag-first-then-cancel semantics in both predisable and remove paths. The `g_us_prox = NULL` ordering in `remove` correctly closes the AFE callback race window before teardown. No wakelock or suspend-blocker issues exist in this driver.
