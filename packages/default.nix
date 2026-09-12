{
  lib,
  stdenvNoCC,
  unzip,
}:

let
  releases = import ./versions.nix;

  # The Sparkle feed names every stable release using its marketing version,
  # build number, and immutable archive identifier.  Keeping those three
  # fields separate makes the provenance visible and lets a maintainer update
  # the table from the official feed without constructing URLs by hand.
  mkSurge =
    {
      version,
      build,
      archiveId,
      hash,
    }:
    stdenvNoCC.mkDerivation {
      pname = "surge";
      inherit version;

      src = builtins.fetchurl {
        url = "https://dl.nssurge.com/mac/v6/Surge-${version}-${build}-${archiveId}.zip";
        sha256 = hash;
      };

      nativeBuildInputs = [ unzip ];

      unpackPhase = ''
        runHook preUnpack
        unzip -qq "$src"
        runHook postUnpack
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p "$out/Applications" "$out/bin" "$out/sbin"
        cp -R Surge.app "$out/Applications/"

        # These executables are part of the app bundle.  The names and paths
        # mirror the Homebrew cask, but Nix exposes the GUI helper under a
        # shell-friendly name and keeps the daemon in sbin.
        ln -s ../Applications/Surge.app/Contents/Applications/surge-cli "$out/bin/surge-cli"
        ln -s ../Applications/Surge.app/Contents/Applications/Surge\ Dashboard.app/Contents/MacOS/Surge\ Dashboard "$out/bin/surge-dashboard"
        ln -s ../Applications/Surge.app/Contents/Applications/surge-dhcpd "$out/sbin/surge-dhcpd"

        runHook postInstall
      '';

      passthru = {
        inherit build archiveId;
      };

      meta = {
        description = "Advanced network toolbox for macOS";
        homepage = "https://nssurge.com/";
        license = lib.licenses.unfree;
        platforms = lib.platforms.darwin;
        mainProgram = "surge-cli";
      };
    };

  byAttribute = lib.listToAttrs (
    map (
      release:
      lib.nameValuePair "surge_${lib.replaceStrings [ "." ] [ "_" ] release.version}" (mkSurge release)
    ) releases
  );

  # The overlay's public package family follows go-overlay's selector shape:
  # `pkgs.surge.versions."6.9.0"`.  Keep normalized names only as a flake
  # output adapter, where shell-friendly attribute names are useful.
  versions = lib.listToAttrs (
    map (
      release:
      lib.nameValuePair release.version
        byAttribute."surge_${lib.replaceStrings [ "." ] [ "_" ] release.version}"
    ) releases
  );
in
{
  inherit byAttribute releases versions;
  latest = versions."6.9.0";
}
