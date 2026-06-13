#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="gwine-build"
OUTPUT_DIR="/tmp/gwine-output"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

podman build -t "${IMAGE_NAME}" -f "${REPO_ROOT}/Containerfile" "${REPO_ROOT}"

mkdir -p "${OUTPUT_DIR}"

podman run --rm -i \
  -v "${REPO_ROOT}/patches:/patches:ro,z" \
  -v "${OUTPUT_DIR}:/output:z" \
  "${IMAGE_NAME}" \
  bash << 'CONTAINER_SCRIPT'
set -u

cd /build
git clone https://github.com/Frogging-Family/wine-tkg-git.git
cd wine-tkg-git/wine-tkg-git

curl -fsSL "https://raw.githubusercontent.com/gohryt/wine-tkg-git/gohryt-1/wine-tkg-git/wine-tkg-patches/proton-tkg-specific/proton-sdl-joy/proton10-sdl-joy.patch" -o wine-tkg-patches/proton-tkg-specific/proton-sdl-joy/proton10-sdl-joy.patch
curl -fsSL "https://raw.githubusercontent.com/gohryt/wine-tkg-git/gohryt-1/wine-tkg-git/wine-tkg-patches/proton-tkg-specific/proton_eac/Revert-ntdll-Get-rid-of-the-wine_nt_to_unix_file_nam.patch" -o wine-tkg-patches/proton-tkg-specific/proton_eac/Revert-ntdll-Get-rid-of-the-wine_nt_to_unix_file_nam.patch

sed -i 's/_use_ntsync="false"/_use_ntsync="true"/g' customization.cfg
sed -i 's/_use_fsync="true"/_use_fsync="false"/g' customization.cfg
sed -i 's/_use_esync="true"/_use_esync="false"/g' customization.cfg
sed -i 's/_wayland_driver="false"/_wayland_driver="true"/g' customization.cfg
sed -i 's/_FS_bypass_compositor="false"/_FS_bypass_compositor="true"/g' customization.cfg
sed -i 's/_proton_fs_hack="false"/_proton_fs_hack="true"/g' customization.cfg
sed -i 's/_proton_mf_patches="false"/_proton_mf_patches="true"/g' customization.cfg
sed -i 's/_msvcrt_nativebuiltin="false"/_msvcrt_nativebuiltin="true"/g' customization.cfg
sed -i 's/_win10_default="false"/_win10_default="true"/g' customization.cfg
sed -i 's/_protonify="false"/_protonify="true"/g' customization.cfg
sed -i 's/_NOLIB32="false"/_NOLIB32="wow64"/g' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/_NOCCACHE="false"/_NOCCACHE="true"/g' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/_PKGNAME_OVERRIDE=""/_PKGNAME_OVERRIDE="none"/g' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/_sdl_joy_support="false"/_sdl_joy_support="true"/g' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/_user_patches_no_confirm="false"/_user_patches_no_confirm="true"/g' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/_nomakepkg_dependency_autoresolver="true"/_nomakepkg_dependency_autoresolver="false"/' customization.cfg
sed -i 's/_build_faudio="false"/_build_faudio="true"/g' customization.cfg

if [ -d /patches ]; then
  cp /patches/*.mypatch wine-tkg-userpatches/ 2>/dev/null || true
  rm -f wine-tkg-userpatches/winegstreamer_nv12_buffer_fix.mypatch
  rm -f wine-tkg-userpatches/opencl_linux_fix.mypatch
  rm -f wine-tkg-userpatches/use_real_username.mypatch
  rm -f wine-tkg-userpatches/content_sniffing_fallback.mypatch
  rm -f wine-tkg-userpatches/mpeg4_m4s2_decoder_fix.mypatch
  rm -f wine-tkg-userpatches/mfplat_buffer_stride_fix.mypatch
  rm -f wine-tkg-userpatches/disable_mediaconv_fallback.mypatch
  echo "Copied custom patches (removed proton-specific patches)"
fi

sed -i 's|_configure_args32+=(--libdir="$_prefix/$_lib32name")|_configure_args32+=(--libdir="$_prefix/$_lib64name")|' non-makepkg-build.sh

( yes | ./non-makepkg-build.sh ) || true

cd /build/wine-tkg-git/wine-tkg-git

BUILD_DIR=$(ls -d non-makepkg-builds/wine-tkg-git-* | head -n 1)
VERSION=$(basename "$BUILD_DIR" | sed 's/^wine-tkg-git-//')
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DEST="gwine-test-${VERSION:-unknown}"

cp -a "$BUILD_DIR" "/build/${DEST}"

UNIX32=$(ls -d "/build/${DEST}"/lib/wine/i386-unix "/build/${DEST}"/lib64/wine/i386-unix 2>/dev/null | head -n 1)
cp -a /opt/ffmpeg32/lib/libav*.so* /opt/ffmpeg32/lib/libsw*.so* "${UNIX32}/" 2>/dev/null || true
cp -a /opt/ffmpeg64/lib/libav*.so* /opt/ffmpeg64/lib/libsw*.so* "/build/${DEST}/lib64/wine/x86_64-unix/" 2>/dev/null || true
patchelf --set-rpath '$ORIGIN' "${UNIX32}/winedmo.so" 2>/dev/null || true
patchelf --set-rpath '$ORIGIN' "/build/${DEST}/lib64/wine/x86_64-unix/winedmo.so" 2>/dev/null || true

GST32=$(ls -d "/build/${DEST}"/lib32/gstreamer-1.0 "/build/${DEST}"/lib/gstreamer-1.0 2>/dev/null | head -n 1)
if [ -n "${GST32}" ]; then
  mkdir -p "${GST32}" "/build/${DEST}/lib64/gstreamer-1.0"
  cp -a /opt/gst-libav32/lib/gstreamer-1.0/libgst*.so "${GST32}/" 2>/dev/null || true
  cp -a /opt/gst-libav64/lib64/gstreamer-1.0/libgst*.so "/build/${DEST}/lib64/gstreamer-1.0/" 2>/dev/null || true
  for f in "${GST32}/"libgst*.so; do patchelf --set-rpath '$ORIGIN/../../wine/i386-unix' "$f" 2>/dev/null || true; done
  for f in "/build/${DEST}/lib64/gstreamer-1.0/"libgst*.so; do patchelf --set-rpath '$ORIGIN/../../wine/x86_64-unix' "$f" 2>/dev/null || true; done
fi

mv "/build/${DEST}" "/output/gwine-${TIMESTAMP}"
ln -sfn "gwine-${TIMESTAMP}" "/output/gwine-latest"
echo "=== Build done: /output/gwine-${TIMESTAMP} ==="
CONTAINER_SCRIPT
