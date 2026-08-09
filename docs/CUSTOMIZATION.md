# Personnalisation : GApps, Splash screen & premier démarrage (OOBE)

## GApps (Google Apps)

LineageOS ne peut légalement pas embarquer les apps Google (licence propriétaire) — elles se
flashent **séparément**, juste après la ROM, dans la même session TWRP (sans reboot entre les
deux).

### Choisir la bonne variante

Le SM-T530 a **1,5 Go de RAM** : c'est le facteur limitant. Utilise une variante légère de
[Open GApps](https://opengapps.org) :

| Variante | Recommandé pour milletwifi ? |
|---|---|
| `pico`  | ✅ Oui — juste Play Store + services Google minimaux |
| `nano`  | ✅ Correct — un peu plus d'apps Google de base |
| `micro` / `mini` | ⚠️ Possible mais tasse la RAM disponible |
| `stock` / `super` | ❌ À éviter — sature la RAM sur cet appareil |

Package attendu : **ARM 32-bit, Android 7.1** (`open_gapps-arm-7.1-pico.zip`), pas ARM64
(le SoC Exynos 3220 de la Tab 4 est 32-bit).

### Installation

```
1. Flash la ROM :        ./scripts/flash.sh rom lineage-14.1-....zip
2. Flash GApps (sans reboot, toujours dans TWRP) :
                          ./scripts/flash.sh gapps open_gapps-arm-7.1-pico.zip
3. Reboot système.
```

### Alternatives à GApps

Si tu veux éviter les services Google : [MicroG](https://microg.org) est une réimplémentation
libre compatible avec la plupart des apps qui dépendent des Play Services, avec une bien plus
faible empreinte RAM. Plus adapté à ce matériel mais demande une signature ROM spécifique
(`signature spoofing`) — hors scope de ce dépôt pour l'instant.

## Splash / écran de démarrage custom

Il y a **deux niveaux distincts** de "splash" sur un appareil Android, à ne pas confondre :

### 1. Bootanimation (niveau système, facile à personnaliser)

C'est l'animation affichée **pendant le boot du système Android** (après le logo bas-niveau,
avant l'écran de verrouillage). C'est un simple fichier `bootanimation.zip` contenant des PNG
+ un `desc.txt`, sans compilation nécessaire.

**Génère le tien :**

```
./scripts/make_bootanimation.sh mes_frames_png/ bootanimation.zip 1280 800 24
```

- `mes_frames_png/` : dossier avec tes images PNG numérotées (`0000.png`, `0001.png`, ...),
  ou une seule image pour un splash statique en boucle
- Résolution recommandée : `1280 800` (résolution native de l'écran), ou plus bas (`800 500`)
  pour alléger le CPU/GPU limité de ce SoC
- FPS raisonnable : 12-24 (au-delà, peu de gain visible et plus de charge)

**Installe-le :**

```
./scripts/flash.sh bootanimation bootanimation.zip
```

### 2. Logo de boot bas-niveau (avant le kernel, complexe et spécifique au device)

C'est le tout premier écran affiché (logo "Samsung Galaxy Tab 4" au démarrage, avant même que
le kernel Linux démarre). Sur les appareils Samsung Exynos de cette génération, ce logo est
généralement stocké dans une partition dédiée (souvent nommée `param` sur les Exynos Samsung)
et flashé via Heimdall/Odin dans un format binaire propriétaire spécifique au bootloader.

**Ce dépôt ne fournit pas d'outil pour ça**, pour deux raisons honnêtes :
- Le format exact et le nom de partition varient selon la révision exacte du bootloader du
  SM-T530 — je n'ai pas de confirmation fiable sans accès à l'appareil physique pour tester.
- Une erreur de flash sur une partition bas-niveau (bootloader/param) est un des rares cas où
  un vrai brick (non récupérable) est possible sur ce type d'appareil — contrairement à
  system/recovery qui se re-flashent sans risque.

**Si tu veux quand même tenter :** cherche sur XDA un thread spécifique "millet" ou "SM-T530
param.bin custom logo" — la communauté a documenté ce genre de mod pour des appareils Exynos
similaires (S3, Note 2, etc.), mais vérifie bien que la procédure correspond exactement à ta
révision de bootloader avant de flasher quoi que ce soit sur `param`.

**Recommandation :** contente-toi du bootanimation.zip (sans risque, facilement réversible) et
laisse le logo bas-niveau d'origine.

## Config personnalisée au premier démarrage (OOBE / SetupWizard)

Quand un appareil LineageOS démarre pour la première fois, l'app **SetupWizard**
(`packages/apps/SetupWizard`, déjà incluse dans la ROM) affiche l'assistant de bienvenue,
sélection de langue, Wi-Fi, etc. Ce dépôt permet de **personnaliser le branding** de cet
assistant (nom, texte d'accueil, couleurs) sans forker l'app entière.

### Ce qui est couvert

- Texte d'accueil ("Bienvenue sur FriteOS") — `overlay/packages/apps/SetupWizard/res/values/strings.xml`
- Couleurs d'accent / barre de statut — `overlay/packages/apps/SetupWizard/res/values/colors.xml`
- Nom affiché dans "À propos de la tablette" et le fingerprint de build — `vendor/frite/vendor.mk`

### Ce qui n'est PAS couvert (hors scope pour l'instant)

Changer le **déroulé** de l'assistant (sauter l'étape compte Google, ajouter un écran custom,
réordonner les pages) demande de forker le code Java/Kotlin de SetupWizard, pas juste ses
ressources — c'est un vrai projet à part entière, avec plus de risques de régression (un bug
dans l'OOBE peut bloquer le premier démarrage). Pas fait ici ; à envisager plus tard si le
besoin est confirmé.

### Comment ça marche techniquement

Ce dépôt utilise le mécanisme d'overlay de ressources standard d'AOSP/LineageOS
(`PRODUCT_PACKAGE_OVERLAYS`) : des fichiers XML qui remplacent des valeurs de ressources
(texte, couleurs) d'une app déjà compilée dans le ROM, **sans toucher à son code**. Ils sont
appliqués automatiquement par `scripts/build.sh` (fonction `apply_branding`) :

1. Copie `overlay/` et `vendor/frite/vendor.mk` de ce dépôt vers `vendor/frite/` dans la
   source tree synchronisée
2. Ajoute (si pas déjà présent) `$(call inherit-product, vendor/frite/vendor.mk)` à la fin de
   `device/samsung/milletwifi/device.mk`

C'est automatique et idempotent — pas d'action manuelle nécessaire pour un build normal.
Pour désactiver ce branding : `SKIP_BRANDING=1 ./scripts/build.sh`.

### ⚠️ Vérifie les noms de ressources après le premier sync

Les noms de ressources utilisés dans `overlay/` (`setup_welcome`, `os_name`, `accent`,
`primary_dark`) correspondent à ceux du SetupWizard sur la branche `cm-14.1`. **Ils peuvent
avoir changé** selon la révision exacte synchronisée. Un overlay qui référence une ressource
inexistante est simplement ignoré (pas d'erreur de build), donc si ton texte n'apparaît pas
après un flash, la première chose à vérifier est :

```
grep -rn "setup_welcome\|os_name" <WORKDIR>/packages/apps/SetupWizard/res/values/strings.xml
grep -rn "\"accent\"\|\"primary_dark\"" <WORKDIR>/packages/apps/SetupWizard/res/values/colors.xml
```

et à ajuster `overlay/packages/apps/SetupWizard/res/values/{strings,colors}.xml` en
conséquence si les noms ont changé.

### Ajouter un logo custom dans l'assistant

Pour remplacer une image (pas juste du texte/couleur), place le PNG au même chemin relatif que
l'original dans `overlay/packages/apps/SetupWizard/res/drawable*/` (même nom de fichier que
celui trouvé dans la source SetupWizard synchronisée) — le mécanisme d'overlay remplace aussi
les ressources drawable, pas seulement les strings/colors.
