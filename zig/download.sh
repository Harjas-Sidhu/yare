#!/usr/bin/env sh


# Inspired by TigerBeetle's zig-download scripting approach
# (https://github.com/tigerbeetle/tigerbeetle, Apache-2.0). This
# implementation has since diverged significantly (dependency
# checks, community mirror fallback, etc.) and is licensed under
# this project's MIT license, not derived/copied from theirs.

set -eu                # Safeguard

REQUIRED_COMMANDS="uname mktemp awk sort cut grep mkdir rm mv basename tar rmdir printf"
 
check_dependencies() {
    check_dependencies_missing=""
 
    for cmd in $REQUIRED_COMMANDS; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            check_dependencies_missing="${check_dependencies_missing} $cmd"
        fi
    done
 
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        check_dependencies_missing="${check_dependencies_missing} curl-or-wget"
    fi
 
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        check_dependencies_missing="${check_dependencies_missing} sha256sum-or-shasum"
    fi
 
    if [ -n "$check_dependencies_missing" ]; then
        echo "Error: missing required command(s):${check_dependencies_missing}"
        echo "Please install the missing tool(s) and re-run this script."
        exit 1
    fi
}
 
check_dependencies

HOST_OS=$(uname)
HOST_ARCH=$(uname -m)

ZIG_MIRROR="https://ziglang.org/download"
ZIG_MIRROR_LIST_URL="https://ziglang.org/download/community-mirrors.txt"
ZIG_RELEASE="0.16.0"

case $HOST_ARCH in
    x86_64|amd64|x64)
        ZIG_ARCH="x86_64"
        ;;
    aarch64|arm64)
        ZIG_ARCH="aarch64"
        ;;
    *)
        echo "Error: ${HOST_ARCH} is an untested platform."
        echo "Supported and tested architectures: aarch64, x86_64."
        echo "To proceed anyway, please manually install Zig from: ${ZIG_MIRROR}"
        exit 1
        ;;
esac

case $HOST_OS in
    Linux)
        ZIG_OS="linux"
        ZIG_EXTENSION=".tar.xz"
        ZIG_BIN_EXT=""
        ;;
    Darwin)
        ZIG_OS="macos"
        ZIG_EXTENSION=".tar.xz"
        ZIG_BIN_EXT=""
        ;;
    CYGWIN*|MSYS*|MINGW*)
        ZIG_OS="windows"
        ZIG_EXTENSION=".zip"
        ZIG_BIN_EXT=".exe"
        if ! command -v unzip >/dev/null 2>&1; then
            echo "Error: 'unzip' is required on Windows but not installed."
            exit 1
        fi
        ;;
    *)
        echo "Error: ${HOST_OS} is an untested platform."
        echo "Supported and tested operating systems: Linux, macOS, and Windows."
        echo "To proceed anyway, please manually install Zig from: ${ZIG_MIRROR}"
        exit 1
        ;;
esac

# Check the docs/experiments/q1-bootstraping-scripts.md to know the rationale behind
# hardcoded hashes present.
case "${ZIG_OS}-${ZIG_ARCH}" in
    linux-x86_64)
        EXPECTED_HASH="70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00"
        ;;
    linux-aarch64)
        EXPECTED_HASH="ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17"
        ;;
    macos-x86_64)
        EXPECTED_HASH="0387557ed1877bc6a2e1802c8391953baddba76081876301c522f52977b52ba7"
        ;;
    macos-aarch64)
        EXPECTED_HASH="b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489"
        ;;
    windows-x86_64)
        EXPECTED_HASH="68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e"
        ;;
    windows-aarch64)
        EXPECTED_HASH="aee38316ee4111717900f45dd3130145c39289e105541d737eb8c5ed653c78ef"
        ;;
    *)
        echo "Something went wrong! Reached Unreachable code."
        exit 1
        ;;
esac

# NB: Bumping ZIG_RELEASE requires adding a new EXPECTED_HASH per platform
# above. This is deliberate, Zig makes real breaking
# changes across versions, so a version bump should be a conscious,
# reviewable act (its own PR).
ZIG_ARCHIVE_NAME="zig-${ZIG_ARCH}-${ZIG_OS}-${ZIG_RELEASE}${ZIG_EXTENSION}"
ZIG_ARCHIVE="./zig/cache/${ZIG_ARCHIVE_NAME}"
ZIG_DIRECTORY=$(basename "$ZIG_ARCHIVE" "$ZIG_EXTENSION")

