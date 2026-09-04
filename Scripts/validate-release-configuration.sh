#!/bin/sh

set -eu
set +x

if [ "${CONFIGURATION:-}" != "Release" ]; then
    exit 0
fi

fail() {
    printf 'error: Release configuration validation failed for %s: %s\n' "${TARGET_NAME:-unknown target}" "$1" >&2
    exit 1
}

is_missing_value() {
    candidate=$1

    if [ -z "$candidate" ]; then
        return 0
    fi

    case "$candidate" in
        *[![:space:]]*)
            ;;
        *)
            return 0
            ;;
    esac

    case "$candidate" in
        *'$('*|*your-project*|*your_*|*paste_from_*|*placeholder*|*example*|*_here*)
            return 0
            ;;
    esac

    return 1
}

environment_value() {
    printenv "$1" 2>/dev/null || true
}

require_environment_value() {
    setting_name=$1
    setting_value=$(environment_value "$setting_name")

    if is_missing_value "$setting_value"; then
        fail "$setting_name is missing or still contains a placeholder"
    fi
}

require_one_environment_value() {
    first_name=$1
    second_name=$2
    first_value=$(environment_value "$first_name")
    second_value=$(environment_value "$second_name")

    if is_missing_value "$first_value" && is_missing_value "$second_value"; then
        fail "both $first_name and $second_name are missing"
    fi
}

