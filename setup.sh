#!/bin/bash

# Default values and configuration
PORTABLE_DIR="backup"
SSH_ALIAS=""
GIT_HOST="github.com"
GIT_NAME=""
GIT_EMAIL=""
GIT_SCOPE="local"
CACHE_PASSPHRASE="no"
MODE="create"

get_host_domain() {
    echo "$1" | sed 's/\.[^.]*$//' | tr '.' '-' | tr '[:upper:]' '[:lower:]'
}

setup_configuration() {
    local portable_dir="$1"
    local git_host="$2"
    local ssh_alias="$3"
    local git_name="$4"
    local git_email="$5"
    local git_scope="$6"
    local cache_passphrase="$7"

    local host_domain="$(get_host_domain "$git_host")"
    local git_alias="${host_domain}-${ssh_alias}"
    local git_config="${HOME}/.gitconfig-${host_domain}-${ssh_alias}"
    local backup_ssh_keys="${portable_dir}/${git_alias}/ssh"
    local backup_ssh_file="${git_alias}-sign"
    local ssh_key_dir="${HOME}/.ssh/keys/${git_alias}/"
    local ssh_config_file="${HOME}/.ssh/config.d/${git_alias}.conf"
    local gpg_key_file="${portable_dir}/${git_alias}/gpg/${git_alias}-private-key.gpg"

    # Check if the portable directory exists
    if [ ! -d "$portable_dir" ]; then
        echo "Error: Directory $portable_dir does not exist."
        exit 1
    fi

    # Check if SSH keys exist in the portable directory
    if [ ! -f "${backup_ssh_keys}/${backup_ssh_file}" ]; then
        echo "Error: SSH keys not found in ${backup_ssh_keys}"
        exit 1
    fi

    # Check if the GPG key file exists
    if [ ! -f "${gpg_key_file}" ]; then
        echo "Error: GPG key file ${gpg_key_file} does not exist."
        exit 1
    fi

    # Create SSH directory with correct permissions
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"

    # Copy SSH keys to ~/.ssh/keys/$git_alias/
    mkdir -p "${ssh_key_dir}"
    chmod 700 "${ssh_key_dir}" # Permissions for keys directory
    cp "${backup_ssh_keys}/${backup_ssh_file}" "${ssh_key_dir}/"
    cp "${backup_ssh_keys}/${backup_ssh_file}.pub" "${ssh_key_dir}/"
    chmod 600 "${ssh_key_dir}/${backup_ssh_file}"
    chmod 644 "${ssh_key_dir}/${backup_ssh_file}.pub"

    # Configure ~/.ssh/config to include config.d/ as the first line, if needed
    mkdir -p "${HOME}/.ssh/config.d"
    chmod 700 "${HOME}/.ssh/config.d" # Permissions for config.d
    EXPECTED_SSH_MAIN_CONFIG="Include ${HOME}/.ssh/config.d/*"
    TEMP_CONFIG=$(mktemp)
    if [ ! -f "${HOME}/.ssh/config" ]; then
        printf "\n# Creating ${HOME}/.ssh/config with Include as the first line\n"
        echo "${EXPECTED_SSH_MAIN_CONFIG}" > "${TEMP_CONFIG}"
    elif grep -Fx "${EXPECTED_SSH_MAIN_CONFIG}" "${HOME}/.ssh/config" > /dev/null; then
        printf "\n# ${HOME}/.ssh/config is already correctly configured, skipping modification.\n"
        cp "${HOME}/.ssh/config" "${TEMP_CONFIG}"
    else
        printf "\n# Updating ${HOME}/.ssh/config to place Include as the first line\n"
        echo "${EXPECTED_SSH_MAIN_CONFIG}" > "${TEMP_CONFIG}"
        grep -vFx "${EXPECTED_SSH_MAIN_CONFIG}" "${HOME}/.ssh/config" >> "${TEMP_CONFIG}"
    fi
    mv "${TEMP_CONFIG}" "${HOME}/.ssh/config"
    chmod 600 "${HOME}/.ssh/config"

    # Configure SSH for the specified alias, if needed
    if [ "$cache_passphrase" = "yes" ]; then
        EXPECTED_SSH_CONFIG=$(cat <<EOL
Host ${git_alias}
    HostName ${git_host}
    User git
    IdentityFile ${ssh_key_dir}${backup_ssh_file}
    IdentitiesOnly yes
    AddKeysToAgent yes
EOL
)
    else
        EXPECTED_SSH_CONFIG=$(cat <<EOL
Host ${git_alias}
    HostName ${git_host}
    User git
    IdentityFile ${ssh_key_dir}${backup_ssh_file}
EOL
)
    fi

    if [ ! -f "${ssh_config_file}" ] || [ "$(cat "${ssh_config_file}")" != "${EXPECTED_SSH_CONFIG}" ]; then
        printf "\n# Creating or updating ${ssh_config_file}\n"
        echo "${EXPECTED_SSH_CONFIG}" > "${ssh_config_file}"
        chmod 600 "${ssh_config_file}"
    else
        printf "\n# ${ssh_config_file} is already correctly configured, skipping modification.\n"
    fi

    # Verify that the SSH configuration file was created
    if [ ! -f "${ssh_config_file}" ]; then
        echo "Error: ${ssh_config_file} was not created."
        exit 1
    fi

    # Import GPG key
    mkdir -p "${HOME}/.gnupg"
    gpg --import "${gpg_key_file}"

    # Automatically extract the GPG key ID
    GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG "${git_email}" 2>/dev/null | grep '^sec' | awk '{print $2}' | cut -d'/' -f2)
    if [ -z "${GPG_KEY_ID}" ]; then
        echo "Error: Could not find a GPG key for ${git_email}."
        exit 1
    fi

    # Check if git scope parameter is valid
    if [ "$git_scope" != "local" ] && [ "$git_scope" != "global" ]; then
        git_scope="local"
    fi

    # Configure Git based on scope
    if [ "$git_scope" = "global" ]; then
        printf "\n# Configuring Git globally...\n"
        cat <<EOL > "${HOME}/.gitconfig"
