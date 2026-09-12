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
            surge = surgeVersions.latest;
          };
        };

      flake.overlays.default =
        final: prev:
        let
          surgeVersions = final.callPackage ./packages { };
        in
        surgeVersions.byAttribute
        // {
          # `surge` is deliberately the newest pinned release, rather than an
          # updater URL.  Older releases remain addressable through both the
          # flat `surge_6_X_Y` names and `surge6."X.Y.Z"`.
          surge = surgeVersions.latest;
          surge6 = surgeVersions.byVersion // {
            latest = surgeVersions.latest;
          };
        };
    };
}
