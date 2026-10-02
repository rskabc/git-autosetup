#!/usr/bin/env bash
set -euo pipefail

# GitHub Auto Setup - server-wide HTTPS authentication
GITHUB_USER="${GITHUB_USER:-rskabc}"
GITHUB_EMAIL="${GITHUB_EMAIL:-backup@users.noreply.github.com}"
GITHUB_HOST="github.com"

CONFIG_DIR="/etc/git"
CONFIG_FILE="${CONFIG_DIR}/github.conf"
TMP_DIR="/tmp/git-autosetup"
GCM_DEB="${TMP_DIR}/gcm.deb"

echo
echo "======================================================"
echo "       GitHub Server Authentication Setup"
echo "======================================================"
echo

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Jalankan sebagai root."
  exit 1
fi

# This script is designed to run as root.
# If invoked through sudo, preserve the original user's home.
REAL_USER="${SUDO_USER:-root}"
if [[ "${REAL_USER}" == "root" ]]; then
  REAL_HOME="/root"
else
  REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
fi

[[ -n "${REAL_HOME}" && -d "${REAL_HOME}" ]] || {
  echo "ERROR: Home directory user ${REAL_USER} tidak ditemukan."
  exit 1
}

# Run a command as REAL_USER without requiring sudo.
run_as_user() {
  if [[ "${REAL_USER}" == "root" ]]; then
    env "$@"
  else
    su -s /bin/bash -c 'exec "$@"' -- "$@"
  fi
}

export DEBIAN_FRONTEND=noninteractive

echo "[1/5] Installing required packages..."

if [[ ! -r /etc/os-release ]]; then
  echo "ERROR: /etc/os-release tidak ditemukan."
  exit 1
fi

. /etc/os-release

if [[ "${ID}" != "debian" ]]; then
  echo "ERROR: Script ini ditujukan untuk Debian. Detected: ${ID:-unknown}"
  exit 1
fi

echo "[INFO] Debian: ${VERSION_ID:-unknown}"
echo "[INFO] Architecture: $(dpkg --print-architecture)"

apt-get update
apt-get install -y git ca-certificates

echo "[OK] Required packages installed."
echo

echo "[2/5] Configuring Git..."
run_as_user git config --global user.name "${GITHUB_USER}"
run_as_user git config --global user.email "${GITHUB_EMAIL}"
run_as_user git config --global init.defaultBranch main
echo "[OK] Git configured."
echo

echo "[3/5] Creating server configuration..."
mkdir -p "${CONFIG_DIR}"
cat > "${CONFIG_FILE}" <<EOF
# GitHub server configuration
# PAT is NOT stored here.
GITHUB_USER="${GITHUB_USER}"
GITHUB_EMAIL="${GITHUB_EMAIL}"
GITHUB_HOST="${GITHUB_HOST}"
EOF
chmod 644 "${CONFIG_FILE}"
echo "[OK] ${CONFIG_FILE}"
echo

echo "[4/5] Configuring Git credential storage..."

CREDENTIAL_FILE="${REAL_HOME}/.git-credentials"

# Simple server setup: store HTTPS credentials in a private file.
# No GPG, pass, pinentry, or gpg-agent is required.
touch "${CREDENTIAL_FILE}"
chown "${REAL_USER}:${REAL_USER}" "${CREDENTIAL_FILE}"
chmod 600 "${CREDENTIAL_FILE}"

run_as_user git config --global --unset-all credential.helper >/dev/null 2>&1 || true
run_as_user git config --global credential.helper store

echo "[OK] Git credential storage configured."
echo

echo "[5/5] Saving GitHub PAT..."
echo "GitHub user: ${GITHUB_USER}"
echo "Masukkan Fine-grained PAT. Input tidak akan ditampilkan."
read -rsp "GitHub PAT: " GITHUB_TOKEN
echo
[[ -n "${GITHUB_TOKEN}" ]] || {
  echo "ERROR: PAT kosong."
  exit 1
}

printf 'protocol=https\nhost=%s\nusername=%s\npassword=%s\n\n' \
  "${GITHUB_HOST}" "${GITHUB_USER}" "${GITHUB_TOKEN}" |
  run_as_user env HOME="${REAL_HOME}" git credential approve

unset GITHUB_TOKEN
chmod 600 "${CREDENTIAL_FILE}"
echo "[OK] PAT stored in ${CREDENTIAL_FILE} (permission 600)."
echo

echo "[6/5] Testing GitHub authentication..."
TEST_REPO="${GITHUB_TEST_REPO:-}"
if [[ -n "${TEST_REPO}" ]]; then
  if run_as_user env \
      GNUPGHOME="${GNUPGHOME}" \
      PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR}" \
      git ls-remote "https://github.com/${TEST_REPO}.git" HEAD >/dev/null 2>&1; then
    echo "[OK] Authentication BERHASIL: ${TEST_REPO}"
  else
    echo "[ERROR] Tidak dapat mengakses ${TEST_REPO}"
    echo "Periksa PAT, Repository access, dan Contents permission."
    exit 1
  fi
else
  echo "[INFO] Test repository dilewati."
  echo "Gunakan GITHUB_TEST_REPO=owner/repo untuk mengujinya."
fi

echo
echo "======================================================"
echo "          GitHub Setup BERHASIL"
echo "======================================================"
echo "GitHub User : ${GITHUB_USER}"
echo "Git Config  : ${REAL_HOME}/.gitconfig"
echo "Server Conf : ${CONFIG_FILE}"
echo "Credential  : GPG/pass via Git Credential Manager"
echo
echo "Contoh:"
echo "  git clone https://github.com/${GITHUB_USER}/NAMA-REPO.git"
echo "  git pull"
echo "  git push"
echo "======================================================"
