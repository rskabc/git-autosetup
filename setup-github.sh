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
  echo "ERROR: Jalankan sebagai root: sudo $0"
  exit 1
fi

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

export DEBIAN_FRONTEND=noninteractive

echo "[1/7] Installing required packages..."
apt-get update
apt-get install -y git ca-certificates curl gnupg pass pinentry-curses
echo "[OK] Packages installed."
echo

echo "[2/7] Installing/checking Git Credential Manager..."
if ! command -v git-credential-manager >/dev/null 2>&1; then
  mkdir -p "${TMP_DIR}"
  rm -f "${GCM_DEB}"

  ARCH="$(dpkg --print-architecture)"
  case "${ARCH}" in
    amd64) GCM_PATTERN="gcm-linux-x64-.*\\.deb" ;;
    arm64) GCM_PATTERN="gcm-linux-arm64-.*\\.deb" ;;
    *)
      echo "ERROR: Architecture ${ARCH} belum didukung oleh script ini."
      exit 1
      ;;
  esac

  echo "[INFO] Downloading official GCM Debian package for ${ARCH}..."
  GCM_URL="$(curl -fsSL https://api.github.com/repos/git-ecosystem/git-credential-manager/releases/latest \
    | grep -oE 'https://[^"]+' \
    | grep -E "${GCM_PATTERN}" \
    | head -n 1)"

  [[ -n "${GCM_URL}" ]] || {
    echo "ERROR: Tidak menemukan paket GCM resmi untuk ${ARCH}."
    exit 1
  }

  echo "[INFO] ${GCM_URL}"
  curl -fL "${GCM_URL}" -o "${GCM_DEB}"
  dpkg -i "${GCM_DEB}" || {
    echo "[INFO] Fixing package dependencies..."
    apt-get install -f -y
  }

  rm -rf "${TMP_DIR}"
fi

command -v git-credential-manager >/dev/null 2>&1 || {
  echo "ERROR: Git Credential Manager tidak tersedia setelah instalasi."
  exit 1
}

sudo -u "${REAL_USER}" git-credential-manager --version
sudo -u "${REAL_USER}" git-credential-manager configure
echo "[OK] Git Credential Manager configured."
echo

echo "[3/7] Configuring Git..."
sudo -u "${REAL_USER}" git config --global user.name "${GITHUB_USER}"
sudo -u "${REAL_USER}" git config --global user.email "${GITHUB_EMAIL}"
sudo -u "${REAL_USER}" git config --global init.defaultBranch main
echo "[OK] Git configured."
echo

echo "[4/7] Creating server configuration..."
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

echo "[5/7] Configuring GPG/pass..."
export GNUPGHOME="${REAL_HOME}/.gnupg"
PASSWORD_STORE_DIR="${REAL_HOME}/.password-store"

mkdir -p "${GNUPGHOME}" "${PASSWORD_STORE_DIR}"
chown -R "${REAL_USER}:${REAL_USER}" "${GNUPGHOME}" "${PASSWORD_STORE_DIR}"
chmod 700 "${GNUPGHOME}" "${PASSWORD_STORE_DIR}"

GPG_KEY_ID="$(sudo -u "${REAL_USER}" env GNUPGHOME="${GNUPGHOME}" \
  gpg --list-secret-keys --with-colons "${GITHUB_EMAIL}" 2>/dev/null \
  | awk -F: '$1=="sec" {print $5; exit}')"

if [[ -z "${GPG_KEY_ID}" ]]; then
  sudo -u "${REAL_USER}" env GNUPGHOME="${GNUPGHOME}" \
    gpg --batch --passphrase '' \
    --quick-generate-key "${GITHUB_USER} GitHub Server <${GITHUB_EMAIL}>" rsa3072 encrypt 0

  GPG_KEY_ID="$(sudo -u "${REAL_USER}" env GNUPGHOME="${GNUPGHOME}" \
    gpg --list-secret-keys --with-colons "${GITHUB_EMAIL}" \
    | awk -F: '$1=="sec" {print $5; exit}')"
fi

[[ -n "${GPG_KEY_ID}" ]] || {
  echo "ERROR: GPG key gagal dibuat."
  exit 1
}

if [[ ! -f "${PASSWORD_STORE_DIR}/.gpg-id" ]]; then
  sudo -u "${REAL_USER}" env PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR}" \
    pass init "${GPG_KEY_ID}"
fi

sudo -u "${REAL_USER}" git config --global credential.helper manager
sudo -u "${REAL_USER}" git config --global credential.credentialStore gpg

echo "[OK] GPG/pass and Git Credential Manager configured."
echo

echo "[6/7] Saving GitHub PAT..."
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
  sudo -u "${REAL_USER}" env \
    GNUPGHOME="${GNUPGHOME}" \
    PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR}" \
    git credential approve

unset GITHUB_TOKEN
echo "[OK] PAT stored through Git Credential Manager."
echo

echo "[7/7] Testing GitHub authentication..."
TEST_REPO="${GITHUB_TEST_REPO:-}"
if [[ -n "${TEST_REPO}" ]]; then
  if sudo -u "${REAL_USER}" env \
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
