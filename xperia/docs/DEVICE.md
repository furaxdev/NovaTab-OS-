# Sony Xperia XZ — F8331 (kagura)

- Numéro de modèle : `F8331` (single SIM ; `F8332` = dual SIM, même codename)
- Codename : `kagura` (plateforme "Tone R2")
- Sorti : octobre 2016, Android d'origine 6.0/7.1 selon la version de firmware

## Caractéristiques matérielles

| Composant | Détail |
|---|---|
| SoC | Qualcomm Snapdragon 820 (MSM8996) |
| RAM | 3 Go |
| Stockage | 32 Go (+ microSD) |
| Écran | 5.2" 1080x1920 |

## Statut LineageOS

Pas de build **officielle** LineageOS pour `kagura`. Builds **non-officielles** connues :
- LineageOS 15.0/15.1 (Android 8) par le développeur **Bitti09** — chercher le thread XDA
  `f8331-kagura-lineageos` pour le lien à jour (les liens de téléchargement communautaires
  bougent, toujours vérifier la date/version avant de flasher).
- Device tree TWRP maintenu par **AndroPlus-org** :
  https://github.com/AndroPlus-org/android_device_sony_kagura

## Débloquer le bootloader

Contrairement à Samsung, Sony fournit un outil **officiel** pour ça :
https://developer.sony.com/develop/open-devices/get-started/unlock-bootloader/

1. Récupère l'IMEI : compose `*#06#` sur le téléphone.
2. Crée un compte développeur Sony, entre l'IMEI, récupère le code `0x...`.
3. **`fastboot oem unlock 0x<code>`** — efface `/data` automatiquement (mécanisme de
   sécurité Sony, pas de moyen de contourner). Sauvegarder AVANT (voir `../README.md`).

⚠️ Comme sur la Tab 4 (Knox), débloquer le bootloader peut désactiver certaines
fonctionnalités liées à la sécurité (DRM widevine L1 → L3 notamment, donc Netflix HD etc.
peuvent être dégradés après déblocage) — c'est irréversible même en reverrouillant.

## Bootloader / flashing

Le Xperia XZ utilise **Fastboot** (standard Android), contrairement à la Tab 4 qui utilise
Odin/Heimdall. Entrer en mode Fastboot : éteindre, puis maintenir **Volume haut** en
branchant le câble USB.

## Root

LineageOS 15.1 supporte l'addon su natif comme pour la Tab 4 (`addonsu-15.1-arm-signed.zip`,
même mécanisme que `addonsu-14.1-arm-signed.zip` utilisé côté Tab 4) — à sideloader depuis
TWRP puis activer via Développeur > Root access.
