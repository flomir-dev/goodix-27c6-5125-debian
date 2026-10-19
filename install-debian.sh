#!/usr/bin/env bash
# install-debian.sh — Debian/Ubuntu installer for the Goodix 27c6:5125 driver.
# GPL-3.0-or-later. Derived from sorguido/goodix-27c6-5125 (Fedora).
#
# Ports the driver's SELF-INITIALISATION path to Ubuntu/Debian:
#   build libfprint+driver -> install runtime -> fprintd drop-in -> state dir.
# The driver generates its own PSK and pairs with the chip on first use:
#   NO Windows material, no bundle, no VM required.
#
# Usage:
#   ./install-debian.sh              install
#   ./install-debian.sh --uninstall  uninstall (keeps the pairing state)
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
LIBFPRINT_SRC="$REPO/reference/libfprint-fedora44-1.94.100/source"
BUILD="/tmp/goodix-bld-$(id -un)"

RUNTIME="/usr/local/lib/goodix-27c6-5125"
DROPIN="/etc/systemd/system/fprintd.service.d/90-goodix-5125-runtime.conf"
STATE="/var/lib/fprint/goodix-5125-state-v2"

log()  { printf '\033[1;32m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo (as your normal user). The script asks for sudo when needed."

if [ "${1:-}" = "--uninstall" ]; then
    log "Uninstalling..."
    sudo rm -f "$DROPIN"
    sudo systemctl daemon-reload
    sudo systemctl restart fprintd 2>/dev/null || true
    sudo rm -rf "$RUNTIME"
    warn "Kept: $STATE (pairing state). Remove it by hand for a full reset."
    log "Done. System fprintd restored."
    exit 0
fi

log "Checking for the 27c6:5125 sensor..."
lsusb -d 27c6:5125 >/dev/null 2>&1 || die "Sensor 27c6:5125 not found (lsusb -d 27c6:5125)."

log "Installing build dependencies (apt)..."
sudo apt-get update
sudo apt-get install -y \
    gcc g++ meson ninja-build pkg-config binutils \
    libglib2.0-dev libgusb-dev libssl-dev libopencv-dev libpam0g-dev \
    libgudev-1.0-dev libnss3-dev \
    fprintd libpam-fprintd

log "Building libfprint + goodix_27c6_5125 driver..."
rm -rf "$BUILD"
meson setup "$BUILD" "$LIBFPRINT_SRC" \
    --prefix=/usr --libdir=lib/x86_64-linux-gnu \
    --buildtype=release --wrap-mode=nodownload \
    -Ddrivers=goodix_27c6_5125 -Dgoodix_production_minimal=true \
    -Dintrospection=false -Ddoc=false -Dinstalled-tests=false \
    -Dudev_rules=disabled -Dudev_hwdb=disabled
meson compile -C "$BUILD" fprint-2
LIB="$BUILD/libfprint/libfprint-2.so.2.0.0"
[ -f "$LIB" ] || die "Build failed: $LIB missing."
log "Driver built: $(nm "$LIB" | grep -c -i goodix) goodix symbols."

log "Installing the runtime library into $RUNTIME..."
sudo install -d -m 755 "$RUNTIME"
sudo install -m 644 "$LIB" "$RUNTIME/libfprint-2.so.2.0.0"
sudo ln -sf libfprint-2.so.2.0.0 "$RUNTIME/libfprint-2.so.2"

log "Configuring the fprintd systemd drop-in..."
sudo install -d -m 755 "$(dirname "$DROPIN")"
sudo tee "$DROPIN" >/dev/null <<DROPIN_EOF
[Service]
Environment=LD_LIBRARY_PATH=$RUNTIME
DROPIN_EOF
sudo systemctl daemon-reload
sudo systemctl restart fprintd 2>/dev/null || true

log "Creating the pairing state directory (0700, root)..."
sudo install -d -o root -g root -m 700 "$STATE"
# Legacy dir unused by self-init: remove an EMPTY leftover if present.
sudo rmdir /var/lib/goodix-5125-poc 2>/dev/null || true

log "Installation complete. The driver self-pairs on first use (no bundle required)."
echo
warn "ENROLLMENT - IMPORTANT: go SLOWLY."
warn "  Firm press, hold the finger still ~1.5 s per contact, vary the area"
warn "  (tip/pad/sides/base). A too-fast enrollment produces a poor-quality"
warn "  template that will not recognise anything."
echo
log "Enroll:                       fprintd-enroll   (keep going until enroll-completed)"
log "Test:                         fprintd-verify"
log "Fingerprint login (GDM/sudo): sudo pam-auth-update  (tick Fingerprint)"
log "Uninstall:                    ./install-debian.sh --uninstall"
