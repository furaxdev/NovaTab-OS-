# vendor.mk — branding FuraxOS pour le Sony Xperia XZ (kagura, F8331)
#
# Ce fichier est inclus depuis le device tree, dans device/sony/kagura/device.mk :
#
#   $(call inherit-product, xperia/vendor/furax/vendor.mk)
#
# (n'importe où après les autres inherit-product)

# Overlay de branding (SetupWizard, etc.) — voir xperia/overlay/
PRODUCT_PACKAGE_OVERLAYS += xperia/overlay

# Nom affiché dans "À propos du téléphone" et le fingerprint de build.
PRODUCT_NAME := furaxos_kagura
PRODUCT_BRAND := FuraxOS
PRODUCT_MODEL := FuraxOS (Xperia XZ F8331)

PRODUCT_PROPERTY_OVERRIDES += \
    ro.product.marketname=FuraxOS \
    ro.build.display.furaxos_version=1.0
