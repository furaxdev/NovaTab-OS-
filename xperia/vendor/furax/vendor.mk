# vendor.mk — branding FuraxOS pour le Sony Xperia XZ (kagura, F8331)
#
# Ce fichier est inclus depuis le device tree, dans device/sony/kagura/device.mk :
#
#   $(call inherit-product, xperia/vendor/furax/vendor.mk)

# Overlay de branding (SetupWizard, etc.) — voir xperia/overlay/
PRODUCT_PACKAGE_OVERLAYS += xperia/overlay

# Identité du produit — écrase les valeurs LineageOS par défaut
PRODUCT_NAME := furaxos_kagura
PRODUCT_BRAND := FuraxOS
PRODUCT_MODEL := FuraxOS (Xperia XZ)
PRODUCT_MANUFACTURER := FuraxOS

PRODUCT_PROPERTY_OVERRIDES += \
    ro.product.brand=FuraxOS \
    ro.product.name=furaxos_kagura \
    ro.product.model=FuraxOS\ (Xperia\ XZ) \
    ro.product.manufacturer=FuraxOS \
    ro.product.marketname=FuraxOS \
    \
    ro.build.display.id=FuraxOS-1.0-kagura \
    ro.build.display.furaxos_version=1.0 \
    \
    ro.lineage.version=FuraxOS-1.0 \
    ro.lineage.display.version=FuraxOS-1.0 \
    ro.cm.version=FuraxOS-1.0 \
    ro.cm.display.version=FuraxOS-1.0 \
    \
    ro.lineage.device=FuraxOS-XZ \
    ro.cm.device=FuraxOS-XZ
