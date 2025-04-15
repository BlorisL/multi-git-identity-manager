#!/bin/bash

# Default values
PORTABLE_DIR=""
SSH_ALIAS=""
GIT_HOST="github.com"
GIT_NAME=""
GIT_EMAIL=""
GIT_SCOPE="local"
CACHE_PASSPHRASE="no" # Default: do not enable passphrase caching

# Parse named parameters
while [ $# -gt 0 ]; do
    case "$1" in
        --backup-dir)
            PORTABLE_DIR="$2"
            shift 2
            ;;
        --ssh-alias)
            SSH_ALIAS="$2"
            shift 2
            ;;
        --git-host)
            GIT_HOST="$2"
            shift 2
            ;;
        --git-name)
            GIT_NAME="$2"
            shift 2
            ;;
        --git-email)
            GIT_EMAIL="$2"
            shift 2
            ;;
        --scope)
            GIT_SCOPE="$2"
            shift 2
            ;;
        --cache-passphrase)
            CACHE_PASSPHRASE="yes"
            shift 1
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: $0 --backup-dir <dir> --ssh-alias <alias> [--git-host <host>] --git-name <name> --git-email <email> [--scope <scope>] [--cache-passphrase]"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$PORTABLE_DIR" ] || [ -z "$SSH_ALIAS" ] || [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    echo "Error: Missing required parameters"
    echo "Usage: $0 --backup-dir <dir> --ssh-alias <alias> [--git-host <host>] --git-name <name> --git-email <email> [--scope <scope>] [--cache-passphrase]"
    exit 1
fi

# Define paths with variables
HOST_DOMAIN="$(echo "${GIT_HOST}" | sed 's/\.[^.]*$//' | tr '.' '-' | tr '[:upper:]' '[:lower:]')"
GIT_CONFIG="${HOME}/.gitconfig-${HOST_DOMAIN}-${SSH_ALIAS}"
GIT_ALIAS="${HOST_DOMAIN}-${SSH_ALIAS}"
DIR_BACKUP_SSH_KEYS="${PORTABLE_DIR}/${GIT_ALIAS}/ssh"
DIR_BACKUP_SSH_FILE="${GIT_ALIAS}-sign"
DIR_BACKUP_SSH_KEY="${DIR_BACKUP_SSH_KEYS}/${DIR_BACKUP_SSH_FILE}"
DIR_SSH_KEYS="${HOME}/.ssh/keys"
DIR_SSH_KEY="${DIR_SSH_KEYS}/${GIT_ALIAS}/"
SSH_CONFIG_DIR="${HOME}/.ssh/config.d"
SSH_CONFIG_FILE="${SSH_CONFIG_DIR}/${GIT_ALIAS}.conf"
SSH_MAIN_CONFIG="${HOME}/.ssh/config"
GPG_KEY_FILE="${PORTABLE_DIR}/${GIT_ALIAS}/gpg/${GIT_ALIAS}-private-key.gpg"

# Check if the portable directory exists
if [ ! -d "$PORTABLE_DIR" ]; then
    echo "Error: Directory $PORTABLE_DIR does not exist."
    exit 1
fi

# Check if SSH keys exist in the portable directory
if [ ! -f "${DIR_BACKUP_SSH_KEY}" ] || [ ! -f "${DIR_BACKUP_SSH_KEY}.pub" ]; then
    echo "Error: SSH keys ${DIR_BACKUP_SSH_KEY} or ${DIR_BACKUP_SSH_KEY}.pub do not exist."
    exit 1
fi

# Check if the GPG key file exists
if [ ! -f "${GPG_KEY_FILE}" ]; then
    echo "Error: GPG key file ${GPG_KEY_FILE} does not exist."
    exit 1
fi

# Create SSH directory with correct permissions
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

# Copy SSH keys to ~/.ssh/keys/$GIT_ALIAS/
mkdir -p "${DIR_SSH_KEY}"
chmod 700 "${DIR_SSH_KEYS}" # Permissions for keys directory
cp "${DIR_BACKUP_SSH_KEY}" "${DIR_SSH_KEY}/"
cp "${DIR_BACKUP_SSH_KEY}.pub" "${DIR_SSH_KEY}/"
chmod 600 "${DIR_SSH_KEY}/${DIR_BACKUP_SSH_FILE}"
chmod 644 "${DIR_SSH_KEY}/${DIR_BACKUP_SSH_FILE}.pub"

# Configure ~/.ssh/config to include config.d/ as the first line, if needed
mkdir -p "${SSH_CONFIG_DIR}"
chmod 700 "${SSH_CONFIG_DIR}" # Permissions for config.d
EXPECTED_SSH_MAIN_CONFIG="Include ${SSH_CONFIG_DIR}/*"
TEMP_CONFIG=$(mktemp)
if [ ! -f "${SSH_MAIN_CONFIG}" ]; then
    printf "\n# Creating ${SSH_MAIN_CONFIG} with Include as the first line\n"
    echo "${EXPECTED_SSH_MAIN_CONFIG}" > "${TEMP_CONFIG}"
elif grep -Fx "${EXPECTED_SSH_MAIN_CONFIG}" "${SSH_MAIN_CONFIG}" > /dev/null; then
    printf "\n# ${SSH_MAIN_CONFIG} is already correctly configured, skipping modification.\n"
    cp "${SSH_MAIN_CONFIG}" "${TEMP_CONFIG}"
else
    printf "\n# Updating ${SSH_MAIN_CONFIG} to place Include as the first line\n"
    echo "${EXPECTED_SSH_MAIN_CONFIG}" > "${TEMP_CONFIG}"
    grep -vFx "${EXPECTED_SSH_MAIN_CONFIG}" "${SSH_MAIN_CONFIG}" >> "${TEMP_CONFIG}"
fi
mv "${TEMP_CONFIG}" "${SSH_MAIN_CONFIG}"
chmod 600 "${SSH_MAIN_CONFIG}"

# Configure SSH for the specified alias, if needed
if [ "$CACHE_PASSPHRASE" = "yes" ]; then
    EXPECTED_SSH_CONFIG=$(cat <<EOL
Host ${GIT_ALIAS}
    HostName ${GIT_HOST}
    User git
    IdentityFile ${DIR_SSH_KEY}${DIR_BACKUP_SSH_FILE}
    IdentitiesOnly yes
    AddKeysToAgent yes
EOL
)
else
    EXPECTED_SSH_CONFIG=$(cat <<EOL
Host ${GIT_ALIAS}
    HostName ${GIT_HOST}
    User git
    IdentityFile ${DIR_SSH_KEY}${DIR_BACKUP_SSH_FILE}
EOL
)
fi

if [ ! -f "${SSH_CONFIG_FILE}" ] || [ "$(cat "${SSH_CONFIG_FILE}")" != "${EXPECTED_SSH_CONFIG}" ]; then
    printf "\n# Creating or updating ${SSH_CONFIG_FILE}\n"
    echo "${EXPECTED_SSH_CONFIG}" > "${SSH_CONFIG_FILE}"
    chmod 600 "${SSH_CONFIG_FILE}"
else
    printf "\n# ${SSH_CONFIG_FILE} is already correctly configured, skipping modification.\n"
fi

# Verify that the SSH configuration file was created
if [ ! -f "${SSH_CONFIG_FILE}" ]; then
    echo "Error: ${SSH_CONFIG_FILE} was not created."
    exit 1
fi

# Import GPG key
mkdir -p "${HOME}/.gnupg"
gpg --import "${GPG_KEY_FILE}"

# Automatically extract the GPG key ID
GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG "${GIT_EMAIL}" 2>/dev/null | grep '^sec' | awk '{print $2}' | cut -d'/' -f2)
if [ -z "${GPG_KEY_ID}" ]; then
    echo "Error: Could not find a GPG key for ${GIT_EMAIL}."
    exit 1
