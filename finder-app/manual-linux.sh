#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
    echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
    git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- defconfig
    make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- all
    make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- modules
    make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- dtbs
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/Image

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
    echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

mkdir -p "$OUTDIR"/rootfs


cd "$OUTDIR"/rootfs
mkdir -p bin sbin etc proc sys dev lib lib64 tmp usr var home
mkdir -p usr/bin usr/lib usr/sbin
mkdir -p var/log
cd "$OUTDIR"

if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    make distclean
    make defconfig
else
    cd busybox
fi

make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make CONFIG_PREFIX="$OUTDIR"/rootfs ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

cd ${OUTDIR}/rootfs

echo "Library dependencies"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"


cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image.gz ${OUTDIR}/rootfs/zImage

cp $(aarch64-none-linux-gnu-gcc --print-sysroot)/lib/ld-linux-aarch64.so.1 ${OUTDIR}/rootfs/lib
cp $(aarch64-none-linux-gnu-gcc --print-sysroot)/lib64/libm.so.6 ${OUTDIR}/rootfs/lib64
cp $(aarch64-none-linux-gnu-gcc --print-sysroot)/lib64/libresolv.so.2 ${OUTDIR}/rootfs/lib64
cp $(aarch64-none-linux-gnu-gcc --print-sysroot)/lib64/libc.so.6 ${OUTDIR}/rootfs/lib64


sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 666 dev/console c 5 1

cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=aarch64-none-linux-gnu-

cp writer  ${OUTDIR}/rootfs/home
cp autorun-qemu.sh  ${OUTDIR}/rootfs/home
cp finder-test.sh  ${OUTDIR}/rootfs/home
cp finder.sh  ${OUTDIR}/rootfs/home

mkdir -p ${OUTDIR}/rootfs/home/conf
cp -R ../conf/*  ${OUTDIR}/rootfs/home/conf

cd ${OUTDIR}
sudo chown -R root:root rootfs

cd ${OUTDIR}/rootfs
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
cd ${OUTDIR}
gzip -f initramfs.cpio
