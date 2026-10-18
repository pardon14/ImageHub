#!/bin/sh
set -eu

###############################################################################
# ImageHub installer
# Installs the latest published ImageHub IPK from GitHub Releases.
# Usage:
#   wget -qO- https://raw.githubusercontent.com/pardon14/ImageHub/master/install.sh | sh
###############################################################################

REPOSITORY="pardon14/ImageHub"
PACKAGE_NAME="enigma2-plugin-extensions-imagehub"
TMP_DIR="/tmp/imagehub-install-$$"
PLUGIN_DIR="/usr/lib/enigma2/python/Plugins/Extensions/ImageHub"
CONFIG_DIR="/etc/enigma2/imagehub"
CONFIG_FILE="${CONFIG_DIR}/download_location"

log() { echo "[ImageHub] $*"; }
error() { echo "[ImageHub] ERROR: $*" >&2; exit 1; }
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT HUP INT TERM

printf '\n'
echo "#####################################################"
echo "#                                                   #"
echo "#              ImageHub Installer                  #"
echo "#                                                   #"
echo "#####################################################"
printf '\n'

log "Preparing installation..."

[ "$(id -u)" = "0" ] || error "This installer must be run as root."
[ -d "/usr/lib/enigma2/python/Plugins" ] || error "Enigma2 plugin directory was not found."
command -v opkg >/dev/null 2>&1 || error "opkg was not found."
command -v wget >/dev/null 2>&1 || error "wget was not found."

PYTHON_BIN=""
if [ -x /usr/bin/python3 ]; then
    PYTHON_BIN=/usr/bin/python3
elif [ -x /usr/bin/python ]; then
    PYTHON_BIN=/usr/bin/python
fi
[ -n "$PYTHON_BIN" ] || error "Python interpreter was not found."

PYTHON_VERSION=$("$PYTHON_BIN" -c 'import sys; print("{}.{}".format(sys.version_info[0], sys.version_info[1]))')
case "$PYTHON_VERSION" in
    3.*) ;;
    *) error "ImageHub requires Python 3. Detected: ${PYTHON_VERSION}" ;;
esac
log "Python: ${PYTHON_VERSION}"

mkdir -p "$TMP_DIR"
RELEASE_INFO="$TMP_DIR/release.json"
ASSET_INFO="$TMP_DIR/asset.txt"

log "Checking latest ImageHub release..."
RELEASE_API_URL="https://api.github.com/repos/${REPOSITORY}/releases/latest"
if ! wget -q --timeout=30 --tries=2 "$RELEASE_API_URL" -O "$RELEASE_INFO"; then
    error "Failed to retrieve the latest ImageHub release information."
fi
[ -s "$RELEASE_INFO" ] || error "GitHub returned an empty release response."

# Read the actual release tag and IPK asset URL from GitHub's API.
# This avoids assuming that release tags always start with 'v'.
if ! "$PYTHON_BIN" - "$RELEASE_INFO" "$PACKAGE_NAME" > "$ASSET_INFO" <<'PY'
import json
import sys

path, package_name = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

if data.get("message"):
    raise SystemExit("GitHub API error: {}".format(data["message"]))

tag = data.get("tag_name", "")
assets = data.get("assets", [])

matches = [
    asset for asset in assets
    if asset.get("name", "").startswith(package_name + "_")
    and asset.get("name", "").endswith(".ipk")
    and asset.get("browser_download_url")
]
if not tag:
    raise SystemExit("Release tag was not found.")
if len(matches) != 1:
    names = [asset.get("name", "") for asset in assets]
    raise SystemExit(
        "Expected exactly one {}_*.ipk asset in the latest release; found {}. Assets: {}".format(
            package_name, len(matches), ", ".join(names) if names else "none"
        )
    )

asset = matches[0]
print(tag)
print(asset["name"])
print(asset["browser_download_url"])
PY
then
    error "Could not identify the ImageHub release and IPK asset. Ensure the latest GitHub Release contains exactly one ${PACKAGE_NAME}_*.ipk asset."
fi

