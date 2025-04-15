#!/bin/bash

# Default values
PORTABLE_DIR=""
SSH_ALIAS=""
GIT_HOST="github.com"
GIT_NAME=""
GIT_EMAIL=""
GIT_SCOPE="local"

# Parse named parameters
while [ $# -gt 0 ]; do
    case "$1" in
        --backup-dir)
            PORTABLE_DIR="$2"
            shift 2
            ;;
        --git-alias)
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
        *)
            echo "Unknown parameter: $1"
            echo "Usage: $0 --backup-dir <dir> --git-alias <alias> [--git-host <host>] --git-name <name> --git-email <email> [--scope <scope>]"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$PORTABLE_DIR" ] || [ -z "$SSH_ALIAS" ] || [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    echo "Error: Missing required parameters"
    echo "Usage: $0 --backup-dir <dir> --git-alias <alias> [--git-host <host>] --git-name <name> --git-email <email> [--scope <scope>]"
    exit 1
fi

# Define paths with variables
DIR_BACKUP_SSH_KEYS="${PORTABLE_DIR}/${SSH_ALIAS}/ssh"
DIR_BACKUP_SSH_FILE="${SSH_ALIAS}-sign"
DIR_BACKUP_SSH_KEY="${DIR_BACKUP_SSH_KEYS}/${DIR_BACKUP_SSH_FILE}"
DIR_SSH_KEYS="${HOME}/.ssh/keys"
DIR_SSH_KEY="${DIR_SSH_KEYS}/${SSH_ALIAS}/"
SSH_CONFIG_DIR="${HOME}/.ssh/config.d"
SSH_CONFIG_FILE="${SSH_CONFIG_DIR}/${SSH_ALIAS}.conf"
SSH_MAIN_CONFIG="${HOME}/.ssh/config"
GPG_KEY_FILE="${PORTABLE_DIR}/${SSH_ALIAS}/gpg/${SSH_ALIAS}-private-key.gpg"
GITCONFIG="${HOME}/.gitconfig-$(echo "${GIT_HOST}" | sed 's/\.[^.]*$//' | tr '.' '-' | tr '[:upper:]' '[:lower:]')-${SSH_ALIAS}"

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

# Copy SSH keys to ~/.ssh/keys/$SSH_ALIAS/
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
    echo "Creating ${SSH_MAIN_CONFIG} with Include as the first line"
    echo "${EXPECTED_SSH_MAIN_CONFIG}" > "${TEMP_CONFIG}"
elif grep -Fx "${EXPECTED_SSH_MAIN_CONFIG}" "${SSH_MAIN_CONFIG}" > /dev/null; then
    echo "${SSH_MAIN_CONFIG} is already correctly configured, skipping modification."
    cp "${SSH_MAIN_CONFIG}" "${TEMP_CONFIG}"
else
    echo "Updating ${SSH_MAIN_CONFIG} to place Include as the first line"
    echo "${EXPECTED_SSH_MAIN_CONFIG}" > "${TEMP_CONFIG}"
    grep -vFx "${EXPECTED_SSH_MAIN_CONFIG}" "${SSH_MAIN_CONFIG}" >> "${TEMP_CONFIG}"
fi
mv "${TEMP_CONFIG}" "${SSH_MAIN_CONFIG}"
chmod 600 "${SSH_MAIN_CONFIG}"

# Configure SSH for the specified alias, if needed
EXPECTED_SSH_CONFIG=$(cat <<EOL
Host ${SSH_ALIAS}
    HostName ${GIT_HOST}
    User git
    IdentityFile ${DIR_SSH_KEY}${DIR_BACKUP_SSH_FILE}
EOL
)
if [ ! -f "${SSH_CONFIG_FILE}" ] || [ "$(cat "${SSH_CONFIG_FILE}")" != "${EXPECTED_SSH_CONFIG}" ]; then
    echo "Creating or updating ${SSH_CONFIG_FILE}"
    echo "${EXPECTED_SSH_CONFIG}" > "${SSH_CONFIG_FILE}"
    chmod 600 "${SSH_CONFIG_FILE}"
else
    echo "${SSH_CONFIG_FILE} is already correctly configured, skipping modification."
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
    echo "Configuring Git globally..."
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
    echo "Configuring Git locally (creating template)..."
    cat <<EOL > "${GITCONFIG}"
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
            echo -e "\n# GPG TTY for git commit signing\nexport GPG_TTY=\$(tty)" >> "${RC_FILE}"
            echo "Added GPG_TTY export to ${RC_FILE}"
        fi
    fi
done

# Verify configuration
if [ "$GIT_SCOPE" = "global" ]; then
    echo "Verifying global Git configuration:"
    git config --global --list
else
    echo "Local Git configuration template (${GITCONFIG}):"
    cat "${GITCONFIG}"
fi
echo "Verifying GPG keys:"
gpg --list-secret-keys
#echo "Verifying contents of ${SSH_MAIN_CONFIG}:"
#cat "${SSH_MAIN_CONFIG}"
echo "Verifying contents of ${SSH_CONFIG_FILE}:"
cat "${SSH_CONFIG_FILE}"
echo "Debugging SSH (loaded config files):"
ssh -G "${SSH_ALIAS}" | grep -i config
echo "Verifying SSH connection to ${GIT_HOST}:"
ssh -T "${SSH_ALIAS}"
#SSH_OUTPUT=$(ssh -T "${SSH_ALIAS}" 2>&1)
#if echo "${SSH_OUTPUT}" | grep -q "successfully authenticated\|Welcome to GitLab\|successfully authenticated"; then
#    echo "SSH connection successful."
#    echo "${SSH_OUTPUT}"
#else
#    echo "Error: SSH connection failed. Output: ${SSH_OUTPUT}"
#fi
#echo "Configuration completed!"
echo ""

if [ "$GIT_SCOPE" = "local" ]; then
    echo "To enable GPG signing only for Git repositories with alias ${SSH_ALIAS}:"
    echo "1. Clone the repository: git clone ${SSH_ALIAS}:user-specific/repo.git"
    echo "2. Navigate to the repository: cd repo"
    echo "3. Configure signing: git config --local include.path ${GITCONFIG}"
    echo "Alternatively, manually add the settings from ${GITCONFIG} to <repository>/.git/config under the [user] and [commit] sections."
fi