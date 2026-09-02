# Packaging and distribution channels

Manifests that put AiCodeStation into the package managers users already have, so it can be
installed and, more importantly, **updated with a verified signature** rather than by
downloading an installer from a web page.

| Channel | Reaches | Status | Files |
|---|---|---|---|
| [winget](winget/) | Windows 10 / 11 | Ready to submit | `winget/<version>/` |
| [AUR](aur/) | Arch, Manjaro, EndeavourOS | Ready to submit | `aur/PKGBUILD` |
| AppImageHub | AppImage users | See below | none yet |
| Flathub | GNOME Software, KDE Discover | Not started | none yet |

Each channel has its own README with the fields to confirm before submitting and how to test
locally. Read those first. Both submissions carry a placeholder that must be verified against
the real build, and getting either wrong is the usual cause of a rejected submission.

## Release checklist

Run `Update-Release.ps1` rather than editing versions by hand. It reads the signed
`SHA256SUMS.txt.asc`, so a wrong checksum cannot reach a public page.

1. Publish the build and its signed checksums
2. Run `Update-Release.ps1 -Version <new>`, review the diff, push
3. Submit the refreshed winget manifest
4. Push the refreshed PKGBUILD to AUR

## AppImageHub

AppImageHub catalogues AppImages and is worth doing because the AppImage build already exists.
Two things are worth knowing before spending time on it:

**The catalogue reads metadata from inside the AppImage.** It expects an embedded AppStream
`metainfo.xml`, a `.desktop` entry, and an icon. If those are missing or thin, the listing shows
poorly or is rejected. Check what the current build actually carries before submitting:

```bash
./AiCodeStation-1.0.30-x86_64.AppImage --appimage-extract
ls squashfs-root/usr/share/metainfo/    # AppStream metadata
cat squashfs-root/*.desktop             # desktop entry
```

**Update information is what makes it useful.** An AppImage built with embedded update
information can update itself through `AppImageUpdate` and delta-download only what changed,
which matters for a 450 MB file. That is a build-time flag on the AppImage tooling, not
something a manifest can add afterwards.

Submission itself goes through the
[AppImage/appimage.github.io](https://github.com/AppImage/appimage.github.io) repository. Follow
the process documented there at the time of submission rather than a copy of it here, since it
has changed more than once.

## Flathub

The largest Linux channel by reach: it is what appears inside GNOME Software and KDE Discover,
so users find the application without ever visiting our website.

It is also the hardest fit for this product, and that should be understood before committing
time to it. Flatpak runs applications in a sandbox with declared permissions. AiCodeStation
runs the user's own tools, scripts, and repositories, which is close to the opposite of what
the sandbox is designed to allow. A working package would need broad permissions such as
`--filesystem=home` and host command execution, reviewers scrutinise exactly those, and some
functionality may not survive the sandbox at all.

Worth attempting only after the cheaper channels are live.
