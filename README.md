# basecubedev APT Repository

Static Debian/Ubuntu APT repository for basecubedev packages, published with GitHub Pages at `repo.basecubedev.de`.

## Install

```bash
sudo install -d -m 0755 /etc/apt/keyrings

curl -fsSL https://repo.basecubedev.de/basecubedev-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/basecubedev.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/basecubedev.gpg] https://repo.basecubedev.de/debian stable main" \
  | sudo tee /etc/apt/sources.list.d/basecubedev.list

sudo apt update
sudo apt install paping-go
```

Current archive signing key fingerprint:

```text
8F26 0E4D 9FD4 BDA3 9E28  547E 541A 3768 67EB B9BA
```

The fingerprint shown here must match the public key served from `https://repo.basecubedev.de/basecubedev-archive-keyring.gpg`. If the archive key is manually rotated, update this fingerprint in the same change.

## Automated Updates

Repository updates are fully automated after `paping-go` releases. The source repository publishes the GitHub Release assets, then triggers `.github/workflows/update-apt.yml` in this repository. This repository downloads the release `.deb` assets itself, requires both `amd64` and `arm64` packages, regenerates and signs the APT metadata, verifies signatures and package contents in CI, then commits the static repository back to `main`.

Required repository secrets:

- `APT_GPG_PRIVATE_KEY`: ASCII-armored private key for signing repository metadata.
- `APT_GPG_PASSPHRASE`: optional passphrase for the private key.
- `APT_GPG_KEY_ID`: optional signing key ID or fingerprint. If omitted, the workflow uses the first imported secret key.

Manual update trigger:

```bash
gh workflow run update-apt.yml \
  --repo basecubedev/basecubedev-apt \
  --ref main \
  -f source_repo=basecubedev/paping-go \
  -f tag=v0.1.2 \
  -f package=paping-go
```

The workflow owns all APT repository generation, signing, and verification logic. Source repositories should only publish release assets and trigger this workflow; they should not copy `.deb` files into this repository manually. Private signing keys must never be committed.
