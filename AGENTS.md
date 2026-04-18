# AGENTS.md — Guide pour les agents IA

## Projet

gwine est un build personnalisé de Wine construit via wine-tkg-git (Frogging-Family). Le dépôt contient uniquement les workflows CI et les patches — le code source Wine est cloné depuis wine-tkg-git lors du build.

## Variants

| Variant | Base | Container CI | winedmo | Description |
|---------|------|-------------|---------|-------------|
| gwine | Wine mainline + staging | artixlinux/artixlinux:latest | Non (upstream n'a pas le code) | Build Wine classique |
| gwine-proton | Valve proton-experimental-bleeding-edge | artixlinux/artixlinux:latest | Non (pas de FFmpeg) | Build basé sur l'arbre Valve |
| gwine-proton-beta | Valve proton-experimental-bleeding-edge | fedora:43 | Oui (FFmpeg shared bundle) | Build expérimental avec winedmo pour la lecture vidéo |

## Fichiers importants

- `.github/workflows/build-gwine.yml` — Workflow CI gwine + gwine-proton (`workflow_dispatch` uniquement)
- `.github/workflows/build-gwine-beta.yml` — Workflow CI gwine-proton-beta (push sur `main` + `workflow_dispatch`)
- `Containerfile` — Image Podman de base pour build local (deps + FFmpeg 32+64-bit + gst-libav)
- `test-build.sh` — Script de build local via Podman (output dans `/tmp/gwine-output/`)
- `patches/*.mypatch` — Patches personnalisés copiés dans wine-tkg-userpatches/
  - `gamepad_axis_32bit_fix.mypatch` — Force axes 32-bit pour compat DirectInput (gwine uniquement, exclu de gwine-proton-beta)

## Build

- gwine/gwine-proton : déclenchement manuel (`workflow_dispatch`)
- gwine-proton-beta : déclenchement sur push `main` + `workflow_dispatch`
- wine-tkg-git est cloné, configuré via sed, puis `non-makepkg-build.sh` est exécuté
- Le dependency auto-resolver de wine-tkg est désactivé (`_nomakepkg_dependency_autoresolver="false"`) car les noms de packages sont obsolètes pour Fedora 43
- Les releases sont des `.tar.xz` avec conservation des 3 dernières par variant
- gwine-proton-beta releases sont marquées `prerelease: true`

## Build local (Podman)

L'image de base `gwine-beta-build` contient les deps + FFmpeg + gst-libav (cachée après le 1er build).

```bash
bash test-build.sh
```

L'output va dans `/tmp/gwine-output/gwine-proton-test/`.

**Notes techniques :**
- `podman run -i` requis pour passer le script via heredoc stdin
- Volume output monté avec `:z` (SELinux sur Kinoite)
- `non-makepkg-build.sh` appelé dans un subshell `( yes | ./non-makepkg-build.sh ) || true` car le script appelle `exit` à la fin

## winedmo (Media Foundation FFmpeg backend)

winedmo est le backend MF basé sur FFmpeg (MR Wine !6442, patchset Valve-only). Il remplace winegstreamer pour le décodage vidéo quand il est disponible.

**Architecture winedmo + winegstreamer :**
- **winedmo** = démuxeur FFmpeg (lit les conteneurs asf, mp4, mkv...) — géré par `dlls/winedmo/unix_demuxer.c`
- **winegstreamer** = décodeurs MFT H.264/AAC (transcode les flux compressés) — géré par `dlls/winegstreamer/video_decoder.c`
- Les deux travaillent ensemble : winedmo ouvre le fichier, puis le topology loader cherche un décodeur MFT via `MFTEnumEx()`
- Si winegstreamer ne trouve pas de plugins GStreamer → erreur `GStreamer doesn't support H.264 decoding`
- **Solution** : bundler `gst-libav` (plugin GStreamer qui wrappe FFmpeg) compilé contre notre FFmpeg custom

**Pourquoi seulement sur gwine-proton-beta :**
- L'arbre Wine upstream (gwine) n'a pas le code winedmo
- gwine-proton (Artix) aurait un glibc trop récent pour Fedora/uBlue → FFmpeg .so incompatibles
- gwine-proton-beta utilise Fedora 43 → même glibc que le système cible (uBlue)

**FFmpeg est compilé en shared (.so)** avec les flags GE-Proton :
- ~40 décodeurs (vc1, wmv1-3, h264, hevc, aac, mpeg4...)
- swscale activé (requis pour la conversion pixel format)
- Demuxers asf, xwma, matroska, mp4...
- 32-bit et 64-bit compilés dans le container Fedora 43
- `.so` bundlés dans le package Wine avec `$ORIGIN` rpath
  - 32-bit → `lib/wine/i386-unix/` (libav*.so, libsw*.so)
  - 64-bit → `lib64/wine/x86_64-unix/` (libav*.so, libsw*.so)
- `.pc` copiés dans les dirs système + `ldconfig` pour que Wine configure trouve FFmpeg
- `--with-ffmpeg` passé aux configure args 32+64 bit
- `patchelf --set-rpath '$ORIGIN'` appliqué sur winedmo.so et tous les FFmpeg .so

**gst-libav** (GStreamer FFmpeg plugin) :
- Compilé depuis le source contre notre FFmpeg custom (version Fedora trop ancienne)
- Version 1.26.11 (match la version GStreamer du système)
- 64-bit installé dans `/opt/gst-libav64/lib/gstreamer-1.0/`
- 32-bit installé dans `/opt/gst-libav32/lib/gstreamer-1.0/`
- Bundlé dans le package Wine :
  - 32-bit → `lib32/gstreamer-1.0/` (rpath → `$ORIGIN/../../wine/i386-unix`)
  - 64-bit → `lib64/gstreamer-1.0/` (rpath → `$ORIGIN/../../wine/x86_64-unix`)
- Au runtime, `GST_PLUGIN_SYSTEM_PATH_1_0` doit pointer vers ces dirs

## Problèmes connus (Fedora 43 container)

### Renommages de packages Fedora 43
- `zlib-devel` → `zlib-ng-compat-devel` (zlib-ng transition)
- `SDL2-devel` → `sdl2-compat-devel` (Fedora 43 SDL3 migration)
- `vulkan-devel` → `vulkan-loader-devel` + `vulkan-headers`
- `libudev-devel` → `systemd-devel`
- `libmpg123-devel` → `mpg123-devel`
- `wget` → `wget2`
- `python-pefile` → `python3-pefile`

### Packages supprimés de Fedora 43
- `fontpackages-devel` — obsolète
- `mesa-libGLU-devel` — retiré de Fedora 43
- `libpng-static.x86_64` — retiré
- `libXxf86dga-devel` — retiré

### Conflits .gir i686/x86_64
Certains packages i686 installent les mêmes fichiers `.gir` dans `/usr/share/gir-1.0/` que leur contrepartie x86_64. `rpm` refuse d'écraser. Solution : télécharger les RPMs et forcer l'install avec `rpm -ivh --replacefiles --nodeps` (install, PAS upgrade — `rpm -Uvh` remplace le package x86_64 et supprime ses `.pc`).

Packages concernés : `glib2-devel.i686`, `gstreamer1-devel.i686`, `gstreamer1-plugins-base-devel.i686`, `gtk3-devel.i686`

**Ordre d'installation important** : les packages x86_64 (`gstreamer1-devel`, `gstreamer1-plugins-base-devel`, `gtk3-devel`) doivent être installés AVANT les i686. Sinon le conflit libstdc++ entre repos updates/fedora fait sauter les x86_64 par dnf.

### Autres problèmes
- **`libgphoto2-devel`** : échec à l'install (conflit systemd/lockdev dans le container). Skip — Wine se compile sans.
- **`libavformat-free-devel`** + `.i686` : provoque un conflit `noopenh264`/`openh264` entre i686 et x86_64. On build notre propre FFmpeg donc pas besoin.
- **`--allowerasing`** : NE JAMAIS utiliser ce flag dnf dans le container. Il peut supprimer des packages critiques (glibc, util-linux) et casser le toolchain 32-bit.
- **systemd-standalone-tmpfiles** : présent dans le container de base, conflit avec le paquet systemd. Ne pas tenter d'installer systemd avec `--allowerasing`.
- **Toolchain 32-bit** : les packages `glibc-devel.i686`, `libgcc.i686`, `libstdc++-devel.i686` doivent être installés AVANT le build FFmpeg 32-bit. Les `.pc` et `ldconfig` doivent être configurés avant le configure Wine.
- **`non-makepkg-build.sh` appelle `exit`** : tue le shell parent. Workaround : subshell `( yes | ./non-makepkg-build.sh ) || true`.
- **`meson` disparaît après les installs i686** : en réalité, `meson` restait installé. Le vrai problème était `rpm -Uvh` (upgrade) qui remplaçait les packages x86_64 par i686, supprimant les `.pc` x86_64 de `/usr/lib64/pkgconfig/`. Fix : `rpm -ivh` (install, pas upgrade). Un `dnf install -y meson` de sécurité est aussi ajouté avant le build gst-libav.

### winegstreamer.so 32-bit manquant — CAUSE RACINE ET FIX

Wine's `configure` **override `PKG_CONFIG_LIBDIR`** pour le build 32-bit (ligne 6544) : `PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR:-/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib32/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig}`. Cela **remplace** le chemin de recherche par défaut (qui inclut `/usr/lib64/pkgconfig/`), donc les dépendances transitives (orc, sysprof, libffi, pcre2, gudev, gbm, xcb, elfutils, xau, libudev, libzstd, libcap) ne sont pas trouvées car leurs `.pc` sont seulement dans `/usr/lib64/pkgconfig/`. Résultat : `GSTREAMER_CFLAGS` vide → `gst/gst.h` pas trouvé → winegstreamer désactivé.

**Fix** : installer tous les packages i686 des dépendances transitives pour que leurs `.pc` atterrissent dans `/usr/lib/pkgconfig/` :
- `orc-devel.i686`, `sysprof-capture-devel.i686`, `libffi-devel.i686`, `pcre2-devel.i686`, `libgudev-devel.i686`, `mesa-libgbm-devel.i686`, `libxcb-devel.i686`, `elfutils-devel.i686`, `libXau-devel.i686`, `systemd-devel.i686`, `libzstd-devel.i686`, `libcap-devel.i686`

## gst-libav — TERMINÉ

- Containerfile : build gst-libav 64+32 bit (meson) + rpath vers FFmpeg + `dnf install -y meson` de sécurité + `rpm -ivh` (pas `-Uvh`)
- CI workflow : étape "Build gst-libav for winegstreamer" + bundling dans Package + `dnf install -y meson` + `rpm -ivh`
- test-build.sh : copie gst-libav + rpath dans l'output (chemin `lib64` corrigé pour 64-bit)
- winegstreamer.so 32-bit : fix via les i686 transitive deps
- **Runtime vérifié** : vidéos H.264 fonctionnent dans Donkey Kong Country avec gst-libav + FFmpeg bundlés

## Conventions de commits

Format : `[variant] type: message`

- variant : `gwine`, `gwine-proton`, `gwine-proton-beta`, ou `all`
- type : `feat`, `fix`, `chore`, `ci`
- Exemples : `[gwine-proton-beta] feat: add FFmpeg build for winedmo`, `[all] fix: correct rpath on winedmo.so`

## Langue

- Code et documentation en français
- Messages de commit en anglais