verify_hash() {
    verify_hash_file="$1"
    verify_hash_expected="$2"
    verify_hash_actual=""

    if command -v sha256sum >/dev/null 2>&1; then
        verify_hash_actual=$(sha256sum "$verify_hash_file" | cut -d ' ' -f 1)
    elif command -v shasum >/dev/null 2>&1; then
        verify_hash_actual=$(shasum -a 256 "$verify_hash_file" | cut -d ' ' -f 1)
    else
        echo "Error: Neither sha256sum nor shasum is installed. Cannot verify download."
        exit 1
    fi

    if [ "$verify_hash_actual" = "$verify_hash_expected" ]; then
        return 0
    else
        return 1
    fi
}

download_file() {
    download_file_url="$1"
    download_file_output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl --location --show-error --silent --fail --output "$download_file_output" "$download_file_url"
    elif command -v wget >/dev/null 2>&1; then
        wget --silent --output-document="$download_file_output" "$download_file_url"
    else
        echo "Error: Neither curl nor wget is installed. Cannot download."
        exit 1
    fi
}

fetch_mirror_list() {
    fetch_mirror_list_raw="$(mktemp)"

    if ! download_file "$ZIG_MIRROR_LIST_URL" "$fetch_mirror_list_raw" 2>/dev/null; then
        rm -f "$fetch_mirror_list_raw"
        return 1
    fi

    awk 'BEGIN { srand() } { print rand() "\t" $0 }' "$fetch_mirror_list_raw" \
        | sort -n \
        | cut -f 2- \
        | grep -v '^[[:space:]]*$'

    rm -f "$fetch_mirror_list_raw"
}

download_with_fallback() {
    download_with_fallback_candidates="$1"
    download_with_fallback_path="$2"

    download_with_fallback_all="$(printf '%s\n%s\n' "$download_with_fallback_candidates" "$ZIG_MIRROR" \
        | grep -v '^[[:space:]]*$')"

    while IFS= read -r base_url; do
        [ -z "$base_url" ] && continue

        candidate_url="${base_url%/}/${ZIG_RELEASE}/${ZIG_ARCHIVE_NAME}"
        echo "Trying ${candidate_url} ..."

        if download_file "$candidate_url" "$download_with_fallback_path"; then
            if verify_hash "$download_with_fallback_path" "$EXPECTED_HASH"; then
                return 0
            fi
            echo "Checksum mismatch from this source, trying next ..."
            rm -f "$download_with_fallback_path"
        else
            echo "Download failed from this source, trying next ..."
            rm -f -- "$download_with_fallback_path" 2>/dev/null || true
        fi
    done <<EOF
        $download_with_fallback_all
EOF

    return 1
}

SKIP_DOWNLOAD=0

if [ -f "$ZIG_ARCHIVE" ]; then
    echo "Found existing archive: $ZIG_ARCHIVE"
    echo "Verifying hash..."

    if verify_hash "$ZIG_ARCHIVE" "$EXPECTED_HASH"; then
        echo "Cached archive is valid. Skipping download."
        SKIP_DOWNLOAD=1
    else
        echo "Cached archive is corrupted (hash mismatch). Redownloading..."
        rm -f "$ZIG_ARCHIVE"
    fi
fi

if [ "$SKIP_DOWNLOAD" -eq 0 ]; then
    echo "Downloading Zig ${ZIG_RELEASE} for ${ZIG_OS}-${ZIG_ARCH}..."
    mkdir -p ./zig/cache

    echo "Checking community mirrors..."
    MIRRORS="$(fetch_mirror_list || true)"
    if [ -z "$MIRRORS" ]; then
        echo "No mirror list available, using ${ZIG_MIRROR} directly."
    fi

    if ! download_with_fallback "$MIRRORS" "$ZIG_ARCHIVE"; then
        echo "Error: Could not download and verify Zig from any source."
        exit 1
    fi
fi

echo "Extracting ${ZIG_ARCHIVE}..."
case "$ZIG_EXTENSION" in
    .tar.xz)
        tar -xf "$ZIG_ARCHIVE" -C ./zig/cache
        ;;
    .zip)
        unzip -q "$ZIG_ARCHIVE" -d ./zig/cache
        ;;
esac

rm -rf zig/doc zig/lib "zig/zig${ZIG_BIN_EXT}"

mv "./zig/cache/${ZIG_DIRECTORY}/LICENSE" zig/
mv "./zig/cache/${ZIG_DIRECTORY}/README.md" zig/
mv "./zig/cache/${ZIG_DIRECTORY}/doc" zig/
mv "./zig/cache/${ZIG_DIRECTORY}/lib" zig/
mv "./zig/cache/${ZIG_DIRECTORY}/zig${ZIG_BIN_EXT}" zig/
rmdir "./zig/cache/${ZIG_DIRECTORY}"

ZIG_BIN="$(pwd)/zig/zig${ZIG_BIN_EXT}"
echo "Zig ${ZIG_RELEASE} ready: ${ZIG_BIN}"
