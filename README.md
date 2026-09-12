# surge-overlay

This flake exposes every stable Surge Mac 6 archive currently retained by
Surge's signed Sparkle feed.  The downloads are proprietary and require a
valid Surge license to use; the package is therefore marked unfree.

## Use as an overlay

```nix
{
  inputs.surge-overlay.url = "github:YOUR-OWNER/surge-overlay";

  outputs = { nixpkgs, surge-overlay, ... }: {
    darwinConfigurations.my-mac = nix-darwin.lib.darwinSystem {
      modules = [
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ surge-overlay.overlays.default ];
          environment.systemPackages = [ pkgs.surge.latest ];
        })
      ];
    };
  };
}
```

`pkgs.surge.latest` and `nix run .` select the newest pinned release,
currently 6.9.0.  Select a specific archived release by its literal upstream
version, for example `pkgs.surge.versions."6.4.4"`.  The flake's direct
package outputs retain normalized names such as `surge_6_4_4` for command-line
convenience; they are not exported by the overlay.

## Build directly

```console
$ NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#surge_6_4_4
$ NIXPKGS_ALLOW_UNFREE=1 nix run --impure .#surge
```

The installed output contains `Applications/Surge.app`, `bin/surge-cli`,
`bin/surge-dashboard`, and `sbin/surge-dhcpd`.  Surge's privileged helper is
not declaratively installed: it is managed by the app and needs macOS
administrator authorization.  Likewise, its in-app updater cannot replace a
read-only Nix-store bundle.  Update this flake to change versions instead.

## Updating the archive

The canonical source is Surge's signed Sparkle feed at
`https://nssurge.com/mac/latest/appcast-signed.xml`.  For each new stable v6
item, record the marketing version, Sparkle build number, archive identifier,
and a freshly calculated SRI SHA-256 in `packages/versions.nix`.  Do not use
the moving `Surge-latest.zip` URL: it would make historical package names
non-reproducible.

The bundle paths deliberately follow the packaging knowledge captured in
Homebrew's `surge` cask.
