{
  description = "Pinned Surge Mac 6 application archives, exported as a Nix overlay";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.*.tar.gz";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      # This overlay intentionally supports Apple Silicon only;
      systems = [
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, ... }:
        let
          surgeVersions = pkgs.callPackage ./packages { };
        in
        {
          packages = surgeVersions.byAttribute // {
            default = surgeVersions.latest;
            latest = surgeVersions.latest;
          };
        };

      flake.overlays.default =
        final: prev:
        let
          surgeVersions = final.callPackage ./packages { };
        in
        {
          # Follow the version-family API used by modern toolchain overlays:
          # selection stays under one domain name, while `latest` is an
          # explicit moving alias to the newest *pinned* archive.
          surge = {
            inherit (surgeVersions) versions;
            latest = surgeVersions.latest;
          };
        };
    };
}