fi

# Check if git scope parameter is valid
if [ "$GIT_SCOPE" != "local" ] && [ "$GIT_SCOPE" != "global" ]; then
    GIT_SCOPE="local"
fi

# Configure Git based on scope
if [ "$GIT_SCOPE" = "global" ]; then
    printf "\n# Configuring Git globally...\n"
    cat <<EOL > "${HOME}/.gitconfig"
[user]
    name = ${GIT_NAME}
    email = ${GIT_EMAIL}
    signingkey = ${GPG_KEY_ID}
[commit]
    gpgsign = true
[gpg]
    program = gpg
    tty = $(tty)
EOL
else
    printf "\n# Configuring Git locally (creating template)...\n"
    cat <<EOL > "${GIT_CONFIG}"
[user]
    name = ${GIT_NAME}
    email = ${GIT_EMAIL}
    signingkey = ${GPG_KEY_ID}
[commit]
    gpgsign = true
[gpg]
    program = gpg
    tty = $(tty)
EOL
fi

# Add GPG_TTY to shell configuration if not already present
for RC_FILE in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    if [ -f "${RC_FILE}" ]; then
        if ! grep -q "export GPG_TTY" "${RC_FILE}"; then
            #echo -e "\n# GPG TTY for git commit signing\nexport GPG_TTY=\$(tty)" >> "${RC_FILE}"
            printf "\n# GPG TTY for git commit signing\nexport GPG_TTY=\$(tty)\n" >> "${RC_FILE}"
            echo "Added GPG_TTY export to ${RC_FILE}"
        fi
    fi
