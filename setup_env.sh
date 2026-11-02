# Source this file: export ROOTDIR=<BSP folder> ; source $ROOTDIR/setup_env.sh
[ -n "$ROOTDIR" ] || { echo "Set ROOTDIR first"; return 1; }
[ -f "$ROOTDIR/output/config.txt" ] && . "$ROOTDIR/output/config.txt"
export ARCH=arm
export BUILDROOT_DIR=$(ls -d "$ROOTDIR"/output/buildroot-* 2>/dev/null | head -1)
GCC=$(ls "$BUILDROOT_DIR"/output/host/bin/arm-*-gcc 2>/dev/null | grep -v -- '-gcc-' | head -1)
if [ -n "$GCC" ]; then
  export CROSS_COMPILE=$(basename "${GCC%gcc}")
  export PATH="$BUILDROOT_DIR/output/host/bin:$PATH"
  echo "CROSS_COMPILE=$CROSS_COMPILE"
else
  echo "No toolchain yet: run ./build.sh buildroot"
fi
