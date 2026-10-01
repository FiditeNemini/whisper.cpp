#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Tag an upstream whisper.cpp release with its vendored ggml/ replaced by the
# ggml of an Unsloth llama.cpp mix tag, so whisper.cpp and llama.cpp build from
# the same ggml source.
#
# This is the source-build equivalent of Unsloth's slim whisper prebuilds
# (unsloth-prebuilt-slim.yml), which build upstream vX.Y.Z after swapping in
# the paired llama.cpp release's ggml/. Here the swap is committed and tagged:
#   <whisper tag>-ggml-<llama tag>     e.g. v1.9.4-ggml-b11160-mix-a6922cc
#
# Usage:
#   scripts/unsloth/make_ggml_tag.sh <whisper tag> <llama tag>
#
# Needs remotes: `upstream` = ggml-org/whisper.cpp, `llama` = the llama.cpp fork
# that carries <llama tag> (scripts/unsloth/make_mix_tag.sh there makes it).
# Run from a clean work tree; returns to the current branch when done.
# Push the tag yourself: git push origin <tag>

set -euo pipefail

die() { echo "make_ggml_tag: $*" >&2; exit 1; }

[ $# -eq 2 ] || die "usage: make_ggml_tag.sh <whisper tag> <llama tag>"
WHISPER_TAG="$1"
LLAMA_TAG="$2"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "work tree has uncommitted changes"
git remote get-url upstream >/dev/null 2>&1 || die "missing remote 'upstream' (ggml-org/whisper.cpp)"
git remote get-url llama >/dev/null 2>&1 || die "missing remote 'llama' (llama.cpp fork)"

TAG="${WHISPER_TAG}-ggml-${LLAMA_TAG}"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "$TAG already exists at $(git rev-parse "$TAG^{commit}")"
    exit 0
fi

ORIG_REF="$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)"
trap 'git checkout -q "$ORIG_REF" 2>/dev/null || true' EXIT

git fetch -q --no-tags upstream "refs/tags/${WHISPER_TAG}:refs/tags/${WHISPER_TAG}"
# Kept out of refs/tags so llama.cpp's tags never mix with whisper.cpp's.
git fetch -q --no-tags llama "refs/tags/${LLAMA_TAG}:refs/llama/${LLAMA_TAG}"
LLAMA_COMMIT="$(git rev-parse "refs/llama/${LLAMA_TAG}^{commit}")"
git rev-parse -q --verify "${LLAMA_COMMIT}:ggml" >/dev/null || die "${LLAMA_TAG} has no ggml/ tree"

git checkout -q --detach "refs/tags/${WHISPER_TAG}"
git rm -r -q ggml
git read-tree --prefix=ggml/ -u "${LLAMA_COMMIT}:ggml"
GGML_VERSION="$(sed -nE 's/^set\(GGML_VERSION_(MAJOR|MINOR|PATCH) ([0-9]+)\)$/\2/p' ggml/CMakeLists.txt | paste -sd. -)"
git commit -q -m "Use ggml from llama.cpp ${LLAMA_TAG}

Vendored ggml/ replaced with ${LLAMA_COMMIT}:ggml (ggml ${GGML_VERSION:-unknown}),
as Unsloth's slim prebuilds do, so whisper.cpp and llama.cpp share one ggml source."

git tag -a "$TAG" -m "whisper.cpp ${WHISPER_TAG} with ggml from llama.cpp ${LLAMA_TAG} (${LLAMA_COMMIT})"

echo "tagged $TAG at $(git rev-parse "$TAG^{commit}") (ggml ${GGML_VERSION:-unknown})"
echo "push with: git push origin $TAG"
