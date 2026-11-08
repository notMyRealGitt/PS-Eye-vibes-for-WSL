# PS Eye video in WSL

**Host checkpoint (2026-11-08): video capture and WSLg software preview now work
at 320×240 / 30 fps.** Persistent module deployment is configured; verification
after a WSL restart remains. See [implementation status and next steps](docs/status.md).

Start with **A: usbipd-win passthrough → Linux GSPCA/V4L2**. First establish USB
enumeration, then supply the missing camera module. Native Windows webcam support
is optional for this route. Stop before kernel work until attachment is verified.

This is a staged guide, researched against primary sources on **2026-11-08**.
Commands below describe the staged procedure. For work actually performed and
the current checkpoint, see [implementation status](docs/status.md). The observed
baseline below records the original investigation and is retained for comparison.

## First checkpoint: a small diagnostic batch

The baseline already established most versions. The immediate unknown is whether
usbipd-win is installed outside PATH and which BUSID identifies the camera.
Run this in **normal Windows PowerShell**:

```powershell
Get-CimInstance Win32_OperatingSystem |
    Select-Object Caption, Version, BuildNumber, OSArchitecture
wsl --version
wsl --list --verbose
Get-Service usbipd -ErrorAction SilentlyContinue

$UsbipdCommand = Get-Command usbipd.exe -ErrorAction SilentlyContinue
$UsbipdExe = if ($UsbipdCommand) { $UsbipdCommand.Source } else {
    Join-Path $env:ProgramFiles 'usbipd-win\usbipd.exe'
}
if (Test-Path $UsbipdExe) {
    & $UsbipdExe --version
    & $UsbipdExe list
} else {
    'usbipd-win not found in PATH or its usual installation directory'
}

Get-PnpDevice -PresentOnly |
    Where-Object { $_.InstanceId -like 'USB\VID_1415&PID_2000*' } |
    Format-List Status, Class, FriendlyName, InstanceId
```

Run this in the **WSL shell**; no sudo is needed:

```bash
uname -r
uname -m
cat /etc/os-release
zgrep -E 'CONFIG_(MODULES|MODVERSIONS|MEDIA_SUPPORT|MEDIA_CAMERA_SUPPORT|MEDIA_USB_SUPPORT|VIDEO_DEV|VIDEOBUF2_VMALLOC|USB_GSPCA|USB_GSPCA_OV534|USBIP_CORE|USBIP_VHCI_HCD)(=| )' /proc/config.gz
modinfo gspca_ov534
modinfo -F filename gspca_main
lsusb
lsusb -t
ls -ld "/lib/modules/$(uname -r)/build"
findmnt -T "/lib/modules/$(uname -r)" -o TARGET,FSTYPE,OPTIONS
```

If `/proc/config.gz` is unavailable on another kernel, check
`/boot/config-$(uname -r)` or the exact kernel's build configuration; absence of
the config file does not prove a driver is disabled. A missing `lsusb` or
`modinfo` executable is a missing diagnostic utility, not missing kernel support.

### Observed baseline

| Item | Read-only result |
| --- | --- |
| Windows | Windows 11 Pro, build `26200.9711`, 64-bit |
| WSL | `2.5.7.0`; `Ubuntu-24.04` is WSL 2 |
| Distribution / CPU | Ubuntu 24.04.4 LTS / `x86_64` |
| Running kernel | `6.6.87.1-microsoft-standard-WSL2` |
| Camera USB ID on Windows | **`1415:2000`**, including composite interfaces `MI_00` and `MI_01` |
| Windows camera status | `MI_00` reports Error; audio `MI_01` reports OK. These are separate interfaces. |
| usbipd-win | `usbipd.exe` not found in Windows PATH; installation/version and BUSID still need checking |
| Camera module | Running config: `# CONFIG_USB_GSPCA_OV534 is not set`; `modinfo` cannot find it |
| Dependencies | GSPCA core, V4L2 and videobuf modules are available for this exact kernel |
| Module versioning | `CONFIG_MODVERSIONS=y`; no matching build directory or `Module.symvers` found |
| Module tree | Appears read-only through the agent's filesystem view; verify from the normal WSL shell before deployment |
| Compiler | Kernel built using GCC 11.2.0; currently installed GCC is 13.3.0 |
| Capture tools | FFmpeg/ffplay, GStreamer and its V4L2 plugin, usbutils, kmod installed; `v4l2-ctl` absent |
| WSLg | Display variables and `/mnt/wslg` present; rendering has not been tested |
| Linux enumeration | No camera observed; attachment has not been attempted |

