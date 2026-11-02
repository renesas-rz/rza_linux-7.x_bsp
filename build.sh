#!/bin/bash
# RZ/A2M Linux 7.x BSP build script
#
#   ./build.sh config [rza2mevb]     select board, write output/config.txt
#   ./build.sh env                   print the commands to set up the build environment
#   ./build.sh buildroot [target]    toolchain + rootfs (default: all; also menuconfig, savedefconfig)
#   ./build.sh kernel [target]       Linux (default: xipImage + dtbs; also menuconfig, savedefconfig, ...)
#   ./build.sh u-boot [target]       U-Boot (default: u-boot.bin; also menuconfig, savedefconfig)
#   ./build.sh images                collect the images in output/images
#   ./build.sh patches [kernel|u-boot]  export a branch to patches-kernel/ or patches-u-boot/
#
set -e
ROOTDIR=$(cd "$(dirname "$0")" && pwd)
OUT=$ROOTDIR/output
CFG=$OUT/config.txt

KERNEL_VER=${KERNEL_VER:-7.3}
KERNEL_BRANCH=rza2m-7.x
BR_BRANCH=${BR_BRANCH:-2026.02.x}
BR_DIR=$OUT/buildroot-$BR_BRANCH
LINUX_DIR=$OUT/linux-$KERNEL_VER
UBOOT_VER=${UBOOT_VER:-2026.10}
UBOOT_BRANCH=rza2m-u-boot
UBOOT_DIR=$OUT/u-boot-$UBOOT_VER

banner() { echo; echo "============== $* =============="; echo "dir: $ROOTDIR"; }
need_config() { [ -f "$CFG" ] || { echo "Run ./build.sh config first"; exit 1; }; . "$CFG"; }

cross() {
  local gcc
  gcc=$(ls "$BR_DIR"/output/host/bin/arm-*-gcc 2>/dev/null | grep -v -- '-gcc-' | head -1)
  [ -n "$gcc" ] || { echo "No toolchain: run ./build.sh buildroot first"; exit 1; }
  echo "${gcc%gcc}"
}

do_config() {
  local board=${1:-rza2mevb}
  [ -d "$ROOTDIR/board/$board" ] || { echo "Unknown board: $board"; exit 1; }
  mkdir -p "$OUT"
  cat > "$CFG" <<CFGEOF
BOARD=$board
SOC=RZA2M
DLRAM_ADDR=0x40000000
UBOOT_ADDR=0x20000000
DTB_ADDR=0x200C0000
KERNEL_ADDR=0x20200000
ROOTFS_ADDR=0x20800000
QSPI=SINGLE
KERNEL_VER=$KERNEL_VER
BR_BRANCH=$BR_BRANCH
CFGEOF
  cat "$CFG"
}

do_env() {
  echo "export ROOTDIR=$ROOTDIR ; source \$ROOTDIR/setup_env.sh"
}

do_buildroot() {
  need_config
  if [ ! -d "$BR_DIR" ]; then
    git clone -b "$BR_BRANCH" https://gitlab.com/buildroot.org/buildroot.git "$BR_DIR"
  fi
  cd "$BR_DIR"
  local def=$ROOTDIR/board/$BOARD/buildroot_defconfig
  if [ ! -f .config ]; then
    make BR2_DEFCONFIG="$def" defconfig
  fi
  sed -i "s|^BR2_ROOTFS_OVERLAY=.*|BR2_ROOTFS_OVERLAY=\"$ROOTDIR/board/$BOARD/overlay\"|" .config
  grep -q '^BR2_ROOTFS_OVERLAY=' .config || \
    echo "BR2_ROOTFS_OVERLAY=\"$ROOTDIR/board/$BOARD/overlay\"" >> .config
  case "$1" in
    savedefconfig)
      make savedefconfig BR2_DEFCONFIG="$def"
      sed -i '/^BR2_ROOTFS_OVERLAY=/d' "$def"
      echo "Saved $def" ;;
    "" | all) make -j"$(nproc)"; ls -lh output/images/ ;;
    *) make "$@" ;;
  esac
  banner "Buildroot Build Successful"
}

