#!/bin/sh

set -e

###############################################################################
# ImageHub installer
#
# Installs the latest official ImageHub IPK package from GitHub Releases.
#
# Usage:
#
#   wget -qO- https://raw.githubusercontent.com/pardon14/ImageHub/main/install.sh | sh
#
###############################################################################

REPOSITORY="pardon14/ImageHub"

PACKAGE_NAME="enigma2-plugin-extensions-imagehub"

TMP_DIR="/tmp/imagehub-install"

PLUGIN_DIR="/usr/lib/enigma2/python/Plugins/Extensions/ImageHub"

CONFIG_DIR="/etc/enigma2/imagehub"

CONFIG_FILE="${CONFIG_DIR}/download_location"


###############################################################################
# Helper functions
###############################################################################

log()
{
    echo "[ImageHub] $1"
}


error()
{
    echo "[ImageHub] ERROR: $1" >&2
    exit 1
}


cleanup()
{
    rm -rf "${TMP_DIR}"
}


trap cleanup EXIT INT TERM


###############################################################################
# Start
###############################################################################

echo
echo "#####################################################"
echo "#                                                   #"
echo "#              ImageHub Installer                  #"
echo "#                                                   #"
echo "#####################################################"
echo

log "Preparing installation..."


###############################################################################
# Root check
###############################################################################

if [ "$(id -u)" != "0" ]; then
    error "This installer must be run as root."
fi


###############################################################################
# Enigma2 check
###############################################################################

if [ ! -d "/usr/lib/enigma2/python/Plugins" ]; then
    error "Enigma2 plugin directory was not found."
fi


###############################################################################
# opkg check
###############################################################################

if ! command -v opkg >/dev/null 2>&1; then
    error "opkg was not found."
fi


###############################################################################
# wget check
###############################################################################

if ! command -v wget >/dev/null 2>&1; then
    error "wget was not found."
fi


###############################################################################
# Python check
#
# ImageHub requires Python 3.
###############################################################################

PYTHON_BIN=""

if [ -x "/usr/bin/python3" ]; then
    PYTHON_BIN="/usr/bin/python3"
elif [ -x "/usr/bin/python" ]; then
    PYTHON_BIN="/usr/bin/python"
fi


if [ -z "${PYTHON_BIN}" ]; then
    error "Python interpreter was not found."
fi


PYTHON_VERSION=$(
    "${PYTHON_BIN}" -c \
    'import sys; print("{}.{}".format(sys.version_info[0], sys.version_info[1]))'
)


case "${PYTHON_VERSION}" in
    3.*)
        ;;
    *)
        error "ImageHub requires Python 3. Detected: ${PYTHON_VERSION}"
        ;;
esac


log "Python: ${PYTHON_VERSION}"


###############################################################################
# Prepare temporary directory
###############################################################################

rm -rf "${TMP_DIR}"

mkdir -p "${TMP_DIR}"


RELEASE_INFO="${TMP_DIR}/release.json"


###############################################################################
# Get latest GitHub release
###############################################################################

log "Checking latest ImageHub release..."


RELEASE_API_URL="https://api.github.com/repos/${REPOSITORY}/releases/latest"


if ! wget \
    -q \
    --timeout=30 \
    --tries=2 \
    "${RELEASE_API_URL}" \
    -O "${RELEASE_INFO}"; then

    error "Failed to retrieve the latest ImageHub release information."
fi


if [ ! -s "${RELEASE_INFO}" ]; then
    error "GitHub returned an empty release response."
fi


###############################################################################
# Read release information
###############################################################################

IMAGEHUB_VERSION=$(
    "${PYTHON_BIN}" - "${RELEASE_INFO}" <<'PY'
import json
import sys

path = sys.argv[1]

with open(path, "r") as file:
    data = json.load(file)

tag = data.get("tag_name", "")

if tag.startswith("v"):
    tag = tag[1:]

if not tag:
    sys.exit(1)

print(tag)
PY
)


if [ -z "${IMAGEHUB_VERSION}" ]; then
    error "Could not determine the latest ImageHub version."
fi


PACKAGE_FILENAME="${PACKAGE_NAME}_${IMAGEHUB_VERSION}_all.ipk"

DOWNLOAD_URL="https://github.com/${REPOSITORY}/releases/download/v${IMAGEHUB_VERSION}/${PACKAGE_FILENAME}"

PACKAGE_FILE="${TMP_DIR}/${PACKAGE_FILENAME}"


log "Latest version: ${IMAGEHUB_VERSION}"

echo


###############################################################################
# Download package
###############################################################################

log "Downloading ${PACKAGE_FILENAME}..."


if ! wget \
    -q \
    --show-progress \
    --timeout=60 \
    --tries=2 \
    "${DOWNLOAD_URL}" \
    -O "${PACKAGE_FILE}"; then

    error "Failed to download ImageHub ${IMAGEHUB_VERSION}."
fi


if [ ! -s "${PACKAGE_FILE}" ]; then
    error "Downloaded ImageHub package is empty."
fi


###############################################################################
# Basic package validation
###############################################################################

log "Checking downloaded package..."


PACKAGE_SIZE=$(
    wc -c < "${PACKAGE_FILE}"
)


if [ "${PACKAGE_SIZE}" -lt 1000 ]; then
    error "Downloaded package appears to be invalid."
fi


case "${PACKAGE_FILE}" in
    *.ipk)
        ;;
    *)
        error "Downloaded file is not an IPK package."
        ;;
esac


###############################################################################
# Install package
###############################################################################

echo
log "Installing ImageHub ${IMAGEHUB_VERSION}..."
echo


if ! opkg install \
    "${PACKAGE_FILE}"; then

    error "opkg failed to install ImageHub."
fi


###############################################################################
# Installation verification
###############################################################################

echo
log "Verifying installation..."


if [ ! -d "${PLUGIN_DIR}" ]; then
    error "ImageHub plugin directory was not installed."
fi


if [ ! -f "${PLUGIN_DIR}/plugin.py" ]; then
    error "ImageHub plugin.py was not installed."
fi


if [ ! -d "${PLUGIN_DIR}/core" ]; then
    error "ImageHub core directory was not installed."
fi


if [ ! -d "${PLUGIN_DIR}/sources" ]; then
    error "ImageHub sources directory was not installed."
fi


if [ ! -d "${PLUGIN_DIR}/ui" ]; then
    error "ImageHub UI directory was not installed."
fi


###############################################################################
# Configuration verification
###############################################################################

if [ ! -d "${CONFIG_DIR}" ]; then
    error "ImageHub configuration directory was not created."
fi


if [ ! -f "${CONFIG_FILE}" ]; then
    error "ImageHub configuration file was not created."
fi


###############################################################################
# Package status verification
###############################################################################

if ! opkg status "${PACKAGE_NAME}" 2>/dev/null | grep -q \
    "Status: install ok installed"; then

    error "ImageHub package is not registered as installed."
fi


###############################################################################
# Finished
###############################################################################

echo

echo "#####################################################"
echo "#                                                   #"
echo "#          ImageHub installed successfully         #"
echo "#                                                   #"
echo "#####################################################"
echo

log "Version: ${IMAGEHUB_VERSION}"
log "Package: ${PACKAGE_NAME}"
log "Configuration: ${CONFIG_FILE}"

echo
log "Restart Enigma2 GUI to load ImageHub."
echo