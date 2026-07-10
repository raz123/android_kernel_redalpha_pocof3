# Battery charge-limit contract

## Scope

Add a kernel-only SOC charge limit for the alioth SMB5 charger. The default
limit is 80%; userspace may configure another valid percentage. The feature
must preserve existing thermal, JEITA, safety, USB-PD, and charger-vote
behavior.

## Interface

Use the battery power-supply interface:

- `POWER_SUPPLY_PROP_CHARGE_CONTROL_LIMIT`: read/write SOC percentage.
- `POWER_SUPPLY_PROP_CHARGE_CONTROL_LIMIT_MAX`: read-only value `100`.
- A value of `0` disables the limit and clears the feature's `CHG_DISABLE`
  vote, restoring normal charging.
- Valid enabled values are `1..100`; invalid values return `-EINVAL` and do
  not change state.
- The setting is runtime-only and resets to disabled on reboot unless a later
  userspace component persists and reapplies it.

The existing target mapping of these properties to `system_temp_level` must be
removed. Thermal-level control remains on its own property and code path.

## Behavior

- When enabled and capacity is at or above the configured limit, cast only the
  charge-limit voter's `CHG_DISABLE` vote.
- Resume only when capacity is at or below `limit - 2` percentage points.
- Never clear votes belonging to thermal, JEITA, USB-PD, safety, or other
  clients.
- Re-evaluate after battery-capacity/power-supply changes, charger
  attach/detach, suspend/resume, and configuration changes.
- On unplug, remove only the charge-limit vote; re-evaluate after replug.
- On disable, remove only the charge-limit vote.
- If battery capacity cannot be read, leave the current vote unchanged and
  fail open for a newly enabled limit.

## Acceptance tests

Static/source checks:

1. `alioth_defconfig` still enables the existing SMB5 driver; no unrelated
   defconfig or device-tree changes are required.
2. The charge-limit property no longer calls thermal-level setters/getters.
3. The implementation uses a unique voter and never writes charger current,
   float voltage, JEITA tables, or safety thresholds.
4. Invalid values, including negative values and values above 100, return
   `-EINVAL` without changing the configured limit or vote.
5. YAML and shell syntax checks pass, and the diff is limited to the feature
   files plus this contract.

Runtime/device checks after the user flashes and boots the package:

1. Read default state: limit disabled and normal charging behavior unchanged.
2. Set 80%: readback is 80; charging is disabled at/above 80% while the
   charger remains attached.
3. Confirm hysteresis: charging stays disabled below 80% until capacity is at
   or below 78%, then resumes.
4. Unplug/replug above the limit: only the feature vote is restored; existing
   charger and thermal votes remain effective.
5. Disable with `0`: charging returns to normal and the feature vote is gone.
6. Verify suspend/resume and reboot behavior; reboot reset is documented if
   no userspace persistence is added.
7. Exercise thermal/JEITA conditions and confirm their votes still disable or
   constrain charging independently.
8. Verify no bootloop or charger-driver regression using read-only ADB logs
   and power-supply state. No flashing or rebooting is performed by Codex.

## Provenance decision

Generic laptop `charge_control_end_threshold` patches and newer Qualcomm/Pixel
charge-to-limit implementations are not clean imports for this Linux 4.19
Xiaomi SMB5 tree: they use different drivers, state models, or ABI contracts.
The implementation should therefore be a minimal target adaptation using the
target's existing power-supply properties and `CHG_DISABLE` votable, with
source provenance documented in the implementation commit.
