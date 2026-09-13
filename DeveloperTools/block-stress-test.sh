#!/bin/zsh

set -eu

readonly stress_pack_name="FoundryStressTest.foundrypack"
readonly default_packs_root="${HOME}/Library/Application Support/Foundry/Packs"
readonly packs_root="${FOUNDRY_STRESS_PACKS_ROOT:-${default_packs_root}}"
readonly stress_pack_path="${packs_root}/${stress_pack_name}"
readonly script_path="${0:A}"

usage() {
    print "Usage:"
    print "  ${script_path} install [block-count] [realistic|heavy]"
    print "  ${script_path} remove"
    print "  ${script_path} path"
    print ""
    print "Set FOUNDRY_STRESS_PACKS_ROOT to generate somewhere other than Foundry's installed-packs directory."
}

validate_target() {
    if [[ -z "${packs_root}" || "${packs_root}" == "/" || "${packs_root}" == "${HOME}" ]]; then
        print -u2 "Refusing to use unsafe packs root: ${packs_root}"
        exit 1
    fi
    if [[ "${stress_pack_path:t}" != "${stress_pack_name}" ]]; then
        print -u2 "Refusing to use unexpected stress-pack path: ${stress_pack_path}"
        exit 1
    fi
}

write_collection_manifest() {
    local destination="$1"
    /bin/mkdir -p "${destination:h}"
    /usr/bin/printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0"><dict><key>collection</key><true/></dict></plist>' \
        > "${destination}"
}

write_block_manifest() {
    local destination="$1"
    local identifier="$2"
    local title="$3"
    /usr/bin/printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0"><dict>' \
        '<key>assets</key><array/>' \
        '<key>author</key><string>Foundry Stress Test</string>' \
        '<key>customItems</key><array/>' \
        '<key>description</key><string>Generated block used to stress-test package loading.</string>' \
        '<key>group</key><string>Other</string>' \
        "<key>id</key><string>${identifier}</string>" \
        '<key>minimumAPIVersion</key><integer>1</integer>' \
        '<key>slots</key><array/>' \
        '<key>tags</key><array><string>stress-test</string></array>' \
        '<key>templates</key><dict>' \
        '<key>files</key><array>' \
        '<dict><key>path</key><string>block.css</string><key>scope</key><string>instance</string></dict>' \
        '<dict><key>path</key><string>block.js</string><key>scope</key><string>instance</string></dict>' \
        '</array><key>html</key><string>block.html</string></dict>' \
        "<key>title</key><string>${title}</string>" \
        '<key>version</key><string>1.0.0</string>' \
        '</dict></plist>' \
        > "${destination}"
}

write_realistic_resources() {
    local resources="$1"
    local sequence="$2"
    /usr/bin/printf '<div {{ block.attributes }}>Stress block %s</div>\n' "${sequence}" \
        > "${resources}/block.html"
    /usr/bin/printf '.stress-block-%s { min-height: 1px; }\n' "${sequence}" \
        > "${resources}/block.css"
    /usr/bin/printf 'void element.offsetWidth;\n' > "${resources}/block.js"
    /usr/bin/printf '%s\n' \
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">' \
        '<rect x="3" y="3" width="18" height="18" rx="3" fill="none" stroke="currentColor" stroke-width="2"/>' \
        '<path d="M7 12h10M12 7v10" stroke="currentColor" stroke-width="2"/>' \
        '</svg>' \
        > "${resources}/icon.svg"
}

write_heavy_resources() {
    local resources="$1"
    local sequence="$2"
    write_realistic_resources "${resources}" "${sequence}"
    /usr/bin/printf '<!--' >> "${resources}/block.html"
    /usr/bin/printf '%*s' 131072 '' | /usr/bin/tr ' ' x >> "${resources}/block.html"
    /usr/bin/printf -- '-->\n' >> "${resources}/block.html"
    /usr/bin/printf '/*' >> "${resources}/block.css"
    /usr/bin/printf '%*s' 131072 '' | /usr/bin/tr ' ' x >> "${resources}/block.css"
    /usr/bin/printf '*/\n' >> "${resources}/block.css"
    /usr/bin/printf '/*' >> "${resources}/block.js"
    /usr/bin/printf '%*s' 131072 '' | /usr/bin/tr ' ' x >> "${resources}/block.js"
    /usr/bin/printf '*/\n' >> "${resources}/block.js"

    /usr/bin/printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24"/><!--' \
        > "${resources}/icon.svg"
    /usr/bin/printf '%*s' 61440 '' | /usr/bin/tr ' ' x >> "${resources}/icon.svg"
    /usr/bin/printf -- '--></svg>\n' >> "${resources}/icon.svg"
}

install_stress_pack() {
    local count="${1:-1000}"
    local profile="${2:-realistic}"
    if [[ "${count}" != <-> ]] || (( count < 1 || count > 10000 )); then
        print -u2 "Block count must be between 1 and 10000."
        exit 1
    fi
    if [[ "${profile}" != "realistic" && "${profile}" != "heavy" ]]; then
        print -u2 "Profile must be realistic or heavy."
        exit 1
    fi
    if [[ -e "${stress_pack_path}" ]]; then
        print -u2 "Stress pack already exists: ${stress_pack_path}"
        print -u2 "Run '${script_path} remove' before generating it again."
        exit 1
    fi

    local staging_path="${packs_root}/.${stress_pack_name}.staging-${$}"
    trap '/bin/rm -rf "${staging_path}"' EXIT INT TERM
    /bin/mkdir -p "${staging_path}/Contents/Resources"
    write_collection_manifest "${staging_path}/Contents/Info.plist"

    local index
    for (( index = 1; index <= count; index++ )); do
        local sequence="$(/usr/bin/printf '%05d' "${index}")"
        local block_root="${staging_path}/Contents/Resources/Stress${sequence}.foundrypack/Contents"
        local resources="${block_root}/Resources"
        /bin/mkdir -p "${resources}"
        write_block_manifest \
            "${block_root}/Info.plist" \
            "foundry.stress.block${sequence}" \
            "Stress ${sequence}"
        if [[ "${profile}" == "heavy" ]]; then
            write_heavy_resources "${resources}" "${sequence}"
        else
            write_realistic_resources "${resources}" "${sequence}"
        fi
    done

    /bin/mv "${staging_path}" "${stress_pack_path}"
    trap - EXIT INT TERM
    print "Installed ${count} ${profile} stress blocks at:"
    print "${stress_pack_path}"
    print "Launch Foundry normally, then run '${script_path} remove' when testing is complete."
}

remove_stress_pack() {
    if [[ ! -e "${stress_pack_path}" ]]; then
        print "No stress pack is installed at ${stress_pack_path}"
        return
    fi
    /bin/rm -rf "${stress_pack_path}"
    print "Removed ${stress_pack_path}"
}

validate_target
case "${1:-}" in
    install)
        install_stress_pack "${2:-1000}" "${3:-realistic}"
        ;;
    remove)
        remove_stress_pack
        ;;
    path)
        print "${stress_pack_path}"
        ;;
    *)
        usage
        exit 1
        ;;
esac
