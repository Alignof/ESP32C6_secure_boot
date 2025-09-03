{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    fenix.url = "github:nix-community/fenix";
    esp-dev.url = "github:mirrexagon/nixpkgs-esp-dev";
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
      fenix,
      esp-dev,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Read the toolchain definition from rust-toolchain.toml.
        spec = (builtins.fromTOML (builtins.readFile ./rust-toolchain.toml)).toolchain;

        # Get the list of components for the toolchain.
        userComponents = spec.components or [ ];
        baseComponents = [
          "rustc"
          "cargo"
          "rust-src"
          "clippy"
          "rustfmt"
          "rust-analyzer"
        ];
        components = pkgs.lib.unique (userComponents ++ baseComponents);

        # Get the list of targets for cross-compilation.
        targets = spec.targets or [ ];

        # Map common channel names to the names fenix uses.
        # This allows using "nightly" in rust-toolchain.toml, which we map to "latest".
        toolchainName =
          if spec.channel == "nightly" then
            "latest"
          else if spec.channel == "stable" then
            "stable"
          else if spec.channel == "beta" then
            "beta"
          else
            spec.channel; # Otherwise, assume a dated version like "nightly-YYYY-MM-DD"

        # Select the toolchain using the mapped name.
        toolchainForChannel = fenix.packages.${system}."${toolchainName}";

        # Build the host toolchain with all specified components.
        hostToolchain = toolchainForChannel.withComponents components;

        # Build the standard libraries for all specified cross-compilation targets.
        targetLibs = builtins.map (
          target: fenix.packages.${system}.targets."${target}"."${toolchainName}".rust-std
        ) targets;

        # Determine the primary cross-compilation target to set RUSTFLAGS.
        primaryTarget = if targets == [ ] then null else builtins.head targets;
        primaryTargetLib = if targetLibs == [ ] then null else builtins.head targetLibs;

      in
      {
        devShell =
          with pkgs;
          mkShell rec {
            # Combine the host toolchain, target libraries, and other dependencies.
            buildInputs = [
              hostToolchain
            ]
            ++ targetLibs
            ++ [
              espflash
              esp-dev.packages.${system}.esp-idf-esp32c6
              python3
              python3Packages.pyserial
              python3Packages.requests
              llvmPackages_19.libclang
              ldproxy
            ];

            RUST_SRC_PATH = "${hostToolchain}/lib/rustlib/src/rust/library";
            LIBCLANG_PATH = "${pkgs.llvmPackages_19.libclang.lib}/lib";

            # Set RUSTFLAGS using the path to the primary target's standard library.
            RUSTFLAGS = pkgs.lib.optionalString (
              primaryTarget != null
            ) "-L ${primaryTargetLib}/lib/rustlib/${primaryTarget}/lib";

            RUST_BACKTRACE = 1;
          };
      }
    );
}
