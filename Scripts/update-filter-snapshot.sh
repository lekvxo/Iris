#!/bin/zsh
set -eu
cd "${0:A:h:h}"
IRIS_ROOT="$PWD"
xcodebuild -resolvePackageDependencies -project Iris.xcodeproj -scheme Iris -clonedSourcePackagesDirPath build/SourcePackages >/dev/null
IRIS_TOOL=$(mktemp -d /tmp/iris-snapshot-tool.XXXXXX)
trap 'rm -rf "$IRIS_TOOL"' EXIT
mkdir -p "$IRIS_TOOL/Sources/SnapshotTool" "$IRIS_TOOL/output"
cat > "$IRIS_TOOL/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SnapshotTool", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "$IRIS_ROOT/build/SourcePackages/checkouts/SafariConverterLib")],
    targets: [.executableTarget(name: "SnapshotTool", dependencies: [
        .product(name: "ContentBlockerConverter", package: "SafariConverterLib")
    ])])
EOF
for IRIS_FILE in BlockerEngine FilterLists BundledBlocker YouTubeRuleStore YouTubeRuleAdapter; do
    cp "Iris/Blocking/$IRIS_FILE.swift" "$IRIS_TOOL/Sources/SnapshotTool/"
done
cp Scripts/FilterSnapshot.swift "$IRIS_TOOL/Sources/SnapshotTool/"
swift run --package-path "$IRIS_TOOL" --scratch-path /tmp/iris-snapshot-build SnapshotTool "$IRIS_TOOL/output"
mkdir -p Iris/Resources/BlockingSnapshot
cp -R "$IRIS_TOOL/output/." Iris/Resources/BlockingSnapshot/
