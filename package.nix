{
  lib,
  buildGoModule,
  fetchFromGitHub,
  stdenv,
  runCommand,
  symlinkJoin,
  makeWrapper,
  nodejs_24,
  pnpm_10,
  fetchPnpmDeps,
  python3,
  bash,
  coreutils,
  openssl,
  curl,
  postgresql,
  cacert,
  tzdata,
  # The published dev images are built with -tags=authdisabled
  # (GO_BUILD_TAGS in build/package/servers.dockerfile).
  buildTags ? [ ],
}:

let
  version = "0.114.2";

  src = fetchFromGitHub {
    owner = "hatchet-dev";
    repo = "hatchet";
    rev = "v${version}";
    hash = "sha256-b+6I6OzDG0P7ckfVSGaiK1SMfGCUd4x+5hsIChFf94M=";
  };

  # build/package/servers.dockerfile:
  #   ENV CGO_ENABLED=0
  #   go build -tags="$GO_BUILD_TAGS" \
  #     -ldflags="-w -s -X 'main.Version=${VERSION}'" -a \
  #     -o ./bin/hatchet-$TARGET ./cmd/hatchet-$TARGET
  #
  # That Dockerfile also runs `go generate ./...`; it is a no-op, the repo has
  # zero //go:generate directives and openapi.gen.go is committed.
  server =
    target:
    buildGoModule {
      pname = "hatchet-${target}";
      inherit version src;
      vendorHash = "sha256-AiE79tJAevdSIibVVa42XgYJkj647pNfmqdsVobpgqo=";
      subPackages = [ "cmd/hatchet-${target}" ];
      env.CGO_ENABLED = "0";
      tags = buildTags;
      ldflags = [
        "-s"
        "-w"
        "-X"
        "main.Version=${version}"
      ];
      doCheck = false;
    };

  lite = server "lite";
  admin = server "admin";
  migrate = server "migrate";

  # The SPA build needs files that are gitignored and produced by
  # frontend/snippets/generate.py (the Dockerfile assumes CI ran it first).
  # generate.py resolves ROOT as ../.. from its own path and writes
  #   <root>/frontend/app/src/lib/generated/docs
  #   <root>/frontend/docs/lib/generated
  generated =
    runCommand "hatchet-${version}-generated-docs"
      {
        nativeBuildInputs = [ python3 ];
      }
      ''
        cp -r ${src} $out
        chmod -R u+w $out
        ( cd $out/frontend/snippets && python3 -X utf8 generate.py )
      '';

  uiSrc = lib.cleanSourceWith {
    src = "${generated}/frontend/app";
    filter =
      path: type:
      !(builtins.elem (baseNameOf path) [
        "node_modules"
        "dist"
      ]);
  };

  # build/package/lite.dockerfile stage 2:
  #   corepack pnpm@10.16.1 install --frozen-lockfile && npm run build
  pnpmDeps = (fetchPnpmDeps.override { pnpm = pnpm_10; }) {
    pname = "hatchet-ui";
    inherit version;
    src = uiSrc;
    hash = "sha256-j0yfTCNzN92HukVNs/cWwwrfkPVuW0grzZqPuf91r9o=";
    fetcherVersion = 3;
  };

  ui = stdenv.mkDerivation {
    pname = "hatchet-ui";
    inherit version;
    src = uiSrc;

    nativeBuildInputs = [
      nodejs_24
      pnpm_10
      pnpm_10.configHook
    ];
    inherit pnpmDeps;

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      # package.json pins "packageManager": "pnpm@10.16.1"; without this pnpm
      # tries to download that exact version from the registry mid-build.
      export npm_config_manage_package_manager_versions=false
      export COREPACK_ENABLE_PROJECT_SPEC=0
      pnpm build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/hatchet
      cp -r dist $out/share/hatchet/static-assets
      runHook postInstall
    '';

    dontFixup = true;
  };
in
symlinkJoin {
  pname = "hatchet-lite";
  inherit version;

  paths = [
    lite
    admin
    migrate
    ui
  ];

  nativeBuildInputs = [ makeWrapper ];

  # lite.dockerfile's alpine stage installs bash, ca-certificates, tzdata,
  # openssl, curl and postgresql-client, and sets LITE_* in the image env.
  postBuild = ''
    for p in hatchet-lite hatchet-admin hatchet-migrate; do
      wrapProgram $out/bin/$p \
        --prefix PATH : ${
          lib.makeBinPath [
            bash
            coreutils
            openssl
            curl
            postgresql
            cacert
            tzdata
          ]
        } \
        --set-default LITE_STATIC_ASSET_DIR $out/share/hatchet/static-assets \
        --set-default LITE_FRONTEND_BASE_PATH / \
        --set-default LITE_FRONTEND_PORT 8081 \
        --set-default LITE_RUNTIME_PORT 8888
    done

    cp ${./start.sh} $out/entrypoint.sh
    chmod +x $out/entrypoint.sh
  '';

  meta = with lib; {
    description = "Hatchet workflow engine, lite build (engine + API + dashboard)";
    homepage = "https://github.com/hatchet-dev/hatchet";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "hatchet-lite";
  };
}