[user]
    name = ${git_name}
    email = ${git_email}
    signingkey = ${GPG_KEY_ID}
[commit]
    gpgsign = true
[gpg]
    program = gpg
    tty = $(tty)
EOL
    else
        printf "\n# Configuring Git locally (creating template)...\n"
        cat <<EOL > "${git_config}"
[user]
    name = ${git_name}
    email = ${git_email}
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
                printf "\n# GPG TTY for git commit signing\nexport GPG_TTY=\$(tty)\n" >> "${RC_FILE}"
                echo "Added GPG_TTY export to ${RC_FILE}"
            fi
        fi
    done

    # Verify configuration
    if [ "$git_scope" = "global" ]; then
        printf "\n# Verifying global Git configuration:\n"
        git config --global --list
    else
        printf "\n# Local Git configuration template (${git_config}):\n"
        cat "${git_config}"
    fi
    printf "\n# Verifying GPG keys:\n"
    gpg --list-secret-keys
    printf "\n# Verifying contents of ${ssh_config_file}:\n"
    cat "${ssh_config_file}"
    printf "\n# Debugging SSH (loaded config files):\n"
    ssh -G "${git_alias}" | grep -i config
    printf "\n# Verifying SSH connection to ${git_host}:\n"
    ssh -T "${git_alias}"

    printf "\n# To update an existing repository to use this identity:\n"
    echo "#   cd <your-repo>"
    echo "#   git remote set-url origin ${git_alias}:<git-user>/<git-project>.git"

    if [ "$git_scope" = "local" ]; then
        printf "\n# To enable GPG signing only for Git repositories with alias ${git_alias}:\n"
        echo "# 1. Clone the repository: git clone ${git_alias}:user-specific/repo.git"
        echo "# 2. Navigate to the repository: cd repo"
        echo "# 3. Configure signing: git config --local include.path ${git_config}"
        echo "# Alternatively, manually add the settings from ${git_config} to <repository>/.git/config under the [user] and [commit] sections."
    fi
    if [ "$cache_passphrase" = "yes" ]; then
        printf "\n# SSH passphrase caching is enabled via AddKeysToAgent.\n"
        echo "# The passphrase will be requested once per session and cached in ssh-agent."
        echo "# To disable, remove 'AddKeysToAgent yes' from ${ssh_config_file}."
    fi
}

