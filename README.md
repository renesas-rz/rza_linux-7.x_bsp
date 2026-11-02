# RZ/A2M Linux 7.x BSP

Linux BSP for the RZ/A2M EVK based on mainline Linux 7.3. The kernel runs in place (XIP) from QSPI flash, the root file system is cramfs XIP, and system RAM is the 8 MB HyperRAM (no DDR).

| Item | Value |
|---|---|
| Kernel | Mainline v7.3 + `patches-kernel/` |
| Root file system | cramfs XIP (Buildroot) |
| Buildroot | 2026.02.x (GCC 15, glibc) |
| U-Boot | Mainline v2026.10 + `patches-u-boot/` (`run xha_boot`) |
| Build host | Docker, Ubuntu 22.04 |

## Contents

| Path | Content |
|---|---|
| `build.sh` | Build script |
| `setup_env.sh` | Environment for building by hand (`ARCH`, `CROSS_COMPILE`, `BUILDROOT_DIR`) |
| `board/rza2mevb/buildroot_defconfig` | Buildroot config: Cortex-A9, glibc, BusyBox, cramfs XIP |
| `board/rza2mevb/overlay/` | Files copied into the rootfs as is (empty in the BSP, not in git) |
| `patches-kernel/` | Kernel patch series on top of `v7.3` |
| `patches-u-boot/` | U-Boot patch series on top of `v2026.10` |
| `docker/Dockerfile` | Build container |
| `output/` | Downloaded sources and build output (not in git) |

### Kernel patches

`patches-kernel/` holds 11 patches on top of v7.3; each file name gives the change.

### U-Boot patches

0001 to 0007 are the RZ/A2 series by Magnus Damm, posted to the U-Boot list (v3, not merged upstream) and rebased on v2026.10. 0008 to 0013 add the RZ/A2M EVK board support.

## 1. Build container

On the host (Ubuntu 22.04 with Docker). Clone the BSP to any location; the container sees it as `/work/rza_linux-7.x_bsp`.

```
git clone https://github.com/renesas-rz/rza_linux-7.x_bsp.git
cd rza_linux-7.x_bsp
docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t rza2m-bsp7:22.04 docker
docker run -it --name rza2m7 -v "$PWD":/work/rza_linux-7.x_bsp rza2m-bsp7:22.04
```

The container user gets your UID and GID, so the files it writes belong to you on the host.

| Task | Command (host) |
|---|---|
| Enter again after `exit` | `docker start -ai rza2m7` |
| Second shell | `docker exec -it rza2m7 bash` |
| Root shell | `docker exec -u root -it rza2m7 bash` |
| Recreate | `docker rm -f rza2m7`, then the `docker run` line from the BSP folder |

All following steps run in the container, in `/work/rza_linux-7.x_bsp`.

## 2. Build

| Step | Command | Result |
|---|---|---|
| Select board | `./build.sh config rza2mevb` | `output/config.txt` |
| Toolchain and rootfs | `./build.sh buildroot` | `output/buildroot-2026.02.x/` (20 to 60 min the first time) |
| Kernel | `./build.sh kernel` | Clones v7.3, applies `patches-kernel/` on branch `rza2m-7.x`, builds `xipImage` and DTB |
| U-Boot | `./build.sh u-boot` | Clones v2026.10, applies `patches-u-boot/` on branch `rza2m-u-boot`, builds `u-boot.bin` |
| Images | `./build.sh images` | `output/images/` |

`output/config.txt`:

| Key | Value |
|---|---|
| BOARD | rza2mevb |
| SOC | RZA2M |
| DLRAM_ADDR | 0x40000000 |
| UBOOT_ADDR | 0x20000000 |
| DTB_ADDR | 0x200C0000 |
| KERNEL_ADDR | 0x20200000 |
| ROOTFS_ADDR | 0x20800000 |
| KERNEL_VER | 7.3 |
| BR_BRANCH | 2026.02.x |

Other targets:

| Command | Purpose |
|---|---|
| `./build.sh buildroot menuconfig` / `savedefconfig` | Change the Buildroot config and save it to `board/rza2mevb/buildroot_defconfig` |
| `./build.sh kernel menuconfig` / `savedefconfig` | Change the kernel config; `savedefconfig` updates `arch/arm/configs/rza2m_xip_defconfig` |
| `./build.sh kernel rza2m_xip_defconfig` | Reload the saved kernel config |
| `./build.sh patches` | Export branch `rza2m-7.x` to `patches-kernel/` after committing a kernel change |
| `./build.sh patches u-boot` | Export branch `rza2m-u-boot` to `patches-u-boot/` after committing a U-Boot change |
| `./build.sh u-boot menuconfig` / `savedefconfig` | Change the U-Boot config; `savedefconfig` updates `configs/rza2mevb_defconfig` |
| `./build.sh env` | Print the command for `setup_env.sh` |

This gives a BSP that boots to a login prompt, with the display (`/dev/fb0`), D/AVE 2D (`/dev/dave2d`) and touch (`/dev/input/event0`) drivers.

Kernel changes: commit them on branch `rza2m-7.x` in `output/linux-7.3`, then `./build.sh patches`.

## 3. Images

`./build.sh images` collects the images in `output/images/`:

| File | QSPI address | Area |
|---|---|---|
| `u-boot.bin` | 0x20000000 | 512 KB |
| `r7s9210-rza2mevb.dtb.bin` | 0x200C0000 | 64 KB |
| `xipImage.bin` | 0x20200000 | 6 MB |
| `rootfs.cramfs.bin` | 0x20800000 | 16 MB |

## 4. Boot

U-Boot boots Linux by itself after a 3 s countdown (`bootcmd=run xha_boot`). Press a key to stop at the U-Boot prompt; `run xha_boot` boots by hand:

| Step of `xha_boot` | Command |
|---|---|
| QSPI to quad I/O DDR XIP read mode | `qspi single a4 d4 ddr` |
| Copy the DTB to HyperRAM | `cp.b 0x200C0000 0x40300000 10000` |
| Start the XIP kernel | `bootx 0x20200000 0x40300000` |

A board that still has an older environment saved in flash keeps it; `env default -a; saveenv` loads the new defaults.

Console: SCIF4 on CN5 (USB-serial "UART"), 115200 baud. Login `root`, no password.

## Notes

| Topic | Detail |
|---|---|
| XIP | No Kconfig patch on 7.3: `EXPERT=y`, `ARCH_MULTIPLATFORM=n`, `ARM_PATCH_PHYS_VIRT=n`, `XIP_PHYS_ADDR=0x20200000`, `PHYS_OFFSET=0x40000000` |
| Kernel command line | From the DTS (`chosen/bootargs`): `root=mtd:rootfs_xipcramfs rootfstype=cramfs console=ttySC0,115200` |
| Early debug | `DEBUG_LL` on SCIF4 is still enabled in the defconfig for bring-up |
| Kernel size limit | `xipImage` must stay below 6 MB (`./build.sh images` warns) |
