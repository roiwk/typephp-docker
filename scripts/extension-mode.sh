# Shared by the entrypoint and the tpc wrappers.
# --wasm accepts one PHP file or project.yml, plus --build-dir.
# --php-builder, --full-static, --sapi and --php-version are rejected.
typephp_requests_wasm() {
    local arg
    for arg in "$@"; do
        if [[ "${arg}" == "--wasm" || "${arg}" == --wasm=* ]]; then
            return 0
        fi
    done
    return 1
}

# --nano composes swoole/php-nano sources and rejects --full-static / --php-builder.
typephp_requests_nano() {
    local arg
    for arg in "$@"; do
        if [[ "${arg}" == "--nano" ]]; then
            return 0
        fi
    done
    return 1
}

# Android and iOS targets use their own compiler and SDK. --full-static and
# --compiler would replace the NDK or Xcode driver.
typephp_target_is_mobile() {
    case "$1" in
        aarch64-linux-android*|arm64-apple-ios*|aarch64-apple-ios*)
            return 0
            ;;
    esac
    return 1
}

typephp_requests_mobile() {
    local arg=""
    local expect_target=0
    for arg in "$@"; do
        if [[ "${expect_target}" == 1 ]]; then
            typephp_target_is_mobile "${arg}" && return 0
            expect_target=0
            continue
        fi
        if [[ "${arg}" == "--target-platform" ]]; then
            expect_target=1
            continue
        fi
        if [[ "${arg}" == --target-platform=* ]]; then
            typephp_target_is_mobile "${arg#--target-platform=}" && return 0
            continue
        fi
        if [[ ( "${arg}" == *.yml || "${arg}" == *.yaml ) && -f "${arg}" ]]; then
            if grep -Eq '^[[:space:]]*target-platform:[[:space:]]*["'\'']?(aarch64-linux-android|arm64-apple-ios|aarch64-apple-ios)' "${arg}"; then
                return 0
            fi
        fi
    done
    return 1
}

# These modes reject the flags the static and private wrappers append.
typephp_requests_direct_tpc() {
    if typephp_requests_wasm "$@"; then
        return 0
    fi
    if typephp_requests_nano "$@"; then
        return 0
    fi
    typephp_requests_mobile "$@"
}

# Prints one line:
#   omit      TYPEPHP_EXTENSIONS was not set (Compose passes __omit__)
#   minimal   set, but no extension names: empty, none, base, minimal, -, []
#   <names>   comma-separated names, spaces removed, lowercased
typephp_extension_selection() {
    local raw="${TYPEPHP_EXTENSIONS-__omit__}"
    if [[ "${raw}" == "__omit__" ]]; then
        printf 'omit\n'
        return 0
    fi
    raw="${raw//[[:space:]]/}"
    raw="${raw,,}"
    case "${raw}" in
        ""|none|base|minimal|-|\[\])
            printf 'minimal\n'
            ;;
        *)
            printf '%s\n' "${raw}"
            ;;
    esac
}
