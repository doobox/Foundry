#!/bin/zsh

set -euo pipefail

curl_version="8.16.0"
libssh2_version="1.11.1"
mbedtls_version="3.6.4"
deployment_target="27.0"
vendor_root="${0:A:h}"
work_root="$(mktemp -d /private/tmp/foundry-curl.XXXXXX)"
source_root="$work_root/sources"
build_root="$work_root/build"
prefix="$work_root/prefix"
python_deps="$work_root/python"

cleanup() {
    rm -rf "$work_root"
}
trap cleanup EXIT

mkdir -p "$source_root" "$build_root" "$prefix/include" "$prefix/lib"

download() {
    local url="$1"
    local output="$2"
    /usr/bin/curl --fail --location --silent --show-error "$url" --output "$output"
}

download "https://curl.se/download/curl-${curl_version}.tar.gz" "$source_root/curl.tar.gz"
download "https://www.libssh2.org/download/libssh2-${libssh2_version}.tar.gz" "$source_root/libssh2.tar.gz"
download "https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-${mbedtls_version}/mbedtls-${mbedtls_version}.tar.bz2" "$source_root/mbedtls.tar.bz2"

verify() {
    local expected="$1"
    local file="$2"
    local actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        echo "Checksum mismatch for ${file:t}" >&2
        exit 1
    fi
}

verify "a21e20476e39eca5a4fc5cfb00acf84bbc1f5d8443ec3853ad14c26b3c85b970" "$source_root/curl.tar.gz"
verify "d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7" "$source_root/libssh2.tar.gz"
verify "ec35b18a6c593cf98c3e30db8b98ff93e8940a8c4e690e66b41dfc011d678110" "$source_root/mbedtls.tar.bz2"

python3 -m pip install --quiet --target "$python_deps" jsonschema jinja2
export PYTHONPATH="$python_deps"

mkdir "$build_root/mbedtls"
tar -xjf "$source_root/mbedtls.tar.bz2" -C "$build_root/mbedtls" --strip-components=1
make -C "$build_root/mbedtls" lib -j8 \
    CFLAGS="-O2 -arch arm64 -mmacosx-version-min=${deployment_target}"
cp -R "$build_root/mbedtls/include/mbedtls" "$build_root/mbedtls/include/psa" "$prefix/include/"
cp "$build_root/mbedtls/library/libmbedcrypto.a" \
   "$build_root/mbedtls/library/libmbedx509.a" \
   "$build_root/mbedtls/library/libmbedtls.a" \
   "$prefix/lib/"

mkdir "$build_root/libssh2"
tar -xzf "$source_root/libssh2.tar.gz" -C "$build_root/libssh2" --strip-components=1
(
    cd "$build_root/libssh2"
    CC="clang -arch arm64" \
    lt_cv_sys_max_cmd_len=262144 \
    CFLAGS="-O2 -mmacosx-version-min=${deployment_target}" \
    CPPFLAGS="-I$prefix/include" \
    LDFLAGS="-arch arm64 -mmacosx-version-min=${deployment_target} -L$prefix/lib" \
    ./configure \
        --disable-shared \
        --enable-static \
        --with-crypto=mbedtls \
        --with-libmbedcrypto-prefix="$prefix" \
        --prefix="$prefix"
    make -j8
    make install
)

mkdir "$build_root/curl"
tar -xzf "$source_root/curl.tar.gz" -C "$build_root/curl" --strip-components=1
(
    cd "$build_root/curl"
    PKG_CONFIG_PATH="$prefix/lib/pkgconfig" \
    lt_cv_sys_max_cmd_len=262144 \
    CC="clang -arch arm64" \
    CFLAGS="-O2 -mmacosx-version-min=${deployment_target}" \
    CPPFLAGS="-I$prefix/include" \
    LDFLAGS="-arch arm64 -mmacosx-version-min=${deployment_target} -L$prefix/lib" \
    LIBS="-lmbedtls -lmbedx509 -lmbedcrypto" \
    ./configure \
        --disable-shared \
        --enable-static \
        --disable-ldap \
        --disable-ldaps \
        --without-libpsl \
        --without-zstd \
        --without-brotli \
        --without-libidn2 \
        --without-nghttp2 \
        --with-mbedtls="$prefix" \
        --with-libssh2="$prefix" \
        --prefix="$prefix"
    make -j8
    make install
)

mkdir -p "$vendor_root/include/curl" "$vendor_root/lib" "$vendor_root/Licenses"
cp -R "$prefix/include/curl/" "$vendor_root/include/curl/"
/usr/bin/libtool -static -o "$vendor_root/lib/libFoundryCurl.a" \
    "$prefix/lib/libcurl.a" \
    "$prefix/lib/libssh2.a" \
    "$prefix/lib/libmbedtls.a" \
    "$prefix/lib/libmbedx509.a" \
    "$prefix/lib/libmbedcrypto.a"
cp "$build_root/curl/COPYING" "$vendor_root/Licenses/curl.txt"
cp "$build_root/libssh2/COPYING" "$vendor_root/Licenses/libssh2.txt"
cp "$build_root/mbedtls/LICENSE" "$vendor_root/Licenses/mbedtls.txt"

file "$vendor_root/lib/libFoundryCurl.a"
echo "FoundryCurl rebuilt successfully."
