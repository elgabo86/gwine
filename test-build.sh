#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="gwine-build"
OUTPUT_DIR="${XDG_DOWNLOAD_DIR:-$(xdg-user-dir DOWNLOAD 2>/dev/null || echo "$HOME/Downloads")}/gwine-output"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PODMAN_BUILD_FLAGS=""

for arg in "$@"; do
    case "$arg" in
        --no-cache) PODMAN_BUILD_FLAGS="--no-cache" ;;
    esac
done

podman build ${PODMAN_BUILD_FLAGS} -t "${IMAGE_NAME}" -f "${REPO_ROOT}/Containerfile" "${REPO_ROOT}"

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

cp /opt/gst64/lib64/pkgconfig/gstreamer*.pc /usr/lib64/pkgconfig/
cp /opt/gst32/lib/pkgconfig/gstreamer*.pc /usr/lib/pkgconfig/
echo "/opt/gst64/lib64" > /etc/ld.so.conf.d/gst64.conf
echo "/opt/gst32/lib" > /etc/ld.so.conf.d/gst32.conf
ldconfig

sed -i 's/_LOCAL_PRESET=""/_LOCAL_PRESET="valve-exp-bleeding"/g' customization.cfg
sed -i 's/_NOLIB32="wow64"/_NOLIB32="false"/g' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/_NOLIB32="true"/_NOLIB32="false"/g' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/^_configure_userargs64=""/_configure_userargs64="--without-dbus --with-ffmpeg"/' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/^_configure_userargs32=""/_configure_userargs32="--without-dbus --with-ffmpeg"/' wine-tkg-profiles/advanced-customization.cfg
sed -i 's/_nomakepkg_dependency_autoresolver="true"/_nomakepkg_dependency_autoresolver="false"/' customization.cfg
sed -i 's/_build_faudio="false"/_build_faudio="true"/g' customization.cfg
sed -i 's/_build_mediaconv="false"/_build_mediaconv="true"/g' customization.cfg
sed -i 's/_user_patches_no_confirm="false"/_user_patches_no_confirm="true"/' wine-tkg-profiles/advanced-customization.cfg

