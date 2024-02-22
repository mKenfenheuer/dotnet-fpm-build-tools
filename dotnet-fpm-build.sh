#!/bin/bash

SYSTEMD_SERVICE="False"
CONFIG_DIRECTORY="False"
USR_BIN_SYMLINK="False"
INSTALL_DIR="/usr/share/"
EXECUTABLE="False"
CSPROJ_FILE="False"
LOG_LEVEL=INFO
PRODUCT_NAME="False"
VERSION="1.0"
MAINTAINER="$(whoami)"
URL="http://$(hostname)"
VENDOR="$(whoami)"
ARCH="$(arch)"
BUILD_DIR=$(realpath "$(pwd)/build")
MAIN_DIR=$(realpath "$(pwd)")

log_debug() {
    if [ $LOG_LEVEL != "DEBUG" ]; then
        return
    fi
    WHITE='\033[0;37m'
    NC='\033[0m' # No Color
    echo -e "${WHITE}DEBUG: $@${NC}"
}

log_error() {
    RED='\033[0;31m'
    NC='\033[0m'
    echo -e "${RED}ERROR: $@${NC}"
}

log_info() {
    if [ $LOG_LEVEL != "INFO" -a $LOG_LEVEL != "DEBUG" ]; then
        return
    fi
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
    echo -e "${CYAN}INFO:  $@${NC}"
}

log_warn() {
    if [ $LOG_LEVEL != "INFO" -a $LOG_LEVEL != "DEBUG" -a $LOG_LEVEL != "WARN" ]; then
        return
    fi
    YELLOW='\033[0;33m'
    NC='\033[0m' # No Color
    echo -e "${YELLOW}WARN:  $@${NC}"
}

run_command() {
    while read -r line; do
        log_debug "$line"
    done < <($@)
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        -s | --systemd)
            SYSTEMD_SERVICE=True
            shift
            ;;
        -c | --config)
            CONFIG_DIRECTORY="$2"
            shift
            shift
            ;;
        -e | --executable)
            USR_BIN_SYMLINK=True
            EXECUTABLE="$2"
            shift
            shift # past argument
            ;;
        -i | --install-dir)
            INSTALL_DIR="$2"
            shift
            shift
            ;;
        -p | --project)
            CSPROJ_FILE=$(basename $2)
            CSPROJ_DIR=$(realpath $(dirname "$(pwd)/$2"))
            shift
            shift
            ;;
        -l | --loglevel)
            LOG_LEVEL="$2"
            shift
            shift
            ;;
        -p | --productname)
            PRODUCT_NAME="$2"
            shift
            shift
            ;;
        -v | --version)
            VERSION="$2"
            shift
            shift
            ;;
        --vendor)
            VENDOR="$2"
            shift
            shift
            ;;
        --architecture)
            ARCH="$2"
            shift
            shift
            ;;
        --maintainer)
            MAINTAINER="$2"
            shift
            shift
            ;;
        --url)
            URL="$2"
            shift
            shift
            ;;
        *)
            log_error "Unknown option $1"
            exit 1
            ;;
        esac
    done

    if [ $PRODUCT_NAME = "False" ]; then
        filename=$(basename -- "$CSPROJ_FILE")
        extension="${filename##*.}"
        filename="${filename%.*}"
        PRODUCT_NAME=$filename
    fi

    log_debug "###### BEGIN ARGUMENTS ######"
    log_debug "SYSTEMD_SERVICE:  $SYSTEMD_SERVICE"
    log_debug "CONFIG_DIRECTORY: $CONFIG_DIRECTORY"
    log_debug "USR_BIN_SYMLINK:  $USR_BIN_SYMLINK"
    log_debug "INSTALL_DIR:      $INSTALL_DIR"
    log_debug "CSPROJ_FILE:      $CSPROJ_FILE"
    log_debug "CSPROJ_DIR:       $CSPROJ_DIR"
    log_debug "BUILD_DIR:        $BUILD_DIR"
    log_debug "LOG_LEVEL:        $LOG_LEVEL"
    log_debug "PRODUCT_NAME:     $PRODUCT_NAME"
    log_debug "VERSION:          $VERSION"
    log_debug "MAINTAINER:       $MAINTAINER"
    log_debug "VENDOR:           $VENDOR"
    log_debug "URL:              $URL"
    log_debug "ARCHITECTURE:     $ARCH"
    log_debug "EXECUTABLE:       $EXECUTABLE"
    log_debug "######  END ARGUMENTS  ######"
}