cleanup_configuration() {
    local git_host="$1"
    local ssh_alias="$2"
    local git_email="$3"
    
    local host_domain="$(get_host_domain "$git_host")"
    local git_alias="${host_domain}-${ssh_alias}"
    local git_config="${HOME}/.gitconfig-${host_domain}-${ssh_alias}"
    local ssh_key_dir="${HOME}/.ssh/keys/${git_alias}/"
    local ssh_config_file="${HOME}/.ssh/config.d/${git_alias}.conf"

    # Remove SSH keys
    if [ -d "${ssh_key_dir}" ]; then
        echo "Removing SSH keys directory: ${ssh_key_dir}"
        rm -rf "${ssh_key_dir}"
    fi

    # Remove SSH config
    if [ -f "${ssh_config_file}" ]; then
        echo "Removing SSH config: ${ssh_config_file}"
        rm -f "${ssh_config_file}"
    fi

    # Remove Git config
    if [ -f "${git_config}" ]; then
        echo "Removing Git config: ${git_config}"
        rm -f "${git_config}"
    fi

    # Clean up GPG key
    if [ ! -z "$git_email" ]; then
        local gpg_fingerprint=$(gpg --list-secret-keys --with-colons --fingerprint "$git_email" 2>/dev/null | grep '^fpr' | head -n 1 | cut -d: -f10)
        if [ ! -z "$gpg_fingerprint" ]; then
            echo "Removing GPG key for $git_email"
            gpg --batch --yes --delete-secret-and-public-keys "$gpg_fingerprint"
        fi
    fi

    echo "Cleanup completed for ${git_alias}"
}

# Parse named parameters
while [ $# -gt 0 ]; do
    case "$1" in
        --backup-dir)
            PORTABLE_DIR="$2"
            shift 2
            ;;
        --mode)
            if [[ "$2" != "create" && "$2" != "remove" ]]; then
                echo "Error: --mode must be 'create' or 'remove'"
                exit 1
            fi
            MODE="$2"
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
            echo "Usage: $0 [--mode create|remove] [--backup-dir <dir>] --ssh-alias <alias> [--git-host <host>] --git-name <name> --git-email <email> [--scope <scope>] [--cache-passphrase]"
            exit 1
            ;;
    esac
done

# Validate parameters based on mode
if [ "$MODE" = "create" ]; then
    if [ -z "$SSH_ALIAS" ] || [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
        echo "Error: Missing required parameters for create mode"
        echo "Usage: $0 [--mode create] [--backup-dir <dir>] --ssh-alias <alias> [--git-host <host>] --git-name <name> --git-email <email> [--scope <scope>] [--cache-passphrase]"
        exit 1
    fi
elif [ "$MODE" = "remove" ]; then
    if [ -z "$SSH_ALIAS" ] || [ -z "$GIT_EMAIL" ]; then
        echo "Error: Missing required parameters for remove mode"
        echo "Usage: $0 --mode remove --ssh-alias <alias> [--git-host <host>] --git-email <email>"
        exit 1
    fi
fi

# Execute requested mode
if [ "$MODE" = "create" ]; then
    setup_configuration "$PORTABLE_DIR" "$GIT_HOST" "$SSH_ALIAS" "$GIT_NAME" "$GIT_EMAIL" "$GIT_SCOPE" "$CACHE_PASSPHRASE"
else
    cleanup_configuration "$GIT_HOST" "$SSH_ALIAS" "$GIT_EMAIL"
fi