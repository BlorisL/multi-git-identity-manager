# multi-git-identity-manager

A bash script to easily manage multiple Git identities with SSH keys and GPG signing on the same machine. Perfect for developers who need to maintain separate identities (work, personal, client-specific) across different Git hosting services like GitHub, GitLab, Bitbucket, etc.

## About

This script automates the setup of SSH keys and GPG signing for Git hosting services with support for multiple accounts and identities.

## Prerequisites

- A Unix-like operating system (Linux, macOS, WSL)
- `git` installed
- `gpg` installed
- SSH client installed

## Directory Structure

Create a backup directory with the following structure:
```
<backup-dir>/
└── <host-domain>-<ssh-alias>/
    ├── ssh/
    │   ├── <host-domain>-<ssh-alias>-sign
    │   └── <host-domain>-<ssh-alias>-sign.pub
    └── gpg/
        └── <host-domain>-<ssh-alias>-private-key.gpg
```
Where:
- `<host-domain>` is derived from `--git-host` by removing the last part and replacing dots with dashes, all lowercase (e.g. `foo.bar.com` → `foo-bar`)
- `<ssh-alias>` is the value you provide to `--ssh-alias`
- The final Git alias will be `<host-domain>-<ssh-alias>` (e.g. if `--git-host=gitlab.com` and `--ssh-alias=work`, then `gitlab-work`)

## Usage

```bash
# Create mode (default)
./setup.sh [--mode create] [--backup-dir <dir>] --ssh-alias <ssh-alias> [--git-host <git-host>] \
           --git-name "<git-name>" --git-email "<git-email>" [--scope <scope>] [--cache-passphrase]

# Remove mode
./setup.sh --mode remove --ssh-alias <ssh-alias> [--git-host <git-host>] --git-email "<git-email>"
```

### Parameters

* `--mode`: Operation mode: 'create' or 'remove' (default: create)
* `--backup-dir`: Path to your backup directory containing SSH and GPG keys (default: "backup")
* `--ssh-alias`: Alias for the SSH config (used in SSH config and as Git remote host)
* `--git-host`: Git hosting service domain (default: github.com)
* `--git-name`: Your full name for Git commits
* `--git-email`: Your email address for Git commits
* `--scope`: Either 'global' or 'local' (default: local)
* `--cache-passphrase`: Enable SSH key passphrase caching via ssh-agent
* `--remove`: Remove configuration for specified host and SSH alias

### Examples

```bash
# Setup new configuration
./setup.sh --mode create \
          --ssh-alias work \
          --git-host gitlab.com \
          --git-name "John Doe" \
          --git-email "john@work.com"

# Remove existing configuration
./setup.sh --mode remove \
          --ssh-alias work-gitlab \
          --git-host gitlab.com \
          --git-email "john@work.com"

# GitHub configuration
./setup.sh --backup-dir /path/to/backup \
          --ssh-alias personal \
          --git-name "John Doe" \
          --git-email "john@personal.com" \
          --scope global

# Custom Git server
./setup.sh --backup-dir /path/to/backup \
          --ssh-alias custom-git \
          --git-host git.company.com \
          --git-name "John Doe" \
          --git-email "john@company.com"
```

## Working with Local Configuration

When using local configuration:

1. Clone repositories using the full Git alias:
```bash
git clone <host-domain>-<ssh-alias>:username/repository.git
```

2. Inside the cloned repository, enable GPG signing:
```bash
git config --local include.path ~/.gitconfig-<host-domain>-<ssh-alias>
```

## Configuring Existing Repositories

If you have existing repositories that you want to configure with the new Git identity:

1. Update the remote URL to use the full Git alias:
```bash
git remote set-url origin <host-domain>-<ssh-alias>:username/repository.git
```

2. Configure the local Git settings as described in the previous section.

3. Test GPG signing:
```bash
# Test GPG key
echo "test" | gpg --armor --clear-sign --default-key <git-email>

# Create a test signed commit
git commit --allow-empty -m "Test signed commit."
```

## Updating Existing Repositories

To update an existing repository to use your new SSH alias and configuration:

```bash
cd <your-repo>
git remote set-url origin <host-domain>-<ssh-alias>:<git-user>/<git-project>.git
git config --local include.path ~/.gitconfig-<host-domain>-<ssh-alias>
```

Note: The script automatically configures GPG_TTY in your shell configuration files (.bashrc and .zshrc) and Git config. If you're still experiencing GPG signing issues after installation, try:
1. Sourcing your shell configuration: `source ~/.bashrc` (or `~/.zshrc`)
2. Starting a new terminal session
3. Manually running: `export GPG_TTY=$(tty)`

## Security Notes

- Keep your backup directory secure
- SSH keys should have 600 permissions (private) and 644 (public)
- GPG keys should be kept secure and backed up safely

## What the Script Does

1. Copies SSH keys to the appropriate location
2. Configures SSH for the specified Git account
3. Imports the GPG key
4. Sets up Git configuration for commit signing
5. Verifies the setup by testing SSH connection

## Support me

[Share with me a cup of tea](https://www.buymeacoffee.com/bloris) ☕