build_project() {
    log_info Building dotnet project
    log_debug Entering directory \"$CSPROJ_DIR\"
    cd $CSPROJ_DIR
    run_command mkdir -p $BUILD_DIR/root$INSTALL_DIR
    run_command dotnet publish --configuration Release --self-contained true --output "$BUILD_DIR/root$INSTALL_DIR/$PRODUCT_NAME" $CSPROJ_FILE 
    log_debug Leaving directory \"$CSPROJ_DIR\"
    cd $MAIN_DIR
    fpm_add_arg "$BUILD_DIR/root$INSTALL_DIR$PRODUCT_NAME/=$INSTALL_DIR$PRODUCT_NAME/"
    if [ $USR_BIN_SYMLINK = "True" ]; then
        run_command mkdir -p $BUILD_DIR/root/usr/bin/
        run_command ln -s "$INSTALL_DIR$PRODUCT_NAME/$EXECUTABLE" "$BUILD_DIR/root/usr/bin/$EXECUTABLE"
        fpm_add_arg "$BUILD_DIR/root/usr/bin/$EXECUTABLE=/usr/bin/$EXECUTABLE"
    fi
}

fpr_args_i=0
fpm_args=()

fpm_add_arg() {
    for arg in "$@"; do
        fpm_args[$fpr_args_i]="$arg"
        ((++fpr_args_i))
    done
}

build_systemd_unit() {
    log_debug Creating systmed service unit $PRODUCT_NAME.service
    run_command mkdir -p $BUILD_DIR/root/etc/systemd/system/
    run_command mkdir -p $BUILD_DIR/root/usr/lib/systemd/system/
    cat <<EOF >> "$BUILD_DIR/root/usr/lib/systemd/system/$PRODUCT_NAME.service"
[Unit]
Description=$PRODUCT_NAME
After=network.target auditd.service

[Service]
Type=simple
ExecStart=/usr/bin/$EXECUTABLE
WorkingDirectory=$INSTALL_DIR
# Works only in systemd v240 and newer!
StandardOutput=append:/var/log/$PRODUCT_NAME/log.log
StandardError=append:/var/log/$PRODUCT_NAME/error.log

[Install]
WantedBy=multi-user.target
EOF
    fpm_add_arg --deb-systemd "$BUILD_DIR/root/usr/lib/systemd/system/$PRODUCT_NAME.service"
    fpm_add_arg --deb-systemd-auto-start
    fpm_add_arg --deb-systemd-enable
}

setup_fpm() {
    if ! command -v fpm >/dev/null 2>&1; then
        log_error "FATAL: fpm not installed."
    fi

    fpm_add_arg -f
    fpm_add_arg -s dir
    fpm_add_arg -t deb
    fpm_add_arg -n $PRODUCT_NAME
    fpm_add_arg --vendor "$VENDOR"
    fpm_add_arg --architecture $ARCH
    fpm_add_arg --maintainer "$MAINTAINER"
    fpm_add_arg --url "$URL"
    fpm_add_arg -v "$VERSION"
    run_command mkdir -p $BUILD_DIR/root/

    if [ $SYSTEMD_SERVICE = "True" ]; then
        build_systemd_unit
    fi
}

build_fpm() {
    log_debug fpm "${fpm_args[@]}" 
    run_command fpm "${fpm_args[@]}"
}

cleanup_build() {
    run_command rm -r $BUILD_DIR
}

parse_arguments $@
cleanup_build
setup_fpm
build_project
build_fpm
cleanup_build
