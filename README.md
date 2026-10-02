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
        +---- /opt/arus-project
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
/opt/git-autosetup/
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

If the setup is executed as another user, Git/GPG/pass use that user's home directory.

## Requirements

- Debian/Ubuntu server
- root/sudo
- internet access
- GitHub account
- Fine-grained Personal Access Token

The PAT should be limited to the repositories and permissions required by the server.

## Installation

### 1. Clone the setup repository

```bash
cd /opt
git clone https://github.com/rskabc/git-autosetup.git
```

### 2. Run the setup

```bash
cd /opt/git-autosetup
chmod 700 setup-github.sh
sudo ./setup-github.sh
```

The script installs Git, GPG, pass, and the official Git Credential Manager Debian package when needed.

The current GCM documentation recommends the official Linux package/tarball installation path; the script downloads the latest stable Debian package from the official GCM GitHub release API and installs it with `dpkg`. citeturn0search0turn1search0

### 3. Enter the PAT

When prompted:

```text
GitHub user: rskabc
Masukkan Fine-grained PAT. Input tidak akan ditampilkan.
GitHub PAT:
```

Paste the PAT and press Enter.

The PAT is not written into this repository, `.env`, Git remote URLs, or the setup script.

### 4. Test

For example:

```bash
sudo GITHUB_TEST_REPO="rskabc/Mikrotik-Backup" \
  /opt/git-autosetup/setup-github.sh
```

Successful output:

```text
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

cd /opt/arus-project
git pull

cd /opt/Mikrotik-Backup
git pull
```

## Adding another repository

If the Fine-grained PAT is restricted to selected repositories:

1. Add the new repository to the PAT's Repository access.
2. Give only the required permissions.
3. Clone normally.

```bash
cd /opt
git clone https://github.com/rskabc/new-project.git
```

No second Git authentication setup is required.

## Git configuration checks

```bash
git config --global --get credential.helper
```

Expected:

```text
manager
```

Check credential store:

```bash
git config --global --get credential.credentialStore
```

Expected:

```text
gpg
```

Check remote:

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

The credential is handled through Git Credential Manager with the GPG/pass credential store. GCM documents GPG/pass as a supported Linux credential store. citeturn0search11

## Credential separation

Do not put GitHub authentication into application configuration.

Correct:

```text
GitHub authentication
  -> Git Credential Manager
  -> GPG/pass

Mikrotik-Backup/.env
  -> MikroTik/Cisco credentials

Arus/.env
  -> database/application credentials
```

## PAT rotation

When a PAT expires or is revoked:

```bash
sudo /opt/git-autosetup/setup-github.sh
```

Enter the new PAT.

Then test:

```bash
sudo GITHUB_TEST_REPO="rskabc/Mikrotik-Backup" \
  /opt/git-autosetup/setup-github.sh
```

## Recovery after server rebuild

1. Install/copy this tool.
2. Create a new Fine-grained PAT or use a still-valid one.
3. Run setup.
4. Clone required repositories.

Example:

```bash
cd /opt
git clone https://github.com/rskabc/git-autosetup.git

cd /opt/git-autosetup
chmod 700 setup-github.sh
sudo ./setup-github.sh
```

Then clone the required repositories.

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
  +--> install/configure Git Credential Manager
  |
  +--> configure GPG/pass
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
