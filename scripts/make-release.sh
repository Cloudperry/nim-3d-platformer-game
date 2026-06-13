#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

release_date="$(date +%Y-%m-%d)"
release_root="releases"
release_dir="$release_root/$release_date"
archive_path="$release_dir.tar.xz"

game_bin="bin/platformer-game"
tester_bin="bin/platformer-game-tester"

nimble build -d:release -d:glfwStaticLib

if [[ ! -x "$game_bin" ]]; then
  echo "Expected game binary not found: $game_bin" >&2
  exit 1
fi

if [[ ! -x "$tester_bin" ]]; then
  echo "Expected tester binary not found: $tester_bin" >&2
  exit 1
fi

rm -rf "$release_dir" "$archive_path"
mkdir -p "$release_dir"

mv "$game_bin" "$tester_bin" "$release_dir/"
cp -a testData "$release_dir/"

nim r src/Game.nim --compileShadersAndQuit

mkdir -p "$release_dir/shaders"
find shaders -maxdepth 1 -type f -name "*.glsl" -print0 |
  while IFS= read -r -d "" shader; do
    cp "$shader" "$release_dir/shaders/"
  done

if ! find "$release_dir/shaders" -maxdepth 1 -type f -name "*.glsl" | grep -q .; then
  echo "No GLSL shader files were copied into $release_dir/shaders" >&2
  exit 1
fi

tar -cJf "$archive_path" -C "$release_dir" .

echo "Created release archive: $archive_path"
