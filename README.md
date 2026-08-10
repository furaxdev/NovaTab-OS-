# FritaxOS

ROM custom type LineageOS pour la **Samsung Galaxy Tab 4 10.1" SM-T530** (WiFi, codename `matissewifi`).

## ⚠️ Lis ça avant de commencer

Ce dépôt fournit le **tooling** (scripts de flash, de patch, de build) pour installer une ROM
basée sur LineageOS. Il ne contient **pas** de firmware binaire prêt à l'emploi : tu dois soit
télécharger une ROM déjà compilée par la communauté (recommandé, voir plus bas), soit tout
recompiler toi-même depuis les sources (~150-250 Go d'espace disque, plusieurs heures — voir
la section "Avancé").

### Pourquoi Android 7.1 et pas 8/10 ?

Le SM-T530 embarque un Exynos 3220 (quad-core Cortex-A7) et **1,5 Go de RAM**. C'est la
config exacte du Galaxy Tab 4 le plus limité côté support communautaire :

| Version cible          | Statut réaliste sur matissewifi                          |
|-------------------------|-----------------------------------------------------------|
| **LineageOS 14.1 (Android 7.1.2)** | ✅ Recommandé — device tree communautaire mature, builds non-officielles stables (XDA) |
| LineageOS 15.1 (Android 8.1)       | ⚠️ Support partiel/instable selon les forks, peu maintenu |
| LineageOS 17.1 (Android 10)        | ❌ Pas de build fonctionnelle connue pour ce SoC/cette RAM — déconseillé |

Cherche donc une build **LineageOS 14.1 non-officielle pour "matissewifi" / "SM-T530"** sur
XDA-Developers — c'est la cible que tout ce dépôt suppose.

## Démarrage rapide — sans rien compiler (recommandé)

Aucune des étapes ci-dessous n'a besoin des 250 Go ni de machine dédiée : tu pars d'une ROM
et d'un recovery TWRP déjà compilés par la communauté (à chercher sur XDA pour "matissewifi").

### Tout en une commande

`scripts/install.sh` enchaîne recovery + ROM + SetupWizard patché (optionnel) + GApps
(optionnel) automatiquement — sortie texte simple (étapes + pourcentage, pas de TUI), et
il attend tout seul que la tablette soit connectée dans le bon mode à chaque étape plutôt
que de te demander d'appuyer sur Entrée à l'aveugle. Tu n'as qu'à faire les actions
physiques demandées à l'écran (bouton, menu TWRP) :

```
./scripts/install.sh twrp-matissewifi.img lineage-14.1-....zip SetupWizard-patched.apk open_gapps-arm-7.1-pico.zip
```

(Les deux derniers arguments sont optionnels — `SetupWizard-patched.apk` s'obtient via
`patch_branding.sh` ou le workflow GitHub Actions, voir plus bas.)

### Étape par étape, avec `flash.sh`

Si tu préfères garder la main à chaque étape :

```
# 1. Flash TWRP (Download Mode : Volume bas + Home + Power, puis Volume haut pour confirmer)
./scripts/flash.sh recovery twrp-matissewifi.img

# 2. Reboot en recovery (Volume haut + Home + Power), puis :

# 3. (Optionnel) Patch le branding "FritaxOS" de l'assistant de premier démarrage
#    En local :
./scripts/patch_branding.sh extract lineage-14.1-....zip SetupWizard.apk
./scripts/patch_branding.sh patch SetupWizard.apk SetupWizard-patched.apk
#    Ou via GitHub Actions (Actions > "Patch branding" > Run workflow avec l'URL du zip
#    de la ROM) : tourne sur un runner gratuit standard, télécharge SetupWizard-patched.apk
#    depuis les artifacts du run une fois terminé.

# 4. Flash la ROM
./scripts/flash.sh rom lineage-14.1-....zip

# 5. (Si étape 3 faite) Installe le SetupWizard patché, toujours avant le premier boot
./scripts/flash.sh setupwizard SetupWizard-patched.apk

# 6. GApps, juste après, toujours dans TWRP, sans reboot entre les deux
./scripts/flash.sh gapps open_gapps-arm-7.1-pico.zip

# 7. Wipe data/cache dans TWRP, puis reboot système

# 8. Une fois démarré : bootanimation custom (nécessite root ou adb root)
./scripts/make_bootanimation.sh frames/ bootanimation.zip 1280 800 24
./scripts/flash.sh bootanimation bootanimation.zip
```

