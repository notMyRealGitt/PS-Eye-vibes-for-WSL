# Conditional fallback: Windows capture forwarded into WSL

This is a source-derived implementation plan, **untested on this host**. Use it only if the observed USB/IP or Linux capture failure makes Windows capture the appropriate fallback. Start with the diagnostic batch in the repository first. Nothing in this guide has been installed or applied automatically.

The proposed path is:

```text
PS3 Eye → WinUSB → PS3EyeDirectShow → Windows FFmpeg
         → MPEG-2 video in MPEG-TS over TCP → WSL FFmpeg / ffplay
```

## Prerequisites and device ownership

WinUSB provides raw USB access. The inspirit library captures through libusb; it does not itself register a webcam. PS3EyeDirectShow adds 32-bit and 64-bit DirectShow filters. Its author describes limited compatibility testing and lists a Media Foundation source as a TODO, so Windows Camera/Media Foundation compatibility is not established. Its installer installs WinUSB and the filters. Select this fallback before changing Windows drivers. [PS3EyeDirectShow README](https://github.com/jkevin/PS3EyeDirectShow), [inspirit README](https://github.com/inspirit/PS3EYEDriver)

Required tools, installed only when this fallback is selected:

- PS3EyeDirectShow and its compatible WinUSB setup.
- A Windows FFmpeg build with DirectShow input, MPEG-2 encoding, MPEG-TS muxing, and TCP support. Match FFmpeg's bitness to an installed DirectShow filter.
- FFmpeg, ffprobe, and optionally ffplay inside the target WSL distribution.

**Windows PowerShell, normal:** detach the camera using the actual bus ID from `usbipd list` before opening it on Windows:

```powershell
usbipd list
$EyeBusId = 'REPLACE_WITH_ACTUAL_BUSID'
usbipd detach --busid $EyeBusId
```

A device attached to WSL is unavailable to Windows. [Microsoft USB attachment documentation](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)

## Establish Windows capture first

**Windows PowerShell, normal:** use the actual FFmpeg executable path and the exact camera name printed by enumeration:

```powershell
$FfmpegPath = (Get-Command ffmpeg.exe -ErrorAction Stop).Source
& $FfmpegPath -hide_banner -devices
& $FfmpegPath -hide_banner -encoders
& $FfmpegPath -hide_banner -list_devices true -f dshow -i dummy
$CameraName = 'REPLACE_WITH_EXACT_ENUMERATED_CAMERA_NAME'
& $FfmpegPath -hide_banner -list_options true -f dshow -i "video=$CameraName"
```

Enumeration commands can exit with an error after printing the requested list; retain that output. Use a supported size, frame rate, and pixel format from the camera's options. The following example applies **only if 320×240 at 30 FPS is offered**. Replace the values with an offered modest mode when necessary. Set an explicit input `-pixel_format` only to a value listed by your filter. [FFmpeg DirectShow documentation](https://ffmpeg.org/ffmpeg-devices.html#dshow)

```powershell
$VideoSize = '320x240'
$FrameRate = '30'
& $FfmpegPath -hide_banner -f dshow -video_size $VideoSize -framerate $FrameRate -i "video=$CameraName" -an -frames:v 1 windows-frame.png
& $FfmpegPath -hide_banner -f dshow -video_size $VideoSize -framerate $FrameRate -i "video=$CameraName" -an -t 32 -c:v mpeg2video -pix_fmt yuv420p -bf 0 -g 15 -q:v 4 windows-30s.ts
& $FfmpegPath -hide_banner -v warning -xerror -i windows-30s.ts -map 0:v:0 -an -f null -
```

Do not proceed until the saved frame is recognizable and the local recording spans at least 30 seconds and decodes successfully. The command requests 32 seconds to leave some margin. A failure here is a Windows camera/filter/capture failure; networking has not yet been involved. The example assumes a normal MPEG-2 output rate such as 30 or 25 FPS; select an offered capture mode accordingly instead of beginning with a high frame rate.

## Choose addresses for the existing networking mode

**WSL:** inspect the existing mode if `wslinfo` is available, plus the IPv4 route and addresses:

```bash
command -v wslinfo >/dev/null && wslinfo --networking-mode
ip -4 route show default
ip -4 -o addr show scope global
```

For default **NAT**, use the default route's gateway as the Windows host address, and obtain the source address WSL uses to reach it:

```bash
WINHOST=$(ip -4 route show default | awk 'NR == 1 { print $3 }')
printf 'Windows host: %s\n' "$WINHOST"
ip -4 route get "$WINHOST"
```

Copy the gateway and the route's `src` IPv4 into the PowerShell variables below. With VPNs or multiple routes, verify the chosen gateway belongs to the Windows WSL interface. These addresses can change after WSL restarts.

For already configured **mirrored** networking, use `127.0.0.1` on both sides instead. Do not change the networking mode merely to use this fallback. Microsoft's documented distinction is Windows host IP for WSL-to-Windows connections in NAT, and IPv4 localhost support in mirrored mode. [Microsoft WSL networking](https://learn.microsoft.com/en-us/windows/wsl/networking)

**Windows PowerShell, normal:**

```powershell
# NAT: paste the actual gateway and WSL source IPv4 found above.
$WinHostIp = 'REPLACE_WITH_WINDOWS_HOST_IPV4'
$WslIpv4 = 'REPLACE_WITH_WSL_SOURCE_IPV4'
$ListenIp = $WinHostIp

# For mirrored mode, use this instead of the NAT variables:
# $ListenIp = '127.0.0.1'
```

For NAT, confirm that Windows owns the gateway address:

```powershell
Get-NetIPAddress -AddressFamily IPv4 -IPAddress $WinHostIp
```

### NAT firewall rule

**Windows PowerShell, elevated:** set these variables again in the elevated session, with the same actual addresses and absolute FFmpeg path used above. The rule allows only that program, local interface address, TCP port, and WSL source address; it does not disable the firewall. [New-NetFirewallRule](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule)

```powershell
$WinHostIp = 'REPLACE_WITH_WINDOWS_HOST_IPV4'
$WslIpv4 = 'REPLACE_WITH_WSL_SOURCE_IPV4'
$FfmpegPath = 'REPLACE_WITH_ABSOLUTE_PATH_TO_ffmpeg.exe'
New-NetFirewallRule -Name 'PS3Eye-WSL-TCP-5000' -DisplayName 'PS3 Eye stream to WSL' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5000 -LocalAddress $WinHostIp -RemoteAddress $WslIpv4 -Program $FfmpegPath -Profile Any
```

This guide uses WSL as the TCP client, so NAT does not require `netsh portproxy` or a WSL inbound listener. The NAT rule is unnecessary for a listener bound only to loopback in mirrored mode. If organizational firewall policy blocks the connection, use the actual error and policy information to diagnose it.

## Stream and verify independently

**Windows PowerShell, normal:** start the listener with the camera values already verified above:

```powershell
& $FfmpegPath -hide_banner -f dshow -video_size $VideoSize -framerate $FrameRate -i "video=$CameraName" -an -c:v mpeg2video -pix_fmt yuv420p -bf 0 -g 15 -q:v 4 -flush_packets 1 -f mpegts "tcp://${ListenIp}:5000?listen=1"
```

The TCP listener serves **one client per run**. It can wait for a connection before video flows. Restart this Windows command before **each** receiver command below; stop any remaining instance with Ctrl+C first. Do not connect a separate network probe to the listener immediately before capture, because that probe can consume its sole connection. FFmpeg documents the TCP listener/client pattern. [FFmpeg TCP protocol](https://ffmpeg.org/ffmpeg-protocols.html#tcp)

**WSL:** set the receiver address for your existing mode:

```bash
# NAT:
WINHOST=$(ip -4 route show default | awk 'NR == 1 { print $3 }')
# Mirrored, instead:
# WINHOST=127.0.0.1
```

First save one decoded image, without a display server:

```bash
ffmpeg -hide_banner -rw_timeout 10000000 -i "tcp://$WINHOST:5000" -map 0:v:0 -frames:v 1 received-frame.png
```

Inspect that file and confirm it depicts a recognizable live scene. Restart the Windows listener, then receive 30 seconds:

```bash
ffmpeg -hide_banner -rw_timeout 10000000 -i "tcp://$WINHOST:5000" -map 0:v:0 -t 32 -c copy received-30s.ts
ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=codec_name,width,height,avg_frame_rate,nb_read_frames:format=duration -of default=noprint_wrappers=1 received-30s.ts
ffmpeg -hide_banner -v warning -xerror -i received-30s.ts -map 0:v:0 -an -f null -
```

Success means at least 30 seconds at the selected dimensions and rate, a plausible decoded frame count (about 960 for a 32-second capture at 30 FPS), and no decode failure. Slight container/timestamp differences can affect the exact duration and count. Moving an object through the scene helps detect frozen content. `ffprobe -count_frames` reports frames read; the final FFmpeg command explicitly decodes the recording. [FFprobe documentation](https://ffmpeg.org/ffprobe.html)

Restart the Windows listener again for live GUI preview:

```bash
ffplay -hide_banner -rw_timeout 10000000 "tcp://$WINHOST:5000"
```

If received files decode correctly but ffplay cannot open a window, investigate WSLg/display separately. Connection refused indicates no reachable listener/address/port; a timeout can indicate filtering, an incorrect address, or stalled capture. Check the corresponding Windows FFmpeg log before choosing a fix. Encoding, TCP buffering, and decoding add CPU use and delay; acceptable performance remains unmeasured.

## What this provides and rollback

WSL receives a network video stream usable by FFmpeg and applications that accept that stream. It does **not** create `/dev/video*`. Exposing it as a V4L2 camera would need a compatible `v4l2loopback` kernel module and another output pipeline, potentially bringing back the exact WSL kernel matching problem. [v4l2loopback upstream](https://github.com/v4l2loopback/v4l2loopback)

Stop Windows FFmpeg and the WSL receiver with Ctrl+C. **Elevated PowerShell**, remove only the rule created above:

```powershell
Remove-NetFirewallRule -Name 'PS3Eye-WSL-TCP-5000'
```

[Remove-NetFirewallRule documentation](https://learn.microsoft.com/en-us/powershell/module/netsecurity/remove-netfirewallrule)

If returning to Linux USB passthrough, close all Windows camera applications and reattach using the actual bus ID. If abandoning the Windows filter installation, uninstall PS3EyeDirectShow through its installer/Windows application management and review the resulting device driver state before making further driver changes.
