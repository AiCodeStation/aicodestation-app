# AUR package

Source of truth for `aicodestation-bin` in the [Arch User Repository](https://aur.archlinux.org).
Serves Arch Linux, Manjaro, EndeavourOS, and Garuda.

```bash
yay -S aicodestation-bin      # or: paru -S aicodestation-bin
```

This is a **binary** package. It repackages the published `.deb` and does not build from
source, which is why the name carries the `-bin` suffix, as AUR policy requires.

## Why the signature check matters here

`validpgpkeys` pins our release key fingerprint, and the `.asc` in `source=` is the detached
signature. `makepkg` verifies the download against that key before `package()` runs, so a
tampered or corrupted file fails the build instead of reaching the user. The `sha256sums`
entry for the signature is `SKIP` because a signature is verified by GPG, not by checksum.

Anyone building this package must first trust the key:

```bash
gpg --recv-keys E77976A5D8A617528244D939E4E65E9412CD53CA
```

## Confirm `depends` before publishing

The `depends=('glibc' 'gcc-libs')` line is a conservative placeholder. An incomplete list is
the usual reason a package installs cleanly and then fails to launch. Derive the real list
from the `.deb` control file:

```bash
# On any machine with dpkg, or inside an Arch container with the deb downloaded
dpkg-deb -f aicodestation_1.0.30_amd64.deb Depends
```

Then map each Debian package to its Arch equivalent. Common mappings for a Qt or Electron
desktop application:

| Debian | Arch |
|---|---|
| `libc6` | `glibc` |
| `libgcc-s1`, `libstdc++6` | `gcc-libs` |
| `libgtk-3-0` | `gtk3` |
| `libnss3` | `nss` |
| `libasound2` | `alsa-lib` |
| `libxss1` | `libxss` |
| `libqt6*` | `qt6-base`, `qt6-webengine` |

A faster empirical check, run inside a clean Arch container after installing the package:

```bash
find /opt /usr/lib/aicodestation -type f -executable -exec ldd {} \; 2>/dev/null \
  | grep "not found" | sort -u
```

Every missing library must be covered by an entry in `depends`.

## Test before publishing

```bash
makepkg -si          # builds, verifies the signature, installs
namcap PKGBUILD      # lints the PKGBUILD
namcap *.pkg.tar.zst # lints the built package, reports missing dependencies
```

`namcap` on the built package is the important one. It detects the missing dependencies that
`depends` should have listed.

## Publishing

```bash
# One-time: add your SSH key at https://aur.archlinux.org/account
git clone ssh://aur@aur.archlinux.org/aicodestation-bin.git
cd aicodestation-bin
cp ../PKGBUILD .
makepkg --printsrcinfo > .SRCINFO      # required, and must match the PKGBUILD
git add PKGBUILD .SRCINFO
git commit -m "Initial import: aicodestation-bin 1.0.30"
git push
```

`.SRCINFO` is generated, never hand-edited. AUR rejects a push where it disagrees with the
PKGBUILD.

## On every new release

Update `pkgver`, reset `pkgrel=1`, refresh `sha256sums`, regenerate `.SRCINFO`, and push. The
checksum for each build is published at <https://aicodestation.com/downloads/> and in the
signed `SHA256SUMS.txt.asc`.
