# NovaTab OS

ROM custom type LineageOS pour la **Samsung Galaxy Tab 4 10.1" SM-T530** (WiFi, codename `milletwifi`).

## ⚠️ Lis ça avant de commencer

Ce dépôt fournit le **tooling** (manifest, scripts de build, scripts de flash) pour compiler
et installer une ROM basée sur LineageOS. Il ne contient **pas** de firmware binaire prêt à
l'emploi : compiler une ROM Android nécessite une vraie source tree AOSP/LineageOS
(~150-250 Go d'espace disque, plusieurs heures de compilation, une machine Linux dédiée ou
un runner CI auto-hébergé). Les GitHub Actions "hébergés" gratuits (14 Go de disque, 6h max)
**ne suffisent pas** pour ce type de build — voir `.github/workflows/build.yml` pour les
détails et l'option runner self-hosted.

### Pourquoi Android 7.1 et pas 8/10 ?

Le SM-T530 embarque un Exynos 3220 (quad-core Cortex-A7) et **1,5 Go de RAM**. C'est la
config exacte du Galaxy Tab 4 le plus limité côté support communautaire :

| Version cible          | Statut réaliste sur milletwifi                          |
|-------------------------|-----------------------------------------------------------|
| **LineageOS 14.1 (Android 7.1.2)** | ✅ Recommandé — device tree communautaire mature, builds non-officielles stables (XDA) |
| LineageOS 15.1 (Android 8.1)       | ⚠️ Support partiel/instable selon les forks, peu maintenu |
| LineageOS 17.1 (Android 10)        | ❌ Pas de build fonctionnelle connue pour ce SoC/cette RAM — déconseillé |

Ce dépôt cible donc **LineageOS 14.1** par défaut. Tu peux tenter 15.1 en changeant la
branche du manifest (voir `manifests/roomservice.xml`), à tes risques.

## Structure du dépôt

```
manifests/
  roomservice.xml       # pointe vers les device trees / kernel / vendor communautaires
overlay/
  packages/apps/SetupWizard/...  # branding de l'assistant de premier démarrage (texte, couleurs)
vendor/novatab/
  vendor.mk              # branche l'overlay + les propriétés de branding dans le build
scripts/
  build.sh               # repo init + sync + branding + build (à lancer sur une machine avec assez d'espace)
  flash.sh               # installation via Heimdall (Download Mode) + ADB sideload (ROM/GApps/bootanimation)
  make_bootanimation.sh  # génère un bootanimation.zip custom à partir d'images PNG
.github/workflows/
  build.yml              # workflow CI (nécessite un runner self-hosted, voir commentaires)
docs/
  DEVICE.md              # infos matérielles, sources utilisées, avertissements
  CUSTOMIZATION.md       # GApps, splash/bootanimation custom, branding du premier démarrage (OOBE)
```

## Démarrage rapide

1. Prépare une machine Linux (Ubuntu 22.04 recommandé) avec ≥250 Go libres et 16 Go de RAM.
2. `./scripts/build.sh` — installe les dépendances, sync les sources LineageOS + ce manifest, lance le build.
3. Récupère le zip généré dans `out/target/product/milletwifi/lineage-*.zip`.

`build.sh` affiche une barre de progression (whiptail) plutôt que de spammer le terminal —
toute la sortie verbeuse (apt, repo sync, brunch) va dans `~/novatab-build/logs/build-*.log`,
et seules les dernières lignes utiles s'affichent en cas d'échec. Pour désactiver la TUI et
revenir à des logs texte classiques (toujours redirigés vers le même fichier) :
`NOVATAB_NO_TUI=1 ./scripts/build.sh`.
4. Branche la tablette en Download Mode, lance `./scripts/flash.sh` pour flasher un recovery
   custom (TWRP) via Heimdall, puis sideload la ROM via ADB.

**Important : Samsung n'utilise pas Fastboot.** Le SM-T530 se flashe via le protocole Odin
(Download Mode), donc `flash.sh` utilise **Heimdall** (l'implémentation libre d'Odin sous
Linux/Mac) pour le recovery, puis `adb sideload` pour la ROM elle-même. Voir `docs/DEVICE.md`.

## GApps & splash custom

Support pour flasher **GApps** (Google Apps) juste après la ROM, et personnaliser le
**bootanimation** (écran d'animation au démarrage du système) — voir
[`docs/CUSTOMIZATION.md`](docs/CUSTOMIZATION.md) pour le détail complet, y compris pourquoi le
logo de boot bas-niveau (avant le kernel) n'est volontairement pas couvert par ce dépôt
(risque de brick, format non confirmé pour ce device).

```
./scripts/flash.sh gapps open_gapps-arm-7.1-pico.zip     # juste après la ROM, dans TWRP
./scripts/make_bootanimation.sh frames/ bootanimation.zip 1280 800 24
./scripts/flash.sh bootanimation bootanimation.zip
```

## Branding du premier démarrage (OOBE)

`scripts/build.sh` applique automatiquement un overlay de branding "NovaTab OS" (texte
d'accueil, couleurs, nom d'appareil) sur l'assistant de configuration LineageOS lors du build —
voir [`docs/CUSTOMIZATION.md`](docs/CUSTOMIZATION.md#config-personnalisée-au-premier-démarrage-oobe--setupwizard)
pour le détail et comment vérifier/ajuster les noms de ressources après un `repo sync`.
Désactivable avec `SKIP_BRANDING=1 ./scripts/build.sh`.

## Sauvegarde tes données avant tout flash

Un flash mal fait peut briquer la tablette (soft-brick récupérable dans la majorité des cas,
mais reste un risque). Sauvegarde tes données, vérifie que la batterie est chargée à >50%,
et ne débranche jamais l'appareil pendant un flash.

## Statut du projet

Scaffold initial : manifest + scripts de build/flash + workflow CI documenté. Prochaine étape :
valider que les device trees communautaires référencés dans `manifests/roomservice.xml`
sont toujours actifs avant de lancer un premier build réel.
