# Template for the mrxnn/homebrew-tap repo. At release time it is copied into the tap as
# Formula/rimlight.rb, with VERSION and SHA256 filled in from what scripts/release prints.
class Rimlight < Formula
  desc "Design app icons for Apple platforms from any coding agent"
  homepage "https://github.com/mrxnn/rimlight"
  url "https://github.com/mrxnn/rimlight/releases/download/vVERSION/rimlight-VERSION-macos.tar.gz"
  sha256 "SHA256"
  license "Apache-2.0"

  # :tahoe is macOS 26 in Homebrew's MacOSVersion table (checked against Homebrew 7.0.6).
  depends_on macos: :tahoe

  def install
    # The binary finds its resource bundle beside its symlink-resolved path, so both go in
    # libexec and bin gets a symlink.
    libexec.install "rimlight", "RimlightCore_RimlightCore.bundle"
    bin.install_symlink libexec/"rimlight"
  end

  def caveats
    <<~EOS
      To add the Rimlight skill to Claude Code, run:
        rimlight install-skill

      `rimlight build`, which turns a picked render into an Icon Composer .icon,
      needs Xcode 26 with Icon Composer for its renders.
    EOS
  end

  test do
    assert_match "rimlight #{version}", shell_output("#{bin}/rimlight version")
  end
end
