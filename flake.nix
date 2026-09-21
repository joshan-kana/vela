{
  description = "Vela: a fast, native frontend for YouTrack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
      treefmt-nix,
      pre-commit-hooks,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [
            "clippy"
            "rust-src"
            "rustfmt"
          ];
        };

        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
        };

        nativeAppCheck = pkgs.buildNpmPackage {
          pname = "vela-native-check";
          version = "0";

          src = ./apps/native;
          npmDepsHash = "sha256-BBHz0p+Mq1YDHUb7xZ49lpZ/a0jph6yXmGjtxYBoZXs=";

          dontNpmBuild = true;

          buildPhase = ''
            runHook preBuild
            npm run lint
            npm run typecheck
            npm test -- --runInBand
            runHook postBuild
          '';

          installPhase = ''
            touch "$out"
          '';
        };

        rustWorkspaceCheck = rustPlatform.buildRustPackage {
          pname = "vela-workspace-check";
          version = "0";

          src = self;

          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
          ];

          buildPhase = ''
            runHook preBuild
            cargo clippy --workspace --all-targets --all-features -- -D warnings
            runHook postBuild
          '';

          checkPhase = ''
            runHook preCheck
            cargo test --workspace --all-features
            runHook postCheck
          '';

          installPhase = ''
            touch "$out"
          '';
        };

        treefmt = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";

          programs = {
            deadnix.enable = true;
            nixfmt.enable = true;
            prettier.enable = true;
            rumdl-check.enable = true;
            rumdl-format.enable = true;
            rustfmt.enable = true;
            statix.enable = true;
            taplo.enable = true;
            typos.enable = true;
          };

          settings.formatter = {
            statix.priority = 1;
            deadnix.priority = 2;
            nixfmt.priority = 3;

            rumdl-format = {
              options = [
                "--disable"
                "MD013"
              ];
              priority = 1;
            };

            rumdl-check = {
              options = [
                "--disable"
                "MD013"
              ];
              priority = 2;
            };

            typos = {
              excludes = [
                "apps/native/**/*.pbxproj"
                "apps/native/**/*.storyboard"
              ];
              includes = [ "*.md" ];
              priority = 3;
            };
          };
        };

        preCommit = pre-commit-hooks.lib.${system}.run {
          src = self;

          hooks = {
            repo-quality = {
              enable = true;
              name = "Repository formatting and linting";
              entry = "nix build --no-link .#checks.${system}.repo-quality";
              files = "\\.(json|lock|md|nix|rs|toml|tsx?|ya?ml)$|^\\.envrc$";
              pass_filenames = false;
            };

            staged-whitespace = {
              enable = true;
              name = "Staged whitespace";
              entry = "${pkgs.lib.getExe pkgs.git} diff --check --cached";
              pass_filenames = false;
              always_run = true;
            };
          };
        };

        formatRepo = pkgs.writeShellScriptBin "fmt" ''
          exec ${pkgs.lib.getExe treefmt.config.build.wrapper} "$@"
        '';

        checkRepo = pkgs.writeShellScriptBin "chk" ''
          exec nix flake check "$@"
        '';

        mkDevShell = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.mkShellNoCC else pkgs.mkShell;
      in
      {
        formatter = treefmt.config.build.wrapper;

        devShells.default = mkDevShell {
          packages =
            (with pkgs; [
              checkRepo
              cmake
              formatRepo
              git
              jq
              nixd
              nodejs_24
              pkg-config
              rust-analyzer
              rustToolchain
              treefmt.config.build.wrapper
            ])
            ++ (
              with pkgs;
              lib.optionals stdenv.hostPlatform.isDarwin [
                cocoapods
                watchman
              ]
            );

          inherit (preCommit) shellHook;

          RUST_BACKTRACE = "1";
        };

        checks = {
          native-app = nativeAppCheck;
          repo-quality = treefmt.config.build.check self;
          rust-workspace = rustWorkspaceCheck;
        };
      }
    );
}
