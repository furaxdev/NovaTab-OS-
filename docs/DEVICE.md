# Samsung Galaxy Tab 4 10.1" — SM-T530 (milletwifi)

Infos relevées depuis la capture "À propos de l'appareil" fournie par l'utilisateur :

- Numéro de modèle : `SM-T530`
- Version Android d'origine : `5.0.2` (Lollipop, OneUI n/a — TouchWiz)
- Version kernel d'origine : `3.4.0-10239154`
- Numéro de build : `LRX22G.T530XXS1BRH1`

## Codename

`milletwifi` — c'est le nom utilisé par les device trees communautaires LineageOS/AOSP
pour le SM-T530 (variante WiFi-only de la famille "millet", qui inclut aussi T531/T535
pour les versions 3G/LTE).

## Caractéristiques matérielles

| Composant | Détail |
|---|---|
| SoC | Exynos 3220 (quad-core Cortex-A7 @ 1.2 GHz) |
| GPU | Mali-400MP4 |
| RAM | 1,5 Go |
| Stockage | 16 Go (+ microSD) |
| Écran | 10.1" 1280x800 |

Ce sont des specs très limitées pour du Android moderne — c'est la raison du choix
d'Android 7.1 comme cible réaliste (voir README).

## Sources utilisées par le manifest

Le fichier `manifests/roomservice.xml` référence les dépôts communautaires suivants
(à vérifier/adapter selon disponibilité au moment du build — les device trees non-officiels
peuvent bouger ou être archivés) :

- Device tree : `device_samsung_milletwifi` (fork communautaire LineageOS 14.1)
- Kernel : `kernel_samsung_smdk3470` ou équivalent kernel commun "millet"
- Vendor (blobs propriétaires) : `vendor_samsung_milletwifi` — extrait avec `extract-files.sh`
  **depuis un dump de ta propre tablette**, jamais depuis un dépôt tiers pour les blobs Wi-Fi/GPS
  propriétaires (question de licence Samsung).

⚠️ Avant de lancer le build, vérifie que ces dépôts existent toujours et sont à jour — le
support communautaire de ce device est ancien (dernières activités connues autour de 2016-2018).
Si un dépôt a disparu, cherche son fork le plus récent sur GitHub/XDA avant de modifier
`roomservice.xml`.

## Bootloader / flashing

Les appareils Samsung de cette génération utilisent le protocole **Odin** en Download Mode,
pas Fastboot. Pour flasher depuis Linux/Mac on utilise **Heimdall**, l'implémentation libre
du protocole Odin.

Entrer en Download Mode sur le SM-T530 : éteindre la tablette, puis maintenir
**Volume bas + Home + Power** jusqu'à l'écran d'avertissement, puis Volume haut pour confirmer.

## Débloquer le bootloader / root

Nécessaire avant tout flash custom :
1. Activer les options développeur (taper 7x sur "Numéro de build")
2. Activer "OEM unlock" et "Débogage USB"
3. Le SM-T530 n'a pas de verrou OEM strict comme les modèles récents — un simple recovery
   custom (TWRP) suffit généralement, sans procédure d'unlock supplémentaire.
