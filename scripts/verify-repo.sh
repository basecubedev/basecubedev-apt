#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

verify_signatures() (
  local gpg_home

  gpg_home=$(mktemp -d)
  chmod 700 "$gpg_home"
  trap 'rm -rf "$gpg_home"' EXIT

  export GNUPGHOME="$gpg_home"
  gpg --batch --import "$repo_root/basecubedev-archive-keyring.gpg" >/dev/null
  gpg --batch --verify "$release_dir/InRelease"
  gpg --batch --verify "$release_dir/Release.gpg" "$release_dir/Release"
)

verify_package_index() {
  local arch=$1
  local packages_file="$release_dir/main/binary-$arch/Packages"
  local packages_gz="$packages_file.gz"
  local filename_prefix="pool/main/$pool_prefix/$package_name/"

  [[ -f "$packages_file" ]] || die "missing $packages_file"
  [[ -f "$packages_gz" ]] || die "missing $packages_gz"
  gzip -t "$packages_gz"

  grep -q "^Package: $package_name$" "$packages_file" || die "$packages_file does not contain Package: $package_name"
  grep -q "^Architecture: $arch$" "$packages_file" || die "$packages_file does not contain Architecture: $arch"
  grep -q "^Filename: $filename_prefix" "$packages_file" ||
    die "$packages_file does not contain Filename: $filename_prefix..."

  awk -v package="$package_name" -v arch="$arch" -v prefix="$filename_prefix" '
    BEGIN {
      RS = "";
      FS = "\n";
      found = 0;
    }
    {
      has_package = 0;
      has_arch = 0;
      has_filename = 0;

      for (i = 1; i <= NF; i++) {
        if ($i == "Package: " package) {
          has_package = 1;
        }
        if ($i == "Architecture: " arch) {
          has_arch = 1;
        }
        if (index($i, "Filename: " prefix) == 1) {
          has_filename = 1;
        }
      }

      if (has_package && has_arch && has_filename) {
        found = 1;
      }
    }
    END {
      exit found ? 0 : 1;
    }
  ' "$packages_file" || die "$packages_file has no complete $package_name $arch entry"
}

contents_has_path() {
  local contents_file=$1
  local expected_path=$2

  awk -v expected_path="$expected_path" '
    {
      path = $NF;
      sub(/^\./, "", path);
      if (path == expected_path) {
        found = 1;
      }
    }
    END {
      exit found ? 0 : 1;
    }
  ' "$contents_file"
}

expected_version_from_filename() {
  local deb=$1
  local basename
  local remainder

  basename=$(basename "$deb")
  remainder=${basename#${package_name}_}
  echo "${remainder%_*}"
}

verify_branding() {
  local old_brand_pattern

  old_brand_pattern="Base""Cube""Dev|Base""Cube|basecube""Dev"
  if (cd "$repo_root" && grep -R -n -E --binary-files=without-match "$old_brand_pattern" . \
    --exclude-dir=.git \
    --exclude='*.deb' \
    --exclude='*.gz' \
    --exclude='*.gpg' \
    --exclude='basecubedev-archive-keyring.gpg'); then
    die "old branding found; use lowercase basecubedev"
  fi
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
debian_root="$repo_root/debian"
package_name=${PACKAGE:-paping-go}
release_dir="$debian_root/dists/stable"

[[ "$package_name" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || die "invalid package name: $package_name"
pool_prefix=${package_name:0:1}
pool_dir="$debian_root/pool/main/$pool_prefix/$package_name"

require_command dpkg-deb
require_command gzip
require_command gpg
require_command grep
require_command awk

[[ -f "$repo_root/basecubedev-archive-keyring.gpg" ]] || die "missing $repo_root/basecubedev-archive-keyring.gpg"
[[ -f "$release_dir/Release" ]] || die "missing $release_dir/Release"
[[ -f "$release_dir/InRelease" ]] || die "missing $release_dir/InRelease"
[[ -f "$release_dir/Release.gpg" ]] || die "missing $release_dir/Release.gpg"

verify_signatures

verify_package_index amd64
verify_package_index arm64

shopt -s nullglob
amd64_debs=("$pool_dir"/"${package_name}"_*_amd64.deb)
arm64_debs=("$pool_dir"/"${package_name}"_*_arm64.deb)
all_debs=("$pool_dir"/"${package_name}"_*.deb)

[[ ${#amd64_debs[@]} -gt 0 ]] || die "no amd64 .deb found in $pool_dir"
[[ ${#arm64_debs[@]} -gt 0 ]] || die "no arm64 .deb found in $pool_dir"
[[ ${#all_debs[@]} -gt 0 ]] || die "no .deb files found in $pool_dir"

for deb in "${all_debs[@]}"; do
  echo "Verifying $deb"
  dpkg-deb --info "$deb" >/dev/null
  deb_package=$(dpkg-deb --field "$deb" Package)
  deb_version=$(dpkg-deb --field "$deb" Version)
  deb_architecture=$(dpkg-deb --field "$deb" Architecture)
  expected_version=$(expected_version_from_filename "$deb")

  [[ "$deb_package" == "$package_name" ]] || die "$deb has Package: $deb_package, expected $package_name"
  [[ -n "$deb_version" ]] || die "$deb has an empty Version field"
  [[ "$deb_version" == "$expected_version" ]] ||
    die "$deb has Version: $deb_version, expected $expected_version from filename"
  [[ "$deb_architecture" == "amd64" || "$deb_architecture" == "arm64" ]] ||
    die "$deb has unsupported Architecture: $deb_architecture"

  contents_file=$(mktemp)
  dpkg-deb --contents "$deb" > "$contents_file"
  if ! contents_has_path "$contents_file" "/usr/bin/$package_name"; then
    rm -f "$contents_file"
    die "$deb does not contain /usr/bin/$package_name"
  fi
  if ! contents_has_path "$contents_file" "/usr/share/doc/$package_name/README.md"; then
    rm -f "$contents_file"
    die "$deb does not contain /usr/share/doc/$package_name/README.md"
  fi
  if ! contents_has_path "$contents_file" "/usr/share/doc/$package_name/LICENSE"; then
    rm -f "$contents_file"
    die "$deb does not contain /usr/share/doc/$package_name/LICENSE"
  fi
  rm -f "$contents_file"
done

verify_branding

echo "APT repository verification passed."
