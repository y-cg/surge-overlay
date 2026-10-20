#!/usr/bin/env nu
# Sync packages/versions.nix with Surge's signed Sparkle appcast.
#
# The appcast is the canonical source: it lists every stable v6 release that
# Surge still serves, with its marketing version, build number, and archive
# URL. Each release missing from versions.nix is prefetched into the Nix store,
# which yields the SRI SHA-256 that `builtins.fetchurl` verifies later.
#
# Invariants:
# - Existing entries are never rewritten. Only missing releases are appended,
#   so historical package hashes stay stable.
# - An existing entry that disagrees with the appcast (build or archive ID) is a
#   hard error. Silently picking one side would hide a re-published archive.
# - Entries are sorted by Sparkle build number, so the last entry is the newest.
#   packages/default.nix derives `latest` from that order.
# - Beta items are out of scope: this flake pins the stable archive only.
#
# Usage: nu scripts/update-versions.nu [--dry-run]

const appcast_url = "https://nssurge.com/mac/latest/appcast-signed.xml"

# Pull `{version, build, archiveId, url}` for each stable v6 item in the appcast.
#
# The version, build, and archive ID come from the enclosure URL, which is the
# only place all three appear together. The Sparkle attributes must agree with
# it, otherwise the feed is internally inconsistent and we stop.
def fetch-appcast-releases [] {
  let feed = (^curl -fsSL $appcast_url | from xml)
  let items = ($feed.content | where tag == channel | first | get content | where tag == item)

  $items
  | each {|item|
    let enclosure = ($item.content | where tag == enclosure | first | get attributes)
    let parsed = (
      $enclosure.url
      | parse --regex 'Surge-(?<version>[0-9.]+)-(?<build>[0-9]+)-(?<archiveId>[0-9a-f]{32})\.zip$'
    )

    if ($parsed | is-empty) {
      # Not a stable v6 archive (for example a beta with a different name). Skip it.
      null
    } else {
      let release = ($parsed | first)

      if $release.version != $enclosure.shortVersionString or $release.build != $enclosure.version {
        error make {msg: $"appcast item disagrees with its own URL: ($enclosure.url)"}
      }

      {
        version: $release.version
        build: $release.build
        archiveId: $release.archiveId
        url: $enclosure.url
      }
    }
  }
  | compact
  | where {|r| $r.version | str starts-with "6." }
}

# Read the pinned releases by evaluating the Nix file, so we see exactly what Nix sees.
def read-pinned-releases [versions_file: path] {
  ^nix eval --json --file $versions_file | from json
}

# Prefetch an archive and return its SRI SHA-256, the same hash `fetchurl` checks.
def prefetch-sri-hash [url: string] {
  ^nix store prefetch-file --json --hash-type sha256 $url
  | from json
  | get hash
}

# Render one attribute set exactly as the existing entries are formatted.
def render-release [release: record] {
  [
    "  {"
    $"    version = \"($release.version)\";"
    $"    build = \"($release.build)\";"
    $"    archiveId = \"($release.archiveId)\";"
    $"    hash = \"($release.hash)\";"
    "  }"
  ]
  | str join "\n"
}

# Keep the leading `#` comment block verbatim so provenance notes survive rewrites.
def read-header [versions_file: path] {
  open --raw $versions_file
  | lines
  | take while {|line| $line starts-with "#" }
  | str join "\n"
}

def main [
  --dry-run # Report what would change without writing versions.nix.
] {
  let versions_file = ($env.FILE_PWD | path join ".." "packages" "versions.nix" | path expand)

  let pinned = (read-pinned-releases $versions_file)
  let pinned_versions = ($pinned | get version)

  let appcast = (fetch-appcast-releases)

  # Check that every release we already pin still matches the appcast.
  for release in $appcast {
    let existing = ($pinned | where version == $release.version)
    if ($existing | is-not-empty) {
      let existing = ($existing | first)
      if $existing.build != $release.build or $existing.archiveId != $release.archiveId {
        error make {msg: $"pinned ($release.version) disagrees with appcast: pinned build=($existing.build) archive=($existing.archiveId); appcast build=($release.build) archive=($release.archiveId)"}
      }
    }
  }

  let missing = ($appcast | where {|r| $r.version not-in $pinned_versions })

  if ($missing | is-empty) {
    print "versions.nix is already up to date."
    return
  }

  print $"New releases: (($missing | get version) | str join ', ')"

  if $dry_run {
    print "Dry run: versions.nix not modified."
    return
  }

  let fetched = ($missing | each {|r|
    print $"Prefetching ($r.url)"
    $r | insert hash {|row| prefetch-sri-hash $row.url } | reject url
  })

  let releases = (
    $pinned
    | append $fetched
    | sort-by {|r| $r.build | into int }
  )

  let body = ($releases | each {|r| render-release $r } | str join "\n")
  let content = $"(read-header $versions_file)\n[\n($body)\n]\n"

  $content | save --force $versions_file
  print $"Updated ($versions_file). Review with: git diff -- packages/versions.nix"
}
