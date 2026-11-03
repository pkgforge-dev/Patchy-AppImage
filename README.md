<div align="center">

# Patchy-AppImage 🐧

[![GitHub Downloads](https://img.shields.io/github/downloads/pkgforge-dev/Patchy-AppImage/total?logo=github&label=GitHub%20Downloads)](https://github.com/pkgforge-dev/Patchy-AppImage/releases/latest)
[![CI Build Status](https://github.com/pkgforge-dev/Patchy-AppImage/actions/workflows/appimage.yml/badge.svg)](https://github.com/pkgforge-dev/Patchy-AppImage/releases/latest)
[![Latest Stable Release](https://img.shields.io/github/v/release/pkgforge-dev/Patchy-AppImage)](https://github.com/pkgforge-dev/Patchy-AppImage/releases/latest)

<p align="center">
  <img src="https://raw.githubusercontent.com/SethRobinson/Patchy/main/packaging/branding/patchy-logo-folded.svg" width="128" />
</p>

| Latest Stable Release | Upstream URL |
| :---: | :---: |
| [Click here](https://github.com/pkgforge-dev/Patchy-AppImage/releases/latest) | [Click here](https://github.com/SethRobinson/Patchy) |

</div>

---

[Patchy](https://github.com/SethRobinson/Patchy) is a free, open-source image editor focused on accurate PSD compatibility: text, vectors, masks, layer styles and Smart Objects stay editable. It opens Affinity, Krita, GIMP, OpenRaster, Paint.NET, PDF, camera raw and the usual flat formats, runs classic 8BF plug-ins, and can be extended with JavaScript.

This AppImage is built from the upstream release tag, against Arch Linux's Qt 6, and it includes everything the upstream Linux builds ship:

* **GEGL filters**, from Patchy's own GEGL build against babl, with the operation set its legal review allows.
* **Object Selection** and the watermark tools, through ONNX Runtime and the pinned models. The larger "high quality" selection model is still downloaded on first use, exactly as in the Flatpak.
* **PDF import**, through Qt PDF (a Qt without that module still exports PDF, it just cannot open one).

Some things are deliberately left to the host, as in the upstream builds: HEIC/HEIF opens through your distribution's `libheif` (with an HEVC decoder, e.g. `libheif-plugin-libde265` on Ubuntu 24.04+).

The in-app update check is compiled out, since this AppImage updates itself instead; it will never replace itself with a different build.

AppImage made using [quick-sharun](https://github.com/pkgforge-dev/Anylinux-AppImages/blob/main/useful-tools/quick-sharun.sh), which makes it extremely easy to turn any binary into a portable package reliably without using containers or similar tricks. 

**This AppImage bundles everything and it should work on any Linux distro, including old and musl-based ones.**

This AppImage doesn't require FUSE to run at all, thanks to the [uruntime](https://github.com/VHSgunzo/uruntime).

This AppImage is also supplied with a self-updater by default, so any updates to this application won't be missed, you will be prompted for permission to check for updates and if agreed you will then be notified when a new update is available.

Self-updater is disabled by default if AppImage managers like [am](https://github.com/ivan-hc/AM), [soar](https://github.com/pkgforge/soar) or [dbin](https://github.com/xplshn/dbin) exist, which manage AppImage updates.

<details>
  <summary><b><i>raison d'être</i></b></summary>
    <img src="https://github.com/user-attachments/assets/d40067a6-37d2-4784-927c-2c7f7cc6104b" alt="Inspiration Image">
  </a>
</details>

---

More at: [AnyLinux-AppImages](https://pkgforge-dev.github.io/Anylinux-AppImages/)
