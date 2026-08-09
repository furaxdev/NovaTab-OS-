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
scripts/
  build.sh              # repo init + sync + build (à lancer sur une machine avec assez d'espace)
  flash.sh              # installation via Heimdall (Download Mode) + ADB sideload
.github/workflows/
  build.yml             # workflow CI (nécessite un runner self-hosted, voir commentaires)
docs/
  DEVICE.md             # infos matérielles, sources utilisées, avertissements
```

## Démarrage rapide

1. Prépare une machine Linux (Ubuntu 22.04 recommandé) avec ≥250 Go libres et 16 Go de RAM.
2. `./scripts/build.sh` — installe les dépendances, sync les sources LineageOS + ce manifest, lance le build.
3. Récupère le zip généré dans `out/target/product/milletwifi/lineage-*.zip`.
4. Branche la tablette en Download Mode, lance `./scripts/flash.sh` pour flasher un recovery
   custom (TWRP) via Heimdall, puis sideload la ROM via ADB.

**Important : Samsung n'utilise pas Fastboot.** Le SM-T530 se flashe via le protocole Odin
(Download Mode), donc `flash.sh` utilise **Heimdall** (l'implémentation libre d'Odin sous
Linux/Mac) pour le recovery, puis `adb sideload` pour la ROM elle-même. Voir `docs/DEVICE.md`.

## Sauvegarde tes données avant tout flash

Un flash mal fait peut briquer la tablette (soft-brick récupérable dans la majorité des cas,
mais reste un risque). Sauvegarde tes données, vérifie que la batterie est chargée à >50%,
et ne débranche jamais l'appareil pendant un flash.
