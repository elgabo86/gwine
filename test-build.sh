#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="gwine-build"
OUTPUT_DIR="/tmp/gwine-output"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

podman build -t "${IMAGE_NAME}" -f "${REPO_ROOT}/Containerfile" "${REPO_ROOT}"

mkdir -p "${OUTPUT_DIR}"

podman run --rm -i \
  -e TIMESTAMP="${TIMESTAMP}" \
  -v "${REPO_ROOT}/patches:/patches:ro,z" \
  -v "${OUTPUT_DIR}:/output:z" \
  "${IMAGE_NAME}" \
  bash << 'CONTAINER_SCRIPT'
set -u

cd /build
git clone https://github.com/Frogging-Family/wine-tkg-git.git
cd wine-tkg-git/wine-tkg-git

sed -i 's/_LOCAL_PRESET=""/_LOCAL_PRESET="valve-exp-bleeding"/g' customization.cfg
sed -i 's/_NOLIB32="wow64"/_NOLIB32="false"/g' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/_NOLIB32="true"/_NOLIB32="false"/g' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/^_configure_userargs64=""/_configure_userargs64="--without-dbus --with-ffmpeg --with-faudio"/' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/^_configure_userargs32=""/_configure_userargs32="--without-dbus --with-ffmpeg --with-faudio"/' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/_nomakepkg_dependency_autoresolver="true"/_nomakepkg_dependency_autoresolver="false"/' customization.cfg
sed -i 's/_build_faudio="false"/_build_faudio="true"/g' customization.cfg
sed -i 's/_build_mediaconv="false"/_build_mediaconv="true"/g' customization.cfg
sed -i 's/_user_patches_no_confirm="false"/_user_patches_no_confirm="true"/' wine-tkg-profiles/advanced-customization.cfg

if [ -d /patches ]; then
  cp /patches/*.mypatch wine-tkg-userpatches/ 2>/dev/null || true
  rm -f wine-tkg-userpatches/gamepad_axis_32bit_fix.mypatch
  echo "=== Copied custom patches to wine-tkg-userpatches/ ==="
  ls -la wine-tkg-userpatches/*.mypatch 2>/dev/null || echo "(no .mypatch files found after cp)"
fi

sed -i 's|_configure_args32+=(--libdir="$_prefix/$_lib32name")|_configure_args32+=(--libdir="$_prefix/$_lib64name")|' non-makepkg-build.sh

( yes | ./non-makepkg-build.sh ) || true

cd /build/wine-tkg-git/wine-tkg-git

shopt -s nullglob
_builds=(non-makepkg-builds/wine-tkg*)
shopt -u nullglob
if [ ${#_builds[@]} -gt 0 ]; then
  BUILD_DIR="${_builds[0]}"
else
  echo "ERROR: No build directory found!" >&2
  exit 1
fi
echo "=== Build directory: $BUILD_DIR ==="

echo "=== Checking if NV12 fix was applied ==="
if strings "$BUILD_DIR/lib/wine/x86_64-unix/winegstreamer.so" 2>/dev/null | grep -q "NV12 fix applied"; then
  echo "=== NV12 fix CONFIRMED in 64-bit binary ==="
elif strings "$BUILD_DIR/lib/wine/i386-unix/winegstreamer.so" 2>/dev/null | grep -q "NV12 fix applied"; then
  echo "=== NV12 fix CONFIRMED in 32-bit binary ==="
else
  echo "=== WARNING: NV12 fix NOT found in binary! ==="
  echo "=== Checking prepare.log for clues ==="
  grep -i "nv12\|winegstreamer_nv12\|Applying your own\|userpatch" prepare.log 2>/dev/null | tail -20 || echo "(no matches in prepare.log)"
fi

VERSION=$(basename "$BUILD_DIR" | sed 's/^wine-tkg[^0-9]*//')
DEST="gwine-proton-${VERSION:-unknown}"

cp -a "$BUILD_DIR" "/build/${DEST}"

UNIX64=""
UNIX32=""
PE64=""
PE32=""
for d in "/build/${DEST}"/lib/wine/x86_64-unix "/build/${DEST}"/lib64/wine/x86_64-unix; do
  if [ -d "$d" ]; then UNIX64="$d"; break; fi
done
for d in "/build/${DEST}"/lib/wine/i386-unix "/build/${DEST}"/lib64/wine/i386-unix; do
  if [ -d "$d" ]; then UNIX32="$d"; break; fi
done
for d in "/build/${DEST}"/lib/wine/x86_64-windows "/build/${DEST}"/lib64/wine/x86_64-windows; do
  if [ -d "$d" ]; then PE64="$d"; break; fi
done
for d in "/build/${DEST}"/lib/wine/i386-windows "/build/${DEST}"/lib64/wine/i386-windows; do
  if [ -d "$d" ]; then PE32="$d"; break; fi
done

cp -a /opt/ffmpeg32/lib/libav*.so* /opt/ffmpeg32/lib/libsw*.so* "${UNIX32}/" 2>/dev/null || true
cp -a /opt/ffmpeg64/lib/libav*.so* /opt/ffmpeg64/lib/libsw*.so* "${UNIX64}/" 2>/dev/null || true
patchelf --set-rpath '$ORIGIN' "${UNIX32}/winedmo.so" 2>/dev/null || true
patchelf --set-rpath '$ORIGIN' "${UNIX64}/winedmo.so" 2>/dev/null || true

cp -a /opt/faudio32/lib/libFAudio.so* "${UNIX32}/" 2>/dev/null || true
cp -a /opt/faudio64/lib64/libFAudio.so* "${UNIX64}/" 2>/dev/null || true

GST32_DIR="/build/${DEST}/lib32/gstreamer-1.0"
GST64_DIR="/build/${DEST}/lib64/gstreamer-1.0"
mkdir -p "${GST32_DIR}" "${GST64_DIR}"
cp -a /opt/gst-libav32/lib/gstreamer-1.0/libgst*.so "${GST32_DIR}/" 2>/dev/null || true
cp -a /opt/gst-libav64/lib64/gstreamer-1.0/libgst*.so "${GST64_DIR}/" 2>/dev/null || true
for f in "${GST32_DIR}/"libgst*.so; do patchelf --set-rpath '$ORIGIN/../../wine/i386-unix' "$f" 2>/dev/null || true; done
for f in "${GST64_DIR}/"libgst*.so; do patchelf --set-rpath '$ORIGIN/../../wine/x86_64-unix' "$f" 2>/dev/null || true; done

cp -a /opt/icu68/win64/*.dll "${PE64}/" 2>/dev/null || true
cp -a /opt/icu68/win32/*.dll "${PE32}/" 2>/dev/null || true

mv "/build/${DEST}" "/output/gwine-proton-${TIMESTAMP}"
ln -sfn "gwine-proton-${TIMESTAMP}" "/output/gwine-proton-latest"
echo "=== Build done: /output/gwine-proton-${TIMESTAMP} ==="
CONTAINER_SCRIPT
