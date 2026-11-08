#!/usr/bin/env bash
# Package a staged WSL module tree without mounting it or requiring root.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: bash $0 STAGING_ROOT KERNEL_RELEASE OUTPUT_DIR" >&2
  exit 2
fi

stage=$1/lib/modules/$2
release=$2
module=$stage/updates/gspca_ov534.ko
out=$3
test -s "$module"
[[ "$(modinfo -F vermagic "$module")" == "$release "* ]]
mkdir -p "$out"
out=$(realpath "$out")
raw=$out/ps-eye-stock-modules.img
vhdx=$out/ps-eye-stock-modules.vhdx

for path in "$raw" "$vhdx" "$out/SHA256SUMS"; do
  if [[ -e "$path" ]]; then
    echo "Refusing to overwrite: $path" >&2
    exit 1
  fi
done
if [[ -e "$out/gspca_ov534.ko" ]]; then
  cmp "$module" "$out/gspca_ov534.ko"
else
  cp "$module" "$out/gspca_ov534.ko"
fi

size=$(du -sb "$stage" | awk '{print $1}')
truncate -s "$((size + 256 * 1024 * 1024))" "$raw"
# WSL expects the contents of the release directory at the filesystem root.
mkfs.ext4 -q -F -d "$stage" "$raw"
e2fsck -fn "$raw"
qemu-img convert -f raw -O vhdx "$raw" "$vhdx"
qemu-img compare -f raw -F vhdx "$raw" "$vhdx"
cd "$out"
sha256sum gspca_ov534.ko ps-eye-stock-modules.vhdx > SHA256SUMS
printf 'Modules image: %s\n' "$vhdx"
