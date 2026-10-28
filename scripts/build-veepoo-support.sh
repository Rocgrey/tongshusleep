#!/bin/bash
set -euo pipefail
vendor="$SRCROOT/Vendor/Veepoo"
objects="$DERIVED_FILE_DIR/VeepooSupport"
mkdir -p "$objects"
if [[ ! -f "$vendor/Frameworks/VeepooBleSDK.framework/VeepooBleSDK" ]]; then
    echo "error: Run /usr/bin/python3 scripts/setup-veepoo.py before building the ring test project."
    exit 1
fi
for source in "$vendor"/FMDB/src/fmdb/*.m "$vendor"/MJExtension/MJExtension/*.m; do
    object="$objects/$(basename "${source%.m}").o"
    xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDKROOT" -miphoneos-version-min=17.0 \
        -fobjc-arc -fmodules -I "$vendor/FMDB/src/fmdb" -I "$vendor/MJExtension/MJExtension" \
        -c "$source" -o "$object"
done
xcrun --sdk iphoneos libtool -static -o "$BUILT_PRODUCTS_DIR/libsleeptongshuVendorSupport.a" "$objects"/*.o
frameworks="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$frameworks"
for name in GRDFUSDK ZipZap JLDialUnit ABParTool; do
    destination="$frameworks/$name.framework"
    ditto "$vendor/Frameworks/$name.framework" "$destination"
    binary="$destination/$name"
    if [[ $(xcrun lipo -archs "$binary" | wc -w) -gt 1 ]]; then
        xcrun lipo "$binary" -thin arm64 -output "$objects/$name"
        cp "$objects/$name" "$binary"
    fi
    if [[ "${CODE_SIGNING_ALLOWED:-NO}" == YES && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
        /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$destination"
    fi
done
licenses="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/VendorLicenses"
mkdir -p "$licenses"
cp "$vendor/LICENSE" "$licenses/Veepoo-Apache-2.0.txt"
cp "$vendor/FMDB/LICENSE.txt" "$licenses/FMDB.txt"
cp "$vendor/MJExtension/LICENSE" "$licenses/MJExtension.txt"