The agent sandbox initially produced `lsusb: unable to initialize libusb: -99`
and blocked Windows interop. An authorized read outside that sandbox reached
Windows and returned no Linux USB devices. **The sandbox errors are not evidence
that this camera or USB/IP is incompatible.** No `/dev/video*` was visible in the
agent view; repeat node checks after attachment and driver loading.

## Ranked approaches

| Rank / approach | Effort and maintenance | Compatibility | Expected performance, not measured here |
| --- | --- | --- | --- |
| **1 — A. USB/IP + Linux GSPCA/V4L2** | Small setup if the module exists; this host needs a matching additional module or custom kernel. Linux maintains the driver; added modules need attention after kernel updates. | Standard Linux V4L2 tools, FFmpeg, GStreamer and applications using V4L2. No Windows camera driver required for capture in WSL. | Uncompressed USB over USB/IP adds overhead; modest supported modes are a reasonable first test. Actual stability/latency remains unknown. |
| **2 — B. USB/IP + userspace libusb** | A practical source candidate is opentrack's PS3EYEDriver fork. Requires building/integrating an application and maintaining that integration; avoids the GSPCA module requirement. | Delivers frames through its own library. Does not automatically create a V4L2 node or an FFmpeg input. Still requires working USB passthrough and raw USB permissions. | Could work well, but shares A's USB/IP transport. It cannot fix a failed attach or transport. No WSL result is established. |
| **3 — C. Windows capture → network stream → WSL** | Most moving parts: Windows USB driver/filter, capture/encoding, networking and decoding. | DirectShow-compatible capture can feed FFmpeg; a network stream is usable by stream-aware Linux apps. It is not a `/dev/video*` device. | Adds encoding/decoding and buffering; compression reduces network bandwidth. Latency and CPU load require measurement. |

