#!/usr/bin/env bash
# Deploy DiSTA Academic Website to Insubria SSH Server
# Remote: jesus.cevallos@193.206.183.130:1902
# Public URL: http://www.dista.uninsubria.it/~jesus.cevallos

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REMOTE_HOST="193.206.183.130"
REMOTE_PORT="1902"
REMOTE_USER="jesus.cevallos"
REMOTE_DEST="${REMOTE_USER}@${REMOTE_HOST}:~/public_html/"
SSH_ARGS=(-p "$REMOTE_PORT" -o BatchMode=yes -o ConnectTimeout=5)
RSYNC_SSH="ssh -p ${REMOTE_PORT} -o BatchMode=yes -o ConnectTimeout=5"

RSYNC_ARGS=(-avz -e "$RSYNC_SSH" --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r)
DRY_RUN=false
CHECK_ONLY=false
case "${1:-}" in
    --dry-run|-n) DRY_RUN=true; RSYNC_ARGS+=(--dry-run) ;;
    --check) CHECK_ONLY=true ;;
    '') ;;
    *) echo 'Usage: scripts/deploy_dista.sh [--dry-run|--check]' >&2; exit 1 ;;
esac
if "$DRY_RUN"; then
    echo "[INFO] Running in dry-run mode. No remote files will be modified."
fi

echo "==========================================================="
echo " Deploying Academic Website to DiSTA (Insubria)"
echo " Server: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}"
echo " Destination: ~/public_html/"
echo " Public URL: http://www.dista.uninsubria.it/~jesus.cevallos"
echo "==========================================================="

# 1. Test SSH connectivity
echo "[1/4] Testing SSH connectivity..."
if ! ssh "${SSH_ARGS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "test -d ~/public_html"; then
    echo "[ERROR] Could not connect to ${REMOTE_HOST}:${REMOTE_PORT} or ~/public_html does not exist."
    echo "Please verify SSH keys and network connectivity."
    exit 1
fi
echo "      Connection successful."
if "$CHECK_ONLY"; then
    exit 0
fi

# 2. Deploy dista_academic_site.html -> ~/public_html/index.html
echo "[2/4] Syncing dista_academic_site.html -> index.html..."
rsync "${RSYNC_ARGS[@]}" \
    "${REPO_ROOT}/dista_academic_site.html" \
    "${REMOTE_USER}@${REMOTE_HOST}:~/public_html/index.html"

# 3. Deploy CV and assets
echo "[3/4] Syncing thesis form, CV and public directory..."
rsync "${RSYNC_ARGS[@]}" \
    "${REPO_ROOT}/tesi.html" \
    "${REMOTE_DEST}"
if [[ -f "${REPO_ROOT}/Jesus_Cevallos_CV.pdf" ]]; then
    rsync "${RSYNC_ARGS[@]}" \
        "${REPO_ROOT}/Jesus_Cevallos_CV.pdf" \
        "${REMOTE_DEST}"
fi

if [[ -f "${REPO_ROOT}/profile.jpeg" ]]; then
    rsync "${RSYNC_ARGS[@]}" \
        "${REPO_ROOT}/profile.jpeg" \
        "${REMOTE_DEST}"
fi

if [[ -d "${REPO_ROOT}/public" ]]; then
    rsync "${RSYNC_ARGS[@]}" \
        --exclude='.env' --exclude='.env.*' --exclude='*.env' --exclude='*.env.*' \
        "${REPO_ROOT}/public/" \
        "${REMOTE_DEST}public/"
fi

# 4. Ensure correct remote permissions (read + execute for web server)
if ! "$DRY_RUN"; then
    echo "[4/4] Verifying remote permissions..."
    ssh "${SSH_ARGS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" \
        'find ~/public_html -maxdepth 1 -type f \( -name index.html -o -name tesi.html -o -name Jesus_Cevallos_CV.pdf -o -name profile.jpeg \) -exec chmod u=rw,go=r {} +; if test -d ~/public_html/public; then chmod -R u=rwX,go=rX ~/public_html/public; fi'
fi

echo "==========================================================="
echo " Deployment completed successfully!"
echo " Visit: http://www.dista.uninsubria.it/~jesus.cevallos"
echo "==========================================================="
