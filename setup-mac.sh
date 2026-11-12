#!/bin/bash
# Sets up this Mac as a GitHub Actions build machine for teemopower/unjam
# (Flipdex, Wren, Recipe Box iOS builds). Safe to run again.
set -e
REPO_URL="https://github.com/teemopower/unjam"
RUNNER_DIR="$HOME/actions-runner"
say() { printf "\n\033[1;34m== %s\033[0m\n" "$1"; }

say "1/6 Checking Xcode"
echo "macOS $(sw_vers -productVersion), $(uname -m)"
if [ ! -d /Applications/Xcode.app ]; then
  for c in /Applications/Xcode*.app "$HOME"/Downloads/Xcode*.app "$HOME"/Applications/Xcode*.app; do
    if [ -d "$c" ]; then echo "Found $c, moving it to /Applications/Xcode.app"; sudo mv "$c" /Applications/Xcode.app; break; fi
  done
fi
if [ ! -d /Applications/Xcode.app ]; then
  echo "Xcode isn't installed yet. On an Intel Mac, download 'Xcode 26.6 Universal.xip'"
  echo "from the page that's opening, unpack it, put it in Applications, open it once,"
  echo "then run this same command again."
  open "https://developer.apple.com/download/all/?q=Xcode%2026.6"
  exit 1
fi
XV=$(defaults read /Applications/Xcode.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo 0)
echo "Xcode in Applications: $XV"
if [ "${XV%%.*}" -lt 26 ] 2>/dev/null; then
  echo
  echo "This Xcode ($XV) is too old to run on this macOS or to build App Store apps."
  echo "1) Drag /Applications/Xcode.app to the Trash."
  echo "2) Download Xcode 26.6 (.xip) from the page that's opening (sign in with your Apple ID)."
  echo "3) Double-click the .xip, rename the result to Xcode, drag it into Applications, open it once."
  echo "4) Run this same command again."
  open "https://developer.apple.com/download/all/?q=Xcode%2026.6"
  exit 1
fi
echo "Your Mac password may be asked for (typing won't show)."
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch >/dev/null 2>&1 || true
xcodebuild -version

say "2/6 Checking the iOS Simulator"
if ! xcrun simctl list runtimes 2>/dev/null | grep -q "iOS"; then
  echo "Downloading the iOS Simulator (several GB, can take a while)..."
  xcodebuild -downloadPlatform iOS
fi
xcrun simctl list runtimes | grep iOS | tail -1

say "3/6 (Homebrew not needed, skipping)"

say "4/6 Installing XcodeGen"
if ! command -v xcodegen >/dev/null 2>&1; then
  TMP=$(mktemp -d)
  curl -fL -o "$TMP/xcodegen.zip" https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
  unzip -q "$TMP/xcodegen.zip" -d "$TMP"
  sudo rm -rf /usr/local/xcodegen && sudo mkdir -p /usr/local/bin
  sudo mv "$TMP/xcodegen" /usr/local/xcodegen
  sudo ln -sf /usr/local/xcodegen/bin/xcodegen /usr/local/bin/xcodegen
  rm -rf "$TMP"
fi
xcodegen --version

say "5/6 Installing the GitHub runner"
mkdir -p "$RUNNER_DIR" && cd "$RUNNER_DIR"
if [ ! -f ./config.sh ]; then
  case "$(uname -m)" in arm64) A=arm64;; *) A=x64;; esac
  V=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"].lstrip("v"))')
  echo "Runner $V ($A)"
  curl -fL -o runner.tar.gz "https://github.com/actions/runner/releases/download/v$V/actions-runner-osx-$A-$V.tar.gz"
  tar xzf runner.tar.gz && rm runner.tar.gz
fi
if [ ! -f .runner ]; then
  echo
  echo "A GitHub page is opening. Sign in if asked, pick macOS, and find the"
  echo "line that starts with ./config.sh. Copy ONLY the code after --token"
  echo "(about 29 letters/numbers) and paste it here."
  open "$REPO_URL/settings/actions/runners/new?arch=x64&os=osx"
  read -r -p "Token: " TOKEN </dev/tty
  ./config.sh --url "$REPO_URL" --token "$TOKEN" --unattended --replace \
    --name "$(scutil --get ComputerName 2>/dev/null || hostname)" --labels macOS
fi
./svc.sh install >/dev/null 2>&1 || true
./svc.sh start
./svc.sh status | tail -3

say "6/6 Keeping the Mac awake on the charger"
sudo pmset -c sleep 0 disksleep 0
echo "The Mac won't sleep while plugged in (the screen can still turn off)."

say "Done! In GitHub › Settings › Actions › Runners this Mac should show 'Idle'."
