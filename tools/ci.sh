#!/bin/bash
# This file is part of the OpenMV project.
#
# Copyright (c) 2024 Ibrahim Abdelkader <iabdalkader@openmv.io>
# Copyright (c) 2024 Kwabena W. Agyeman <kwagyeman@openmv.io>
#
# This work is licensed under the MIT license, see the file LICENSE for details.

# Install ARM GCC.
########################################################################################
TFLM_REPO_PATH=tflite-micro
ETHOSU_DRIVER_URL="https://gitlab.arm.com/artificial-intelligence/ethos-u/ethos-u-core-driver.git"
ETHOSU_DRIVER_TAG=26.08
ETHOSU_DRIVER_PATH=${TFLM_REPO_PATH}/tensorflow/lite/micro/tools/make/downloads/ethos_u_core_driver
TOOLCHAIN_PATH=${HOME}/cache/gcc
export PATH=${TOOLCHAIN_PATH}/bin:${PATH}
TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/14.3.rel1/binrel/arm-gnu-toolchain-14.3.rel1-x86_64-arm-none-eabi.tar.xz"

ci_install_arm_gcc() {
    mkdir -p ${TOOLCHAIN_PATH}
    wget --no-check-certificate -O - ${TOOLCHAIN_URL} | tar --strip-components=1 -Jx -C ${TOOLCHAIN_PATH}
    export PATH=${TOOLCHAIN_PATH}/bin:${PATH}
    arm-none-eabi-gcc --version
}

# Update Submodules.
########################################################################################
ci_update_submodules() {
    git submodule update --init --depth=1 --no-single-branch
}

# Clone the Ethos-U core driver into TFLM's download path, which skips its download.
########################################################################################
ci_clone_ethosu_driver() {
    git clone --depth=1 --branch ${ETHOSU_DRIVER_TAG} ${ETHOSU_DRIVER_URL} ${ETHOSU_DRIVER_PATH}
}

# Apply TFLM patches.
########################################################################################
ci_apply_patches() {
    for patch in patches/*.patch; do
        git -C ${TFLM_REPO_PATH} apply -v ../${patch}
    done
}

# Build Targets.
########################################################################################
ci_build_target() {
    TARGET_NAME=${1}
    TARGET_ARCH=${2}
    TARGET_KERNEL=${3}
    TARGET_COPROC=${4}
    TARGET_ARGS="${5}"
    TARGET_BUILD=${6}

    # CMSIS-NN is provided by the firmware. Setting CMSIS_NN_LIBS stops TFLM from
    # building the CMSIS-NN sources into the library (only used to link TFLM's own
    # binaries). The CMSIS and CMSIS-NN paths must be set with it, and are set to
    # the default download paths so the headers are still downloaded and used.
    EXTERNAL_LIBS_ARGS=""
    if [ "${TARGET_KERNEL}" == "cmsis_nn" ]; then
        EXTERNAL_LIBS_ARGS="CMSIS_NN_LIBS=none CMSIS_PATH=\$(DOWNLOADS_DIR)/cmsis CMSIS_NN_PATH=\$(DOWNLOADS_DIR)/cmsis_nn"
    fi

    # The Ethos-U core driver is also provided by the firmware. Setting ETHOSU_DRIVER_LIBS
    # stops TFLM from building the driver sources into the library (the headers are
    # still used).
    if [ "${TARGET_COPROC}" == "ethos_u" ]; then
        EXTERNAL_LIBS_ARGS="${EXTERNAL_LIBS_ARGS} ETHOSU_DRIVER_LIBS=none"
    fi

    pushd ${TFLM_REPO_PATH}
echo "make -j$(nproc) -f tensorflow/lite/micro/tools/make/Makefile \
TARGET=cortex_m_generic TARGET_ARCH=${TARGET_ARCH} CO_PROCESSOR=${TARGET_COPROC} \
${TARGET_ARGS} ${EXTERNAL_LIBS_ARGS} OPTIMIZED_KERNEL_DIR=${TARGET_KERNEL} CORE_OPTIMIZATION_LEVEL=-O2 \
KERNEL_OPTIMIZATION_LEVEL=-O2 THIRD_PARTY_KERNEL_OPTIMIZATION_LEVEL=-O2 \
TARGET_TOOLCHAIN_ROOT=${TOOLCHAIN_PATH}/bin/ TARGET_TOOLCHAIN_PREFIX=arm-none-eabi- \
BUILD_TYPE=${TARGET_BUILD} MICROLITE_LIB_NAME=libtflm.a microlite"
    
    make -j$(nproc) -f tensorflow/lite/micro/tools/make/Makefile \
         TARGET=cortex_m_generic TARGET_ARCH=${TARGET_ARCH} CO_PROCESSOR=${TARGET_COPROC} \
         ${TARGET_ARGS} ${EXTERNAL_LIBS_ARGS} OPTIMIZED_KERNEL_DIR=${TARGET_KERNEL} CORE_OPTIMIZATION_LEVEL=-O2 \
         KERNEL_OPTIMIZATION_LEVEL=-O2 THIRD_PARTY_KERNEL_OPTIMIZATION_LEVEL=-O2 \
         TARGET_TOOLCHAIN_ROOT=${TOOLCHAIN_PATH}/bin/ TARGET_TOOLCHAIN_PREFIX=arm-none-eabi- \
         BUILD_TYPE=${TARGET_BUILD} MICROLITE_LIB_NAME=libtflm.a microlite
    popd
    mv ${TFLM_REPO_PATH}/gen/*/lib/libtflm.a libtflm-${TARGET_NAME}-${TARGET_BUILD}.a
}

# Build Headers.
########################################################################################
ci_build_headers() {
    TARGET_NAME=${1}
    TARGET_ARCH=${2}
    TARGET_KERNEL=${3}
    TARGET_COPROC=${4}
    TARGET_ARGS="${5}"
    TARGET_BUILD=${6}

    pushd ${TFLM_REPO_PATH}
    python3 tensorflow/lite/micro/tools/project_generation/create_tflm_tree.py --makefile_options="TARGET=cortex_m_generic TARGET_ARCH=${TARGET_ARCH} CO_PROCESSOR=${TARGET_COPROC} ${TARGET_ARGS} OPTIMIZED_KERNEL_DIR=${TARGET_KERNEL} TARGET_TOOLCHAIN_ROOT=${TOOLCHAIN_PATH}/bin/ TARGET_TOOLCHAIN_PREFIX=arm-none-eabi- BUILD_TYPE=${TARGET_BUILD}" headers
    popd
    mv ${TFLM_REPO_PATH}/headers ${TARGET_NAME}-headers

    # CMSIS-NN and the Ethos-U core driver are provided by the firmware.
    rm -rf ${TARGET_NAME}-headers/third_party/cmsis_nn
    rm -rf ${TARGET_NAME}-headers/third_party/ethos_u_core_driver
}
