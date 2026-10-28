#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh release

staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/TokenIsland-dmg.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT
content_directory="$staging_directory/content"
mkdir -p "$content_directory"
# Extract the clean, signed archive rather than copying a File Provider bundle.
ditto -x -k dist/TokenIsland.zip "$content_directory"
app="$content_directory/TokenIsland.app"
codesign --verify --deep --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
architectures="$(lipo -archs "$app/Contents/MacOS/TokenIsland")"
case "$architectures" in
  arm64) architecture="arm64" ;;
  x86_64) architecture="x86_64" ;;
  'arm64 x86_64'|'x86_64 arm64') architecture="universal" ;;
  *) echo "Unsupported architectures: $architectures" >&2; exit 1 ;;
esac

ln -s /Applications "$content_directory/Applications"
cat > "$content_directory/安装说明.txt" <<'EOF'
TokenIsland 安装说明

1. 将 TokenIsland.app 拖入 Applications（应用程序）文件夹。
2. 从“应用程序”打开 TokenIsland。顶部数值区域点击展开，再次点击收起。
3. 在“更多”或菜单栏菜单中开启或关闭“开机自启”。

需要 macOS 14 或以上，以及带内置 Codex CLI 的新版 ChatGPT Mac 应用。
本机架构请以 DMG 文件名为准：arm64 适用于 Apple Silicon，x86_64 适用于 Intel。

当前构建采用 ad-hoc 开发签名，尚未进行 Developer ID 签名和 Apple 公证。
账号日统计可能延迟；账号接口不提供精确小时明细，可切换本机实时曲线。
仅支持 ChatGPT Work / Codex 任务，普通 ChatGPT 聊天的完整 Token 用量暂不支持。

项目与版本更新：https://github.com/chenzhen411/TokenIsland
EOF

filename="TokenIsland-${version}-macos-${architecture}.dmg"
hdiutil create -volname "TokenIsland $version" -srcfolder "$content_directory" \
  -fs HFS+ -format UDZO "$staging_directory/TokenIsland.dmg"
hdiutil verify "$staging_directory/TokenIsland.dmg"
mv "$staging_directory/TokenIsland.dmg" "$PWD/dist/$filename"
(
  cd dist
  shasum -a 256 "$filename" > "$filename.sha256"
)
echo "Packaged: $PWD/dist/$filename"
echo "Checksum: $PWD/dist/$filename.sha256"
