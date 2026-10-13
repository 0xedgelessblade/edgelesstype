#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 || "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]]; then
  echo 'edgelesstype only supports M-series Macs with macOS 26 or later.' >&2
  exit 1
fi
for tool in swift cmake ffmpeg python3; do
  if ! command -v "$tool" >/dev/null; then
    echo "Missing $tool. Install Xcode Command Line Tools and run: brew install cmake ffmpeg python3" >&2
    exit 1
  fi
done
REV=a91dd3be72f70dd1b3cb6e252f35fa17b93f596c
SOURCE="$ROOT/ThirdParty/whisper-$REV"
mkdir -p ThirdParty Engine Models Config
if [[ ! -f "$SOURCE/CMakeLists.txt" ]]; then
  curl -fL --connect-timeout 20 --max-time 1800 --retry 3 --retry-max-time 3600 "https://github.com/ggml-org/whisper.cpp/archive/$REV.tar.gz" -o ThirdParty/whisper.tar.gz.part
  tar -xzf ThirdParty/whisper.tar.gz.part -C ThirdParty
  mv "ThirdParty/whisper.cpp-$REV" "$SOURCE"
  rm ThirdParty/whisper.tar.gz.part
fi
if [[ ! -f "$SOURCE/.edgelesstype-patched" ]]; then
  patch -d "$SOURCE" -p1 < Patches/whisper-server.patch
  touch "$SOURCE/.edgelesstype-patched"
fi
echo "Building the pinned local speech engine…"
cmake -S "$SOURCE" -B .build/speech -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8.2-a+fp16+dotprod \
  -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_SERVER=ON -DWHISPER_BUILD_TESTS=OFF \
  "-DCMAKE_C_FLAGS=-ffile-prefix-map=\"$ROOT=/src/edgelesstype\"" \
  "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=\"$ROOT=/src/edgelesstype\""
cmake --build .build/speech --target whisper-server -j 4
cp .build/speech/bin/whisper-server Engine/whisper-server
codesign --force --sign - Engine/whisper-server
fetch_model() {
  local name="$1" expected="$2" target="Models/$1"
  local base_url="${3:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main}"
  if [[ -f "$target" ]] && [[ "$(shasum -a 256 "$target" | cut -d' ' -f1)" == "$expected" ]]; then return; fi
  echo "Downloading speech model: $name"
  curl -fL --connect-timeout 20 --max-time 1800 --retry 3 --retry-max-time 3600 "$base_url/$name" -o "$target.part"
  if [[ "$(shasum -a 256 "$target.part" | cut -d' ' -f1)" != "$expected" ]]; then
    echo "Checksum mismatch: $name" >&2; exit 1
  fi
  mv "$target.part" "$target"
}
fetch_model ggml-small.bin 1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b
fetch_model ggml-large-v3-turbo.bin 1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69
fetch_model ggml-silero-v5.1.2.bin 29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf https://huggingface.co/ggml-org/whisper-vad/resolve/main
if [[ ! -f Config/app.json ]]; then
  python3 - <<'PY'
import json, shutil
from pathlib import Path
c=json.loads(Path('Config/app.example.json').read_text())
c['ffmpegPath']=shutil.which('ffmpeg')
Path('Config/app.json').write_text(json.dumps(c,ensure_ascii=False,indent=2)+'\n')
PY
fi
echo 'Ready. Run bash Scripts/pack-app.sh to build the app.'
