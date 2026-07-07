# Potential Import: MGLRU (Multi-Gen LRU)

**Date:** 2026-07-07
**Source:** Upstream Linux 6.1 (Yu Zhao, Google)
**Status:** RESEARCHED — NOT recommended for import

---

## What it is

MGLRU replaces the traditional LRU list mechanism with a multi-generation approach for memory reclaim. Instead of scanning pages on active/inactive lists, it tracks page access patterns across multiple "generations" and reclaims the oldest generation first.

**Performance claims (Google fleet):**
- 40% less kswapd CPU usage
- 85% fewer LMKD kills (P75)
- 18% faster app launches (P50)

**Independent lab results:**
- 20-49% improvements on database workloads (95% CI)

---

## Scope

- **14 patches, 39 files changed, 4,095 insertions** in the v14 series that merged into Linux 6.1
- Core changes in `mm/vmscan.c`, `include/linux/mmzone.h`, `include/linux/mm_types.h`
- New page flags, new mm_struct fields, new kswapd behavior

---

## Why NOT now

1. **No existing 4.19 backport** — no one has successfully ported MGLRU to 4.19 for SM8250
2. **Upstream churn** — original author Yu Zhao has disappeared; Google, Tencent, HONOR working on unification with traditional LRU (LSFMM+BPF 2026)
3. **kswapd 100% CPU bug** — known issue (Launchpad #2087886) that needs separate fix
4. **Page flag pressure on 4.19 arm64** — 4.19 has fewer page flags available
5. **No runtime kill switch** — minimal backport can't be disabled at runtime
6. **Moderate conflict with vendor async reclaim patch** — our tree has Qualcomm-specific mm changes

---

## When to revisit

- When MGLRU-FG patches stabilize (Google's unified LRU approach)
- When kernel base moves to 5.10+ (better page flag support)
- When an existing 4.19 SM8250 backport appears (check Kosminor, kvsnr113)

---

## References

- Upstream: https://patchew.org/linux/20220815071332.627393-1-yuzhao@google.com/
- Unification: https://lwn.net/Articles/1072866/ (May 2026)
- kswapd bug: Launchpad #2087886
- HONOR presentation: LSFMM+BPF 2026