**Important : Samsung n'utilise pas Fastboot.** Le SM-T530 se flashe via le protocole Odin
(Download Mode), donc `flash.sh` utilise **Heimdall** (l'implémentation libre d'Odin) pour le
recovery, puis `adb sideload`/`adb push` pour le reste. `heimdall`, `adb`, `apktool` et les
autres dépendances s'installent automatiquement via `apt` s'ils manquent. Voir `docs/DEVICE.md`
pour le détail matériel et `docs/CUSTOMIZATION.md` pour GApps/splash/OOBE en détail (variantes
GApps à privilégier vu la RAM limitée, risques de la resignature APK, etc.).

## Sauvegarde tes données avant tout flash

Un flash mal fait peut briquer la tablette (soft-brick récupérable dans la majorité des cas,
mais reste un risque). Sauvegarde tes données (`./scripts/flash.sh backup`), vérifie que la
batterie est chargée à >50%, et ne débranche jamais l'appareil pendant un flash.

## Avancé : compiler depuis les sources

Seulement si tu veux vraiment builder la ROM toi-même plutôt que d'en flasher une déjà
compilée (recompiler ne débloque rien de plus que ce que fait déjà `patch_branding.sh` pour
le branding — c'est juste plus lourd).

1. Machine Linux (Ubuntu 22.04 recommandé) avec ≥250 Go libres et 16 Go de RAM.
2. `./scripts/build.sh` — installe les dépendances, sync les sources LineageOS + ce manifest,
   applique le branding, lance le build. Affiche une barre de progression (whiptail) plutôt que
   de spammer le terminal — toute la sortie verbeuse va dans `~/fritaxos-build/logs/build-*.log`.
   Désactivable avec `FRITAXOS_NO_TUI=1 ./scripts/build.sh`.
3. Récupère le zip dans `out/target/product/matissewifi/lineage-*.zip`, puis reprends la séquence
   `flash.sh` ci-dessus à partir de l'étape 4.

Ça ne tourne **pas** sur les runners GitHub Actions hébergés gratuits (14 Go de disque max) —
voir `.github/workflows/build.yml` pour l'option runner self-hosted (qui a besoin des mêmes
250 Go, GitHub Actions n'y change rien).

## Structure du dépôt

```
scripts/
  install.sh              # tout en une commande : recovery + ROM + SetupWizard + GApps, texte pur, attente auto
  flash.sh                # Heimdall (Download Mode) + ADB : recovery/ROM/GApps/bootanimation/SetupWizard
  patch_branding.sh    # patche le branding OOBE sur une ROM déjà compilée (sans recompiler)
  make_bootanimation.sh   # génère un bootanimation.zip custom à partir d'images PNG
  build.sh                # (avancé) repo init + sync + branding + build complet
manifests/
  roomservice.xml         # pour build.sh : device trees / kernel / vendor communautaires
overlay/
  packages/apps/SetupWizard/...  # branding OOBE (texte, couleurs), utilisé par build.sh et patch_branding.sh
vendor/fritax/
  vendor.mk               # pour build.sh : branche l'overlay dans la compilation
.github/workflows/
  patch-branding.yml   # patche le branding OOBE via CI, tourne sur un runner gratuit standard
  build.yml               # CI pour build.sh (nécessite un runner self-hosted)
docs/
  DEVICE.md               # infos matérielles, sources utilisées, avertissements
  CUSTOMIZATION.md         # GApps, splash/bootanimation, branding OOBE (les deux méthodes)
```

## Statut du projet

Scaffold initial : scripts de flash/patch/build documentés. Prochaine étape : valider le tout
sur une tablette réelle avec une build LineageOS 14.1 matissewifi trouvée sur XDA.
