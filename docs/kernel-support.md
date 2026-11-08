# Deferred kernel support for this PS Eye

Use this guide only after the camera attaches successfully with usbipd-win and its **actual** USB ID appears in WSL. Failure to attach or enumerate is a transport problem; rebuilding the camera driver does not fix it. Follow the main guide for attachment, capture, and preview.

These instructions target the environment observed during the initial investigation:

- Ubuntu 24.04.4, `x86_64`.
- `6.6.87.1-microsoft-standard-WSL2`.
- Modules and module versioning enabled; GSPCA core and V4L2 dependencies configured as modules.
- `CONFIG_USB_GSPCA_OV534` disabled and `gspca_ov534` unavailable.

If `uname -r` or `uname -m` changes, stop and select the matching Microsoft source tag and architecture again. These are not universal instructions for every WSL release or ARM64 machine.

## Choose the smallest change

Try a matching additional module first. This kernel already enables the necessary media infrastructure. Building a kernel image to obtain build artifacts does **not** mean you have to boot that image.

The [Linux GSPCA Kconfig](https://github.com/torvalds/linux/blob/master/drivers/media/usb/gspca/Kconfig) names `gspca_ov534` and its `VIDEO_DEV` / `USB_GSPCA` dependencies. GSPCA core selects the videobuf2 vmalloc backend. `uvcvideo` does not replace this driver.

A module must match the running kernel's source, architecture, release string, configuration affecting its ABI, and exported symbol versions. Ubuntu generic-kernel modules do not match this Microsoft WSL kernel. Matching `uname -r` and vermagic alone is insufficient.

Here `CONFIG_MODVERSIONS=y`, so a matching `Module.symvers` matters. The [Kbuild documentation](https://docs.kernel.org/kbuild/modules.html) explains that `modules_prepare` does not generate it; without matching artifacts, use a complete build. The source tag alone is not a substitute for those artifacts.

The installed compiler is GCC 13.3, while the running vendor kernel reports GCC 11.2 and binutils ld 2.37. An identical compiler version is not a blanket loading requirement, but compiler/configuration differences must be investigated if they change ABI or cause build/load failures. Keep compiler metadata in the build record, review configuration differences, and use the real loader's CRC checks. Never use force-vermagic, force-modversion, or other force-load options.

## Build and temporarily load only the missing module

Everything in this section runs in **WSL**. The source/build directory is separate from the project. Install build dependencies only when this path has been selected:

```bash
sudo apt update
sudo apt install build-essential flex bison dwarves libssl-dev libelf-dev cpio qemu-utils git
```

If compatible build dependencies are already installed, reuse them. `qemu-utils` is needed later for packaging a modules VHDX.
For the observed GCC 13 toolchain, install `gcc-13-plugin-dev` too if retaining
`CONFIG_GCC_PLUGINS=y`; this host's compiler plugin headers were not found.
Recheck that package against the compiler actually selected if using another GCC.

Pin the source to the [Microsoft 6.6.87.1 release](https://github.com/microsoft/WSL2-Linux-Kernel/releases/tag/linux-msft-wsl-6.6.87.1), rather than the moving `linux-msft-wsl-6.6.y` branch:

```bash
test "$(uname -r)" = 6.6.87.1-microsoft-standard-WSL2 || exit 1
test "$(uname -m)" = x86_64 || exit 1
mkdir -p "$HOME/pseye-kernel-build"
cd "$HOME/pseye-kernel-build"
git clone --depth 1 --branch linux-msft-wsl-6.6.87.1 \
  https://github.com/microsoft/WSL2-Linux-Kernel.git WSL2-Linux-Kernel-module
cd WSL2-Linux-Kernel-module
export LOCALVERSION=''
git rev-parse HEAD
gcc --version
ld --version
zcat /proc/config.gz > config.running
cp config.running .config
scripts/config --module USB_GSPCA_OV534
make olddefconfig
scripts/diffconfig config.running .config
make -s kernelrelease
```

Review the diff **before building**. The intended functional change is `USB_GSPCA_OV534: n -> m`. Compiler-generated metadata may differ. Do not silently accept unrelated configuration or ABI changes. Preserve the running `CONFIG_LOCALVERSION` and disable no existing compatibility/security settings just to bypass a failure.

Kbuild's extra `LOCALVERSION` is set to empty in this shell; the intended release
suffix comes from `.config`. Keep that environment when building and packaging.
The printed kernel release must be exactly `6.6.87.1-microsoft-standard-WSL2`.
Check the selected dependencies:

```bash
grep -E '^(CONFIG_(MODULES|MODVERSIONS|MEDIA_SUPPORT|MEDIA_CAMERA_SUPPORT|VIDEO_DEV|MEDIA_USB_SUPPORT|USB_GSPCA|USB_GSPCA_OV534|VIDEOBUF2_VMALLOC|USB|USBIP_CORE|USBIP_VHCI_HCD)=)' .config
```

With no matching prepared build tree and symbol file available, perform a complete build to produce the module and symbol versions. This can take substantial time and disk space; lower the job count if memory is constrained.

```bash
make -j"$(nproc)"
test -s Module.symvers
test "$(make -s kernelrelease)" = "$(uname -r)" || exit 1
modinfo -F vermagic drivers/media/usb/gspca/gspca_ov534.ko
modinfo -F vermagic gspca_main
modinfo -F depends drivers/media/usb/gspca/gspca_ov534.ko
```

The vermagic strings should agree. This is a useful check before the kernel's stronger symbol-version checks, not proof of compatibility by itself. Preserve the source tree, `config.running`, final `.config`, `Module.symvers`, and build log for reproducibility.

For this stock-kernel deployment, make a separate copy without split BTF debug
metadata. The build tested on this host passed the loader's symbol CRC checks,
but its BTF metadata referred to the regenerated kernel's type table rather than
the running vendor kernel's table and produced a BTF mismatch warning. Removing
these optional debug sections leaves executable code and module version checks
intact; keep the original module for the build record. Do not disable the running
kernel's BTF or other compatibility/security settings.

```bash
test ! -e gspca_ov534-stock.ko || exit 1
cp drivers/media/usb/gspca/gspca_ov534.ko gspca_ov534-stock.ko
objcopy --remove-section .BTF --remove-section .BTF.ext gspca_ov534-stock.ko
```

Keep the camera attached. Load the installed matching dependency modules, then load the additional driver by absolute path:

```bash
sudo modprobe gspca_main
sudo insmod "$PWD/gspca_ov534-stock.ko"
lsmod | grep -E 'gspca|videodev|videobuf'
lsusb -t
sudo dmesg | tail -n 100
ls -l /sys/class/video4linux
```

`modprobe gspca_main` handles its installed dependencies. Loading the new driver should probe an already attached matching camera. The USB driver's name can appear as `ov534`; its module is `gspca_ov534`.

Do not install anything persistently until this succeeds and the main guide's headless frame and 30-second capture checks pass. An `invalid module format` or symbol-version disagreement requires checking `dmesg`, source/configuration/toolchain differences, and matching artifacts. `Unknown symbol` also requires checking dependencies. A camera absent from `lsusb` still requires attachment troubleshooting.

For temporary rollback, close capture applications and run:

```bash
sudo rmmod gspca_ov534
```

Use `rmmod` for this temporary absolute-path load: `modprobe -r` may fail to
resolve a module that is not present in the installed module index. The manually
loaded module also disappears when the shared WSL VM shuts down.

## Persist a module that has passed the stock-kernel test

The observed module path appears to be supplied through a read-only WSL module mount; the diagnostic sandbox may also influence that view. Inspect it on the actual host before deployment:

```bash
readlink -f "/lib/modules/$(uname -r)"
findmnt -T "/lib/modules/$(uname -r)"
```

Do not overwrite the stock module tree. One reproducible option is a custom modules VHDX containing a copy of the existing matching tree plus the tested additional module. This keeps the Microsoft kernel image. It is suitable only if the installed WSL version supports `kernelModules` and the temporary stock-kernel load and capture tests passed.

In **WSL**, from the module build directory:

```bash
release=$(uname -r)
test "$(make -s kernelrelease)" = "$release" || exit 1
stock_module_dir=$(readlink -f "/lib/modules/$release")
stock_stage="$PWD/module-stage-stock"
test ! -e "$stock_stage" || exit 1
mkdir -p "$stock_stage/lib/modules/$release"
while IFS= read -r -d '' entry; do
  cp -a --no-preserve=ownership "$entry" "$stock_stage/lib/modules/$release/"
done < <(find "$stock_module_dir" -mindepth 1 -maxdepth 1 \
  ! -name lost+found ! -name rw ! -name build ! -name source -print0)
install -Dm644 gspca_ov534-stock.ko \
  "$stock_stage/lib/modules/$release/updates/gspca_ov534.ko"
depmod -b "$stock_stage" "$release"
modinfo -b "$stock_stage" -k "$release" gspca_ov534
sudo ./Microsoft/scripts/gen_modules_vhdx.sh \
  "$stock_stage" "$release" "$PWD/ps-eye-stock-modules.vhdx"
```

Resolve any copy or `depmod` errors before continuing. The copy excludes filesystem
bookkeeping, overlay work directories and build-tree links. The staged tree must
contain the original kernel's other modules, not just the camera driver. Retain
any existing added module directories too. Inspect the staged tree before packaging.

The VHD generator comes from the pinned [6.6.87.1 source](https://github.com/microsoft/WSL2-Linux-Kernel/blob/linux-msft-wsl-6.6.87.1/Microsoft/scripts/gen_modules_vhdx.sh). Do not substitute a different release's script/layout. The current 6.18 branch uses a different artifacts layout.

Replace `WINDOWS_USER` with the real Windows profile directory name, then copy the artifact in **WSL**:

```bash
windows_artifacts=/mnt/c/Users/WINDOWS_USER/PS-Eye-WSL
mkdir -p "$windows_artifacts"
cp ps-eye-stock-modules.vhdx "$windows_artifacts/"
```

In **ordinary Windows PowerShell**, record and back up the current global configuration:

```powershell
$wslConfig = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $wslConfig) {
    $configBackup = "$wslConfig.pseye-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $wslConfig -Destination $configBackup
    Get-Content -LiteralPath $wslConfig
    Write-Output "Backup: $configBackup"
}
notepad.exe $wslConfig
```

Merge this setting into the existing `[wsl2]` section, or create that section if absent. Preserve all other settings and record any previous `kernelModules` value:

```ini
[wsl2]
kernelModules=C:\\Users\\WINDOWS_USER\\PS-Eye-WSL\\ps-eye-stock-modules.vhdx
```

Do not add a `kernel=` override for this module-only deployment. Save work in **all** WSL 2 distributions first, then run in **ordinary Windows PowerShell**:

```powershell
wsl --shutdown
```

Restart the intended distribution, reattach the USB camera from Windows, and in **WSL** run:

```bash
uname -r
modinfo gspca_ov534
sudo modprobe gspca_ov534
```

Repeat USB binding, node selection, headless capture, and preview verification. The override must remain matched to `6.6.87.1-microsoft-standard-WSL2`. After a WSL kernel update, remove/replace that override with artifacts for the new kernel; do not keep using an old modules VHDX with a new kernel.

## Build and boot a matching custom kernel if needed

Use this alternative if the stock kernel cannot accept a correctly built extra module, matching artifacts cannot be reproduced, or necessary built-in infrastructure is absent. A custom kernel creates an ongoing need to rebuild for Microsoft kernel updates.

This procedure remains pinned to the observed x86_64 host and source tag. It builds an isolated kernel release with **all** matching modules. In **WSL**:

```bash
test "$(uname -r)" = 6.6.87.1-microsoft-standard-WSL2 || exit 1
test "$(uname -m)" = x86_64 || exit 1
mkdir -p "$HOME/pseye-kernel-build"
cd "$HOME/pseye-kernel-build"
git clone --depth 1 --branch linux-msft-wsl-6.6.87.1 \
  https://github.com/microsoft/WSL2-Linux-Kernel.git WSL2-Linux-Kernel-custom
cd WSL2-Linux-Kernel-custom
export LOCALVERSION=''
zcat /proc/config.gz > config.running
cp config.running .config
scripts/config \
  --set-str LOCALVERSION '-microsoft-standard-WSL2-pseye' \
  --disable LOCALVERSION_AUTO \
  --module MEDIA_SUPPORT \
  --enable MEDIA_CAMERA_SUPPORT \
  --module VIDEO_DEV \
  --enable MEDIA_USB_SUPPORT \
  --module USB_GSPCA \
  --module USB_GSPCA_OV534
make olddefconfig
scripts/diffconfig config.running .config
grep -E '^(CONFIG_(USB|USBIP_CORE|USBIP_VHCI_HCD|MEDIA_SUPPORT|MEDIA_CAMERA_SUPPORT|VIDEO_DEV|MEDIA_USB_SUPPORT|USB_GSPCA|USB_GSPCA_OV534|VIDEOBUF2_VMALLOC)=)' .config
make -s kernelrelease
```

Expected release: `6.6.87.1-microsoft-standard-WSL2-pseye`. `USB_GSPCA_OV534` and its media dependencies must be enabled, with `VIDEOBUF2_VMALLOC` selected by Kconfig. Preserve the existing Microsoft USB/IP/VHCI, Hyper-V, storage, filesystem, WSLg, and other integration settings. Review the diff before building.

```bash
make -j"$(nproc)"
custom_release=$(make -s kernelrelease)
custom_stage="$PWD/module-stage-custom"
test ! -e "$custom_stage" || exit 1
make INSTALL_MOD_PATH="$custom_stage" modules_install
depmod -b "$custom_stage" "$custom_release"
modinfo -b "$custom_stage" -k "$custom_release" gspca_ov534
sudo ./Microsoft/scripts/gen_modules_vhdx.sh \
  "$custom_stage" "$custom_release" "$PWD/ps-eye-custom-modules.vhdx"
windows_artifacts=/mnt/c/Users/WINDOWS_USER/PS-Eye-WSL
mkdir -p "$windows_artifacts"
cp arch/x86/boot/bzImage "$windows_artifacts/ps-eye-bzImage"
cp ps-eye-custom-modules.vhdx "$windows_artifacts/"
```

This uses the x86 kernel image path because this host is `x86_64`. ARM64 requires its own configuration, toolchain/architecture choice and image path. Do not reuse this image on ARM64. There is no need for `make install` into the distribution's `/boot`; WSL boots the image selected from Windows.

Back up `%UserProfile%\.wslconfig` using the PowerShell procedure above, then merge these two settings into its existing `[wsl2]` section:

```ini
[wsl2]
kernel=C:\\Users\\WINDOWS_USER\\PS-Eye-WSL\\ps-eye-bzImage
kernelModules=C:\\Users\\WINDOWS_USER\\PS-Eye-WSL\\ps-eye-custom-modules.vhdx
```

The image and modules must be from the same completed custom build. Save work across WSL, run `wsl --shutdown` from Windows, restart the intended distribution, and verify in **WSL**:

```bash
uname -r
modinfo -F vermagic gspca_ov534
sudo modprobe gspca_ov534
```

Expect the custom release suffix. Reattach the camera and repeat the main guide's verification sequence. A loaded module alone is not successful camera capture.

Microsoft's [tagged build README](https://github.com/microsoft/WSL2-Linux-Kernel/blob/linux-msft-wsl-6.6.87.1/README.md) documents the source configuration and modules packaging workflow. [Microsoft's configuration reference](https://learn.microsoft.com/en-us/windows/wsl/wsl-config) defines the custom kernel/modules settings and Windows path syntax.

## Roll back a persistent override

`.wslconfig` and the Linux kernel belong to the shared WSL 2 VM. Changing the kernel or modules affects all WSL 2 distributions, and `wsl --shutdown` stops them all. A separate test distribution does not isolate the kernel change.

In **ordinary Windows PowerShell**, restore the exact recorded backup if there have been no other configuration edits since it was made:

```powershell
$wslConfig = Join-Path $env:USERPROFILE '.wslconfig'
Copy-Item -LiteralPath 'C:\Users\WINDOWS_USER\.wslconfig.pseye-backup-TIMESTAMP' `
    -Destination $wslConfig -Force
wsl --shutdown
```

Alternatively, edit the file and restore only the prior `kernel` / `kernelModules` values, preserving later unrelated changes. If neither key existed initially, remove the keys you added. If the file was initially absent, leaving unrelated settings intact or an empty `[wsl2]` section is sufficient; deleting artifacts is unnecessary for rollback.

Restart WSL, confirm the previous `uname -r`, and reattach the USB camera as needed. Restoring the stock kernel also restores its original lack of the PS Eye subdriver. USB sharing created by `usbipd bind` is a separate persistent Windows setting; kernel rollback does not unshare the device.