The Linux source explicitly identifies `1415:2000`, uses **bulk transfers** in
the OV772x path, and provides YUYV/raw Bayer modes. Enabling only `uvcvideo` does
not supply this driver. Generic objections about isochronous webcams do not
establish a problem for this camera. Source support is established; successful
capture on this host is not. [Linux OV534 source](https://github.com/torvalds/linux/blob/master/drivers/media/usb/gspca/ov534.c),
[GSPCA configuration](https://github.com/torvalds/linux/blob/master/drivers/media/usb/gspca/Kconfig).

For B, the [opentrack fork's history](https://github.com/opentrack/PS3EYEDriver/commits/master/)
shows maintenance through December 2025; the [original inspirit history](https://github.com/inspirit/PS3EYEDriver/commits/master/)
ends in 2017. Its [build file](https://github.com/opentrack/PS3EYEDriver/blob/master/CMakeLists.txt)
has Linux libusb/pthread paths and test programs, but expects embedding in a parent
CMake project. It is a plausible fallback, not a verified turnkey WSL package.
Its [interface claim code](https://github.com/opentrack/PS3EYEDriver/blob/master/ps3eye.cpp)
does not automatically detach a bound Linux driver. If selected, use a small
30-fps capture harness rather than a test that sweeps high rates.

For C, distinguish four layers: **WinUSB** enables raw USB access;
**PS3EYEDriver** captures in userspace; **PS3EyeDirectShow** exposes a DirectShow
source filter; **Media Foundation compatibility is a separate feature**. The
DirectShow project's README lists a Media Foundation source as TODO, so do not
assume Windows Camera compatibility. [PS3EyeDirectShow](https://github.com/jkevin/PS3EyeDirectShow),
[PS Move API camera documentation](https://psmoveapi.readthedocs.io/en/latest/camera.html).

## Establish attachment before building anything

If the initial PowerShell check confirms usbipd-win is absent, the next small
installation is the USB/IP host tool, **not a Windows camera driver**. In normal
**Windows PowerShell**, run:

```powershell
winget install --interactive --exact dorssel.usbipd-win
```

Accept the installer's elevation if required, then open a fresh normal PowerShell
and run `usbipd --version` and `usbipd list`. The interactive option lets the
installer present any restart requirement. The current release checked is
[5.3.0](https://github.com/dorssel/usbipd-win/releases/tag/v5.3.0); use its current
documentation if an existing installation is older. No Linux USB/IP client
package is required by the modern workflow. [Microsoft USB guide](https://learn.microsoft.com/en-us/windows/wsl/connect-usb),
[usbipd-win WSL guide](https://github.com/dorssel/usbipd-win/wiki/WSL-support).

Keep a WSL terminal open. In **elevated Windows PowerShell**, select the actual
BUSID from the current list for VID:PID `1415:2000`:

```powershell
usbipd list
$BusId = Read-Host 'Actual BUSID for 1415:2000 from the list'
usbipd bind --busid $BusId
usbipd list
```

Binding is persistent. Once Shared, switch to **normal Windows PowerShell**:

```powershell
$BusId = Read-Host 'Same actual camera BUSID'
usbipd attach --wsl --busid $BusId
usbipd list
```

The camera is unavailable to Windows while attached and is available to the shared
WSL 2 environment. Do not install WinUSB/Zadig, CL-Eye or a DirectShow filter to
investigate this route. If `bind` requests a force option or reports a filter/driver
conflict, retain the exact error and investigate it before changing drivers.
[Documented attachment workflow](https://github.com/dorssel/usbipd-win/wiki/WSL-support).

In **WSL**:

```bash
lsusb -d 1415:2000
lsusb -t
sudo dmesg | tail -n 100
```

**Pass:** usbipd reports Attached and Linux reports `1415:2000`. A V4L2 node is
not expected yet on this kernel because the camera subdriver is absent.
Save the exact attach error and relevant kernel messages if this checkpoint fails.

## Supply the camera driver, only after enumeration passes

On this host the GSPCA core and dependencies already exist. Prefer a matching
additional `gspca_ov534` module first. Matching means the actual Microsoft source
tag, configuration, release/architecture and compatible symbol versions; the
version string alone is insufficient. Do not install Ubuntu generic-kernel
modules into this Microsoft kernel.

The running kernel uses symbol CRC checks (`CONFIG_MODVERSIONS=y`). Matching
`Module.symvers` or a complete matching build is needed; `modules_prepare` alone
does not provide those CRCs. This can require a full compilation **without
replacing the running kernel**. [Kbuild module documentation](https://docs.kernel.org/kbuild/modules.html).

Follow [the conditional module/custom-kernel guide](docs/kernel-support.md) after
the attachment checkpoint. It covers a temporary module load, persistence with
the stock kernel, and a separately identified custom-kernel option with rollback.
Do not run a large build merely to diagnose USB attachment.

## Verify capture one layer at a time

Once the module is installed or temporarily loaded, use the normal **WSL shell**.
If needed at this stage, install only the missing inspection utility:

```bash
sudo apt install v4l-utils
```

### Binding, node identity and permissions

```bash
sudo modprobe gspca_ov534
lsusb -t
sudo dmesg | tail -n 100
v4l2-ctl --list-devices
ls -l /dev/video* /dev/v4l/by-id/ 2>/dev/null
```

If testing a temporary absolute-path `insmod`, skip `modprobe gspca_ov534` here:
the installed module index does not know about that file yet. Inspect the load
result and messages as described in the kernel guide.

Identify the camera's capture node from the device listing and USB path; do not
assume `/dev/video0`. Set it explicitly, using its by-id path when available:

```bash
read -r -p 'PS Eye capture node or by-id path: ' CAM
v4l2-ctl -d "$CAM" --all
udevadm info --query=property --name="$CAM"
id
ls -l "$CAM"
stat -Lc '%A %U %G %n' "$CAM"
```

**Pass:** the USB interface has the OV534/GSPCA driver, the node identifies the
camera and advertises video capture, and the user can open it. Use the USB
VID/PID in udev properties or its device-parent chain to confirm identity.
For an access error, compare `sudo v4l2-ctl -d "$CAM" --all` once. If the node
belongs to group `video` with group read/write access, use
`sudo usermod -aG video "$USER"`, then start a fresh login with that membership
and confirm using `id`. If necessary, use `newgrp video` for a new shell and
reassign `CAM`. If the node has no appropriate owner/mode, inspect udev and its
rules; group membership cannot fix an absent device or failed driver probe.

### Enumerate formats and rates

```bash
v4l2-ctl -d "$CAM" --list-formats-ext
ffmpeg -hide_banner -f v4l2 -list_formats all -i "$CAM"
```

The FFmpeg enumeration command may exit nonzero after printing its list; that
alone is not a capture failure. The actual device output chooses the settings.
The OV772x driver source suggests **320×240 YUYV at 30 fps** as an initial mode;
640×480 at 15 fps is another modest choice if listed. Do not assume MJPEG: JPEG
in the same source belongs to a different sensor path. [Driver mode tables](https://github.com/torvalds/linux/blob/master/drivers/media/usb/gspca/ov534.c),
[V4L2 format enumeration](https://docs.kernel.org/userspace-api/media/v4l/vidioc-enum-fmt.html).

Only if the device lists 320×240 YUYV at 30 fps, use these explicit settings:

```bash
v4l2-ctl -d "$CAM" \
  --set-fmt-video=width=320,height=240,pixelformat=YUYV --set-parm=30
v4l2-ctl -d "$CAM" --get-fmt-video --get-parm
```

Check the returned format/rate; applications and drivers can negotiate a different
value. `YUYV` is the V4L2 FourCC; FFmpeg calls this format `yuyv422` and GStreamer
calls it `YUY2`.

### Headless image, then at least 30 seconds of video

Use unused output filenames. These commands intentionally do not overwrite files.
The `timeout` limits a stalled capture and is not a success criterion:

```bash
timeout 20s ffmpeg -hide_banner -nostdin \
  -f v4l2 -input_format yuyv422 -video_size 320x240 -framerate 30 \
  -i "$CAM" -vf 'select=gte(n\,30)' -frames:v 1 -update 1 frame.png

timeout 45s ffmpeg -hide_banner -nostdin \
  -f v4l2 -input_format yuyv422 -video_size 320x240 -framerate 30 \
  -i "$CAM" -t 32 -an -c:v ffv1 modest-test.mkv

ffprobe -v error -select_streams v:0 -count_frames \
  -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_read_frames:format=duration \
  -of default=noprint_wrappers=1 modest-test.mkv
ffmpeg -hide_banner -v error -i modest-test.mkv -f null -
sudo dmesg | tail -n 100
```

**Pass 1:** `frame.png` visibly contains a recognizable scene. Inspect the saved
file independently; file creation alone is insufficient. The frame selection lets
about a second pass before saving to allow automatic exposure to settle.

**Pass 2:** the recording spans at least 30 seconds, decodes cleanly, contains
roughly the expected number of frames (about 960 for 32 seconds at 30 fps), and
shows continuing motion without sustained freezes or repeated USB errors.
Review actual negotiated rate and timestamp/frame-count behavior if these differ.
Use a clock or moving object in the scene to expose frozen/duplicated content.
Capturing uncompressed YUYV at this mode is approximately 4.6 MB/s of image data,
before USB/IP overhead; this is arithmetic, not a measured throughput result.

The commands use FFmpeg's documented V4L2 input options. No display server is
involved in either capture. [FFmpeg V4L2 documentation](https://ffmpeg.org/ffmpeg-devices.html#video4linux2_002c-v4l2).

### Preview after headless capture succeeds

```bash
ffplay -hide_banner -f v4l2 -input_format yuyv422 \
  -video_size 320x240 -framerate 30 -i "$CAM"
```

Or, with GStreamer:

```bash
gst-launch-1.0 -v v4l2src device="$CAM" \
  ! 'video/x-raw,format=YUY2,width=320,height=240,framerate=30/1' \
  ! videoconvert ! autovideosink
```

This uses explicit raw-video caps with the standard
[GStreamer V4L2 source](https://gstreamer.freedesktop.org/documentation/video4linux2/v4l2src.html).
Run one camera reader at a time. If GUI preview fails after successful capture,
check display independently:

```bash
printf 'DISPLAY=%s\nWAYLAND_DISPLAY=%s\n' "$DISPLAY" "$WAYLAND_DISPLAY"
ffplay -f lavfi -i testsrc=size=320x240:rate=30 -t 5
```

A display/test-pattern failure is a WSLg/SDL/display issue; it does not erase a
successful headless camera test. If rendering works but capture fails, preserve
the input negotiation and driver errors. Investigate higher frame rates only
after both image and sustained modest-mode success.

## Choose the next step from the observed error

| Observation | Next action |
| --- | --- |
| No Windows USB/PnP enumeration | Recheck connection, port and hardware; Linux modules cannot repair this. The earlier Raspberry Pi picture is useful history, not a current hardware test. |
| usbipd missing / bind / attach error | Establish installation/version, actual BUSID, sharing state, WSL 2 status, service and the exact transport/firewall error. Do not replace camera drivers based on a guess. |
| Attached but no `1415:2000` in WSL | Inspect `lsusb -t`, `vhci_hcd`/USB-IP support and kernel messages; resolve transport before either A or B. |
| USB enumerates; OV534 missing | Matching module first; B is an alternative if avoiding kernel work matters. |
| Module rejected: invalid format / symbol version / unknown symbol | Inspect `dmesg`, exact build/config/CRC match and dependencies. Never force-load; consider a matching custom kernel. |
| Driver probes but no node | Inspect probe messages, interface binding, V4L2 core and device-node/udev setup. |
| Permission denied | Inspect ownership, ACL/group membership and udev; use root only for diagnosis. |
| Unsupported format / `EINVAL` | Enumerate supported formats and rates and check returned negotiation. |
| Capture timeout / USB errors | Save logs; try a modest supported mode and a direct USB port. B shares USB/IP and may share the failure. Consider C if the observed failure points to the USB/IP path. |
| Headless succeeds, preview fails | Debug WSLg/display separately. |

If C is warranted, follow the concrete [Windows forwarding guide](docs/windows-forwarding.md).
It specifies capture, TCP transport, receiving, addressing and a scoped firewall
rule. Receiving a stream does not create V4L2; adding `v4l2loopback` would again
require compatible kernel support.

In **normal Windows PowerShell**, release the camera when finished:

```powershell
usbipd detach --busid $BusId
```

Unplugging or restarting WSL also detaches it. Detaching retains the persistent
sharing setting; `usbipd unbind --busid $BusId` from elevated PowerShell removes
sharing when it is no longer wanted. [usbipd-win lifecycle](https://github.com/dorssel/usbipd-win/wiki/WSL-support).

Original baseline uncertainties: installed usbipd-win version/location and actual BUSID;
successful USB attachment; module build/load compatibility and deployment outside
the sandbox; camera probe and supported modes on this unit; permissions; a
recognizable frame; sustained capture; display operation; and all latency/high-rate
performance. See [implementation status](docs/status.md) for subsequent measured
results and the remaining restart verification. None of these should be inferred
from source support alone.