done

# Verify configuration
if [ "$GIT_SCOPE" = "global" ]; then
    printf "\n# Verifying global Git configuration:\n"
    git config --global --list
else
    printf "\n# Local Git configuration template (${GIT_CONFIG}):\n"
    cat "${GIT_CONFIG}"
fi
printf "\n# Verifying GPG keys:\n"
gpg --list-secret-keys
#printf "\n# Verifying contents of ${SSH_MAIN_CONFIG}:\n"
#cat "${SSH_MAIN_CONFIG}"
printf "\n# Verifying contents of ${SSH_CONFIG_FILE}:\n"
cat "${SSH_CONFIG_FILE}"
printf "\n# Debugging SSH (loaded config files):\n"
ssh -G "${GIT_ALIAS}" | grep -i config
printf "\n# Verifying SSH connection to ${GIT_HOST}:\n"
ssh -T "${GIT_ALIAS}"
#SSH_OUTPUT=$(ssh -T "${GIT_ALIAS}" 2>&1)
#if echo "${SSH_OUTPUT}" | grep -q "successfully authenticated\|Welcome to GitLab\|successfully authenticated"; then
#    echo "SSH connection successful."
#    echo "${SSH_OUTPUT}"
#else
#    echo "Error: SSH connection failed. Output: ${SSH_OUTPUT}"
#fi
#echo "Configuration completed!"

printf "\n# To update an existing repository to use this identity:\n"
echo "#   cd <your-repo>"
echo "#   git remote set-url origin ${GIT_ALIAS}:<git-user>/<git-project>.git"

if [ "$GIT_SCOPE" = "local" ]; then
    printf "\n# To enable GPG signing only for Git repositories with alias ${GIT_ALIAS}:\n"
    echo "# 1. Clone the repository: git clone ${GIT_ALIAS}:user-specific/repo.git"
    echo "# 2. Navigate to the repository: cd repo"
    echo "# 3. Configure signing: git config --local include.path ${GIT_CONFIG}"
    echo "# Alternatively, manually add the settings from ${GIT_CONFIG} to <repository>/.git/config under the [user] and [commit] sections."
fi
if [ "$CACHE_PASSPHRASE" = "yes" ]; then
    printf "\n# SSH passphrase caching is enabled via AddKeysToAgent.\n"
    echo "# The passphrase will be requested once per session and cached in ssh-agent."
    echo "# To disable, remove 'AddKeysToAgent yes' from ${SSH_CONFIG_FILE}."
fi