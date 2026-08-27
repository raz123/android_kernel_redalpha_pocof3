# SPDX-License-Identifier: GPL-2.0-only

# auto-detect subdirs
ifeq ($(CONFIG_ARCH_KONA), y)
include $(srctree)/techpack/camera-xiaomi/config/konacamera.conf
endif

ifeq ($(CONFIG_ARCH_LITO), y)
include $(srctree)/techpack/camera-xiaomi/config/litocamera.conf
endif

ifeq ($(CONFIG_ARCH_BENGAL), y)
include $(srctree)/techpack/camera-xiaomi/config/bengalcamera.conf
endif

ifeq ($(CONFIG_ARCH_KONA), y)
LINUXINCLUDE    += \
		-include $(srctree)/techpack/camera-xiaomi/config/konacameraconf.h
endif

ifeq ($(CONFIG_ARCH_LITO), y)
LINUXINCLUDE    += \
		-include $(srctree)/techpack/camera-xiaomi/config/litocameraconf.h
endif

ifeq ($(CONFIG_ARCH_BENGAL), y)
LINUXINCLUDE    += \
		-include $(srctree)/techpack/camera-xiaomi/config/bengalcameraconf.h
endif

ifdef CONFIG_SPECTRA_CAMERA
# Use USERINCLUDE when you must reference the UAPI directories only.
USERINCLUDE     += \
                -I$(srctree)/techpack/camera-xiaomi/include/uapi

# Use LINUXINCLUDE when you must reference the include/ directory.
# Needed to be compatible with the O= option
LINUXINCLUDE    += \
                -I$(srctree)/techpack/camera-xiaomi/include/uapi \
                -I$(srctree)/techpack/camera-xiaomi/include \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_cdm \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_core \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_cpas \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_cust \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_fd \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_icp \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_isp \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_jpeg \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_lrme \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_req_mgr \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_sensor_module \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_smmu \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_sync \
                -I$(srctree)/techpack/camera-xiaomi/drivers/cam_utils
obj-y += drivers/
else
$(info Target not found)
endif
