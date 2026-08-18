# FuraxOS — Xperia XZ (F8331 / kagura)

ROM custom basée sur **LineageOS 15.1 (Android 8.1 Oreo)**, branding **FuraxOS**, pour le
**Sony Xperia XZ** modèle **F8331** (codename `kagura`).

Ce dossier est indépendant de `../vendor/fritax` (branding FritaxOS pour la Galaxy Tab 4) —
appareil différent, chaîne de flash différente (Fastboot/Sony au lieu d'Odin/Heimdall).

## ⚠️ Lis ça avant de commencer

- Pas de build LineageOS **officielle** pour `kagura`. On utilise une build **non-officielle**
  (ex: celle du développeur **Bitti09**, LineageOS 15.0/15.1) — cherche la plus récente sur
  XDA-Developers, thread `f8331-kagura-lineageos`.
- **Débloquer le bootloader efface `/data` automatiquement** — c'est un mécanisme de sécurité
  Sony, aucun moyen de le contourner. **Sauvegarde tout AVANT** (voir plus bas).
- Sony fournit un outil **officiel** pour récupérer le code de déblocage : compte Sony +
  IMEI du téléphone, voir `docs/DEVICE.md`.

## 1. Sauvegarder AVANT de débloquer le bootloader

```
adb pull /sdcard ~/Sauvegardes/xperia-sdcard
adb backup -apk -shared -all -f ~/Sauvegardes/xperia-xz-apps.ab
```

Voir `scripts/restore_backup.sh` pour tout remettre une fois FuraxOS installé.

## 2. Débloquer le bootloader

1. Active les options développeur (7 taps sur "Numéro de build").
2. Active "Débogage USB" et "Déverrouillage OEM".
3. Récupère ton code de déblocage sur https://developer.sony.com/develop/open-devices/get-started/unlock-bootloader/
   (nécessite l'IMEI, `*#06#` pour l'afficher).
4. `fastboot oem unlock 0x<code>` — **ceci efface `/data`**, assure-toi d'avoir fini l'étape 1.

## 3. Flash TWRP puis FuraxOS

```
./scripts/flash.sh recovery /chemin/vers/twrp-kagura.img
./scripts/flash.sh rom /chemin/vers/lineage-15.1-....zip
./scripts/flash.sh gapps /chemin/vers/open_gapps-arm-8.1-....zip   # optionnel
```

Voir `docs/DEVICE.md` pour les liens (device tree TWRP AndroPlus-org, build Bitti09).

## 4. Restaurer tes données

```
./scripts/restore_backup.sh ~/Sauvegardes/xperia-xz-apps.ab ~/Sauvegardes/xperia-sdcard
```

## Branding FuraxOS

`vendor/furax/vendor.mk` + `overlay/` : mêmes mécanismes que `vendor/fritax` côté Tab 4
(nom affiché dans "À propos du téléphone", texte d'accueil SetupWizard). `../scripts/patch_branding.sh`
pointe en dur vers `overlay/` à la racine du dépôt (pas ce dossier-ci) — pour patcher le
SetupWizard de la build kagura, adapte le chemin `overlay/packages/apps/SetupWizard/res/values`
dans une copie du script, ou déplace temporairement `xperia/overlay/*` vers `overlay/` avant de
lancer `patch_branding.sh`.
