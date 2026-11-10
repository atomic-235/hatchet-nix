# hatchet-nix

[Hatchet](https://github.com/hatchet-dev/hatchet) built from source with Nix —
the three Go binaries (`hatchet-lite`, `hatchet-admin`, `hatchet-migrate`) and the
React dashboard. No prebuilt binaries, no container image, no Docker.

## What it builds

| Output | Source |
|---|---|
| `bin/hatchet-lite` | `./cmd/hatchet-lite`, `CGO_ENABLED=0`, `-ldflags "-s -w -X main.Version=…"` |
| `bin/hatchet-admin` | `./cmd/hatchet-admin` |
| `bin/hatchet-migrate` | `./cmd/hatchet-migrate` |
| `share/hatchet/static-assets/` | `frontend/app` (Vite, via pnpm) |
| `entrypoint.sh` | `hack/lite/start.sh`, verbatim |

Each binary is wrapped so `PATH` contains the tools the Alpine image installs
(`bash`, `openssl`, `curl`, `postgresql`, `cacert`, `tzdata`) and the `LITE_*`
environment variables the image sets are already exported.

## Usage

As a flake input:

```nix
{
  inputs.hatchet-nix.url = "github:you/hatchet-nix";

  # ...
  environment.systemPackages = [
    inputs.hatchet-nix.packages.${pkgs.system}.default
  ];
}
```

Or via the overlay:

```nix
{
  inputs.hatchet-nix.url = "github:you/hatchet-nix";
  outputs = { nixpkgs, hatchet-nix, ... }: {
    nixpkgs.overlays = [ hatchet-nix.overlays.default ];
    # pkgs.hatchet-lite and pkgs.hatchet-lite-dev now exist
  };
}
```

Build it directly:

```bash
nix build .#              # auth-enabled build
nix build .#hatchet-lite-dev   # -tags=authdisabled, like the published *-dev images
nix flake check
```

## Running it locally

```bash
nix develop
cd example
process-compose up -p 8090
```

`process-compose` starts Postgres (data in `example/data/pg`), runs migrations,
generates the config, and starts `hatchet-lite` on <http://localhost:8888>.

`-p 8090` is required: process-compose's own HTTP server defaults to **8080**,
which `hatchet-lite` uses for its API.

The dev image's auth-free build is `hatchet-lite-dev`; it prints a fixed worker
token at startup (`example/data/config/authdisabled-token`).

## Using it with the Python/TypeScript SDKs

```bash
export HATCHET_CLIENT_TOKEN="$(cat example/data/config/authdisabled-token)"
export HATCHET_CLIENT_HOST_PORT=localhost:7077
export HATCHET_CLIENT_TLS_STRATEGY=none
```

## Bumping the version

Three hashes are pinned in `package.nix`:

| Hash | Where it comes from |
|---|---|
| `src.hash` | `fetchFromGitHub` source tarball |
| `vendorHash` | Go module vendor tree (`buildGoModule`) |
| `pnpmDeps.hash` | `pnpm_10.fetchDeps` |

Set each to `lib.fakeHash`, run `nix build`, and copy the `got:` value from the
error. Then bump `version`.

## What is intentionally not reproduced

- `-a` in the official `go build` (rebuilds all packages; build-time only).
- The `GOFIPS140` FIPS variant.
- The split `hatchet-api` / `hatchet-dashboard` images — those exist for the
  Kubernetes deployment; the lite image is a single process.

## Notes on the upstream build

Two things in `build/package/*.dockerfile` are easy to misread:

1. `go generate ./...` does nothing — the repository contains no
   `//go:generate` directives, and `openapi.gen.go` is committed.
2. The frontend build fails from a clean checkout unless
   `frontend/snippets/generate.py` runs first: `src/lib/generated` is
   gitignored. The Dockerfile assumes CI ran it before building the image.
