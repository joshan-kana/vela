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
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        androidComposition = pkgs.androidenv.composeAndroidPackages {
          platformVersions = [ "36" ];
          buildToolsVersions = [ "36.0.0" ];
          includeNDK = true;
          ndkVersions = [ "27.1.12297006" ];
          includeCmake = true;
          cmakeVersions = [ "3.22.1" ];
          includeEmulator = false;
          includeSystemImages = false;
        };

        androidSdk = androidComposition.androidsdk;
        androidSdkRoot = "${androidSdk}/libexec/android-sdk";
        androidNdkRoot = "${androidSdkRoot}/ndk/27.1.12297006";

        emulatorSupported = pkgs.stdenv.hostPlatform.isDarwin || pkgs.stdenv.hostPlatform.isx86_64;
        emulatorAbi = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64-v8a" else "x86_64";
        androidEmulator =
          if emulatorSupported then
            pkgs.androidenv.emulateApp {
              name = "vela-android-emulator";
              platformVersion = "36";
              abiVersion = emulatorAbi;
              systemImageType = "google_apis";
              deviceName = "vela-api36-${emulatorAbi}";
              androidUserHome = "$HOME/.cache/vela/android-emulator";
              configOptions = {
                "hw.keyboard" = "yes";
                "hw.gpu.enabled" = "yes";
                "hw.gpu.mode" = "auto";
              };
            }
          else
            null;

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [
            "clippy"
            "rust-src"
            "rustfmt"
          ];
          targets = [
            "aarch64-linux-android"
            "armv7-linux-androideabi"
            "i686-linux-android"
            "x86_64-linux-android"
          ]
          ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            "aarch64-apple-darwin"
            "aarch64-apple-ios"
            "x86_64-apple-darwin"
          ]
          ++ pkgs.lib.optionals (pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64) [
            "aarch64-apple-ios-sim"
          ]
          ++ pkgs.lib.optionals (pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isx86_64) [
            "x86_64-apple-ios"
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
          npmDepsHash = "sha256-+AQNKeRv5c++DtG4KyJ+jkfWmsmOXioolV+P4tSpkY8=";

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
            clang-format.enable = true;
            deadnix.enable = true;
            ktlint.enable = true;
            nixfmt.enable = true;
            prettier.enable = true;
            rumdl-check.enable = true;
            rumdl-format.enable = true;
            rustfmt.enable = true;
            shellcheck.enable = true;
            shfmt = {
              enable = true;
              useEditorConfig = true;
            };
            statix.enable = true;
            taplo.enable = true;
            typos.enable = true;
            xmllint.enable = true;
          };

          settings.formatter = {
            clang-format.includes = [
              "*.c"
              "*.cc"
              "*.cpp"
              "*.h"
              "*.hh"
              "*.hpp"
              "*.m"
              "*.mm"
            ];

            ktlint.includes = [ "apps/native/android/**/*.kt" ];

            groovy-lint = {
              command = pkgs.lib.getExe pkgs.npm-groovy-lint;
              includes = [ "*.gradle" ];
              options = [
                "--noserver"
                "--format"
                "--failon"
                "error"
              ];
            };

            xmllint.includes = [ "apps/native/android/**/*.xml" ];

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

            swift-format = {
              command = pkgs.lib.getExe pkgs.swift-format;
              includes = [ "apps/**/*.swift" ];
              options = [
                "format"
                "--in-place"
              ];
              priority = 1;
            };

            swift-lint = {
              command = pkgs.lib.getExe pkgs.swift-format;
              includes = [ "apps/**/*.swift" ];
              options = [ "lint" ];
              priority = 2;
            };

            shfmt.priority = 1;
            shellcheck.priority = 2;
            ktlint.priority = 1;
          };
        };

        preCommit = pre-commit-hooks.lib.${system}.run {
          src = self;

          hooks = {
            repo-quality = {
              enable = true;
              name = "Repository formatting and linting";
              entry = "nix build --no-link .#checks.${system}.repo-quality";
              files = "\\.(c|cc|cpp|gradle|h|hh|hpp|js|json|kt|kts|lock|m|md|mm|nix|plist|rs|sh|swift|toml|tsx?|xml|ya?ml)$|^\\.(clang-format|editorconfig|envrc)$";
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
          repo_root="$(${pkgs.lib.getExe pkgs.git} rev-parse --show-toplevel)"
          cd "$repo_root"

          nix flake check "$@"

          if [ "$(uname -s)" = "Darwin" ]; then
            exec ./scripts/check-macos-app.sh
          fi
        '';

        mkDevShell = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.mkShellNoCC else pkgs.mkShell;
      in
      {
        formatter = treefmt.config.build.wrapper;

        packages = pkgs.lib.optionalAttrs emulatorSupported {
          android-emulator = androidEmulator;
        };

        devShells.default = mkDevShell {
          packages =
            (with pkgs; [
              androidSdk
              cargo-ndk
              checkRepo
              cmake
              formatRepo
              git
              jdk17
              jq
              nixd
              nodejs_24
              pkg-config
              rust-analyzer
              rustToolchain
              swift-format
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

          ANDROID_HOME = androidSdkRoot;
          ANDROID_SDK_ROOT = androidSdkRoot;
          ANDROID_NDK_HOME = androidNdkRoot;
          ANDROID_NDK_ROOT = androidNdkRoot;
          JAVA_HOME = pkgs.jdk17.home;
          GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidSdkRoot}/build-tools/36.0.0/aapt2";

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
