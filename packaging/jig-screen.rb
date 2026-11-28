# The Homebrew formula for Jig Screen. This is the copy of record: the one that installs lives in
# the tap, HammaRidgeVentures/homebrew-tap, as Formula/jig-screen.rb.
#
# It builds from source, so the app needs no Apple notarizing.
# For a new version: tag it, then set `url` and `sha256` here and in the tap.
#   curl -sL <url> | shasum -a 256
class JigScreen < Formula
  desc "Status screen for Jig agents when your Mac is idle"
  homepage "https://github.com/HammaRidgeVentures/jig-ui-macos"
  url "https://github.com/HammaRidgeVentures/jig-ui-macos/archive/refs/tags/v0.6.0.tar.gz"
  sha256 "6a724e1a9e11ec01aa3f33587b4b598fa5807237720a7ea8ba536f4dec60cd2c"
  license "MIT"

  depends_on macos: :ventura

  def install
    # SwiftPM has a sandbox of its own, which can't start inside Homebrew's.
    ENV["SWIFT_BUILD_FLAGS"] = "--disable-sandbox"
    system "bash", "scripts/bundle.sh"
    prefix.install "build/Jig Screen.app"
    (bin/"jig-screen").write <<~SH
      #!/bin/bash
      # Opens Jig Screen. With an argument (--version, --snapshot out.png), runs the program itself.
      app="#{opt_prefix}/Jig Screen.app"
      if [ $# -gt 0 ]; then exec "$app/Contents/MacOS/JigScreen" "$@"; fi
      exec open "$app"
    SH
  end

  service do
    run [opt_prefix/"Jig Screen.app/Contents/MacOS/JigScreen"]
    process_type :interactive
  end

  def caveats
    <<~EOS
      Start Jig Screen now, and at every login:
        brew services start jig-screen
      Or open it once:
        jig-screen
      Then set the macOS screen saver to Never. Keep display sleep and the password.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/jig-screen --version")
  end
end
