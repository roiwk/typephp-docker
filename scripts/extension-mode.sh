# Shared by the entrypoint and the tpc wrappers.
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
