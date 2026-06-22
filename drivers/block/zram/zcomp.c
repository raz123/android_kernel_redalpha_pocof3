/*
 * Copyright (C) 2014 Sergey Senozhatsky.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 */

#include <linux/kernel.h>
#include <linux/string.h>
#include <linux/err.h>
#include <linux/slab.h>
#include <linux/wait.h>
#include <linux/sched.h>
#include <linux/cpu.h>
#include <linux/crypto.h>

#include "zcomp.h"
extern const struct zcomp_ops backend_lz4;

static const struct zcomp_ops *zcomp_backends[] = {
#if IS_ENABLED(CONFIG_ZRAM_BACKEND_LZ4)
	&backend_lz4,
#endif
	NULL
};

static const struct zcomp_ops *lookup_backend_ops(const char *comp)
{
	int i;

	for (i = 0; zcomp_backends[i]; i++) {
		if (sysfs_streq(comp, zcomp_backends[i]->name))
			return zcomp_backends[i];
	}
	return NULL;
}

static const char * const backends[] = {
#if IS_ENABLED(CONFIG_CRYPTO_LZO)
	"lzo",
	"lzo-rle",
#endif
#if IS_ENABLED(CONFIG_CRYPTO_LZ4)
	"lz4",
#endif
#if IS_ENABLED(CONFIG_CRYPTO_LZ4HC)
	"lz4hc",
#endif
#if IS_ENABLED(CONFIG_CRYPTO_LZ4K)
	"lz4k",
#endif
#if IS_ENABLED(CONFIG_CRYPTO_LZ4K_OPLUS)
	"lz4k_oplus",
#endif
#if IS_ENABLED(CONFIG_CRYPTO_LZ4KD)
	"lz4kd",
#endif
#if IS_ENABLED(CONFIG_CRYPTO_DEFLATE)
	"deflate",
#endif
#if IS_ENABLED(CONFIG_CRYPTO_842)
	"842",
#endif
#if IS_ENABLED(CONFIG_CRYPTO_ZSTD)
	"zstd",
#endif
#if IS_ENABLED(CONFIG_CRYPTO_ZSTDN)
	"zstdn",
#endif
	NULL
};

static void zcomp_strm_free(struct zcomp *comp, struct zcomp_strm *zstrm)
{
	if (comp->ops)
		comp->ops->destroy_ctx(&zstrm->ctx);
	if (!IS_ERR_OR_NULL(zstrm->tfm))
		crypto_free_comp(zstrm->tfm);
	free_pages((unsigned long)zstrm->buffer, 1);
	kfree(zstrm);
}

static struct zcomp_strm *zcomp_strm_alloc(struct zcomp *comp)
{
	struct zcomp_strm *zstrm = kzalloc(sizeof(*zstrm), GFP_KERNEL);
	if (!zstrm)
		return NULL;

	if (comp->ops) {
		int ret = comp->ops->create_ctx(comp->params, &zstrm->ctx);
		if (ret) {
			kfree(zstrm);
			return NULL;
		}
	} else {
		zstrm->tfm = crypto_alloc_comp(comp->name, 0, 0);
		if (IS_ERR_OR_NULL(zstrm->tfm)) {
			kfree(zstrm);
			return NULL;
		}
	}
	/*
	 * allocate 2 pages. 1 for compressed data, plus 1 extra for the
	 * case when compressed size is larger than the original one
	 */
	zstrm->buffer = (void *)__get_free_pages(GFP_KERNEL | __GFP_ZERO, 1);
	if (!zstrm->buffer) {
		if (comp->ops)
			comp->ops->destroy_ctx(&zstrm->ctx);
		kfree(zstrm);
		return NULL;
	}
	return zstrm;
}

bool zcomp_available_algorithm(const char *comp)
{
	int i;

	i = __sysfs_match_string(backends, -1, comp);
	if (i >= 0)
		return true;

	/*
	 * Crypto does not ignore a trailing new line symbol,
	 * so make sure you don't supply a string containing
	 * one.
	 * This also means that we permit zcomp initialisation
	 * with any compressing algorithm known to crypto api.
	 */
	return crypto_has_comp(comp, 0, 0) == 1;
}

/* show available compressors */
ssize_t zcomp_available_show(const char *comp, char *buf)
{
	bool known_algorithm = false;
	ssize_t sz = 0;
	int i = 0;

	for (; backends[i]; i++) {
		if (!strcmp(comp, backends[i])) {
			known_algorithm = true;
			sz += scnprintf(buf + sz, PAGE_SIZE - sz - 2,
					"[%s] ", backends[i]);
		} else {
			sz += scnprintf(buf + sz, PAGE_SIZE - sz - 2,
					"%s ", backends[i]);
		}
	}

	/*
	 * Out-of-tree module known to crypto api or a missing
	 * entry in `backends'.
	 */
	if (!known_algorithm && crypto_has_comp(comp, 0, 0) == 1)
		sz += scnprintf(buf + sz, PAGE_SIZE - sz - 2,
				"[%s] ", comp);

	sz += scnprintf(buf + sz, PAGE_SIZE - sz, "\n");
	return sz;
}

struct zcomp_strm *zcomp_stream_get(struct zcomp *comp)
{
	return *get_cpu_ptr(comp->stream);
}

void zcomp_stream_put(struct zcomp *comp)
{
	put_cpu_ptr(comp->stream);
}

