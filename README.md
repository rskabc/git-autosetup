# GitHub Auto Setup

Server-wide GitHub authentication for multiple private repositories.

## Purpose

Configure Git once at server level so repositories under `/opt` can use:

```text
git clone
git pull
git push
```

without storing a GitHub PAT inside each application.

## Architecture

```text
GitHub Fine-grained PAT
        |
        v
Git Credential Manager
        |
        v
GPG / pass
        |
        +---- /opt/arus
        +---- /opt/arus-portable
        +---- /opt/billing
        +---- /opt/Mikrotik-Backup
        +---- other repositories
```

Application credentials remain separate:

```text
/opt/Mikrotik-Backup/.env  -> MikroTik/Cisco credentials
/opt/arus/.env              -> application/database credentials
Git credential store        -> GitHub authentication
```

## Files

```text
/opt/github/git-autosetup/
├── setup-github.sh
├── README.md
└── .gitignore
```

Runtime configuration is outside this repository:

```text
/etc/git/github.conf
/root/.gitconfig
/root/.gnupg/
/root/.password-store/
```

If the setup is executed as another user, the Git/GPG/pass paths follow that user's home directory.

## Requirements

- Debian/Ubuntu server
- root/sudo
- internet access
- GitHub account
- Fine-grained Personal Access Token

The PAT should be limited to the repositories and permissions required by the server.

## Installation

Make the script executable:

```bash
chmod 700 /opt/github/git-autosetup/setup-github.sh
```

Run:

```bash
sudo /opt/github/git-autosetup/setup-github.sh
```

The script installs Git, GPG, pass, and Git Credential Manager when needed.

## Example output

```text
======================================================
       GitHub Server Authentication Setup
======================================================

[1/7] Installing required packages...
[OK] Packages installed.

[2/7] Installing/checking Git Credential Manager...
[OK] Git Credential Manager available.

[3/7] Configuring Git...
[OK] Git configured.

[4/7] Creating server configuration...
[OK] /etc/git/github.conf

[5/7] Configuring GPG/pass...
[OK] GPG/pass and Git Credential Manager configured.

[6/7] Saving GitHub PAT...
GitHub user: rskabc
Masukkan Fine-grained PAT. Input tidak akan ditampilkan.
GitHub PAT: ********
[OK] PAT stored through Git Credential Manager.

[7/7] Testing GitHub authentication...
[INFO] Test repository dilewati.

======================================================
          GitHub Setup BERHASIL
======================================================
```

## Test a private repository

Recommended:

```bash
sudo GITHUB_TEST_REPO="rskabc/Mikrotik-Backup" \
  /opt/github/git-autosetup/setup-github.sh
```

Successful output:

```text
[7/7] Testing GitHub authentication...
[OK] Authentication BERHASIL: rskabc/Mikrotik-Backup
```

## First clone

After setup:

```bash
cd /opt
git clone https://github.com/rskabc/Mikrotik-Backup.git
```

Then normal operations:

```bash
cd /opt/Mikrotik-Backup
git pull
git push
```

The PAT is not entered on every operation.

## Multiple repositories

The same server-level credential can be used by multiple repositories, provided the Fine-grained PAT has access to them.

Example:

```bash
cd /opt/arus
git pull

cd /opt/arus-portable
git pull

cd /opt/billing
git pull

cd /opt/Mikrotik-Backup
git pull
```

## Adding another repository

1. Add the repository to the PAT's Repository access.
2. Give only the required permissions.
3. Clone normally:

```bash
cd /opt
git clone https://github.com/rskabc/new-project.git
```

No second GitHub authentication setup is required.

## Git configuration checks

```bash
git config --global --list
```

Credential helper:

```bash
git config --global --get credential.helper
```

Expected:

```text
manager
```

Credential store:

```bash
git config --global --get credential.credentialStore
```

Expected:

```text
gpg
```

Remote URL:

```bash
git remote -v
```

Expected form:

```text
https://github.com/rskabc/repository.git
```

Never use:

```text
https://TOKEN@github.com/...
```

## Security model

The PAT is not stored in:

- this repository
- application `.env` files
- Docker Compose files
- Git remote URLs
- the setup script
- README
- shell commands

The credential is handled through Git Credential Manager with the GPG/pass credential store.

## Credential separation

Do not put GitHub authentication into application configuration.

Correct:

```text
GitHub authentication
  -> Git Credential Manager

Mikrotik-Backup/.env
  -> MikroTik/Cisco credentials

Arus/.env
  -> database/application credentials
```

## PAT rotation

When a PAT expires or is revoked:

```bash
sudo /opt/github/git-autosetup/setup-github.sh
```

Enter the new PAT.

Then test:

```bash
sudo GITHUB_TEST_REPO="rskabc/Mikrotik-Backup" \
  /opt/github/git-autosetup/setup-github.sh
```

## Recovery

If the server is rebuilt:

1. Install/copy this tool.
2. Create a new Fine-grained PAT or use a still-valid one.
3. Run setup.
4. Clone required repositories.

Example:

```bash
sudo /opt/github/git-autosetup/setup-github.sh

cd /opt
git clone https://github.com/rskabc/arus.git
git clone https://github.com/rskabc/arus-portable.git
git clone https://github.com/rskabc/billing.git
git clone https://github.com/rskabc/Mikrotik-Backup.git
```

## Important security note

If a PAT has ever been exposed in chat, source code, terminal history, screenshots, logs, or Git history, revoke it and create a replacement.

Do not commit:

```text
PAT
GPG private keys
.password-store
.gnupg
.git-credentials
```

## Operational flow

```text
Admin
  |
  | creates Fine-grained PAT
  v
setup-github.sh
  |
  +--> install/configure Git
  |
  +--> configure GPG/pass
  |
  +--> configure Git Credential Manager
  |
  +--> enter PAT once
  |
  v
encrypted credential store
  |
  +--> git clone
  +--> git pull
  +--> git push
  |
  v
GitHub
```

## Design principle

GitHub authentication is a **server-level concern**.

Application credentials are **application-level concerns**.

Keep them separate.
