# PS Eye in WSL

The PS Eye (`1415:2000`) uses usbipd-win passthrough and Linux's existing
OV534 driver to provide a V4L2 camera. Verified on 2026-11-08: a recognizable
still, 32-second recording (959 frames), and WSLg software preview at
320×240 / 30 fps. **Persistence after a WSL restart still needs verification.**

## Restart and attach

Save work in all WSL distributions, then run in Windows PowerShell:

```powershell
wsl --shutdown
```

Reopen Ubuntu and keep its terminal open. In normal Windows PowerShell:

```powershell
$Usbipd = "$env:ProgramFiles\usbipd-win\usbipd.exe"
& $Usbipd list
& $Usbipd attach --wsl --busid 1-6
```

Use the BUSID for `1415:2000` from the list; `1-6` was its last observed ID.
Reattach after each WSL restart or USB reconnection. Initial sharing is already
configured.

## Check and preview in Ubuntu

```bash
uname -r
modinfo -F filename gspca_ov534
v4l2-ctl --list-devices

CAM=/dev/v4l/by-id/usb-OmniVision_Technologies__Inc._USB_Camera-B4.09.24.1-video-index0
SDL_RENDER_DRIVER=software ffplay -hide_banner -f v4l2 \
  -input_format yuyv422 -video_size 320x240 -framerate 30 -i "$CAM"
```

Expect kernel `6.6.87.1-microsoft-standard-WSL2`, a module path under
`updates/`, and a capture device (previously `/dev/video0`). Close preview
with `q`; use one camera application at a time.

## Files to keep

- Windows: `%USERPROFILE%\.wslconfig` and
  `%USERPROFILE%\PS-Eye-WSL\ps-eye-stock-modules.vhdx`.
- This repo: the saved kernel configuration in `config/`, WSL configuration
  template, packaging script in `scripts/`, and [agent rebuild notes](AGENTS.md).
- `artifacts/stock-6.6.87.1/` holds local modules, build records, and test captures.
  It is ignored by Git; binaries must be backed up separately or rebuilt.

The module image matches this exact kernel. Before a WSL kernel update, remove
the `kernelModules` setting or prepare a matching replacement. To undo module
deployment, remove that setting while preserving other `.wslconfig` entries,
then restart WSL.
