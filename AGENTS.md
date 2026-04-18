# AGENTS.md — Guide pour les agents IA

## Projet

gwine est un build personnalisé de Wine construit via wine-tkg-git (Frogging-Family). Le dépôt contient uniquement les workflows CI et les patches — le code source Wine est cloné depuis wine-tkg-git lors du build.

## Variants

| Variant | Base | Container CI | winedmo | Description |
|---------|------|-------------|---------|-------------|
| gwine | Wine mainline + staging | artixlinux/artixlinux:latest | Non (topology_loader stub) | Build Wine classique, pas de vidéo MF |
| gwine-proton | Valve proton-experimental-bleeding-edge | fedora:43 | Oui (FFmpeg shared bundle) | Build basé sur l'arbre Valve avec winedmo pour la lecture vidéo |

## Fichiers importants

- `.github/workflows/build-gwine.yml` — Workflow CI gwine + gwine-proton (`workflow_dispatch` uniquement)
- `Containerfile` — Image Podman de base pour build local (deps + FFmpeg 32+64-bit + gst-libav)
- `test-build.sh` — Script de build local gwine-proton via Podman (output dans `/tmp/gwine-output/`)
- `test-build-gwine.sh` — Script de build local gwine via Podman (output dans `/tmp/gwine-output/`)
- `patches/*.mypatch` — Patches personnalisés copiés dans wine-tkg-userpatches/
  - `gamepad_axis_32bit_fix.mypatch` — Force axes 32-bit pour compat DirectInput (gwine uniquement, exclu de gwine-proton)
  - `winegstreamer_nv12_buffer_fix.mypatch` — Fix buffer size mismatch NV12 dans winegstreamer (gwine + gwine-proton, voir section dédiée)

## Build

- gwine/gwine-proton : déclenchement manuel (`workflow_dispatch`)
- wine-tkg-git est cloné, configuré via sed, puis `non-makepkg-build.sh` est exécuté
- Le dependency auto-resolver de wine-tkg est désactivé (`_nomakepkg_dependency_autoresolver="false"`) car les noms de packages sont obsolètes pour Fedora 43
- Les releases sont des `.tar.xz` avec conservation des 3 dernières par variant

## Build local (Podman)

L'image de base `gwine-build` contient les deps + FFmpeg + gst-libav (cachée après le 1er build).

```bash
bash test-build.sh        # gwine-proton
bash test-build-gwine.sh  # gwine
```

L'output va dans `/tmp/gwine-output/gwine-proton-{timestamp}/` (ou `gwine-{timestamp}/`), avec un symlink `*-latest` vers la plus récente.

**Notes techniques :**
- `podman run -i` requis pour passer le script via heredoc stdin
- **Volumes SELinux** : sur Kinoite, TOUS les volumes montés dans le conteneur doivent avoir le flag `:z` (ou `:ro,z` pour read-only). Sans `:z`, le conteneur ne peut pas lire les fichiers (Permission denied silencieux). Le volume patches (`/patches:ro,z`) et output (`/output:z`) le sont déjà — ne pas oublier pour tout nouveau volume.
- `non-makepkg-build.sh` appelé dans un subshell `( yes | ./non-makepkg-build.sh ) || true` car le script appelle `exit` à la fin

## winedmo (Media Foundation FFmpeg backend)

winedmo est le backend MF basé sur FFmpeg (MR Wine !6442, patchset Valve-only). Il remplace winegstreamer pour le décodage vidéo quand il est disponible.

**Architecture winedmo + winegstreamer :**
- **winedmo** = démuxeur FFmpeg (lit les conteneurs asf, mp4, mkv...) — géré par `dlls/winedmo/unix_demuxer.c`
- **winegstreamer** = décodeurs MFT H.264/AAC (transcode les flux compressés) — géré par `dlls/winegstreamer/video_decoder.c`
- Les deux travaillent ensemble : winedmo ouvre le fichier, puis le topology loader cherche un décodeur MFT via `MFTEnumEx()`
- Si winegstreamer ne trouve pas de plugins GStreamer → erreur `GStreamer doesn't support H.264 decoding`
- **Solution** : bundler `gst-libav` (plugin GStreamer qui wrappe FFmpeg) compilé contre notre FFmpeg custom

