#!/bin/bash
# abort if anything goes sideways
set -eu -o pipefail

# Set some variabled
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
BACKUP_SUFFIX=".backup-klipper-motd"
SSHD_CONFIG="/etc/ssh/sshd_config"
MOTD_DIR="/etc/update-motd.d"

# Check for root permissions
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root." >&2
   exit 1
fi

get_help(){
    cat << EOF

    Usage: setup.sh [OPTIONS]

        Easily install/update/remove Klipper-MoTD.

        Written by Tomasz Paluszkiewicz (GitHub: tomaski)

    OPTIONS
        -i, --install
            The MoTD files will be placed at their intended locations.
            Additionaly, certain system settings will be changed. 

        -r, --remove
            The MoTD files will be removed from the system,
            and all changes reverted.

        -u, --update
            Check for updates. If newer version is found,
            you'll be asked whether to update or not. 

        -m, --moonraker
            Search for moonraker.conf. If the file is found,
            prompt will be shown to add update check for this script.

        -h, --help
            Display this help text and exit. No changes are made.

EOF
}

backup_sshd_config(){

    if [ -f "$SSHD_CONFIG" ]; then
        cp "$SSHD_CONFIG" "${SSHD_CONFIG}${BACKUP_SUFFIX}"
        echo "> Created backup of ${SSHD_CONFIG}"
    else
        echo "Error: ${SSHD_CONFIG} not found." >&2
        exit 1
    fi
}

restore_sshd_config(){

    if [ -f "${SSHD_CONFIG}${BACKUP_SUFFIX}" ]; then
        mv "${SSHD_CONFIG}${BACKUP_SUFFIX}" "$SSHD_CONFIG"
        echo "> Restored backup of ${SSHD_CONFIG}"
    else
        echo "Error: ${SSHD_CONFIG}${BACKUP_SUFFIX} not found." >&2
        exit 1
    fi
}

install_motd(){
    
    # Configure SSH
    if ! grep -q "^PrintLastLog" "$SSHD_CONFIG"; then
        echo "PrintLastLog no" >> "$SSHD_CONFIG"
    else
        sed -i '/PrintLastLog/cPrintLastLog no' "$SSHD_CONFIG"
    fi
    echo "> Disabled standard LastLog info."

    # Backup and disable default MOTD
    if [ -f /etc/motd ]; then
        mv /etc/motd "/etc/motd${BACKUP_SUFFIX}"
        echo "> Disabled default static MoTD file."
    fi

    # Disable default dynamic MOTD
    if [ -f "${MOTD_DIR}/10-uname" ]; then
        chmod -x "${MOTD_DIR}/10-uname"
        echo "> Disabled default dynamic MoTD file."
    fi

    # Install new MOTD files
    mkdir -p "$MOTD_DIR"
    cp -r "${SCRIPT_DIR}/files/." "$MOTD_DIR/"
    chmod +x "${MOTD_DIR}/10-klipper-motd"
    echo "> Copied the klipper MoTD files."

    # Install dependencies
    if ! [ -x "$(command -v figlet)" ]; then
        apt-get update > /dev/null 2>&1
        apt-get install -y figlet > /dev/null 2>&1
        echo "> Installed necessary 'figlet' package."
    fi

    # Install configurator
    chmod +x "${SCRIPT_DIR}/motd-config"
    cp "${SCRIPT_DIR}/motd-config" /usr/bin/motd-config
    echo "> Installed the MoTD configurator."
}

uninstall_motd(){

    # Restore SSH config
    sed -i 's/^PrintLastLog\(.*\)$/#PrintLastLog yes/' "$SSHD_CONFIG"
    echo "> Enabled standard LastLog info."

    # Restore default MOTD
    if [ -n "/etc/motd${BACKUP_SUFFIX}" ]; then
        mv "/etc/motd${BACKUP_SUFFIX}" /etc/motd
        echo "> Restored default static MoTD file."
    fi

    # Restore default dynamic MOTD
    if [ -f "${MOTD_DIR}/10-uname" ]; then
        chmod +x "${MOTD_DIR}/10-uname"
        echo "> Enabled default dynamic MoTD file."
    fi

    # Remove Klipper MOTD files
    if [ -f "${MOTD_DIR}/10-klipper-motd" ]; then
        rm "${MOTD_DIR}/10-klipper-motd"
    fi
    if [ -d "${MOTD_DIR}/logos" ]; then
        rm -rf "${MOTD_DIR}/logos"
    fi
    echo "> Removed the klipper MoTD files."

    # Remove figlet if installed by this script
    if [ -x "$(command -v figlet)" ]; then
        apt-get remove -y figlet > /dev/null 2>&1
        apt-get autoremove -y > /dev/null 2>&1
        echo "> Removed the 'figlet' package."
    fi

    # Remove configurator
    if [ -f /usr/bin/motd-config ]; then
        rm /usr/bin/motd-config
    fi
    echo "> Deleted the MoTD configurator."
}

