# gwine

Custom Wine build for [Gablue](https://github.com/elgabo86/gablue), based on Valve's Proton experimental tree.

## Key features

- **winedmo** — Media Foundation FFmpeg backend (demuxing: ASF, MP4, MKV…)
- **winegstreamer** — Bundled GStreamer + gst-libav (H.264/AAC/WMA decoding)
- **ICU 68** — Bundled DLLs for Unicode-aware games
- **Custom patches** — CPUID faulting, username passthrough, content sniffing fallback, M4S2/MPEG-4 decoder, NV12 & buffer stride fixes
- **Shared FFmpeg** — ~40 codecs compiled in, `$ORIGIN` rpath for self-contained deployment
- **Built on Fedora 44** — same glibc/GLib as the target Gablue system

## Build

Uses [wine-tkg-git](https://github.com/Frogging-Family/wine-tkg-git) with the `valve-exp-bleeding` preset. The CI workflow runs on `fedora:44`.

### Local build (Podman)

```bash
bash test-build.sh              # Build with cache
bash test-build.sh --no-cache   # Rebuild container image from scratch
```

Output goes to `~/Downloads/gwine-output/gwine-{timestamp}/`.

### CI

Triggered manually via `workflow_dispatch` (`build-gwine.yml`). The latest 3 releases are kept.

## Releases

Each release is a `gwine-{version}.tar.xz` archive containing a self-contained Wine tree with bundled FFmpeg, GStreamer plugins, and ICU DLLs. Ready to extract and use — no system dependencies beyond glibc.

Used by the [gwine launcher](https://github.com/elgabo86/gablue/tree/main/src/gwine-launcher) which handles download, extraction, and runtime configuration.

## License

See [LICENSE](LICENSE).
