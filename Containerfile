FROM fedora:43

RUN dnf upgrade -y && \
    dnf install -y \
  git make ccache gcc-c++ mingw32-gcc mingw32-gcc-c++ mingw32-cpp \
  mingw64-gcc mingw64-gcc-c++ mingw64-cpp \
  wayland-devel sdl2-compat-devel openal-soft-devel opencl-headers ocl-icd-devel \
  libvkd3d-devel icoutils vulkan-loader-devel vulkan-headers \
  lcms2-devel mpg123-devel libva-devel fontforge gsm-devel \
  libjpeg-turbo-devel systemd-devel libv4l-devel pulseaudio-libs-devel \
  xz audiofile-devel giflib-devel ImageMagick-devel libpcap-devel \
  alsa-lib-devel autoconf bison coreutils cups-devel dbus-devel \
  desktop-file-utils flex fontconfig-devel freetype-devel freeglut-devel \
  gawk gettext-devel gnutls-devel krb5-devel libattr-devel \
  libpng-devel librsvg2-devel libstdc++-devel libtiff-devel \
  libX11-devel libXcomposite-devel libXcursor-devel libXext-devel \
  libXi-devel libXinerama-devel libxml2-devel libXmu-devel \
  libXrandr-devel libXrender-devel libxslt-devel libXxf86vm-devel \
  mesa-libGL-devel mesa-libEGL-devel ncurses-devel openldap-devel \
  sane-backends-devel unixODBC-devel unzip util-linux \
  zlib-ng-compat-devel wget2 python3-pefile rust cargo glslang patch \
  libgcrypt-devel libXpresent-devel yasm jq pkgconf-pkg-config \
  gcc nasm patchelf curl tar libdrm-devel libxkbcommon-devel \
  libunwind-devel vulkan-devel meson && \
  dnf install -y gstreamer1-devel gstreamer1-plugins-base-devel gtk3-devel && \
  dnf install -y \
  pkgconf.i686 gcc-c++.i686 glibc-devel.i686 libX11-devel.i686 \
  wayland-devel.i686 libXcomposite-devel.i686 \
  libXcursor-devel.i686 libXext-devel.i686 libXi-devel.i686 \
  libXinerama-devel.i686 libxml2-devel.i686 libXmu-devel.i686 \
  libXrandr-devel.i686 libXrender-devel.i686 libxslt-devel.i686 \
  libXxf86vm-devel.i686 mesa-libGL-devel.i686 mesa-libEGL-devel.i686 \
  ncurses-devel.i686 openldap-devel.i686 freetype-devel.i686 \
  sdl2-compat-devel.i686 openal-soft-devel.i686 libvkd3d-devel.i686 \
  lcms2-devel.i686 libva-devel.i686 giflib-devel.i686 libpcap-devel.i686 \
  alsa-lib-devel.i686 cups-devel.i686 dbus-devel.i686 \
  fontconfig-devel.i686 libjpeg-turbo-devel.i686 libpng-devel.i686 \
  pulseaudio-libs-devel.i686 gnutls-devel.i686 krb5-devel.i686 \
  krb5-libs.i686 libstdc++-devel.i686 vulkan-loader-devel.i686 \
  libv4l-devel.i686 gsm-devel.i686 sane-backends-devel.i686 \
  libXfixes-devel.i686 libgcrypt-devel.i686 libXpresent-devel.i686 \
  libdrm-devel.i686 libglvnd-devel.i686 libunwind-devel.i686 \
  libxkbcommon-devel.i686 zlib-ng-compat-devel.i686 mpg123-devel.i686 \
  orc-devel.i686 sysprof-capture-devel.i686 libffi-devel.i686 \
  pcre2-devel.i686 libgudev-devel.i686 mesa-libgbm-devel.i686 \
  libxcb-devel.i686 elfutils-devel.i686 libXau-devel.i686 \
  systemd-devel.i686 libzstd-devel.i686 libcap-devel.i686 ocl-icd-devel.i686 && \
  mkdir -p /tmp/i686-rpms && \
  dnf download --destdir=/tmp/i686-rpms --resolve glib2-devel.i686 gstreamer1-devel.i686 gstreamer1-plugins-base-devel.i686 gtk3-devel.i686 2>/dev/null || true; \
  if ls /tmp/i686-rpms/*.rpm 1>/dev/null 2>&1; then \
    rpm -ivh --replacefiles --nodeps /tmp/i686-rpms/*.rpm 2>/dev/null || true; \
  fi; \
  rm -rf /tmp/i686-rpms

ARG FFMPEG_VER=8.1

RUN curl -L "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VER}.tar.xz" | tar xJ -C /tmp && \
    cd /tmp/ffmpeg-${FFMPEG_VER} && \
    FFMPEG64_OPTS="--enable-shared --disable-static --disable-programs --disable-doc --disable-inline-asm --disable-all --enable-avcodec --enable-avfilter --enable-avutil --enable-swresample --enable-avformat --enable-swscale --enable-bsfs --enable-zlib --enable-protocol=file --enable-filter=scale --enable-decoder=vc1,vc1image,wmv3,wmv3image,wmv2,wmv1,wmav1,wmav2,wmapro,wmalossless,xma1,xma2 --enable-decoder=h264,hevc,aac,mp3,flac,mpeg4,mpegvideo,mpeg1video,msmpeg4v1,msmpeg4v2,msmpeg4v3 --enable-decoder=gif,apng,mp2,indeo5,adpcm_ms,alac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f32be,pcm_u8,pcm_mulaw,pcm_alaw --enable-demuxer=asf,xwma,matroska,mp4,aac,ogg,mov,mp3,flac,wav,flv,mpegts --enable-muxer=asf,asf_stream,flv,mp4,dash,webm,mpegts --enable-parser=mpeg4video,h264,hevc" && \
    ./configure --prefix=/opt/ffmpeg64 --libdir=/opt/ffmpeg64/lib ${FFMPEG64_OPTS} --target-os=linux --arch=x86_64 && \
    make -j$(nproc) && make install && make distclean 2>/dev/null || true

RUN cd /tmp/ffmpeg-${FFMPEG_VER} && \
    FFMPEG32_OPTS="--enable-shared --disable-static --disable-programs --disable-doc --disable-inline-asm --disable-all --enable-avcodec --enable-avfilter --enable-avutil --enable-swresample --enable-avformat --enable-swscale --enable-bsfs --enable-zlib --enable-protocol=file --enable-filter=scale --enable-decoder=vc1,vc1image,wmv3,wmv3image,wmv2,wmv1,wmav1,wmav2,wmapro,wmalossless,xma1,xma2 --enable-decoder=h264,hevc,aac,mp3,flac,mpeg4,mpegvideo,mpeg1video,msmpeg4v1,msmpeg4v2,msmpeg4v3 --enable-decoder=gif,apng,mp2,indeo5,adpcm_ms,alac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f32be,pcm_u8,pcm_mulaw,pcm_alaw --enable-demuxer=asf,xwma,matroska,mp4,aac,ogg,mov,mp3,flac,wav,flv,mpegts --enable-muxer=asf,asf_stream,flv,mp4,dash,webm,mpegts --enable-parser=mpeg4video,h264,hevc" && \
    export PKG_CONFIG_PATH="/usr/lib/pkgconfig" CFLAGS="-m32" LDFLAGS="-m32 -L/usr/lib" && \
    ./configure --prefix=/opt/ffmpeg32 --libdir=/opt/ffmpeg32/lib ${FFMPEG32_OPTS} --target-os=linux --arch=x86_32 --host-cflags="-m32" --host-ldflags="-m32 -L/usr/lib" && \
    make -j$(nproc) && make install && rm -rf /tmp/ffmpeg-${FFMPEG_VER}

RUN cp /opt/ffmpeg64/lib/pkgconfig/*.pc /usr/lib64/pkgconfig/ && \
    cp /opt/ffmpeg32/lib/pkgconfig/*.pc /usr/lib/pkgconfig/ && \
    echo "/opt/ffmpeg64/lib" > /etc/ld.so.conf.d/ffmpeg64.conf && \
    echo "/opt/ffmpeg32/lib" > /etc/ld.so.conf.d/ffmpeg32.conf && \
    ldconfig && \
    for f in /opt/ffmpeg64/lib/libav*.so.* /opt/ffmpeg64/lib/libsw*.so.*; do patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true; done && \
    for f in /opt/ffmpeg32/lib/libav*.so.* /opt/ffmpeg32/lib/libsw*.so.*; do patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true; done

ARG GST_VER=1.26.11

RUN dnf install -y meson git && \
    git clone --depth 1 --branch "${GST_VER}" https://gitlab.freedesktop.org/gstreamer/gstreamer.git /tmp/gstreamer && \
    cd /tmp/gstreamer/subprojects/gst-libav && \
    PKG_CONFIG_PATH="/opt/ffmpeg64/lib/pkgconfig:/usr/lib64/pkgconfig" \
    meson setup build64 \
      --prefix=/opt/gst-libav64 \
      --buildtype=release && \
    meson compile -C build64 -j$(nproc) && \
    meson install -C build64 && \
    rm -rf build64 && \
    PKG_CONFIG_PATH="/opt/ffmpeg32/lib/pkgconfig:/usr/lib/pkgconfig" \
    CFLAGS="-m32" CXXFLAGS="-m32" LDFLAGS="-m32 -L/usr/lib" \
    meson setup build32 \
      --prefix=/opt/gst-libav32 \
      --libdir=/opt/gst-libav32/lib \
      --buildtype=release && \
    meson compile -C build32 -j$(nproc) && \
    meson install -C build32 && \
    rm -rf /tmp/gstreamer

RUN for f in /opt/gst-libav64/lib64/gstreamer-1.0/libgst*.so; do patchelf --set-rpath '/opt/ffmpeg64/lib' "$f" 2>/dev/null || true; done && \
    for f in /opt/gst-libav32/lib/gstreamer-1.0/libgst*.so; do patchelf --set-rpath '/opt/ffmpeg32/lib' "$f" 2>/dev/null || true; done

ARG ICU_VER=68_2
RUN mkdir -p /opt/icu68/win64 /opt/icu68/win32 && \
    curl -L "https://github.com/unicode-org/icu/releases/download/release-${ICU_VER/_/-}/icu4c-${ICU_VER}-Win64-MSVC2019.zip" -o /tmp/icu64.zip && \
    unzip -j /tmp/icu64.zip "bin64/icuuc68.dll" "bin64/icuin68.dll" "bin64/icudt68.dll" -d /opt/icu68/win64 && \
    curl -L "https://github.com/unicode-org/icu/releases/download/release-${ICU_VER/_/-}/icu4c-${ICU_VER}-Win32-MSVC2019.zip" -o /tmp/icu32.zip && \
    unzip -j /tmp/icu32.zip "bin/icuuc68.dll" "bin/icuin68.dll" "bin/icudt68.dll" -d /opt/icu68/win32 && \
    rm -f /tmp/icu64.zip /tmp/icu32.zip

WORKDIR /build
