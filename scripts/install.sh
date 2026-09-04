#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
app_dir="$HOME/Applications/LomoTalk.app"
bin_dir="$HOME/.local/bin"

cd "$repo_dir"
if ! xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1; then
  print -u2 "Apple's Command Line Tools installation cannot resolve the macOS SDK."
  print -u2 "Update/reinstall Command Line Tools (or select a full Xcode install), then run this installer again."
  exit 1
fi
swift build -c release

mkdir -p "$app_dir/Contents/MacOS" "$bin_dir"
cp ".build/release/lomo_talk" "$app_dir/Contents/MacOS/lomo_talk"
cp "$repo_dir/Support/Info.plist" "$app_dir/Contents/Info.plist"
ln -sfn "$app_dir/Contents/MacOS/lomo_talk" "$bin_dir/lomo_talk"

print "Installed lomo_talk at $bin_dir/lomo_talk"
if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
  print "Add this to ~/.zshrc, then open a new terminal:"
  print 'export PATH="$HOME/.local/bin:$PATH"'
fi