int zcomp_compress(struct zcomp *comp, struct zcomp_strm *zstrm,
		const void *src, unsigned int *dst_len)
{
	if (comp->ops) {
		struct zcomp_req req = {
			.src = src,
			.dst = zstrm->buffer,
			.src_len = PAGE_SIZE,
			.dst_len = 2 * PAGE_SIZE,
		};
		int ret;

		might_sleep();
		ret = comp->ops->compress(comp->params, &zstrm->ctx, &req);
		if (!ret)
			*dst_len = req.dst_len;
		return ret;
	}

	/*
	 * Crypto fallback: our dst memory (zstrm->buffer) is always
	 * `2 * PAGE_SIZE' sized because sometimes we can endup having
	 * a bigger compressed data due to various reasons: for example
	 * compression algorithms tend to add some padding to the
	 * compressed buffer.
	 */
	*dst_len = PAGE_SIZE * 2;

	return crypto_comp_compress(zstrm->tfm,
			src, PAGE_SIZE,
			zstrm->buffer, dst_len);
}

int zcomp_decompress(struct zcomp *comp, struct zcomp_strm *zstrm,
		const void *src, unsigned int src_len, void *dst)
{
	unsigned int dst_len = PAGE_SIZE;

	if (comp->ops) {
		struct zcomp_req req = {
			.src = src,
			.dst = dst,
			.src_len = src_len,
			.dst_len = PAGE_SIZE,
		};

		might_sleep();
		return comp->ops->decompress(comp->params, &zstrm->ctx, &req);
	}

	return crypto_comp_decompress(zstrm->tfm,
			src, src_len,
			dst, &dst_len);
}
int zcomp_setup_params(struct zcomp *comp, struct zcomp_params *params)
{
	int ret = 0;

	comp->params = params;
	if (comp && comp->ops && comp->ops->setup_params)
		ret = comp->ops->setup_params(params);
	return ret;
}

int zcomp_cpu_up_prepare(unsigned int cpu, struct hlist_node *node)
{
	struct zcomp *comp = hlist_entry(node, struct zcomp, node);
	struct zcomp_strm *zstrm;

	if (WARN_ON(*per_cpu_ptr(comp->stream, cpu)))
		return 0;

	zstrm = zcomp_strm_alloc(comp);
	if (IS_ERR_OR_NULL(zstrm)) {
		pr_err("Can't allocate a compression stream\n");
		return -ENOMEM;
	}
	*per_cpu_ptr(comp->stream, cpu) = zstrm;
	return 0;
}

int zcomp_cpu_dead(unsigned int cpu, struct hlist_node *node)
{
	struct zcomp *comp = hlist_entry(node, struct zcomp, node);
	struct zcomp_strm *zstrm;

	zstrm = *per_cpu_ptr(comp->stream, cpu);
	if (!IS_ERR_OR_NULL(zstrm))
		zcomp_strm_free(comp, zstrm);
	*per_cpu_ptr(comp->stream, cpu) = NULL;
	return 0;
}

static int zcomp_init(struct zcomp *comp)
{
	int ret;

	comp->stream = alloc_percpu(struct zcomp_strm *);
	if (!comp->stream)
		return -ENOMEM;

	ret = cpuhp_state_add_instance(CPUHP_ZCOMP_PREPARE, &comp->node);
	if (ret < 0)
		goto cleanup;
	return 0;

cleanup:
	free_percpu(comp->stream);
	return ret;
}

void zcomp_destroy(struct zcomp *comp)
{
	cpuhp_state_remove_instance(CPUHP_ZCOMP_PREPARE, &comp->node);
	if (comp->ops)
		comp->ops->release_params(comp->params);
	free_percpu(comp->stream);
	kfree(comp);
}

/*
 * search available compressors for requested algorithm.
 * allocate new zcomp and initialize it. return compressing
 * backend pointer or ERR_PTR if things went bad. ERR_PTR(-EINVAL)
 * if requested algorithm is not supported, ERR_PTR(-ENOMEM) in
 * case of allocation error, or any other error potentially
 * returned by zcomp_init().
 */
struct zcomp *zcomp_create(const char *compress)
{
	struct zcomp *comp;
	int error;

	if (!zcomp_available_algorithm(compress))
		return ERR_PTR(-EINVAL);

	comp = kzalloc(sizeof(struct zcomp), GFP_KERNEL);
	if (!comp)
		return ERR_PTR(-ENOMEM);

	comp->name = compress;
	error = zcomp_init(comp);
	if (error) {
		kfree(comp);
		return ERR_PTR(error);
	}
	return comp;
}

struct zcomp *zcomp_create_with_ops(const char *alg, struct zcomp_params *params)
{
	struct zcomp *comp;
	int error;

	comp = kzalloc(sizeof(struct zcomp), GFP_KERNEL);
	if (!comp)
		return ERR_PTR(-ENOMEM);

	comp->ops = lookup_backend_ops(alg);
	if (!comp->ops) {
		kfree(comp);
		return ERR_PTR(-EINVAL);
	}
	comp->name = alg;

	error = zcomp_init(comp);
	if (error) {
		kfree(comp);
		return ERR_PTR(error);
	}

	if (params) {
		comp->params = params;
		error = comp->ops->setup_params(params);
		if (error) {
			zcomp_destroy(comp);
			return ERR_PTR(error);
		}
	}

	return comp;
}
