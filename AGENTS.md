# AGENTS.md — Guide pour les agents IA

## Projet

gwine est un build personnalisé de Wine construit via wine-tkg-git (Frogging-Family). Le dépôt contient uniquement le workflow CI et les patches — le code source Wine est cloné depuis wine-tkg-git lors du build.

## Variants

| Variant | Base | Container CI | winedmo | Description |
|---------|------|-------------|---------|-------------|
| gwine | Wine mainline + staging | artixlinux/artixlinux:latest | Non (upstream n'a pas le code) | Build Wine classique |
| gwine-proton | Valve proton-experimental-bleeding-edge | artixlinux/artixlinux:latest | Non (pas de FFmpeg) | Build basé sur l'arbre Valve |
| gwine-proton-beta | Valve proton-experimental-bleeding-edge | fedora:43 | Oui (FFmpeg shared bundle) | Build expérimental avec winedmo pour la lecture vidéo |

## Fichiers importants

- `.github/workflows/build-gwine.yml` — Workflow CI unique, matrix avec 3 variants
- `patches/*.mypatch` — Patches personnalisés copiés dans wine-tkg-userpatches/
  - `gamepad_axis_32bit_fix.mypatch` — Force axes 32-bit pour compat DirectInput (gwine uniquement)

## Build

- Déclenchement manuel (`workflow_dispatch`)
- wine-tkg-git est cloné, configuré via sed, puis `non-makepkg-build.sh` est exécuté
- Les releases sont des `.tar.xz` avec conservation des 3 dernières par variant

## winedmo (Media Foundation FFmpeg backend)

winedmo est le backend MF basé sur FFmpeg (MR Wine !6442, patchset Valve-only). Il remplace winegstreamer pour le décodage vidéo quand il est disponible.

**Pourquoi seulement sur gwine-proton-beta :**
- L'arbre Wine upstream (gwine) n'a pas le code winedmo
- gwine-proton (Artix) aurait un glibc trop récent pour Fedora/uBlue → FFmpeg .so incompatibles
- gwine-proton-beta utilise Fedora 43 → même glibc que le système cible

**FFmpeg est compilé en shared (.so)** avec les flags GE-Proton :
- ~40 décodeurs (vc1, wmv1-3, h264, hevc, aac, mpeg4...)
- swscale activé (requis pour la conversion pixel format)
- Demuxers asf, xwma, matroska, mp4...
- `.so` bundlés dans le package Wine avec `$ORIGIN` rpath

## Conventions de commits

Format : `[variant] type: message`

- variant : `gwine`, `gwine-proton`, `gwine-proton-beta`, ou `all`
- type : `feat`, `fix`, `chore`, `ci`
- Exemples : `[gwine-proton-beta] feat: add FFmpeg build for winedmo`, `[all] fix: correct rpath on winedmo.so`

## Langue

- Code et documentation en français
- Messages de commit en anglais
