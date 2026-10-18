
#!/bin/sh
set -eu

###############################################################################
# ImageHub installer
# Installs the latest published ImageHub IPK from GitHub Releases.
#
# Usage:
# wget -qO- https://raw.githubusercontent.com/pardon14/ImageHub/master/install.sh | sh
###############################################################################

REPOSITORY="pardon14/ImageHub"
PACKAGE_NAME="enigma2-plugin-extensions-imagehub"
TMP_DIR="/tmp/imagehub-install-$$"

PLUGIN_DIR="/usr/lib/enigma2/python/Plugins/Extensions/ImageHub"
CONFIG_DIR="/etc/enigma2/imagehub"
CONFIG_FILE="${CONFIG_DIR}/download_location"

log() {
    echo "[ImageHub] $*"
}

error() {
    echo "[ImageHub] ERROR: $*" >&2
    exit 1
}

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT HUP INT TERM

echo
echo "#####################################################"
echo "#                                                   #"
echo "#              ImageHub Installer                  #"
echo "#                                                   #"
echo "#####################################################"
echo

log "Preparing installation..."

# Environment checks

[ "$(id -u)" = "0" ] || error "This installer must be run as root."

[ -d "/usr/lib/enigma2/python/Plugins" ] ||
    error "Enigma2 plugin directory was not found."

command -v opkg >/dev/null 2>&1 ||
    error "opkg was not found."

command -v wget >/dev/null 2>&1 ||
    error "wget was not found."

PYTHON_BIN=""

if [ -x "/usr/bin/python3" ]; then
    PYTHON_BIN="/usr/bin/python3"
elif [ -x "/usr/bin/python" ]; then
    PYTHON_BIN="/usr/bin/python"
fi

[ -n "$PYTHON_BIN" ] || error "Python interpreter was not found."

PYTHON_VERSION=$(
    "$PYTHON_BIN" -c \
    'import sys; print("{}.{}".format(sys.version_info[0], sys.version_info[1]))'
)

case "$PYTHON_VERSION" in
    3.*) ;;
    *) error "ImageHub requires Python 3. Detected: $PYTHON_VERSION" ;;
esac

log "Python: $PYTHON_VERSION"

# Prepare temporary directory

mkdir -p "$TMP_DIR"

RELEASE_INFO="$TMP_DIR/release.json"
ASSET_INFO="$TMP_DIR/asset.txt"

# Get latest GitHub release

log "Checking latest ImageHub release..."

RELEASE_API_URL="https://api.github.com/repos/${REPOSITORY}/releases/latest"

if ! wget -q --timeout=30 --tries=2 \
    "$RELEASE_API_URL" -O "$RELEASE_INFO"; then
    error "Failed to retrieve the latest ImageHub release information."
fi

[ -s "$RELEASE_INFO" ] ||
    error "GitHub returned an empty release response."

# Find IPK asset and release tag

if ! "$PYTHON_BIN" - "$RELEASE_INFO" "$PACKAGE_NAME" \
    > "$ASSET_INFO" <<'PY'
import json
import sys

path, package_name = sys.argv[1], sys.argv[2]

try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception as exc:
    raise SystemExit("Cannot read GitHub release JSON: {}".format(exc))

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
        "Expected exactly one {}_*.ipk asset; found {}. Assets: {}".format(
            package_name,
            len(matches),
            ", ".join(names) if names else "none"
        )
    )

asset = matches[0]

print(tag)
print(asset["name"])
print(asset["browser_download_url"])
PY
then
    error "Could not identify the release and IPK asset. Check GitHub Releases."
fi

IMAGEHUB_VERSION=$(sed -n '1p' "$ASSET_INFO")
PACKAGE_FILENAME=$(sed -n '2p' "$ASSET_INFO")
DOWNLOAD_URL=$(sed -n '3p' "$ASSET_INFO")

[ -n "$IMAGEHUB_VERSION" ] ||
    error "Could not determine the ImageHub release tag."

[ -n "$PACKAGE_FILENAME" ] ||
    error "Could not determine the IPK filename."

[ -n "$DOWNLOAD_URL" ] ||
    error "Could not determine the IPK download URL."

PACKAGE_FILE="$TMP_DIR/$PACKAGE_FILENAME"

log "Latest release: $IMAGEHUB_VERSION"
log "Package: $PACKAGE_FILENAME"

# Download package

log "Downloading package..."

if ! wget -q --timeout=60 --tries=2 \
    "$DOWNLOAD_URL" -O "$PACKAGE_FILE"; then
    error "Failed to download $PACKAGE_FILENAME."
fi

[ -s "$PACKAGE_FILE" ] ||
    error "Downloaded ImageHub package is empty."

PACKAGE_SIZE=$(wc -c < "$PACKAGE_FILE" | tr -d ' ')

[ "$PACKAGE_SIZE" -ge 1000 ] ||
    error "Downloaded package is too small to be a valid IPK."

# Install package

echo
log "Installing ImageHub $IMAGEHUB_VERSION..."
echo

if ! opkg install "$PACKAGE_FILE"; then
    error "opkg failed to install ImageHub."
fi

# Installation verification

echo
log "Verifying installation..."

[ -d "$PLUGIN_DIR" ] ||
    error "ImageHub plugin directory was not installed."

[ -f "$PLUGIN_DIR/plugin.py" ] ||
    error "ImageHub plugin.py was not installed."

[ -f "$PLUGIN_DIR/main.py" ] ||
    error "ImageHub main.py was not installed."

[ -d "$PLUGIN_DIR/backend/core" ] ||
    error "ImageHub backend/core directory was not installed."

[ -d "$PLUGIN_DIR/backend/sources" ] ||
    error "ImageHub backend/sources directory was not installed."

[ -d "$PLUGIN_DIR/backend/config" ] ||
    error "ImageHub backend/config directory was not installed."

[ -d "$PLUGIN_DIR/icons" ] ||
    error "ImageHub icons directory was not installed."

[ -d "$PLUGIN_DIR/logos" ] ||
    error "ImageHub logos directory was not installed."

[ -f "$CONFIG_FILE" ] ||
    error "ImageHub configuration file was not installed."

# Package status verification

if ! opkg status "$PACKAGE_NAME" 2>/dev/null |
    grep -q "Status: install ok installed"; then
    error "ImageHub package is not registered as installed."
fi

# Finished

echo
echo "#####################################################"
echo "#                                                   #"
echo "#          ImageHub installed successfully         #"
echo "#                                                   #"
echo "#####################################################"
echo

log "Version: $IMAGEHUB_VERSION"
log "Package: $PACKAGE_NAME"
log "Configuration: $CONFIG_FILE"
log "Restart Enigma2 GUI to load ImageHub."

echo