if [ -d /patches ]; then
  cp /patches/*.mypatch wine-tkg-userpatches/ 2>/dev/null || true
  # faketime est appliqué après staging via apply-faketime.py
  rm -f wine-tkg-userpatches/faketime.mypatch
  echo "=== Copied custom patches to wine-tkg-userpatches/ ==="
  ls -la wine-tkg-userpatches/*.mypatch 2>/dev/null || echo "(no .mypatch files found after cp)"
fi

sed -i 's|_configure_args32+=(--libdir="$_prefix/$_lib32name")|_configure_args32+=(--libdir="$_prefix/$_lib64name")|' non-makepkg-build.sh

# Injecter apply-faketime.py avant make_requests (modifie protocol.def → régénéré par make_requests)
# La fonction _prepare() est dans wine-tkg-scripts/prepare.sh
sed -i '/tools\/make_requests/i /usr/bin/python3 /patches/apply-faketime.py "$_sourcedir" || echo "faketime: partial apply OK"' wine-tkg-scripts/prepare.sh

( yes | ./non-makepkg-build.sh ) || true
if ! ls -d non-makepkg-builds/wine-tkg* 1>/dev/null 2>&1; then
  echo "ERROR: Build failed - no output directory found. Check prepare.log:"
  cat prepare.log 2>/dev/null || echo "prepare.log not found"
  exit 1
fi

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
DEST="gwine-${VERSION:-unknown}"

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

GST32_DIR="/build/${DEST}/lib32/gstreamer-1.0"
GST64_DIR="/build/${DEST}/lib64/gstreamer-1.0"
GSTLIBS32_DIR="/build/${DEST}/lib32/gst-libs"
GSTLIBS64_DIR="/build/${DEST}/lib64/gst-libs"
GSTLIBS_LIB_DIR="/build/${DEST}/lib/gst-libs"
mkdir -p "${GST32_DIR}" "${GST64_DIR}" "${GSTLIBS32_DIR}" "${GSTLIBS64_DIR}" "${GSTLIBS_LIB_DIR}"
cp -a /opt/gst32/lib/gstreamer-1.0/libgst*.so "${GST32_DIR}/" 2>/dev/null || true
rm -f "${GST32_DIR}/libgstges.so"
cp -a /opt/gst64/lib64/gstreamer-1.0/libgst*.so "${GST64_DIR}/" 2>/dev/null || true
rm -f "${GST64_DIR}/libgstges.so"
cp -a /opt/gst32/lib/libgst*-1.0.so* "${GSTLIBS32_DIR}/" 2>/dev/null || true
cp -a /opt/gst64/lib64/libgst*-1.0.so* "${GSTLIBS64_DIR}/" 2>/dev/null || true
cp -a /opt/gst32/lib/libgst*-1.0.so* "${GSTLIBS_LIB_DIR}/" 2>/dev/null || true
cp -a /usr/lib/libgraphene-1.0.so* "${GSTLIBS32_DIR}/" 2>/dev/null || true
cp -a /usr/lib64/libgraphene-1.0.so* "${GSTLIBS64_DIR}/" 2>/dev/null || true
cp -a /usr/lib/libgraphene-1.0.so* "${GSTLIBS_LIB_DIR}/" 2>/dev/null || true
mkdir -p "/build/${DEST}/lib64/libexec/gstreamer-1.0" "/build/${DEST}/lib32/libexec/gstreamer-1.0"
cp -a /opt/gst64/libexec/gstreamer-1.0/gst-plugin-scanner "/build/${DEST}/lib64/libexec/gstreamer-1.0/" 2>/dev/null || true
cp -a /opt/gst32/libexec/gstreamer-1.0/gst-plugin-scanner "/build/${DEST}/lib32/libexec/gstreamer-1.0/" 2>/dev/null || true
UNIX32_RPATH=""
for d in "/build/${DEST}"/lib/wine/i386-unix "/build/${DEST}"/lib32/wine/i386-unix; do
  if [ -d "$d" ]; then UNIX32_RPATH=$(echo "$d" | sed "s|/build/${DEST}/||"); break; fi
done
UNIX64_RPATH=""
for d in "/build/${DEST}"/lib/wine/x86_64-unix "/build/${DEST}"/lib64/wine/x86_64-unix; do
  if [ -d "$d" ]; then UNIX64_RPATH=$(echo "$d" | sed "s|/build/${DEST}/||"); break; fi
done
for f in "${GST32_DIR}/"libgst*.so; do [ -n "$UNIX32_RPATH" ] && patchelf --force-rpath --set-rpath "\$ORIGIN/../gst-libs:\$ORIGIN/../../${UNIX32_RPATH}" "$f" 2>/dev/null || true; done
for f in "${GST64_DIR}/"libgst*.so; do [ -n "$UNIX64_RPATH" ] && patchelf --force-rpath --set-rpath "\$ORIGIN/../gst-libs:\$ORIGIN/../../${UNIX64_RPATH}" "$f" 2>/dev/null || true; done

GSTLIBS64_RPATH=""
if [ -d "/build/${DEST}/lib64/gst-libs" ]; then GSTLIBS64_RPATH="lib64/gst-libs"
elif [ -d "/build/${DEST}/lib/gst-libs" ]; then GSTLIBS64_RPATH="lib/gst-libs"
fi
GSTLIBS32_RPATH=""
if [ -d "/build/${DEST}/lib32/gst-libs" ]; then GSTLIBS32_RPATH="lib32/gst-libs"
elif [ -d "/build/${DEST}/lib/gst-libs" ]; then GSTLIBS32_RPATH="lib/gst-libs"
fi
WG_REL64=""
UNIX64_BASE=$(basename "${UNIX64}")
UNIX64_PARENT=$(basename "$(dirname "${UNIX64}")")
UNIX64_GRANDPARENT=$(basename "$(dirname "$(dirname "${UNIX64}")")")
if [ "$UNIX64_GRANDPARENT" = "lib" ] || [ "$UNIX64_GRANDPARENT" = "lib64" ]; then
  WG_REL64="../../../${GSTLIBS64_RPATH}"
else
  WG_REL64="../../${GSTLIBS64_RPATH}"
fi
WG_REL32=""
UNIX32_BASE=$(basename "${UNIX32}")
UNIX32_PARENT=$(basename "$(dirname "${UNIX32}")")
UNIX32_GRANDPARENT=$(basename "$(dirname "$(dirname "${UNIX32}")")")
if [ "$UNIX32_GRANDPARENT" = "lib" ] || [ "$UNIX32_GRANDPARENT" = "lib32" ]; then
  WG_REL32="../../../${GSTLIBS32_RPATH}"
else
  WG_REL32="../../${GSTLIBS32_RPATH}"
fi
for f in "${UNIX64}/"winegstreamer.so; do
  [ -n "${GSTLIBS64_RPATH}" ] && patchelf --set-rpath "\$ORIGIN:${WG_REL64}" "$f" 2>/dev/null && echo "patchelf OK: $f" || { echo "WARNING: patchelf failed on $f, trying with --force-rpath (may corrupt ELF)"; patchelf --force-rpath --set-rpath "\$ORIGIN:${WG_REL64}" "$f" 2>/dev/null || echo "FATAL: patchelf --force-rpath also failed on $f"; }
done
for f in "${UNIX32}/"winegstreamer.so; do
  [ -n "${GSTLIBS32_RPATH}" ] && patchelf --set-rpath "\$ORIGIN:${WG_REL32}" "$f" 2>/dev/null && echo "patchelf OK: $f" || { echo "WARNING: patchelf failed on $f, trying with --force-rpath (may corrupt ELF)"; patchelf --force-rpath --set-rpath "\$ORIGIN:${WG_REL32}" "$f" 2>/dev/null || echo "FATAL: patchelf --force-rpath also failed on $f"; }
done

for f in "${UNIX64}/"winedmo.so; do patchelf --set-rpath "\$ORIGIN" "$f" 2>/dev/null || { echo "WARNING: patchelf failed on $f, trying with --force-rpath"; patchelf --force-rpath --set-rpath "\$ORIGIN" "$f" 2>/dev/null || echo "FATAL: patchelf --force-rpath failed on $f"; }; done
for f in "${UNIX32}/"winedmo.so; do patchelf --set-rpath "\$ORIGIN" "$f" 2>/dev/null || { echo "WARNING: patchelf failed on $f, trying with --force-rpath"; patchelf --force-rpath --set-rpath "\$ORIGIN" "$f" 2>/dev/null || echo "FATAL: patchelf --force-rpath failed on $f"; }; done

cp -a /opt/icu68/win64/*.dll "${PE64}/" 2>/dev/null || true
cp -a /opt/icu68/win32/*.dll "${PE32}/" 2>/dev/null || true

mv "/build/${DEST}" "/output/gwine-${TIMESTAMP}"
ln -sfn "gwine-${TIMESTAMP}" "/output/gwine-latest"
echo "=== Build done: /output/gwine-${TIMESTAMP} ==="
CONTAINER_SCRIPT