IMAGEHUB_VERSION=$(sed -n '1p' "$ASSET_INFO")
PACKAGE_FILENAME=$(sed -n '2p' "$ASSET_INFO")
DOWNLOAD_URL=$(sed -n '3p' "$ASSET_INFO")
[ -n "$IMAGEHUB_VERSION" ] || error "Could not determine the ImageHub release tag."
[ -n "$PACKAGE_FILENAME" ] || error "Could not determine the IPK filename."
[ -n "$DOWNLOAD_URL" ] || error "Could not determine the IPK download URL."

PACKAGE_FILE="$TMP_DIR/$PACKAGE_FILENAME"
log "Latest release: ${IMAGEHUB_VERSION}"
log "Package: ${PACKAGE_FILENAME}"
log "Downloading package..."

if ! wget -q --timeout=60 --tries=2 "$DOWNLOAD_URL" -O "$PACKAGE_FILE"; then
    error "Failed to download ${PACKAGE_FILENAME}."
fi
[ -s "$PACKAGE_FILE" ] || error "Downloaded ImageHub package is empty."
PACKAGE_SIZE=$(wc -c < "$PACKAGE_FILE" | tr -d ' ')
[ "$PACKAGE_SIZE" -ge 1000 ] || error "Downloaded package is too small to be a valid IPK."

# If a matching .sha256 asset is attached to the release, verify it.
# The checksum asset should be named exactly: <IPK filename>.sha256
CHECKSUM_URL=$("$PYTHON_BIN" - "$RELEASE_INFO" "$PACKAGE_FILENAME" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
expected = sys.argv[2] + ".sha256"
for asset in data.get("assets", []):
    if asset.get("name") == expected and asset.get("browser_download_url"):
        print(asset["browser_download_url"])
        break
PY
)

if [ -n "$CHECKSUM_URL" ]; then
    CHECKSUM_FILE="$TMP_DIR/${PACKAGE_FILENAME}.sha256"
    log "Downloading SHA-256 checksum..."
    wget -q --timeout=30 --tries=2 "$CHECKSUM_URL" -O "$CHECKSUM_FILE" || error "Failed to download checksum file."
    EXPECTED_SHA=$(awk 'NR == 1 {print $1}' "$CHECKSUM_FILE")
    [ -n "$EXPECTED_SHA" ] || error "Checksum file is empty or invalid."
    ACTUAL_SHA=$("$PYTHON_BIN" - "$PACKAGE_FILE" <<'PY'
import hashlib
import sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
)
    [ "$EXPECTED_SHA" = "$ACTUAL_SHA" ] || error "SHA-256 checksum mismatch. Aborting installation."
    log "SHA-256 checksum verified."
else
    log "No SHA-256 asset found; continuing with basic package validation."
fi

printf '\n'
log "Installing ImageHub ${IMAGEHUB_VERSION}..."
if ! opkg install "$PACKAGE_FILE"; then
    error "opkg failed to install ImageHub."
fi

printf '\n'
log "Verifying installation..."
[ -d "$PLUGIN_DIR" ] || error "ImageHub plugin directory was not installed."
[ -f "$PLUGIN_DIR/plugin.py" ] || error "ImageHub plugin.py was not installed."
[ -d "$PLUGIN_DIR/core" ] || error "ImageHub core directory was not installed."
[ -d "$PLUGIN_DIR/sources" ] || error "ImageHub sources directory was not installed."
[ -d "$PLUGIN_DIR/ui" ] || error "ImageHub UI directory was not installed."
[ -d "$CONFIG_DIR" ] || error "ImageHub configuration directory was not created."
[ -f "$CONFIG_FILE" ] || error "ImageHub configuration file was not created."

if ! opkg status "$PACKAGE_NAME" 2>/dev/null | grep -q "Status: install ok installed"; then
    error "ImageHub package is not registered as installed."
fi

printf '\n'
echo "#####################################################"
echo "#                                                   #"
echo "#          ImageHub installed successfully         #"
echo "#                                                   #"
echo "#####################################################"
printf '\n'
log "Version: ${IMAGEHUB_VERSION}"
log "Package: ${PACKAGE_NAME}"
log "Configuration: ${CONFIG_FILE}"
log "Restart Enigma2 GUI to load ImageHub."
printf '\n'