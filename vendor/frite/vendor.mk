# vendor.mk — branding FriteOS pour le SM-T530 (matissewifi)
#
# Ce fichier est inclus depuis le device tree via une ligne ajoutée par scripts/build.sh
# (ou à ajouter manuellement, voir docs/CUSTOMIZATION.md) :
#
#   $(call inherit-product, vendor/frite/vendor.mk)
#
# dans device/samsung/matissewifi/device.mk (n'importe où après les autres inherit-product).

# Overlay de branding (SetupWizard, etc.) — voir overlay/
PRODUCT_PACKAGE_OVERLAYS += vendor/frite/overlay

# Nom affiché dans "À propos de la tablette" et le fingerprint de build.
PRODUCT_NAME := friteos_matissewifi
PRODUCT_BRAND := FriteOS
PRODUCT_MODEL := FriteOS (SM-T530)

PRODUCT_PROPERTY_OVERRIDES += \
    ro.product.marketname=FriteOS \
    ro.build.display.friteos_version=1.0
