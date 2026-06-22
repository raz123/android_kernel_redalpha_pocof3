// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * LZ4 compression backend with dictionary support for zram.
 *
 * Ported from EmanuelCN's dictionary optimization implementation.
 * Key optimization: template stream pre-processing via LZ4_loadDict
 * eliminates per-compression LZ4_loadDict overhead, yielding 3-6x
 * speedup when using dictionaries.
 *
 * When a dictionary is configured (params->dict/dict_sz), this backend:
 *   - Loads the dict once into a template LZ4_stream_t at setup_params time
 *   - On each compress: memcpy the template stream, then compress_fast_continue
 *   - On each decompress: LZ4_setStreamDecode + LZ4_decompress_safe_continue
 *
 * When no dictionary is configured, falls back to plain LZ4_compress_fast /
 * LZ4_decompress_safe.
 */

#include <linux/kernel.h>
#include <linux/lz4.h>
#include <linux/slab.h>
#include <linux/vmalloc.h>

#include "backend_lz4.h"
#ifndef LZ4_ACCELERATION_DEFAULT
#define LZ4_ACCELERATION_DEFAULT 1
#endif

struct lz4_ctx {
	void *mem;

	LZ4_streamDecode_t *dstrm;
	LZ4_stream_t *cstrm;
};

static void lz4_release_params(struct zcomp_params *params)
{
	LZ4_stream_t *dict_stream = params->drv_data;

	params->drv_data = NULL;
	if (!dict_stream)
		return;

	kfree(dict_stream);
}

static int lz4_setup_params(struct zcomp_params *params)
{
	LZ4_stream_t *dict_stream;
	int ret;

	if (params->drv_data)
		lz4_release_params(params);

	if (params->level == ZCOMP_PARAM_NO_LEVEL)
		params->level = LZ4_ACCELERATION_DEFAULT;

	if (!params->dict || !params->dict_sz)
		return 0;

	dict_stream = kzalloc(sizeof(*dict_stream), GFP_KERNEL);
	if (!dict_stream)
		return -ENOMEM;

	ret = LZ4_loadDict(dict_stream,
			   params->dict, params->dict_sz);
	if (ret != params->dict_sz) {
		kfree(dict_stream);
		return -EINVAL;
	}
	params->drv_data = dict_stream;

	return 0;
}

static void lz4_destroy(struct zcomp_ctx *ctx)
{
	struct lz4_ctx *zctx = ctx->context;

	if (!zctx)
		return;

	vfree(zctx->mem);
	kfree(zctx->dstrm);
	kfree(zctx->cstrm);
	kfree(zctx);
}

static int lz4_create(struct zcomp_params *params, struct zcomp_ctx *ctx)
{
	struct lz4_ctx *zctx;
	pr_err("lz4_create: params=%p, dict_sz=%zu\n", params, params ? params->dict_sz : 0);

	zctx = kzalloc(sizeof(*zctx), GFP_KERNEL);
	if (!zctx)
		return -ENOMEM;

	ctx->context = zctx;
	if (params->dict_sz == 0) {
		zctx->mem = vmalloc(LZ4_MEM_COMPRESS);
		if (!zctx->mem)
			goto error;
	} else {
		zctx->dstrm = kzalloc(sizeof(*zctx->dstrm), GFP_KERNEL);
		if (!zctx->dstrm)
			goto error;

		zctx->cstrm = kzalloc(sizeof(*zctx->cstrm), GFP_KERNEL);
		if (!zctx->cstrm)
			goto error;
	}

	return 0;

error:
	lz4_destroy(ctx);
	return -ENOMEM;
}

static int lz4_compress(struct zcomp_params *params, struct zcomp_ctx *ctx,
			struct zcomp_req *req)
{
	struct lz4_ctx *zctx = ctx->context;
	int ret;
	if (!zctx) { pr_err("lz4_compress: zctx is NULL\n"); return -EINVAL; }
	if (!zctx->mem) { pr_err("lz4_compress: zctx->mem is NULL\n"); return -EINVAL; }

	if (!zctx->cstrm) {
		ret = LZ4_compress_fast_extState(zctx->mem, req->src, req->dst,
					req->src_len, req->dst_len,
					params->level);
	} else {
		/* cstrm needs to be reset from the template each time */
		memcpy(zctx->cstrm, params->drv_data, sizeof(*zctx->cstrm));
		ret = LZ4_compress_fast_continue(zctx->cstrm, req->src,
						 req->dst, req->src_len,
						 req->dst_len, params->level);
	}
	if (!ret)
		return -EINVAL;
	req->dst_len = ret;
	return 0;
}

static int lz4_decompress(struct zcomp_params *params, struct zcomp_ctx *ctx,
			  struct zcomp_req *req)
{
	struct lz4_ctx *zctx = ctx->context;
	int ret;
	if (!zctx) { pr_err("lz4_decompress: zctx is NULL\n"); return -EINVAL; }

	if (!zctx->dstrm) {
		ret = LZ4_decompress_safe(req->src, req->dst, req->src_len,
					  req->dst_len);
	} else {
		/* dstrm needs to be reset from the raw dict each time */
		ret = LZ4_setStreamDecode(zctx->dstrm, params->dict,
					  params->dict_sz);
		if (!ret)
			return -EINVAL;
		ret = LZ4_decompress_safe_continue(zctx->dstrm, req->src,
						   req->dst, req->src_len,
						   req->dst_len);
	}
	if (ret < 0)
		return -EINVAL;
	return 0;
}

const struct zcomp_ops backend_lz4 = {
	.compress	= lz4_compress,
	.decompress	= lz4_decompress,
	.create_ctx	= lz4_create,
	.destroy_ctx	= lz4_destroy,
	.setup_params	= lz4_setup_params,
	.release_params	= lz4_release_params,
	.name		= "lz4",
};
