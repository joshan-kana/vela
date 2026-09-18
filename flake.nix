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
      in
      {
        formatter = treefmt.config.build.wrapper;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            checkRepo
            formatRepo
            git
            jq
            nixd
            nodejs_24
            pnpm
            rust-analyzer
            rustToolchain
            treefmt.config.build.wrapper
          ];

          inherit (preCommit) shellHook;

          RUST_BACKTRACE = "1";
        };

        checks.repo-quality = treefmt.config.build.check self;
      }
    );
}
