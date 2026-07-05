#!/bin/bash
# 编译并组装 ListeningClipPipe.app（菜单栏 App）。
# 用法: ./build_app.sh          # 构建
#       ./build_app.sh --run    # 构建并启动
#
# 说明一：本机 CommandLineTools 的 SPM 清单库损坏（swift build 无法解析 Package.swift），
# 所以这里直接用 swiftc 编译。项目无第三方依赖，结果等价。
#
# 说明二：本机 CLT 混装了新旧版本，/Library/Developer/CommandLineTools/usr/include/swift/
# 下的 module.modulemap（2023 残留）与 bridging.modulemap（当前）重复定义 SwiftBridging，
# 导致 import Foundation 直接报错。下面用 VFS overlay 把旧文件虚拟置空绕过。
# 永久修复（可选，需要密码）：
#   sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap{,.bak}
set -euo pipefail
cd "$(dirname "$0")"

ARCH="$(uname -m)"
mkdir -p build

# --- CLT 重复 modulemap 的 workaround ---
EXTRA_FLAGS=()
CLT_SWIFT_INC="/Library/Developer/CommandLineTools/usr/include/swift"
if [[ -f "$CLT_SWIFT_INC/module.modulemap" && -f "$CLT_SWIFT_INC/bridging.modulemap" ]]; then
    printf '// intentionally empty: real definition lives in bridging.modulemap\n' \
        > build/empty.modulemap
    cat > build/overlay.yaml <<EOF
{
  "version": 0,
  "case-sensitive": "false",
  "roots": [
    {
      "name": "$CLT_SWIFT_INC/module.modulemap",
      "type": "file",
      "external-contents": "$(pwd)/build/empty.modulemap"
    }
  ]
}
EOF
    EXTRA_FLAGS=(-vfsoverlay "$(pwd)/build/overlay.yaml"
                 -Xcc -ivfsoverlay -Xcc "$(pwd)/build/overlay.yaml")
fi

swiftc -O -swift-version 5 \
    -target "${ARCH}-apple-macosx14.4" \
    ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} \
    Sources/ListeningClipPipe/*.swift \
    -o build/ListeningClipPipe

APP="build/ListeningClipPipe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/ListeningClipPipe "$APP/Contents/MacOS/ListeningClipPipe"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 本机自用 ad-hoc 签名。注意：每次重新构建签名会变化，
# macOS 可能重新弹一次「系统音频录制」授权，属正常现象。
codesign --force --sign - "$APP"

echo "✅ Built: $(pwd)/$APP"
if [[ "${1:-}" == "--run" ]]; then
    open "$APP"
fi
