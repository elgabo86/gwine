#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="gwine-build"
OUTPUT_DIR="/tmp/gwine-output"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

podman build -t "${IMAGE_NAME}" -f "${REPO_ROOT}/Containerfile" "${REPO_ROOT}"

mkdir -p "${OUTPUT_DIR}"

podman run --rm -i \
  -v "${REPO_ROOT}/patches:/patches:ro" \
  -v "${OUTPUT_DIR}:/output:z" \
  "${IMAGE_NAME}" \
  bash << 'CONTAINER_SCRIPT'
set -euo pipefail

cd /build
git clone https://github.com/Frogging-Family/wine-tkg-git.git
cd wine-tkg-git/wine-tkg-git

sed -i 's/_LOCAL_PRESET=""/_LOCAL_PRESET="valve-exp-bleeding"/g' customization.cfg
sed -i 's/_NOLIB32="wow64"/_NOLIB32="false"/g' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/_NOLIB32="true"/_NOLIB32="false"/g' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/^_configure_userargs64=""/_configure_userargs64="--without-dbus --with-ffmpeg"/' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/^_configure_userargs32=""/_configure_userargs32="--without-dbus --with-ffmpeg"/' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/_nomakepkg_dependency_autoresolver="true"/_nomakepkg_dependency_autoresolver="false"/' customization.cfg

if [ -d /patches ]; then
  cp /patches/*.mypatch wine-tkg-userpatches/ 2>/dev/null || true
  rm -f wine-tkg-userpatches/gamepad_axis_32bit_fix.mypatch
  echo "Copied custom patches (removed gwine-specific gamepad patch)"
fi

( yes | ./non-makepkg-build.sh ) || true

cd /build/wine-tkg-git/wine-tkg-git

BUILD_DIR=$(ls -d non-makepkg-builds/wine-tkg* | head -n 1)
VERSION=$(basename "$BUILD_DIR" | sed 's/^wine-tkg[^0-9]*//')
DEST="gwine-proton-${VERSION:-unknown}"

cp -a "$BUILD_DIR" "/build/${DEST}"

cp -a /opt/ffmpeg32/lib/libav*.so* /opt/ffmpeg32/lib/libsw*.so* "/build/${DEST}/lib/wine/i386-unix/" 2>/dev/null || true
cp -a /opt/ffmpeg64/lib/libav*.so* /opt/ffmpeg64/lib/libsw*.so* "/build/${DEST}/lib64/wine/x86_64-unix/" 2>/dev/null || true
patchelf --set-rpath '$ORIGIN' "/build/${DEST}/lib/wine/i386-unix/winedmo.so" 2>/dev/null || true
patchelf --set-rpath '$ORIGIN' "/build/${DEST}/lib64/wine/x86_64-unix/winedmo.so" 2>/dev/null || true

mkdir -p "/build/${DEST}/lib32/gstreamer-1.0" "/build/${DEST}/lib64/gstreamer-1.0"
cp -a /opt/gst-libav32/lib/gstreamer-1.0/libgst*.so "/build/${DEST}/lib32/gstreamer-1.0/" 2>/dev/null || true
cp -a /opt/gst-libav64/lib64/gstreamer-1.0/libgst*.so "/build/${DEST}/lib64/gstreamer-1.0/" 2>/dev/null || true
for f in "/build/${DEST}/lib32/gstreamer-1.0/"libgst*.so; do patchelf --set-rpath '$ORIGIN/../../wine/i386-unix' "$f" 2>/dev/null || true; done
for f in "/build/${DEST}/lib64/gstreamer-1.0/"libgst*.so; do patchelf --set-rpath '$ORIGIN/../../wine/x86_64-unix' "$f" 2>/dev/null || true; done

mv "/build/${DEST}" "/output/gwine-proton-${TIMESTAMP}"
ln -sfn "gwine-proton-${TIMESTAMP}" "/output/gwine-proton-latest"
echo "=== Build done: /output/gwine-proton-${TIMESTAMP} ==="
CONTAINER_SCRIPT
