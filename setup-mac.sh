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
  echo "Xcode isn't installed yet. Opening the App Store page for Xcode."
  echo "Install it, open it once, then run this same command again."
  open "macappstore://apps.apple.com/app/xcode/id497799835"
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

say "3/6 Checking Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$($b shellenv)"; done
fi
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$($b shellenv)"; done
  BREW_LINE="eval \"\$($(command -v brew) shellenv)\""
  grep -qF "$BREW_LINE" "$HOME/.zprofile" 2>/dev/null || echo "$BREW_LINE" >> "$HOME/.zprofile"
fi
brew --version | head -1

say "4/6 Installing XcodeGen"
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
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
