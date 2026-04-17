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
- `patches/*.mypatch` — Patches personnalisés copiés dans wine-tkg-userpatches/
  - `gamepad_axis_32bit_fix.mypatch` — Force axes 32-bit pour compat DirectInput (gwine uniquement)

## Build

- gwine/gwine-proton : déclenchement manuel (`workflow_dispatch`)
- gwine-proton-beta : déclenchement sur push `main` + `workflow_dispatch`
- wine-tkg-git est cloné, configuré via sed, puis `non-makepkg-build.sh` est exécuté
- Les releases sont des `.tar.xz` avec conservation des 3 dernières par variant
- gwine-proton-beta releases sont marquées `prerelease: true`

## winedmo (Media Foundation FFmpeg backend)

winedmo est le backend MF basé sur FFmpeg (MR Wine !6442, patchset Valve-only). Il remplace winegstreamer pour le décodage vidéo quand il est disponible.

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
- `.pc` copiés dans les dirs système + `ldconfig` pour que Wine configure trouve FFmpeg
- `--with-ffmpeg` passé aux configure args 32+64 bit

## Problèmes connus (Fedora 43 container)

- **`libgphoto2-devel`** : échec à l'install (conflit systemd/lockdev dans le container). Patch `|| true` sur le script deps wine-tkg pour continuer malgré l'absence.
- **`SDL2-devel.i686`** et **`gstreamer1-devel.i686`** : n'existent pas dans les repos Fedora 43. Wine se compile sans (SDL2 64-bit OK, winedmo remplace winegstreamer pour la vidéo). Non bloquant mais à investiguer.
- **`--allowerasing`** : NE JAMAIS utiliser ce flag dnf dans le container. Il peut supprimer des packages critiques (glibc, util-linux) et casser le toolchain 32-bit.
- **systemd-standalone-tmpfiles** : présent dans le container de base, conflit avec le paquet systemd. Ne pas tenter d'installer systemd avec `--allowerasing`.
- **Toolchain 32-bit** : les packages `glibc-devel.i686`, `libgcc.i686`, `libstdc++-devel.i686` doivent être installés AVANT le build FFmpeg 32-bit. Les `.pc` et `ldconfig` doivent être configurés avant le configure Wine.

## Patches appliqués au script wine-tkg-scripts/deps (beta uniquement)

1. `dnf ${_confirm_str}install` → `dnf ${_confirm_str}install --skip-broken` : les packages i686 absents ne font pas échouer le build
2. `|| return 1` → `|| true` : un package qui fail après 3 tentatives ne tue pas le build

## Conventions de commits

Format : `[variant] type: message`

- variant : `gwine`, `gwine-proton`, `gwine-proton-beta`, ou `all`
- type : `feat`, `fix`, `chore`, `ci`
- Exemples : `[gwine-proton-beta] feat: add FFmpeg build for winedmo`, `[all] fix: correct rpath on winedmo.so`

## Langue

- Code et documentation en français
- Messages de commit en anglais
