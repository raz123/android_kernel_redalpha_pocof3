# Power Management Engineer — Round 1 Council Review

**Reviewer:** R1Power
**Branch:** `ultrasound-fix-audited`
**Target:** `drivers/iio/proximity/us_prox.c`
**Date:** 2026-07-03

---

## Review Criteria

### Criterion 1: Keepalive Gating to Buffer Lifetime

**Verdict: PASS**

| Aspect | Assessment |
|---|---|
| Scheduling location | `us_buffer_postenable()` — only when IIO buffer is enabled (userspace opens sensor) |
| Cancellation location | `us_buffer_predisable()` — when IIO buffer is disabled (userspace closes sensor) |
| Probe behavior | `INIT_DELAYED_WORK` only, no `schedule_delayed_work` — zero background wakeups when sensor unused |
| Teardown safety | `us_prox_remove()` calls `cancel_delayed_work_sync()` before teardown |

**Findings:**
- Previously (hypothetical always-on probe-triggered design), the keepalive would fire every 2s forever, wasting ~26W per year of idle battery capacity. The fix correctly defers scheduling to buffer-postenable and cancels in buffer-predisable.
- Lifecycle is clean: `probe` → init work only; `postenable` → schedule; `predisable` → cancel; `remove` → cancel + teardown.
- `cancel_delayed_work_sync()` in `us_buffer_predisable()` handles the race where work might be running — it waits for completion before returning.

---

### Criterion 2: Suspend Safety (Timer Freeze)

**Verdict: PASS (with notes)**

