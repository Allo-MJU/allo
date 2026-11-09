#!/usr/bin/env bash
# Unity 탐험 화면을 Android 라이브러리로 내보내 phone/unity/unityLibrary 에 둔다.
# 쓰는 법: scripts/export_unity.sh   (UNITY 환경변수로 에디터 경로를 바꿀 수 있다)
set -euo pipefail
cd "$(dirname "$0")/.."
UNITY="${UNITY:-/Applications/Unity/Hub/Editor/6000.0.85f2/Unity.app/Contents/MacOS/Unity}"
PROJECT="$PWD/unity/allo_explore"
LOG="${TMPDIR:-/tmp}/allo_unity_export.log"

run() { "$UNITY" -batchmode -quit -projectPath "$PROJECT" -executeMethod "$1" -logFile "$LOG" || { tail -40 "$LOG"; exit 1; }; }

[ -f "$PROJECT/Assets/Scenes/Explore.unity" ] || run AlloBuild.CreateSpikeScene
run AlloBuild.ExportAndroid

# unityLibrary 는 ../shared/*.gradle 과 루트 gradle.properties 의 unity.* 값을 쓴다
rm -rf phone/unity/unityLibrary phone/unity/shared
mv phone/unity/export/unityLibrary phone/unity/unityLibrary
mv phone/unity/export/shared phone/unity/shared
grep -E '^(unity\.|unityStreamingAssets)' phone/unity/export/gradle.properties > phone/unity/unity.properties
rm -rf phone/unity/export
test -f phone/unity/unityLibrary/build.gradle && echo "OK: phone/unity/unityLibrary"
