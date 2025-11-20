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
    
    make ARCH=arm64 mrproper
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- defconfig
    make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- all
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- modules
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- dtbs
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/Image

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
    echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm -rf ${OUTDIR}/rootfs
fi

# Create necessary base directories
echo "Creating root filesystem directory structure..."
mkdir -p ${OUTDIR}/rootfs/bin
mkdir -p ${OUTDIR}/rootfs/sbin
mkdir -p ${OUTDIR}/rootfs/etc
mkdir -p ${OUTDIR}/rootfs/lib
mkdir -p ${OUTDIR}/rootfs/lib64
mkdir -p ${OUTDIR}/rootfs/dev
mkdir -p ${OUTDIR}/rootfs/proc
mkdir -p ${OUTDIR}/rootfs/sys
mkdir -p ${OUTDIR}/rootfs/tmp
mkdir -p ${OUTDIR}/rootfs/usr/bin
mkdir -p ${OUTDIR}/rootfs/usr/sbin
mkdir -p ${OUTDIR}/rootfs/usr/lib
mkdir -p ${OUTDIR}/rootfs/var/log
mkdir -p ${OUTDIR}/rootfs/home
mkdir -p ${OUTDIR}/rootfs/home/conf

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
    echo "Cloning busybox..."
    git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
else
    cd busybox
fi

# Configure busybox
echo "Configuring busybox..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

# Make and install busybox
echo "Building busybox..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -j4
echo "Installing busybox to rootfs..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} \
    CONFIG_PREFIX=${OUTDIR}/rootfs install

echo "Checking library dependencies..."
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "program interpreter" || true
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library" || true

# Add library dependencies to rootfs
echo "Finding sysroot..."
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
echo "SYSROOT is: ${SYSROOT}"

if [ ! -d "${SYSROOT}" ]; then
    echo "ERROR: SYSROOT directory not found: ${SYSROOT}"
    exit 1
fi

# Copy interpreter
echo "Copying program interpreter..."
if [ -f ${SYSROOT}/lib/ld-linux-aarch64.so.1 ]; then
    cp -v ${SYSROOT}/lib/ld-linux-aarch64.so.1 ${OUTDIR}/rootfs/lib/
else
    echo "WARNING: Program interpreter not found at ${SYSROOT}/lib/ld-linux-aarch64.so.1"
    # Try alternative location
    find ${SYSROOT} -name "ld-linux-aarch64.so.1" -exec cp -v {} ${OUTDIR}/rootfs/lib/ \;
fi

# Copy libraries
echo "Copying required libraries..."
LIBS=$(${CROSS_COMPILE}readelf -d ${OUTDIR}/rootfs/bin/busybox 2>/dev/null | grep "NEEDED" | awk '{print $5}' | tr -d '[]')

if [ -n "$LIBS" ]; then
    echo "Found libraries: $LIBS"
    for lib in $LIBS; do
        echo "Looking for $lib..."
        LIB_PATH=$(find ${SYSROOT} -name "$lib" -type f | head -n 1)
        if [ -n "$LIB_PATH" ]; then
            echo "Copying $LIB_PATH to rootfs/lib/"
            cp -v "$LIB_PATH" ${OUTDIR}/rootfs/lib/
        else
            echo "WARNING: Library $lib not found in sysroot"
        fi
    done
else
    echo "No dynamic libraries needed (static build)"
fi

# Copy lib64 if it exists
if [ -d ${SYSROOT}/lib64 ]; then
    echo "Copying lib64 directory..."
    cp -av ${SYSROOT}/lib64/*.so* ${OUTDIR}/rootfs/lib64/ 2>/dev/null || true
fi

# Verify dependencies
echo "Verifying library dependencies..."
${CROSS_COMPILE}readelf -d ${OUTDIR}/rootfs/bin/busybox 2>/dev/null | grep NEEDED || echo "Static binary - no dependencies"

# Make device nodes
echo "Creating device nodes..."
sudo mknod -m 0666 ${OUTDIR}/rootfs/dev/null c 1 3
sudo mknod -m 0600 ${OUTDIR}/rootfs/dev/console c 5 1

# Clean and build the writer utility
echo "Building writer utility..."
cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE} all

# Copy the finder related scripts and executables to the /home directory
echo "Copying finder application files to rootfs..."
sudo cp -fv writer ${OUTDIR}/rootfs/home/
sudo cp -fv finder.sh ${OUTDIR}/rootfs/home/
sudo cp -fv finder-test.sh ${OUTDIR}/rootfs/home/
sudo cp -fv autorun-qemu.sh ${OUTDIR}/rootfs/home/
sudo cp -fv conf/username.txt ${OUTDIR}/rootfs/home/conf/
sudo cp -fv conf/assignment.txt ${OUTDIR}/rootfs/home/conf/

# Set proper permissions
echo "Setting permissions..."
sudo chown root:root ${OUTDIR}/rootfs/bin/busybox
sudo chmod 4755 ${OUTDIR}/rootfs/bin/busybox

# Make sure sh exists
if [ -f ${OUTDIR}/rootfs/bin/sh ]; then
    sudo chmod 755 ${OUTDIR}/rootfs/bin/sh
fi

# Create init symlink
echo "Creating init symlink..."
cd ${OUTDIR}/rootfs
sudo ln -sf bin/busybox init
sudo chmod 755 init

# Verify home directory contents before creating archive
echo "=========================================="
echo "Verifying /home directory contents:"
ls -la ${OUTDIR}/rootfs/home/
echo "Contents of /home/conf:"
ls -la ${OUTDIR}/rootfs/home/conf/
echo "=========================================="

# Chown the root directory and create initramfs
echo "Creating initramfs archive..."
cd ${OUTDIR}/rootfs
sudo find . -print0 | sudo cpio --null -ov --format=newc > ${OUTDIR}/initramfs.cpio
echo "CPIO archive created successfully"

# Create initramfs.cpio.gz
echo "Compressing initramfs..."
cd ${OUTDIR}
gzip -f initramfs.cpio
echo "Compression complete"

echo "=========================================="
echo "Build complete!"
echo "Image: ${OUTDIR}/Image"
echo "Initramfs: ${OUTDIR}/initramfs.cpio.gz"
echo "=========================================="
echo "Verifying /home in final archive:"
gunzip -c ${OUTDIR}/initramfs.cpio.gz | cpio -t 2>/dev/null | grep "^home" | head -20
echo "=========================================="