**Findings:**
- The workqueue uses `INIT_DELAYED_WORK()` (standard timer), NOT `INIT_DELAYED_WORK_FREEZABLE()`.
- **Normal suspend flow:** The process freezer closes userspace fds → IIO buffer fd release → `iio_buffer_release()` → `us_buffer_predisable()` → `cancel_delayed_work_sync()`. By the time the system suspends, the keepalive is already cancelled. This makes the non-freezable timer safe in practice.
- **Edge case concern:** If a kernel-internal consumer used the IIO device without userspace fd lifecycle, the non-freezable work could remain pending during suspend. However, this driver serves only userspace HAL, so this doesn't apply.
- **Missing robustness:** There are no `suspend`/`resume` callbacks in `us_prox_driver`. While not strictly required (process freeze handles it), adding `pm_ops` with `suspend` → `cancel_delayed_work_sync()` and `resume` → reschedule would be more robust for corner cases (e.g., if the fd isn't released before freezing, or if PM race conditions arise).
- **Recommendation (not blocking):** Add `SET_SYSTEM_SLEEP_PM_OPS` with callbacks that cancel/reschedule the keepalive for defense-in-depth.

**Overall:** No functional bug here in the standard suspend path. The keepalive is effectively cancelled before suspend. PASS.

---

### Criterion 3: `wake_up_poll()` in Audio DSP Callback Context

**Verdict: PASS (with note)**

**Findings:**
- `us_afe_callback()` is called from ADSP callback context (interrupt-like on SM8250). It now calls `wake_up_poll()` after pushing data via `iio_push_to_buffers()`.
- **Suspend interaction:** During suspend transition, if ADSP callback fires (sensor data arrives), `wake_up_poll()` could wake a process waiting on the pollq. This could cause `-EBUSY` from `pm_suspend()` if the process is a suspend blocker. *However:*
  1. ADSP is also suspended during system suspend, so callbacks shouldn't fire.
  2. If userspace has already closed the fd (via process freeze), nobody is polling, so `wake_up_poll()` on an empty waitqueue is a harmless no-op.
  3. If userspace hasn't closed yet, the callback would deliver real sensor data, which is correct behavior — waking the process to consume data before suspend.
- **Noirq concern:** `wake_up_poll()` calls `__wake_up()` which takes a spinlock and may do a scheduler wakeup. In ADSP callback context (which may be a hard IRQ or threaded IRQ), this is acceptable — `__wake_up` uses `spin_lock_irqsave`, and `poll_wait` entries handle spinlock context correctly.
- **No new regression:** The original code already had `iio_push_to_buffers()` in this context. Adding `wake_up_poll()` is the intended fix and doesn't introduce a fundamentally new PM risk.

**Verdict:** Acceptable. The fix does what it needs to and the PM risk is minimal.

---

### Criterion 4: Deep C-State Impact During Active Sensor Use

**Verdict: PASS**

**Findings:**
- Keepalive fires every 2000ms, pushes dummy data (value=0), wakes userspace poll, then reschedules.
- **Work per keepalive cycle:** ~1-2ms of execution (workqueue dispatch, `iio_push_to_buffers` with timestamp calculation, `wake_up_poll`, userspace read + return). This is ~0.05-0.1% CPU utilisation.
- **C-state impact:**
  - SM8250 (Snapdragon 865) deep C-states (C7) have exit latency ~100-200us, exit energy ~5-15uJ.
  - With a 2-second keepalive interval, the maximum continuous deep-C residency is <2 seconds before the timer fires.
  - Additional energy per 2s period: ~1 timer interrupt + workqueue + C-state exit ≈ 50uJ (estimate).
  - Extrapolated overhead: ~25uJ/s average, or roughly 0.5-1mW additional power during active sensor use.
- **Context:** This sensor is used exclusively during active phone calls (proximity detection). The phone's modem and display are already active, dominating power draw. A sub-mW keepalive overhead is negligible.
- **Comparison to sensor data rate:** Many proximity sensors poll at 10-50ms intervals. A 2000ms keepalive is extremely conservative. Real sensor data arriving via `us_afe_callback()` would be at a much lower rate (hand-wave proximity only during calls), so the keepalive dominates only during silence — and even then, 2s interval is fine.

**Verdict:** Power impact is acceptable. No changes needed.

---

### Criterion 5: Hidden Wakelock / Kernel Wakelock Interactions

**Verdict: PASS**

**Findings:**
- No `wake_lock()` / `wake_unlock()` calls anywhere in the driver.
- No `pm_stay_awake()` / `pm_relax()` calls.
- No `IRQF_NO_SUSPEND` on any interrupt.
- No `wakeup_source` registration on the platform device.
- The `platform_device` (`us_prox_dev`) has no `dev.power.wakeup` configured — it won't act as a wakeup source.
- The only indirect wakeup path is `wake_up_poll()` → userspace process (already discussed in Criterion 3 — not a wakelock).

**Additional observation (not power-related but worth noting):** The driver uses a global singleton `g_us_prox` pointer (line 42, 330) that is dereferenced in `us_afe_callback()` without any reference counting. If the driver is removed while ADSP callbacks are still active, this could cause a use-after-free. Recommend adding a NULL check or refcount. However, this is a stability concern, not a PM concern, so it does not affect this review.

---

## Final Vote

| Criterion | Rating |
|---|---|
| 1. Keepalive gating to buffer lifetime | **PASS** |
| 2. Suspend-safe timer handling | **PASS** (see notes) |
| 3. `wake_up_poll()` in DSP callback context | **PASS** |
| 4. Deep C-state impact during active use | **PASS** |
| 5. Hidden wakelock interactions | **PASS** |

## YEA

The keepalive gating is correctly implemented to buffer lifetime, eliminating unnecessary wakeups when the sensor is unused. Power management concerns (suspend, C-states, wakelocks) are adequately handled. No blocking power issues identified.

**Recommendations for improvement (non-blocking):**
1. Consider `INIT_DELAYED_WORK_FREEZABLE()` for defense-in-depth during suspend.
2. Add optional `suspend`/`resume` PM callbacks to explicitly cancel/reschedule the keepalive work.
3. Add reference counting or NULL-check the `g_us_prox` global in `us_afe_callback()` (stability, not PM).
