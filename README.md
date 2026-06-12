# basecubedev APT Repository

Official public Debian/Ubuntu package repository for selected basecubedev open source projects.

This is a third-party APT repository. Add it only if you trust basecubedev as the package publisher.

## Available packages

- `paping-go` - TCP port ping utility written in Go

## Quick install

Add the repository key, configure the APT source, update APT, and install `paping-go`:

```bash
sudo install -d -m 0755 /etc/apt/keyrings

curl -fsSL https://repo.basecubedev.de/basecubedev-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/basecubedev.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/basecubedev.gpg] https://repo.basecubedev.de/debian stable main" \
  | sudo tee /etc/apt/sources.list.d/basecubedev.list

sudo apt update
sudo apt install paping-go
```

After installation, you can check the installed command:

```bash
paping-go --version
paping-go --help
```

## Verify repository / package info

Use APT to inspect which repository provides `paping-go` and which package metadata is available:

```bash
apt-cache policy paping-go
apt show paping-go
```

## Remove repository

Remove the APT source and keyring, then refresh APT:

```bash
sudo rm -f /etc/apt/sources.list.d/basecubedev.list
sudo rm -f /etc/apt/keyrings/basecubedev.gpg
sudo apt update
```

## Signing key

The repository metadata is signed with the basecubedev APT archive key.

Current public signing key fingerprint:

```text
DD12 048C E83D 87A5 A67A  974B 8B71 DCDC B8A2 4912
```

The fingerprint must match the public key served from:

```text
https://repo.basecubedev.de/basecubedev-archive-keyring.gpg
```

## Repository layout

The static APT repository is published at:

```text
https://repo.basecubedev.de/debian
```

APT metadata is stored under `/debian/dists`, and package files are stored under `/debian/pool`.

## Maintainer notes

This repository is updated automatically. Source projects publish `.deb` files as GitHub Release assets and then trigger the `update-apt.yml` workflow in this repository. The workflow downloads the release assets, regenerates APT metadata, signs `InRelease` and `Release.gpg`, verifies the repository, and commits the updated static repository back to `main`.

Private signing keys must never be committed.
