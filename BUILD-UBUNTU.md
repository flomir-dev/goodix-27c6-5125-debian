# Portage Ubuntu / Debian — notes de build & état

Portage de `sorguido/goodix-27c6-5125` (Fedora 44 KDE) vers **Ubuntu 26.04**
(famille Debian, apt). Ce document consigne ce qui fonctionne, comment reproduire,
et ce qu'il reste à porter.

## Résultat (résumé)

Le **driver C compile, se charge et pilote le capteur** sous Ubuntu 26.04 :

| Étape | État |
|---|---|
| Compilation `libfprint` + driver `goodix_27c6_5125` | ✅ |
| Chargement dans `fprintd`, probe du device | ✅ |
| Ouverture du capteur (`claim` / `open`) | ✅ |
| Préflight (7 commandes) | ✅ |
| Démarrage de l'enrôlement | ✅ |
| Ouverture du répertoire d'état `state-v2` | ✅ (après `mkdir`) |
| Provisionnement du matériel + appairage (PSK/TLS) | ⛔ bundle requis |

Seul mur restant : le **bundle de matériel d'appairage** propriétaire, qui s'extrait
d'une **VM Windows** (passthrough USB + pilote OEM Goodix + contexte DPAPI). C'est une
contrainte matérielle, pas un problème de code ni de distribution.

## Dépendances de build (Debian/Ubuntu)

Équivalents apt des `BUILD_PACKAGES` Fedora de `production/build-public.py` :

```bash
sudo apt install -y gcc g++ meson ninja-build pkg-config \
  libglib2.0-dev libgusb-dev libssl-dev libopencv-dev libpam0g-dev binutils \
  libgudev-1.0-dev libnss3-dev
```

| Fedora | Debian/Ubuntu |
|---|---|
| `gcc-c++` | `g++` |
| `ninja-build` | `ninja-build` |
| `pkgconf-pkg-config` | `pkg-config` |
| `glib2-devel` | `libglib2.0-dev` |
| `libgusb-devel` | `libgusb-dev` |
| `openssl-devel` | `libssl-dev` |
| `opencv-devel` | `libopencv-dev` |
| `pam-devel` | `libpam0g-dev` |

## Compiler (commande qui fonctionne)

Différence clé avec Fedora : `--libdir=lib64` → `--libdir=lib/x86_64-linux-gnu`.

```bash
rm -rf /tmp/goodix-bld
meson setup /tmp/goodix-bld reference/libfprint-fedora44-1.94.100/source \
  --prefix=/usr --libdir=lib/x86_64-linux-gnu \
  --buildtype=release --wrap-mode=nodownload \
  -Ddrivers=goodix_27c6_5125 \
  -Dgoodix_production_minimal=true \
  -Dintrospection=false -Ddoc=false -Dinstalled-tests=false \
  -Dudev_rules=disabled -Dudev_hwdb=disabled
meson compile -C /tmp/goodix-bld fprint-2
```

Produit `/tmp/goodix-bld/libfprint/libfprint-2.so.2.0.0` (driver `goodix_27c6_5125`
intégré ; vérifiable avec `nm … | grep goodix`).

## Tester sans installer (réversible)

```bash
sudo systemctl stop fprintd
sudo pkill -f /usr/libexec/fprintd
sudo LD_LIBRARY_PATH=/tmp/goodix-bld/libfprint G_MESSAGES_DEBUG=all /usr/libexec/fprintd -t &
sleep 2
fprintd-enroll
# retour à la normale :
sudo kill %1 ; sudo systemctl start fprintd
```

Comportement observé : le capteur est ouvert, le préflight passe, l'enrôlement démarre,
puis s'arrête sur le provisionnement de l'état (`state-v2` / `runtime coordinator
directory policy`) faute de matériel d'appairage.

## Ce qu'il reste à porter (`deployment/install.py`)

Fichier Fedora-spécifique à adapter :

- Paquets : `rpm -q` / `dnf` → `dpkg -s` / `apt` ; `RUNTIME_PACKAGES` :
  `fprintd-pam` → `libpam-fprintd`, retirer `policycoreutils-python-utils`.
- **SELinux** (`semanage`, `semodule`, `restorecon`, type `fprintd_var_lib_t`,
  xattr `security.selinux`) → neutraliser sous Ubuntu (AppArmor), ces fonctions
  deviennent des no-op.
- Chemins : `RUNTIME`/`SUPPORT` en `/usr/local/lib64/` → `/usr/local/lib/`.
- **Login** : `plasmalogin` (KDE) → GDM/GNOME (`/etc/pam.d/gdm-password`) ou
  `pam-auth-update`. Fichiers concernés : `deployment/plasma-login-opt-in/`.
- `host_preflight()` : vérifie l'unité/ExecStart fprintd « Fedora » → chemins Debian
  (`/usr/libexec/fprintd` est OK sur Ubuntu).
- Politique du répertoire d'état (`runtime coordinator directory policy`) : reproduire
  les droits/propriétaire/manifeste attendus lors de la création de
  `/var/lib/fprint/goodix-5125-state-v2` et `/var/lib/goodix-5125-poc`.

## Prérequis hors-logiciel (inchangé vs amont)

- Bundle de matériel (5 fichiers : `target-material-manifest.json`,
  `transport-material.bin`, …) à extraire d'une VM Windows. Sans lui, l'enrôlement
  ne peut pas aboutir.

## Licence

Dérivé GPL-3.0-or-later. Crédit : `sorguido/goodix-27c6-5125`.
