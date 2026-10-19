#!/usr/bin/env bash
# install-debian.sh — Installeur Debian/Ubuntu pour le driver Goodix 27c6:5125 (portage).
# GPL-3.0-or-later. Dérivé de sorguido/goodix-27c6-5125 (Fedora).
#
# Reproduit, en version apt/Debian, ce qui a été validé sous Ubuntu 26.04 :
#   build libfprint+driver -> install runtime -> drop-in fprintd -> dirs d'état.
# Le matériel d'appairage (bundle, extrait d'une VM Windows) reste à déposer ensuite.
#
# Usage :
#   ./install-debian.sh              installe
#   ./install-debian.sh --uninstall  désinstalle (conserve état/matériel)
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
LIBFPRINT_SRC="$REPO/reference/libfprint-fedora44-1.94.100/source"
BUILD="/tmp/goodix-bld-$(id -un)"

# Conventions amont, adaptées Debian (lib au lieu de lib64)
RUNTIME="/usr/local/lib/goodix-27c6-5125"
DROPIN="/etc/systemd/system/fprintd.service.d/90-goodix-5125-runtime.conf"
STATE="/var/lib/fprint/goodix-5125-state-v2"
MATERIAL="/var/lib/goodix-5125-poc"

log()  { printf '\033[1;32m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Lance SANS sudo (ton utilisateur normal). Le script demandera sudo au besoin."

# --- Désinstallation ----------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
    log "Désinstallation…"
    sudo rm -f "$DROPIN"
    sudo systemctl daemon-reload
    sudo systemctl restart fprintd 2>/dev/null || true
    sudo rm -rf "$RUNTIME"
    warn "Répertoires conservés : $STATE et $MATERIAL (supprime-les à la main si tu veux)."
    log "Terminé. fprintd système restauré."
    exit 0
fi

# --- 1. Capteur présent -------------------------------------------------------
log "Vérification du capteur 27c6:5125…"
lsusb -d 27c6:5125 >/dev/null 2>&1 || die "Capteur 27c6:5125 introuvable (lsusb -d 27c6:5125)."

# --- 2. Dépendances de build (apt) -------------------------------------------
log "Installation des dépendances (apt)…"
sudo apt-get update
sudo apt-get install -y \
    gcc g++ meson ninja-build pkg-config binutils \
    libglib2.0-dev libgusb-dev libssl-dev libopencv-dev libpam0g-dev \
    libgudev-1.0-dev libnss3-dev \
    fprintd libpam-fprintd

# --- 3. Compilation libfprint + driver ---------------------------------------
log "Compilation de libfprint + driver goodix_27c6_5125…"
rm -rf "$BUILD"
meson setup "$BUILD" "$LIBFPRINT_SRC" \
    --prefix=/usr --libdir=lib/x86_64-linux-gnu \
    --buildtype=release --wrap-mode=nodownload \
    -Ddrivers=goodix_27c6_5125 -Dgoodix_production_minimal=true \
    -Dintrospection=false -Ddoc=false -Dinstalled-tests=false \
    -Dudev_rules=disabled -Dudev_hwdb=disabled
meson compile -C "$BUILD" fprint-2
LIB="$BUILD/libfprint/libfprint-2.so.2.0.0"
[ -f "$LIB" ] || die "Build échoué : $LIB absent."
log "Driver compilé : $(nm "$LIB" | grep -c -i goodix) symboles goodix."

# --- 4. Installation de la lib runtime ---------------------------------------
log "Installation de la lib dans $RUNTIME…"
sudo install -d -m 755 "$RUNTIME"
sudo install -m 644 "$LIB" "$RUNTIME/libfprint-2.so.2.0.0"
sudo ln -sf libfprint-2.so.2.0.0 "$RUNTIME/libfprint-2.so.2"

# --- 5. Drop-in fprintd : charger NOTRE libfprint ----------------------------
log "Configuration du drop-in systemd fprintd…"
sudo install -d -m 755 "$(dirname "$DROPIN")"
sudo tee "$DROPIN" >/dev/null <<EOF
[Service]
Environment=LD_LIBRARY_PATH=$RUNTIME
EOF
sudo systemctl daemon-reload
sudo systemctl restart fprintd 2>/dev/null || true

# --- 6. Répertoires d'état / matériel (policy : 0700 root) -------------------
log "Création des répertoires d'état/matériel (0700, root)…"
sudo install -d -o root -g root -m 700 "$STATE"
sudo install -d -o root -g root -m 700 "$MATERIAL"

# --- Fin ----------------------------------------------------------------------
log "Installation terminée."
echo
warn "ÉTAPE RESTANTE — déposer le bundle de matériel dans :"
warn "  $MATERIAL/"
warn "  (target-material-manifest.json, transport-material.bin, … extraits via VM Windows,"
warn "   en 0600 root). Sans lui, l'enrôlement s'arrête sur 'material absent'."
echo
log "Une fois le bundle en place :  fprintd-enroll"
log "Activer le login par empreinte (GNOME/GDM) :  sudo pam-auth-update  (coche Fingerprint)"
log "Désinstaller :  ./install-debian.sh --uninstall"