do_kernel() {
  need_config
  if [ ! -d "$LINUX_DIR" ]; then
    git clone --depth 1 -b "v$KERNEL_VER" \
      https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "$LINUX_DIR"
    cd "$LINUX_DIR"
    git checkout -b "$KERNEL_BRANCH"
    ls "$ROOTDIR"/patches-kernel/*.patch >/dev/null 2>&1 && \
      git -c user.name="${GIT_NAME:-RZ/A2M BSP}" -c user.email="${GIT_EMAIL:-bsp@localhost}" \
        am "$ROOTDIR"/patches-kernel/*.patch
  fi
  local CC; CC=$(cross)
  cd "$LINUX_DIR"
  local K="make ARCH=arm CROSS_COMPILE=$CC"
  [ -f .config ] || $K rza2m_xip_defconfig
  case "$1" in
    "" | xipImage)
      $K -j"$(nproc)" xipImage dtbs
      ls -lh arch/arm/boot/xipImage arch/arm/boot/dts/renesas/r7s9210-rza2mevb.dtb ;;
    savedefconfig)
      $K savedefconfig
      cp defconfig arch/arm/configs/rza2m_xip_defconfig
      echo "Updated arch/arm/configs/rza2m_xip_defconfig: commit it on $KERNEL_BRANCH, then ./build.sh patches" ;;
    *) $K "$@" ;;
  esac
  banner "Kernel Build Successful"
}

do_uboot() {
  need_config
  if [ ! -d "$UBOOT_DIR" ]; then
    git clone --depth 1 -b "v$UBOOT_VER" https://source.denx.de/u-boot/u-boot.git "$UBOOT_DIR"
    cd "$UBOOT_DIR"
    git checkout -b "$UBOOT_BRANCH"
    git -c user.name="${GIT_NAME:-RZ/A2M BSP}" -c user.email="${GIT_EMAIL:-bsp@localhost}" \
      am "$ROOTDIR"/patches-u-boot/*.patch
  fi
  local CC; CC=$(cross)
  cd "$UBOOT_DIR"
  local U="make CROSS_COMPILE=$CC"
  [ -f .config ] || $U "${BOARD}_defconfig"
  case "$1" in
    "")
      $U -j"$(nproc)"
      ls -lh u-boot.bin ;;
    savedefconfig)
      $U savedefconfig
      cp defconfig "configs/${BOARD}_defconfig"
      echo "Updated configs/${BOARD}_defconfig: commit it on $UBOOT_BRANCH, then ./build.sh patches u-boot" ;;
    *) $U "$@" ;;
  esac
  banner "U-Boot Build Successful"
}

do_images() {
  need_config
  local I=$OUT/images
  mkdir -p "$I"
  cp "$LINUX_DIR/arch/arm/boot/dts/renesas/r7s9210-rza2mevb.dtb" "$I/r7s9210-rza2mevb.dtb.bin"
  cp "$LINUX_DIR/arch/arm/boot/xipImage"                         "$I/xipImage.bin"
  cp "$BR_DIR/output/images/rootfs.cramfs"                       "$I/rootfs.cramfs.bin"
  [ -f "$UBOOT_DIR/u-boot.bin" ] || { echo "No U-Boot: run ./build.sh u-boot first"; exit 1; }
  cp "$UBOOT_DIR/u-boot.bin"                                     "$I/u-boot.bin"
  local max=$(( ROOTFS_ADDR - KERNEL_ADDR )) size
  size=$(stat -c %s "$I/xipImage.bin")
  [ "$size" -le "$max" ] || echo "WARNING: xipImage ($size bytes) overlaps the rootfs at $ROOTFS_ADDR"
  cd "$I" && ls -lh ./*.bin && md5sum ./*.bin
}

do_patches() {
  case "${1:-kernel}" in
    kernel)
      cd "$LINUX_DIR"
      rm -f "$ROOTDIR"/patches-kernel/*.patch
      git format-patch "v$KERNEL_VER..$KERNEL_BRANCH" -o "$ROOTDIR/patches-kernel" ;;
    u-boot)
      cd "$UBOOT_DIR"
      rm -f "$ROOTDIR"/patches-u-boot/*.patch
      git format-patch "v$UBOOT_VER..$UBOOT_BRANCH" -o "$ROOTDIR/patches-u-boot" ;;
    *) echo "Usage: ./build.sh patches [kernel|u-boot]"; exit 1 ;;
  esac
}

cmd=$1; shift || true
case "$cmd" in
  config)    do_config "$@" ;;
  env)       do_env ;;
  buildroot) do_buildroot "$@" ;;
  kernel)    do_kernel "$@" ;;
  u-boot)    do_uboot "$@" ;;
  images)    do_images ;;
  patches)   do_patches "$@" ;;
  *) sed -n '2,/^set -e/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
