#!/usr/bin/env bash
# Single entry point for GitHub Pages and DiSTA publication.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

COMMIT_MESSAGE="Publish website updates"
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--message)
            [[ $# -ge 2 && -n "$2" ]] || { echo 'Specify a commit message.' >&2; exit 1; }
            COMMIT_MESSAGE="$2"
            shift 2
            ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -h|--help)
            echo 'Usage: scripts/publish_site.sh [--dry-run] [-m "Commit message"]'
            echo 'Commits all non-ignored changes on main, pushes, deploys DiSTA and waits for GitHub Pages.'
            exit 0
            ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
done

[[ "$(git branch --show-current)" == main ]] || {
    echo 'Run publication from the main branch.' >&2
    exit 1
}
# Respect the repository rule: dotenv credentials must never be published.
if [[ -n "$(git ls-files --cached --others --exclude-standard -- \
    '*.env' '*.env.*' '.env' '.env.*' ':!*.env.example' ':!.env.example')" ]]; then
    echo 'Publication stopped: a credentials file is tracked or is not ignored.' >&2
    exit 1
fi
git diff --check
git diff --cached --check

if "$DRY_RUN"; then
    git status --short
    echo 'Dry run: commit non-ignored changes, push main, deploy DiSTA (including tesi.html), verify GitHub Pages.'
    exit 0
fi

for dependency in gh ssh rsync tar; do
    command -v "$dependency" >/dev/null || {
        printf 'Required command missing: %s\n' "$dependency" >&2
        exit 1
    }
done

PHASE='preflight checks'
SNAPSHOT_DIR=''
trap '[[ -z "$SNAPSHOT_DIR" ]] || rm -rf "$SNAPSHOT_DIR"' EXIT
trap 'printf "Publication stopped during: %s. Fix the error and rerun the script.\n" "$PHASE" >&2' ERR

gh auth status >/dev/null 2>&1
bash "$SCRIPT_DIR/deploy_dista.sh" --check
git fetch origin main
git merge-base --is-ancestor origin/main HEAD || {
    echo 'Remote main contains changes missing locally. Synchronize main before publishing.' >&2
    exit 1
}

PHASE='commit'
git add --all
if ! git diff --cached --quiet; then
    git -c core.hooksPath=/dev/null commit -m "$COMMIT_MESSAGE"
else
    echo 'No new changes to commit; publishing the current commit.'
fi
PUBLISH_SHA="$(git rev-parse HEAD)"
# Deploy only committed files, keeping ignored local files out of both sites.
SNAPSHOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/publish-site.XXXXXX")"
git archive "$PUBLISH_SHA" | tar -x -C "$SNAPSHOT_DIR"

PHASE='push to GitHub'
git -c core.hooksPath=/dev/null push origin main

PHASE='DiSTA deployment'
bash "$SNAPSHOT_DIR/scripts/deploy_dista.sh"

PHASE='GitHub Pages deployment'
RUN_ID=''
for attempt in {1..12}; do
    RUN_ID="$(gh run list --workflow deploy-pages.yml --branch main --limit 20 \
        --json databaseId,headSha --jq ".[] | select(.headSha == \"$PUBLISH_SHA\") | .databaseId" | head -n 1)"
    [[ -z "$RUN_ID" ]] || break
    sleep 5
done
[[ -n "$RUN_ID" ]] || {
    echo 'Push and DiSTA deployment completed, but the GitHub Pages workflow was not found.' >&2
    exit 1
}
RUN_CONCLUSION="$(gh run view "$RUN_ID" --json conclusion --jq .conclusion)"
if [[ -n "$RUN_CONCLUSION" && "$RUN_CONCLUSION" != success ]]; then
    gh run rerun "$RUN_ID"
    # A rerun is scheduled asynchronously; wait until the old conclusion clears.
    for attempt in {1..12}; do
        RUN_CONCLUSION="$(gh run view "$RUN_ID" --json conclusion --jq .conclusion)"
        [[ -n "$RUN_CONCLUSION" ]] || break
        sleep 5
    done
fi
gh run watch "$RUN_ID" --exit-status --interval 5

printf '\nPublished commit %s to both sites:\n' "${PUBLISH_SHA:0:7}"
echo 'GitHub Pages: https://qwertyjacob.github.io/'
echo 'DiSTA: https://www.dista.uninsubria.it/~jesus.cevallos/'
