# Homebrew Cask for Cover Artwall.
#
# This file lives here for reference/version control, but Homebrew only
# reads Casks from a *tap* repo (one named `homebrew-<something>`, e.g.
# `homebrew-tap`). To actually publish it:
#
#   1. Create a repo named `homebrew-tap` (or similar) under your GitHub
#      account.
#   2. Copy this file into that repo's `Casks/cover-artwall.rb`.
#   3. Replace OWNER below with your GitHub username, and fill in `version`
#      + `sha256` from the release workflow's output (Actions -> Release ->
#      the run's summary/log has the sha256; it's also in the release body).
#   4. Push. Users can then run:
#        brew tap OWNER/tap
#        brew install --cask cover-artwall
#
# Since this ships unsigned (no Apple Developer ID), first launch needs one
# right-click -> Open, or `xattr -cr "/Applications/Cover Artwall.app"`.
# `brew install --cask` does NOT clear the quarantine flag for you.

cask "cover-artwall" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE_WORKFLOW"

  url "https://github.com/OWNER/cover-artwall/releases/download/v#{version}/CoverArtwall.app.zip"
  name "Cover Artwall"
  desc "Turns the cover art of what's currently playing into your desktop wallpaper"
  homepage "https://github.com/OWNER/cover-artwall"

  depends_on macos: ">= :ventura"

  app "Cover Artwall.app"

  zap trash: [
    "~/Library/Caches/CoverArtwall",
  ]
end
