#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <directory-with-deb-files>" >&2
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

detect_gpg_key_id() {
  gpg --batch --list-secret-keys --with-colons |
    awk -F: '
      $1 == "fpr" && seen_sec {
        print $10
        exit
      }
      $1 == "sec" {
        seen_sec = 1
      }
    '
}

gpg_with_passphrase() {
  if [[ -n "${APT_GPG_PASSPHRASE:-}" ]]; then
    gpg --batch --yes --pinentry-mode loopback --passphrase "$APT_GPG_PASSPHRASE" "$@"
  else
    gpg --batch --yes --pinentry-mode loopback "$@"
  fi
}

[[ $# -eq 1 ]] || {
  usage
  exit 2
}

incoming_dir=$1
package_name=${PACKAGE:-paping-go}
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
debian_root="$repo_root/debian"
release_dir="$debian_root/dists/stable"
conf_file="$repo_root/apt-ftparchive.conf"

[[ "$package_name" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || die "invalid package name: $package_name"
pool_prefix=${package_name:0:1}
pool_dir="$debian_root/pool/main/$pool_prefix/$package_name"
[[ -d "$incoming_dir" ]] || die "input directory does not exist: $incoming_dir"
[[ -f "$conf_file" ]] || die "missing apt-ftparchive config: $conf_file"

require_command dpkg-scanpackages
require_command apt-ftparchive
require_command gzip
require_command gpg

shopt -s nullglob
all_debs=("$incoming_dir"/*.deb)
[[ ${#all_debs[@]} -gt 0 ]] || die "no .deb files found in $incoming_dir"

amd64_debs=("$incoming_dir"/"${package_name}"_*_amd64.deb)
arm64_debs=("$incoming_dir"/"${package_name}"_*_arm64.deb)

[[ ${#amd64_debs[@]} -eq 1 ]] || die "expected exactly one amd64 package, found ${#amd64_debs[@]}"
[[ ${#arm64_debs[@]} -eq 1 ]] || die "expected exactly one arm64 package, found ${#arm64_debs[@]}"

package_debs=("${amd64_debs[@]}" "${arm64_debs[@]}")

mkdir -p \
  "$pool_dir" \
  "$release_dir/main/binary-amd64" \
  "$release_dir/main/binary-arm64"

for deb in "${package_debs[@]}"; do
  dest="$pool_dir/$(basename "$deb")"
  cp "$deb" "$dest"
done

(
  cd "$debian_root"

  dpkg-scanpackages --arch amd64 pool /dev/null > dists/stable/main/binary-amd64/Packages
  gzip -knf dists/stable/main/binary-amd64/Packages

  dpkg-scanpackages --arch arm64 pool /dev/null > dists/stable/main/binary-arm64/Packages
  gzip -knf dists/stable/main/binary-arm64/Packages

  apt-ftparchive -c "$conf_file" release dists/stable > dists/stable/Release
)

key_id=${APT_GPG_KEY_ID:-}
if [[ -z "$key_id" ]]; then
  key_id=$(detect_gpg_key_id)
fi
[[ -n "$key_id" ]] || die "no GPG secret key found; set APT_GPG_KEY_ID or import a signing key"

gpg_with_passphrase --output "$repo_root/basecubedev-archive-keyring.gpg" --export "$key_id"
gpg_with_passphrase --local-user "$key_id" --clearsign --digest-algo SHA256 \
  --output "$release_dir/InRelease" "$release_dir/Release"
gpg_with_passphrase --local-user "$key_id" --detach-sign --armor --digest-algo SHA256 \
  --output "$release_dir/Release.gpg" "$release_dir/Release"

PACKAGE="$package_name" "$repo_root/scripts/verify-repo.sh"

echo "APT repository updated for $package_name."
