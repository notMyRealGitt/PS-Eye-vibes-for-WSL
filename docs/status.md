# Implementation status

Updated 2026-11-08. **The PS Eye now captures video in WSL.** A still image,
32-second recording, and live WSLg software preview have passed. Persistent
module deployment is configured; verification after a WSL restart remains.

## Completed

- Reviewed all three guides and checked the attachment workflow against
  [Microsoft's USB guide](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)
  and [usbipd-win's documentation](https://github.com/dorssel/usbipd-win/wiki/WSL-support).
- Reconfirmed Ubuntu 24.04.4, x86_64, and running kernel
  `6.6.87.1-microsoft-standard-WSL2`.
- Installed usbipd-win **5.3.0**, shared only the PS Eye (USB ID **1415:2000**,
  current Windows BUSID **1-6**), attached it to WSL, and verified enumeration.
- Installed missing build/inspection tools: flex, bison, dwarves/pahole,
  libssl-dev, cpio, qemu-utils, gcc-13-plugin-dev, and v4l-utils, plus their
  dependencies. The package manager also updated the matching OpenSSL runtime
  and executable. Your account already belonged to the video group.
- Built the pinned Microsoft kernel source and its modules successfully with
  USB_GSPCA_OV534=m. Loaded only the additional camera module against the
  running stock kernel, with normal symbol-version checks enabled.
- Verified driver **ov534**, normal-user access, node **/dev/video0**, and camera
  identity through its USB VID/PID and udev properties.
- Captured and visually inspected a recognizable still image at 320×240 YUYV,
  30 fps. Recorded **32.000 seconds / 959 frames** to FFV1. All 959 decoded
  images have distinct hashes; no consecutive identical images were found.
- Verified live camera playback through WSLg using SDL software rendering.
  The bounded live viewer was closed by timeout; exit 124 was expected for
  that externally limited preview. Hardware rendering was not established.
- Packaged the original stock module tree plus the tested additional module,
  regenerated its module index, checked the ext4 filesystem, and verified that
  the VHDX conversion is identical to the raw filesystem image.
- Copied the image to `C:\Users\stfn\PS-Eye-WSL\ps-eye-stock-modules.vhdx` and
  created the previously absent `C:\Users\stfn\.wslconfig` with only:

```ini
[wsl2]
kernelModules=C:\\Users\\stfn\\PS-Eye-WSL\\ps-eye-stock-modules.vhdx
```

The stock Microsoft kernel image is still running. No Windows camera driver
replacement, custom kernel override, or Windows capture fallback was installed.
The camera remains attached to WSL and is available for use now.

## Build details and findings

Source directory: `/tmp/pseye-kernel-6.6.87.1`, tag `linux-msft-wsl-6.6.87.1`,
commit `7573ea4347d2adc267f3de8852ecca885ec2cc9d`.
Tools: GCC 13.3.0, binutils 2.42, pahole 1.25. The full build used 12 parallel
jobs and completed successfully. The configuration diff enabled the camera
driver; remaining changes were toolchain metadata/capability detection and
disabled options exposed by newer tools. Two objtool warnings concerned the
unrelated AMD virtualization module.

The first camera module load passed symbol-version checks but warned about BTF
debug metadata referring to the regenerated kernel's type table. The deployed
copy has only `.BTF` / `.BTF.ext` removed, and was successfully reloaded without
a new BTF warning. Executable `.text` bytes and imported symbol CRCs were compared
before/after and are identical. No force-load options were used. The original
module with BTF is retained in the artifacts. The kernel guide now covers this.

The recording preserved camera timestamps. Three timestamp intervals were zero;
none went backwards, and the largest gap was 67 ms. These repeated timestamps
produce null-muxer DTS warnings during a direct FFmpeg decode check, although
all frames decode. Decoding with strict error detection and a regular 30-fps
output timestamp grid completed with an empty warning/error log. The original
recording and its timestamps were retained; timing jitter is not hidden in the
capture result. Higher rates and latency remain unmeasured.

Kernel messages showed USB/IP unlink status -104 when readers closed. These
occurred at capture shutdown, consistent with asynchronous URB cancellation
described in the [kernel USB error documentation](https://docs.kernel.org/driver-api/usb/error-codes.html).
No mid-recording USB failure was observed.

The kernel guide's temporary unload command was corrected to `rmmod`: on this
host, `modprobe -r` could not resolve the manually inserted module before it was
added to a persistent module index.

## Artifacts

Local outputs are in `artifacts/stock-6.6.87.1/`, ignored by Git:

- `frame.png`, `modest-test.mkv`, capture probe/validation JSON, frame hashes,
  original frame timestamps, and decode logs.
- Deployed and original camera modules, `Module.symvers`, running/build configs,
  config diff, source commit, and full build log.
- Raw filesystem image, modules VHDX, packaging script/log, and SHA-256 hashes.

The modules image uses the release-directory-at-filesystem-root layout of the
pinned Microsoft generator. `mkfs.ext4 -d` populated that layout directly,
without a privileged mount or temporary loop device.

Modules VHDX SHA-256, also verified on the Windows copy:

```text
a4a4c4d54a41e53a649c2d2c02887373e770e8b7f8e0a3e528588568b5844ad1
```

## Remaining: restart and verify persistence

This needs your session: shutdown stops **all** WSL 2 distributions, including
the one hosting this work. Save work first. In ordinary Windows PowerShell:

```powershell
wsl --shutdown
```

Reopen Ubuntu and keep its terminal open. In Windows PowerShell, check the BUSID
again, then reattach the camera (currently 1-6; use its actual ID if changed):

```powershell
& "$env:ProgramFiles\usbipd-win\usbipd.exe" list
& "$env:ProgramFiles\usbipd-win\usbipd.exe" attach --wsl --busid 1-6
```

In Ubuntu, verify the release, installed module, and camera:

```bash
uname -r
modinfo -F filename gspca_ov534
v4l2-ctl --list-devices
```

Expect the same kernel release, a module path under `updates/`, and the PS Eye
capture device. If automatic binding has not occurred, run
`sudo modprobe gspca_ov534` and inspect the kernel messages. Preview with:

```bash
CAM=/dev/v4l/by-id/usb-OmniVision_Technologies__Inc._USB_Camera-B4.09.24.1-video-index0
SDL_RENDER_DRIVER=software ffplay -hide_banner -f v4l2 \
  -input_format yuyv422 -video_size 320x240 -framerate 30 -i "$CAM"
```

Close the preview with `q`. Reattachment is required after WSL restarts;
USB sharing remains persistent. After a WSL kernel update, remove or rebuild
the `kernelModules` override to match the new kernel.

## Rollback

Close camera applications. For the currently temporary module, use
`sudo rmmod gspca_ov534`. To release the camera to Windows, detach using its
actual BUSID. To remove future module deployment, remove only `kernelModules`
from `.wslconfig`, preserving any settings added later, then save work and
restart WSL. The file was absent before this work; an empty `[wsl2]` section
is harmless. The original modules image was not modified.
