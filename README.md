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
└── <git-alias>/
    ├── ssh/
    │   ├── <git-alias>-sign
    │   └── <git-alias>-sign.pub
    └── gpg/
        └── <git-alias>-private-key.gpg
```

## Usage

```bash
./setup.sh --backup-dir <backup-dir> --git-alias <git-alias> [--git-host <git-host>] \
           --git-name "<git-name>" --git-email "<git-email>" [--scope <scope>]
```

### Parameters

* `--backup-dir`: Path to your backup directory containing SSH and GPG keys
* `--git-alias`: Alias for the Git account (used in SSH config)
* `--git-host`: Git hosting service domain (default: github.com)
* `--git-name`: Your full name for Git commits
* `--git-email`: Your email address for Git commits
* `--scope`: Either 'global' or 'local' (default: local)

### Examples

```bash
# GitLab configuration
./setup.sh --backup-dir /path/to/backup \
          --git-alias work-gitlab \
          --git-host gitlab.com \
          --git-name "John Doe" \
          --git-email "john@work.com" \
          --scope local

# GitHub configuration
./setup.sh --backup-dir /path/to/backup \
          --git-alias personal-github \
          --git-name "John Doe" \
          --git-email "john@personal.com" \
          --scope global

# Custom Git server
./setup.sh --backup-dir /path/to/backup \
          --git-alias custom-git \
          --git-host git.company.com \
          --git-name "John Doe" \
          --git-email "john@company.com"
```

## Working with Local Configuration

When using local configuration:

1. Clone repositories using your SSH alias:
```bash
# For GitHub
git clone <git-alias>:username/repository.git

# For GitLab
git clone <git-alias>:username/repository.git

# For custom Git servers
# First, configure the host in your SSH config file with the correct hostname
git clone <git-alias>:username/repository.git
```

2. Inside the cloned repository, enable GPG signing:
```bash
git config --local include.path ~/.gitconfig-github-<git-alias>
```

## Configuring Existing Repositories

If you have existing repositories that you want to configure with the new Git identity:

1. Update the remote URL to use the new SSH alias:
```bash
git remote set-url origin <git-alias>:<git-user>/<git-project>.git
```

2. Configure the local Git settings as described in the previous section.

3. Test GPG signing:
```bash
# Test GPG key
echo "test" | gpg --armor --clear-sign --default-key <git-email>

# Create a test signed commit
git commit --allow-empty -m "Test signed commit."
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