validate_supabase_url() {
    case "$1" in
        https://*)
            supabase_host=${1#https://}
            ;;
        *)
            fail "$2 is not a hosted HTTPS Supabase URL"
            ;;
    esac

    case "$supabase_host" in
        ?*.supabase.co)
            ;;
        *)
            fail "$2 is not a hosted HTTPS Supabase URL"
            ;;
    esac

    case "$supabase_host" in
        */*|*:*|*[!A-Za-z0-9.-]*)
            fail "$2 contains an invalid hosted Supabase URL"
            ;;
    esac
}

validate_supabase_key() {
    case "$1" in
        sb_publishable_?*)
            ;;
        sb_secret_*)
            fail "$2 is a server-only Supabase secret key"
            ;;
        *)
            fail "$2 is not a client-safe Supabase publishable key"
            ;;
    esac
}

validate_revenuecat_key() {
    case "$1" in
        appl_?*)
            ;;
        sk_*)
            fail "$2 is a server-only RevenueCat secret key"
            ;;
        *)
            fail "$2 is not a public App Store RevenueCat SDK key"
            ;;
    esac
}

validate_intercom_key() {
    case "$1" in
        ios_sdk-?*)
            ;;
        *)
            fail "$2 is not an Intercom iOS SDK key"
            ;;
    esac
}

validate_intercom_app_id() {
    case "$1" in
        ''|*[!A-Za-z0-9_-]*)
            fail "$2 is not a valid Intercom app ID"
            ;;
    esac
}

plist_value() {
    plist_path=$1
    plist_key=$2
    /usr/bin/plutil -extract "$plist_key" raw -o - "$plist_path" 2>/dev/null || true
}

require_plist_value() {
    plist_path=$1
    plist_key=$2
    resolved_value=$(plist_value "$plist_path" "$plist_key")

    if is_missing_value "$resolved_value"; then
        fail "$plist_key is missing from the built app Info.plist"
    fi
}

require_one_plist_value() {
    plist_path=$1
    first_key=$2
    second_key=$3
    first_value=$(plist_value "$plist_path" "$first_key")
    second_value=$(plist_value "$plist_path" "$second_key")

    if is_missing_value "$first_value" && is_missing_value "$second_value"; then
        fail "both $first_key and $second_key are missing from the built app Info.plist"
    fi
}

validate_firebase_plist() {
    firebase_plist=$1
    expected_bundle_id=${2:-}

    [ -s "$firebase_plist" ] || fail "GoogleService-Info.plist is missing"
    /usr/bin/plutil -lint "$firebase_plist" >/dev/null || fail "GoogleService-Info.plist is invalid"

    for firebase_key in API_KEY GOOGLE_APP_ID GCM_SENDER_ID PROJECT_ID BUNDLE_ID; do
        firebase_value=$(plist_value "$firebase_plist" "$firebase_key")
        if is_missing_value "$firebase_value"; then
            fail "$firebase_key is missing from GoogleService-Info.plist"
        fi
    done

    firebase_bundle_id=$(plist_value "$firebase_plist" BUNDLE_ID)
    if [ -n "$expected_bundle_id" ] && [ "$firebase_bundle_id" != "$expected_bundle_id" ]; then
        fail "GoogleService-Info.plist BUNDLE_ID does not match the app bundle identifier"
    fi
}

validate_embedded_version() {
    embedded_plist=$1
    embedded_name=$2

    [ -s "$embedded_plist" ] || fail "$embedded_name Info.plist is missing"
    /usr/bin/plutil -lint "$embedded_plist" >/dev/null || fail "$embedded_name Info.plist is invalid"

    embedded_marketing_version=$(plist_value "$embedded_plist" CFBundleShortVersionString)
    embedded_build_number=$(plist_value "$embedded_plist" CFBundleVersion)

    [ "$embedded_marketing_version" = "${MARKETING_VERSION:-}" ] || fail "$embedded_name marketing version does not match the main app"
    [ "$embedded_build_number" = "${CURRENT_PROJECT_VERSION:-}" ] || fail "$embedded_name build number does not match the main app"
}

require_environment_value SUPABASE_URL
require_environment_value SUPABASE_ANON_KEY

supabase_url=$(environment_value SUPABASE_URL)
supabase_key=$(environment_value SUPABASE_ANON_KEY)
validate_supabase_url "$supabase_url" SUPABASE_URL
validate_supabase_key "$supabase_key" SUPABASE_ANON_KEY

case "${PLATFORM_NAME:-}" in
    iphoneos|iphonesimulator)
        require_environment_value REVENUECAT_IOS_API_KEY
        require_environment_value INTERCOM_IOS_API_KEY
        require_environment_value INTERCOM_APP_ID
        revenuecat_key=$(environment_value REVENUECAT_IOS_API_KEY)
        intercom_key=$(environment_value INTERCOM_IOS_API_KEY)
        intercom_app_id=$(environment_value INTERCOM_APP_ID)
        validate_revenuecat_key "$revenuecat_key" REVENUECAT_IOS_API_KEY
        validate_intercom_key "$intercom_key" INTERCOM_IOS_API_KEY
        validate_intercom_app_id "$intercom_app_id" INTERCOM_APP_ID
        ;;
    macosx)
        require_one_environment_value REVENUECAT_MACOS_API_KEY REVENUECAT_IOS_API_KEY
        if ! is_missing_value "$(environment_value REVENUECAT_MACOS_API_KEY)"; then
            revenuecat_key=$(environment_value REVENUECAT_MACOS_API_KEY)
            validate_revenuecat_key "$revenuecat_key" REVENUECAT_MACOS_API_KEY
        else
            revenuecat_key=$(environment_value REVENUECAT_IOS_API_KEY)
            validate_revenuecat_key "$revenuecat_key" REVENUECAT_IOS_API_KEY
        fi
        ;;
    *)
        fail "unsupported PLATFORM_NAME ${PLATFORM_NAME:-unset}"
        ;;
esac

source_firebase_plist="${SRCROOT}/Gradely/GoogleService-Info.plist"
validate_firebase_plist "$source_firebase_plist" "${PRODUCT_BUNDLE_IDENTIFIER:-}"

if [ -n "${TARGET_BUILD_DIR:-}" ]; then
    [ -n "${INFOPLIST_PATH:-}" ] || fail "INFOPLIST_PATH is unavailable"
    [ -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ] || fail "UNLOCALIZED_RESOURCES_FOLDER_PATH is unavailable"

    built_info_plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
    built_firebase_plist="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"

    [ -s "$built_info_plist" ] || fail "the built app Info.plist is missing"
    /usr/bin/plutil -lint "$built_info_plist" >/dev/null || fail "the built app Info.plist is invalid"

    require_plist_value "$built_info_plist" SupabaseURL
    require_plist_value "$built_info_plist" SupabaseAnonKey

    built_supabase_url=$(plist_value "$built_info_plist" SupabaseURL)
    built_supabase_key=$(plist_value "$built_info_plist" SupabaseAnonKey)
    validate_supabase_url "$built_supabase_url" SupabaseURL
    validate_supabase_key "$built_supabase_key" SupabaseAnonKey
    [ "$built_supabase_url" = "$supabase_url" ] || fail "built SupabaseURL does not match SUPABASE_URL"
    [ "$built_supabase_key" = "$supabase_key" ] || fail "built SupabaseAnonKey does not match SUPABASE_ANON_KEY"

    case "${PLATFORM_NAME:-}" in
        iphoneos|iphonesimulator)
            require_plist_value "$built_info_plist" RevenueCatIOSAPIKey
            require_plist_value "$built_info_plist" IntercomIOSAPIKey
            require_plist_value "$built_info_plist" IntercomAppID
            built_revenuecat_key=$(plist_value "$built_info_plist" RevenueCatIOSAPIKey)
            built_intercom_key=$(plist_value "$built_info_plist" IntercomIOSAPIKey)
            built_intercom_app_id=$(plist_value "$built_info_plist" IntercomAppID)
            validate_revenuecat_key "$built_revenuecat_key" RevenueCatIOSAPIKey
            validate_intercom_key "$built_intercom_key" IntercomIOSAPIKey
            validate_intercom_app_id "$built_intercom_app_id" IntercomAppID
            [ "$built_revenuecat_key" = "$revenuecat_key" ] || fail "built RevenueCatIOSAPIKey does not match REVENUECAT_IOS_API_KEY"
            [ "$built_intercom_key" = "$intercom_key" ] || fail "built IntercomIOSAPIKey does not match INTERCOM_IOS_API_KEY"
            [ "$built_intercom_app_id" = "$intercom_app_id" ] || fail "built IntercomAppID does not match INTERCOM_APP_ID"
            ;;
        macosx)
            require_one_plist_value "$built_info_plist" RevenueCatMacOSAPIKey RevenueCatIOSAPIKey
            if ! is_missing_value "$(plist_value "$built_info_plist" RevenueCatMacOSAPIKey)"; then
                built_revenuecat_key=$(plist_value "$built_info_plist" RevenueCatMacOSAPIKey)
                validate_revenuecat_key "$built_revenuecat_key" RevenueCatMacOSAPIKey
            else
                built_revenuecat_key=$(plist_value "$built_info_plist" RevenueCatIOSAPIKey)
                validate_revenuecat_key "$built_revenuecat_key" RevenueCatIOSAPIKey
            fi
            [ "$built_revenuecat_key" = "$revenuecat_key" ] || fail "built RevenueCat key does not match the selected build setting"
            ;;
    esac

    require_plist_value "$built_info_plist" CFBundleIdentifier
    validate_firebase_plist "$built_firebase_plist" "$(plist_value "$built_info_plist" CFBundleIdentifier)"

    for firebase_key in API_KEY GOOGLE_APP_ID GCM_SENDER_ID PROJECT_ID BUNDLE_ID; do
        [ "$(plist_value "$built_firebase_plist" "$firebase_key")" = "$(plist_value "$source_firebase_plist" "$firebase_key")" ] || \
            fail "built GoogleService-Info.plist $firebase_key does not match the source configuration"
    done

    built_app_dir="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
    validate_embedded_version "$built_info_plist" "main app"
    case "${PLATFORM_NAME:-}" in
        iphoneos|iphonesimulator)
            validate_embedded_version "$built_app_dir/PlugIns/GradelyWidgets.appex/Info.plist" "iOS widget"
            validate_embedded_version "$built_app_dir/Watch/GradelyWatch.app/Info.plist" "watch app"
            validate_embedded_version "$built_app_dir/Watch/GradelyWatch.app/PlugIns/GradelyWatchComplications.appex/Info.plist" "watch complication"
            ;;
        macosx)
            validate_embedded_version "$built_app_dir/Contents/PlugIns/GradelyMacWidgets.appex/Contents/Info.plist" "macOS widget"
            ;;
    esac
fi

printf 'Release runtime configuration validated for %s %s (%s).\n' \
    "${TARGET_NAME:-unknown target}" \
    "${MARKETING_VERSION:-unknown version}" \
    "${CURRENT_PROJECT_VERSION:-unknown build}"
