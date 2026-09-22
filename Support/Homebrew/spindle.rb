# The cask in afshinghezeli/homebrew-tap. Scripts/update-cask.sh fills in the version and the
# checksum of each release's DMG; edit this template, not the copy in the tap.
cask "spindle" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/afshinghezeli/spindle/releases/download/v#{version}/Spindle-#{version}.dmg"
  name "Spindle"
  desc "Clipboard history with instant search"
  homepage "https://github.com/afshinghezeli/spindle"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sequoia

  app "Spindle.app"

  uninstall quit: "com.afshinghezeli.Spindle"

  zap trash: [
    "~/Library/Application Scripts/com.afshinghezeli.Spindle",
    "~/Library/Caches/com.afshinghezeli.Spindle",
    "~/Library/Containers/com.afshinghezeli.Spindle",
  ]

  caveats <<~EOS
    Spindle is signed with its own certificate, not an Apple Developer ID, so macOS
    blocks the first launch. Open Spindle once, then choose Open Anyway in
    System Settings > Privacy & Security.
  EOS
end