check_update_motd(){
    git remote update
    local current_version
    local latest_version
    
    current_version=$(git describe --tags --abbrev=0 --match "*.*.*" main)
    latest_version=$(git describe --tags --abbrev=0 --match "*.*.*" origin/main)
    
    if [ "$current_version" != "$latest_version" ]; then
        echo "New version $latest_version available. You are on $current_version"
        while true; do
            read -r -n 1 -p "Do you wish to update [y/n]? " run_update
            case $run_update in
                [Yy] ) run_update_motd; break;;
                [Nn] ) exit;;
                * ) echo "Please answer y or n.";;
            esac
        done   
    else
        echo "You are already on the latest version ($current_version)."
    fi
}

run_update_motd(){
    if [ -f "${MOTD_DIR}/10-klipper-motd" ]; then
        git pull --no-edit
        cp -r "${SCRIPT_DIR}/files/." "$MOTD_DIR/"
        chmod +x "${MOTD_DIR}/10-klipper-motd"
        echo -e "\nKlipper MoTD has been successfully updated.\n\nRun 'sudo motd-config' to set it up."
    else
        echo "Error: Klipper MoTD is not installed!" >&2
        exit 1
    fi
}

find_moonraker_conf(){
    find /home -type f -name "moonraker.conf" | grep -E '^/home/[^/]+/(printer_data/config/moonraker.conf|moonraker.conf)$'
}

add_moonraker_config(){
    local config_path
    config_path=$(find_moonraker_conf)
    
    if [ -n "$config_path" ] && [ -f "$config_path" ]; then
        while true; do
            read -r -n 1 -p "> Moonraker detected. Add update check to the dashboard [y/n]? " configure_moonraker
            case $configure_moonraker in
                [Yy] ) 
                    cat "${SCRIPT_DIR}/files/moonraker_config" >> "$config_path"
                    echo -e "\n> Added Moonraker update check." 
                    reload_moonraker
                    break;;
                [Nn] ) break;;
                * ) echo -e "\nPlease answer y or n.";;
            esac
        done 
    fi
}

remove_moonraker_config(){
    local config_path=$(find_moonraker_conf)
    local begin_marker="### BEGIN KLIPPER-MOTD CONFIG"
    local end_marker="### END KLIPPER-MOTD CONFIG"

    if [ -n "$config_path" ] && [ -f "$config_path" ]; then
        sed -i "/$begin_marker/,/$end_marker/d" "$config_path"
        echo "> Removed Moonraker update check."
        reload_moonraker
    fi
}

reload_sshd(){
    systemctl reload sshd.service
    echo "> Reloaded sshd.service"
}

reload_moonraker(){
    systemctl restart moonraker.service
    echo "> Reloaded moonraker.service"
}


if [ "$#" -eq 0 ]; then
    echo -e "\nError: No arguments provided."
    echo -e "Type 'sudo ./"$(basename "$0")" --help' for usage info.\n"
    exit 1
fi

if [ "$#" -gt 1 ]; then
    echo -e "\nError: This script accepts exactly one argument."
    echo -e "Type 'sudo ./"$(basename "$0")" --help' for usage info.\n"
    exit 1
fi

    case "$1" in
        -i | --install)
            backup_sshd_config
            install_motd
            reload_sshd
            add_moonraker_config
            echo -e "\nKlipper MoTD has been succesfully installed.\n\nRun 'sudo motd-config' to set it up."
            exit 0
            ;;
        -r | --remove)
            backup_sshd_config
            uninstall_motd
            remove_moonraker_config
            reload_sshd
            echo -e "\nKlipper MoTD has been succesfully removed."
            exit 0
            ;;
        -u | --update)
            check_update_motd
            exit 0
            ;;
        -m | --moonraker)
            add_moonraker_config
            exit 0
            ;;
        -h | --help)
            get_help
            exit 0
            ;;
        *)
            echo -e "\nUnknown option '${1}'. Type 'sudo ./"$(basename "$0")" --help' for usage info.\n"
            exit 1
            ;;
    esac
