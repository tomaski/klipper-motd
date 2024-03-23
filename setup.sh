#!/bin/bash

# abort if anything goes sideways
set -eu -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# are we running with elevated permissions?
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

get_help(){
    cat << EOF

    Usage: setup.sh [OPTIONS]

        Easily install/update/remove Klipper-MoTD.

        Written by Tomasz Paluszkiewicz (GitHub: tomaski)

    OPTIONS
        -i, --install
            The MoTD files will be placed at their inended locations.
            Additionaly, certain system settings will be changed. 

        -r, --remove
            The MoTD files will be removed from the system,
            and all changes reverted.

        -u, --update
            Check for updates. If newer version is found,
            you'll be asked whether to update or not. 

        -h, --help
            Display this help text and exit. No changes are made.

EOF
}

backup_sshd_config(){
    if [ -f /etc/ssh/sshd_config ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.1
        echo "> Created backup of /etc/ssh/sshd_config"
    else
        echo "> File /etc/ssh/sshd_config not found."
        exit 1
    fi
}

install_motd(){
    sed -i '/PrintLastLog/cPrintLastLog no' /etc/ssh/sshd_config
    echo "> Disabled standard LastLog info."

    if [ -f /etc/motd ]; then
        mv /etc/motd /etc/motd.1
        echo "> Disabled default static MoTD file."
    fi

    if [ -f /etc/update-motd.d/10-uname ]; then
        chmod -x /etc/update-motd.d/10-uname
        echo "> Disabled default dynamic MoTD file."
    fi

    mkdir -p /etc/update-motd.d
    cp -r $SCRIPT_DIR/files/* /etc/update-motd.d/
    chmod +x /etc/update-motd.d/10-klipper-motd
    echo "> Copied the klipper MoTD files."

    if ! [ -x "$(command -v figlet)" ]; then
        apt install figlet -y > /dev/null 2>&1
        echo "> Installed necessary 'figlet' package."
    fi

    chmod +x $SCRIPT_DIR/motd-config
    cp $SCRIPT_DIR/motd-config /usr/bin/motd-config
    echo "> Installed the MoTD configurator."
}

uninstall_motd(){
    sed -i 's/^PrintLastLog\(.*\)$/#PrintLastLog yes/' /etc/ssh/sshd_config
    echo "> Enabled standard LastLog info."

    if [ -f /etc/motd.1 ]; then
        mv /etc/motd.1 /etc/motd
        echo "> Enabled default static MoTD file."
    fi

    if [ -f /etc/update-motd.d/10-uname ]; then
        chmod +x /etc/update-motd.d/10-uname
        echo "> Enabled default dynamic MoTD file."
    fi

    if [ -f /etc/update-motd.d/10-klipper-motd ]; then
        rm /etc/update-motd.d/10-klipper-motd
    fi

    if [ -d /etc/update-motd.d/logos ]; then
        rm -rf /etc/update-motd.d/logos
    fi
    echo "> Removed the klipper MoTD files."

    if [ -x "$(command -v figlet)" ]; then
        apt remove figlet -y > /dev/null 2>&1
        echo "> Removed the 'figlet' package."
    fi

    if [ -f /usr/bin/motd-config ]; then
        rm /usr/bin/motd-config
    fi
    echo "> Deleted the MoTD configurator."
}

check_update_motd(){

    git remote update
    CURRENT_VERSION=`git describe --tags --abbrev=0 --match "*.*.*" main`
    LAST_VERSION=`git describe --tags --abbrev=0 --match "*.*.*" origin/main`

    if [ $CURRENT_VERSION != $LAST_VERSION ]; then
        echo "New version $LAST_VERSION available. You are on $CURRENT_VERSION"
        while true; do
            read -r -n 1 -p "Do you wish to update [y/n]? " run_update
            case $run_update in
                [Yy] ) run_update_motd(); break;;
                [Nn] ) exit;;
                * ) echo "Please answer yes or no.";;
            esac
        done   
    else
        echo "You are already on the latest version ($CURRENT_VERSION)."
    fi
}

run_update_motd(){
    git pull --no-edit
    cp -r $SCRIPT_DIR/files/* /etc/update-motd.d/
    chmod +x /etc/update-motd.d/10-klipper-motd
    echo -e "\nKlipper MoTD has been succesfully updated.\n\nRun 'sudo motd-config' to set it up."
}

reload_sshd(){
    systemctl reload sshd.service
    echo "> Reloaded sshd.service"
}


if [ "$#" -eq 0 ]; then
    get_help
    exit 1
fi

while [ $# -gt 0 ]; do
    case "$1" in
        -i | --install)
            backup_sshd_config
            install_motd
            reload_sshd
            echo -e "\nKlipper MoTD has been succesfully installed.\n\nRun 'sudo motd-config' to set it up."
            shift
            ;;
        -r | --remove)
            backup_sshd_config
            uninstall_motd
            reload_sshd
            echo -e "\nKlipper MoTD has been succesfully removed."
            shift
            ;;
        -u | --update)
            check_update_motd
            shift
            ;;
        -h | --help)
            get_help
            # exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo -e "\nUnknown option ${1}. Type 'sudo ./"$(basename "$0")" --help' for usage info.\n"
            exit 1
            ;;
    esac
done
