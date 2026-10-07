#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/thesis-guide.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

cd "$REPO_ROOT/theses"
TEXINPUTS="$REPO_ROOT/public/thesis-guide:${TEXINPUTS:-}" \
    latexmk -pdf -interaction=nonstopmode -halt-on-error \
    -outdir="$BUILD_DIR" autum26.tex

cp "$BUILD_DIR/autum26.pdf" "$REPO_ROOT/public/thesis-guide/autum26.pdf"
echo "Built public/thesis-guide/autum26.pdf"
