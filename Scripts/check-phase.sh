#!/bin/zsh
set -eu
cd "${0:A:h:h}"
GENERATOR=${IRIS_XCODEGEN:-xcodegen}
PHASE=${1:-final}
SPEC=project.yml
if [[ -n "${IRIS_TEST_DEPLOYMENT:-}" ]]; then
    SPEC=.test-project.yml
    sed "s/visionOS: '27.0'/visionOS: '$IRIS_TEST_DEPLOYMENT'/" project.yml > "$SPEC"
fi
trap 'if [[ "$SPEC" != project.yml ]]; then rm -f "$SPEC"; "$GENERATOR" generate --spec project.yml >/dev/null; fi' EXIT
"$GENERATOR" generate --spec "$SPEC"
xcodebuild -project Iris.xcodeproj -scheme Iris -destination 'platform=visionOS Simulator,name=Apple Vision Pro' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build > "/tmp/iris-$PHASE-build.log" 2>&1
xcodebuild -project Iris.xcodeproj -scheme Iris -destination 'platform=visionOS Simulator,name=Apple Vision Pro' -derivedDataPath build -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test > "/tmp/iris-$PHASE-test.log" 2>&1
tail -5 "/tmp/iris-$PHASE-build.log"
tail -10 "/tmp/iris-$PHASE-test.log"
