// SPDX-License-Identifier: GPL-2.0-only
/*
 * Stub for SUSFS workqueue symbol referenced by patched workqueue.h.
 * The full SUSFS implementation is in fs/susfs.c (requires CONFIG_KSU_SUSFS=y).
 * This provides the symbol unconditionally so vmlinux links cleanly when
 * SUSFS patches modify workqueue.h but CONFIG_KSU_SUSFS is not enabled.
 *
 * Guarded by ifneq ($(CONFIG_KSU_SUSFS),y) in fs/Makefile — never compiled
 * alongside the real fs/susfs.o.
 */

#include <linux/workqueue.h>

/* No-op handler — real work is in fs/susfs.c when CONFIG_KSU_SUSFS=y */
static void susfs_extra_works_handler(struct work_struct *work) {}

DEFINE_WORK(susfs_extra_works, susfs_extra_works_handler);
