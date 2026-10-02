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

echo "[1/7] Installing required packages..."

# Detect Debian version and architecture so the script works on a fresh
# Debian server without manually installing dependencies.
if [[ ! -r /etc/os-release ]]; then
  echo "ERROR: /etc/os-release tidak ditemukan."
  exit 1
fi

. /etc/os-release

if [[ "${ID}" != "debian" ]]; then
  echo "ERROR: Script ini ditujukan untuk Debian. Detected: ${ID:-unknown}"
  exit 1
fi

ARCH="$(dpkg --print-architecture)"
case "${ARCH}" in
  amd64|arm64)
    ;;
  *)
    echo "ERROR: Architecture ${ARCH} belum didukung."
    exit 1
    ;;
esac

echo "[INFO] Debian: ${VERSION_ID:-unknown}"
echo "[INFO] Architecture: ${ARCH}"

apt-get update

PACKAGES=(
  git
  ca-certificates
  curl
  gnupg
  pass
  pinentry-curses
)

# GCM is a .NET application and requires ICU globalization support.
# Select the ICU runtime available in the configured Debian repository.
ICU_PACKAGE=""
for candidate in libicu76 libicu72 libicu67 libicu66 libicu63; do
  if apt-cache show "${candidate}" >/dev/null 2>&1; then
    ICU_PACKAGE="${candidate}"
    break
  fi
done

if [[ -z "${ICU_PACKAGE}" ]]; then
  echo "ERROR: Paket ICU (libicu) tidak ditemukan di repository Debian."
  echo "Periksa repository APT lalu jalankan kembali script."
  exit 1
fi

PACKAGES+=("${ICU_PACKAGE}")
echo "[INFO] ICU runtime: ${ICU_PACKAGE}"

apt-get install -y "${PACKAGES[@]}"

# Refresh dynamic linker cache before starting the .NET-based GCM.
ldconfig

echo "[OK] All required packages installed."
echoecho "[2/7] Installing/checking Git Credential Manager..."
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

GCM_VERSION="$(run_as_user git-credential-manager --version 2>&1)" || {
  echo "ERROR: Git Credential Manager terpasang tetapi gagal dijalankan."
  echo "${GCM_VERSION}"
  echo "Pastikan dependency ICU/.NET runtime tersedia."
  exit 1
}

echo "[OK] Git Credential Manager ${GCM_VERSION}"
run_as_user git-credential-manager configure
echo "[OK] Git Credential Manager configured."
echo

echo "[3/7] Configuring Git..."
run_as_user git config --global user.name "${GITHUB_USER}"
run_as_user git config --global user.email "${GITHUB_EMAIL}"
run_as_user git config --global init.defaultBranch main
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

# Headless GPG configuration: disable terminal pinentry requirements and
# force loopback mode so key creation never waits for interactive input.
GPG_AGENT_CONF="${GNUPGHOME}/gpg-agent.conf"
cat > "${GPG_AGENT_CONF}" <<'EOF'
allow-loopback-pinentry
default-cache-ttl 3600
max-cache-ttl 7200
EOF
chown "${REAL_USER}:${REAL_USER}" "${GPG_AGENT_CONF}"
chmod 600 "${GPG_AGENT_CONF}"

run_as_user env GNUPGHOME="${GNUPGHOME}" gpgconf --kill gpg-agent >/dev/null 2>&1 || true
run_as_user env GNUPGHOME="${GNUPGHOME}" gpgconf --launch gpg-agent

GPG_KEY_ID="$(run_as_user env GNUPGHOME="${GNUPGHOME}" \
  gpg --batch --with-colons --list-secret-keys "${GITHUB_EMAIL}" 2>/dev/null \
  | awk -F: '$1=="sec" {print $5; exit}')"

if [[ -z "${GPG_KEY_ID}" ]]; then
  echo "[INFO] Creating non-interactive GPG key..."

  run_as_user env GNUPGHOME="${GNUPGHOME}" \
    gpg --batch --yes --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "${GITHUB_USER} GitHub Server <${GITHUB_EMAIL}>" \
    rsa3072 encrypt 0

  GPG_KEY_ID="$(run_as_user env GNUPGHOME="${GNUPGHOME}" \
    gpg --batch --with-colons --list-secret-keys "${GITHUB_EMAIL}" \
    | awk -F: '$1=="sec" {print $5; exit}')"
fi

[[ -n "${GPG_KEY_ID}" ]] || {
  echo "ERROR: GPG key gagal dibuat."
  exit 1
}

echo "[INFO] GPG key: ${GPG_KEY_ID}"

if [[ ! -f "${PASSWORD_STORE_DIR}/.gpg-id" ]]; then
  echo "[INFO] Initializing password-store..."
  run_as_user env GNUPGHOME="${GNUPGHOME}" PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR}" \
    pass init "${GPG_KEY_ID}" >/dev/null
fi

[[ -f "${PASSWORD_STORE_DIR}/.gpg-id" ]] || {
  echo "ERROR: password-store gagal diinisialisasi."
  exit 1
}

run_as_user git config --global credential.helper manager
run_as_user git config --global credential.credentialStore gpg

echo "[OK] GPG/pass and Git Credential Manager configured."
echoecho "[6/7] Saving GitHub PAT..."
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
  run_as_user env \
    GNUPGHOME="${GNUPGHOME}" \
    PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR}" \
    git credential approve

unset GITHUB_TOKEN
echo "[OK] PAT stored through Git Credential Manager."
echo

echo "[7/7] Testing GitHub authentication..."
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
