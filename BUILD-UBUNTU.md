# Ubuntu / Debian port — build & status

Port of `sorguido/goodix-27c6-5125` (Fedora 44 KDE) to **Ubuntu 26.04**
(Debian family, apt). This document records what works and how to reproduce it.

## Result (summary)

The driver **builds, loads, pairs the chip and authenticates** on Ubuntu 26.04,
with **no Windows material and no pairing bundle**. It self-initialises: it
generates its own PSK and pairs with the sensor on first use, exactly as the
upstream "first-use" path describes.

| Step | Status |
|---|---|
| Build `libfprint` + `goodix_27c6_5125` driver | ✅ |
| Load into `fprintd`, device probe | ✅ |
| Sensor open (`claim` / `open`) | ✅ |
| Preflight (7 commands) | ✅ |
| Self-pairing (PSK generated, E0 write, TLS, E4 = MATCH) | ✅ |
| Enrollment (`fprintd-enroll` → `enroll-completed`) | ✅ |
| Verification (`fprintd-verify` → `verify-match`) | ✅ |
| Fingerprint login via PAM (sudo, GDM lock screen) | ✅ |

> **The "material bundle" is NOT required.** An earlier version of these notes
> claimed a Windows-extracted 5-file bundle was mandatory — that was a wrong
> diagnosis. The driver provisions everything from the reader's own OTP plus a
> locally generated pairing key. No Windows, no VM, no DPAPI, no USB capture.

## Build dependencies (Debian/Ubuntu)

```bash
sudo apt install -y gcc g++ meson ninja-build pkg-config binutils \
  libglib2.0-dev libgusb-dev libssl-dev libopencv-dev libpam0g-dev \
  libgudev-1.0-dev libnss3-dev fprintd libpam-fprintd
```

| Fedora | Debian/Ubuntu |
|---|---|
| `gcc-c++` | `g++` |
| `pkgconf-pkg-config` | `pkg-config` |
| `glib2-devel` | `libglib2.0-dev` |
| `libgusb-devel` | `libgusb-dev` |
| `openssl-devel` | `libssl-dev` |
| `opencv-devel` | `libopencv-dev` |
| `pam-devel` | `libpam0g-dev` |

## Install

```bash
./install-debian.sh
```

Builds the driver, installs the runtime library under
`/usr/local/lib/goodix-27c6-5125`, adds an `fprintd` systemd drop-in pointing
`LD_LIBRARY_PATH` at it, and creates the root-only pairing state directory
`/var/lib/fprint/goodix-5125-state-v2`. Key difference from Fedora: the meson
`--libdir` (`lib64` → `lib/x86_64-linux-gnu`).

### Build command (reference)

```bash
rm -rf /tmp/goodix-bld
meson setup /tmp/goodix-bld reference/libfprint-fedora44-1.94.100/source \
  --prefix=/usr --libdir=lib/x86_64-linux-gnu \
  --buildtype=release --wrap-mode=nodownload \
  -Ddrivers=goodix_27c6_5125 -Dgoodix_production_minimal=true \
  -Dintrospection=false -Ddoc=false -Dinstalled-tests=false \
  -Dudev_rules=disabled -Dudev_hwdb=disabled
meson compile -C /tmp/goodix-bld fprint-2
```

## Enroll, verify, log in

```bash
fprintd-enroll          # keep going until "enroll-completed"
fprintd-verify          # expect "verify-match"
sudo pam-auth-update    # tick "Fingerprint authentication" for GDM/sudo
```

> **⚠️ Enroll slowly — this is the one real pitfall.** Press firmly, hold the
> finger still ~1.5 s per contact, and vary the area (tip / pad / sides / base).
> A rushed enrollment builds a degenerate template whose SIGFM match score is 0
> against every sample, so every verify returns `no-match`. A careful ~60–70 s
> enrollment yields scores well above threshold (e.g. 200–3000 vs 40).

## Debugging

```bash
sudo systemctl stop fprintd
sudo pkill -f /usr/libexec/fprintd
sudo LD_LIBRARY_PATH=/usr/local/lib/goodix-27c6-5125 G_MESSAGES_DEBUG=all \
     /usr/libexec/fprintd -t &
fprintd-enroll
# restore: sudo kill %1 ; sudo systemctl start fprintd
```

Useful audit lines: `GOODIX_PRODUCTION_EPOCH_AUDIT` (look for `pairing_active=1`,
`tls=1`, `secure_e4_contract=MATCH`) and `GOODIX_SIGFM_MATCH_AUDIT`
(per-sample `score=` vs `threshold=40`).

## Notes on the Fedora installer

The upstream `install.sh` / `deployment/install.py` is Fedora-specific
(`dnf`/`rpm`, SELinux `semanage`/`restorecon`, Plasma Login). On the Debian
family use `install-debian.sh` instead — the driver itself reads no SELinux
labels, so no SELinux porting is needed for the self-init path to work.

## License

Derived, GPL-3.0-or-later. Credit: `sorguido/goodix-27c6-5125`.