**Pourquoi seulement sur gwine-proton :**
- L'arbre Wine upstream (gwine) a winedmo et winegstreamer mais le `topology_loader` de mfplat est un **stub** — il ne connecte pas winedmo → winegstreamer. Résultat : les vidéos MF ne marchent pas, peu importe le bundling FFmpeg/gst-libav. Valve a implémenté le topology loader complet dans son arbre Proton uniquement.
- gwine-proton utilise Fedora 43 → même glibc que le système cible (uBlue)

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

## winegstreamer NV12 buffer size mismatch — EN COURS

**Symptôme** : vidéos H.264 (ex: Legend of Mana) affichent un écran noir, erreur en boucle :
```
videometa gstvideometa.c:424:default_map: plane 1, no memory at offset 2088960
default video-frame.c:168:gst_video_frame_map_id: failed to map video frame plane 1
```

**Cause racine** : dans `dlls/winegstreamer/wg_transform.c`, fonction `wg_transform_push_data`, le GstBuffer de sortie est créé via `gst_buffer_new_wrapped_full` avec `maxsize=sample->max_size` et `size=sample->max_size` (quand `sample->stride != 0`). Pour du NV12 1920×1088 : `max_size=2 088 960` (plan Y seul) mais `sample->size=3 133 440` (Y+UV complet). Le `GstVideoMeta` ajouté ensuite décrit le plan UV à l'offset 2 088 960, qui est au-delà de la mémoire du buffer → `gst_buffer_find_memory` échoue.

Le bug est côté **input** (push des données encodées dans le pipeline GStreamer), pas côté output. L'erreur se manifeste côté output car `videoconvert` essaie de mapper le plan UV du buffer et échoue.

**Fix** (`winegstreamer_nv12_buffer_fix.mypatch`) :
- `maxsize` → `max((gsize)sample->max_size, (gsize)sample->size)` — garantit maxsize >= size
- `size` → toujours `sample->size` au lieu de `sample->stride ? sample->max_size : sample->size` — utilise la vraie taille des données

**Statut** : patch créé, s'applique proprement (0 fuzz) sur l'arbre Valve bleeding-edge. **En attente de validation runtime** — les 3 premiers builds ont échoué à cause du volume SELinux (voir ci-dessous), le patch n'a jamais été copié dans le conteneur. Le patch contient un marqueur debug `[NV12 fix applied]` pour confirmer son application dans les logs.

**Portée** : gwine-proton (CI + local). Exclu de gwine (le topology_loader mfplat est un stub, pas de vidéo MF).

**Note sur les patches wine-tkg** : `patch -Np1` rejette silencieusement les hunks avec fuzz > 0 quand exécuté dans un pipe `yes |`. Toujours vérifier avec `patch -p1 --dry-run` sur un clone de l'arbre cible. Générer le patch via `git diff` garantit un contexte exact.

**Note sur les volumes SELinux** : le volume `/patches` était monté avec `:ro` au lieu de `:ro,z`, ce qui causait un Permission denied silencieux. Le conteneur ne pouvait pas lire les patches, le `cp` échouait silencieusement (`2>/dev/null || true`), et le patch n'était jamais copié dans `wine-tkg-userpatches/`. Fix : `:ro,z` sur TOUS les volumes montés.

## Conventions de commits

Format : `[variant] type: message`

- variant : `gwine`, `gwine-proton`, ou `all`
- type : `feat`, `fix`, `chore`, `ci`
- Exemples : `[gwine-proton] feat: add FFmpeg build for winedmo`, `[all] fix: correct rpath on winedmo.so`

## Langue

- Code et documentation en français
- Messages de commit en anglais
