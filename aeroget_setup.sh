#!/usr/bin/env bash
# =============================================================================
# AeroGet — setup.sh
# Sets up the Python venv, installs dependencies, and creates a desktop entry
# Tested on EndeavourOS / Arch-based systems
# =============================================================================

# Intentionally no set -e — individual steps handle their own failures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="AeroGet"
VENV_DIR="$SCRIPT_DIR/.venv"
DESKTOP_DIR="$HOME/.local/share/applications"
BIN_LINK="$HOME/.local/bin/aeroget"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[•]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}$*${NC}"; }

echo ""
echo -e "${CYAN}${BOLD}  ░░░ AeroGet — Setup ░░░${NC}"
echo -e "${CYAN}  Next-Generation Media Downloader${NC}"
echo ""

# ── Check Python ──────────────────────────────────────────────────────────────
header "1. Checking Python"

if ! command -v python3 &>/dev/null; then
    error "python3 not found. Install it with: sudo pacman -S python"
fi
PY_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
info "Python $PY_VERSION detected"

if ! python3 -c "import venv" &>/dev/null; then
    error "python3-venv not available. Install it with: sudo pacman -S python"
fi

# ── System dependencies ───────────────────────────────────────────────────────
header "2. System dependencies"

# yt-dlp
if command -v yt-dlp &>/dev/null; then
    success "yt-dlp already installed: $(yt-dlp --version 2>/dev/null)"
else
    info "Installing yt-dlp..."
    # Try pacman first, fall back to pip if it fails (e.g. keyring issues)
    if sudo pacman -S --noconfirm yt-dlp 2>/dev/null; then
        success "yt-dlp installed via pacman"
    else
        warn "pacman install failed (possible keyring issue). Trying pip fallback..."
        if pip install yt-dlp --break-system-packages --quiet 2>/dev/null; then
            success "yt-dlp installed via pip"
            warn "Tip: fix pacman keyring with: sudo pacman -Sy archlinux-keyring"
        else
            warn "yt-dlp could not be installed automatically."
            warn "Fix pacman with: sudo pacman -Sy archlinux-keyring && sudo pacman -S yt-dlp"
        fi
    fi
fi

# ffmpeg (required by yt-dlp for merging video+audio)
if command -v ffmpeg &>/dev/null; then
    success "ffmpeg already installed"
else
    info "Installing ffmpeg..."
    if sudo pacman -S --noconfirm ffmpeg 2>/dev/null; then
        success "ffmpeg installed"
    else
        warn "ffmpeg install failed. Try: sudo pacman -Sy archlinux-keyring && sudo pacman -S ffmpeg"
    fi
fi

# zenity (for folder picker dialog)
if command -v zenity &>/dev/null; then
    success "zenity already installed"
else
    info "Installing zenity..."
    if sudo pacman -S --noconfirm zenity 2>/dev/null; then
        success "zenity installed"
    else
        warn "zenity install failed — folder picker will fall back to ~/Downloads"
    fi
fi

# webkit2gtk (required by pywebview on Linux)
if pacman -Q webkit2gtk-4.1 &>/dev/null 2>&1 || pacman -Q webkit2gtk &>/dev/null 2>&1; then
    success "webkit2gtk already installed"
else
    info "Installing webkit2gtk-4.1 (required for pywebview)..."
    if sudo pacman -S --noconfirm webkit2gtk-4.1 2>/dev/null; then
        success "webkit2gtk-4.1 installed"
    else
        warn "webkit2gtk install failed. Try: sudo pacman -Sy archlinux-keyring && sudo pacman -S webkit2gtk-4.1"
    fi
fi

# ── Python virtual environment ────────────────────────────────────────────────
header "3. Python virtual environment"

if [ -d "$VENV_DIR" ]; then
    info "Existing venv found at $VENV_DIR"
    read -rp "$(echo -e "${CYAN}[?]${NC} Recreate venv from scratch? [y/N]: ")" RECREATE
    if [[ "$RECREATE" =~ ^[Yy]$ ]]; then
        rm -rf "$VENV_DIR"
        python3 -m venv "$VENV_DIR" --system-site-packages || error "Failed to create venv"
        success "Venv recreated"
    else
        success "Using existing venv"
    fi
else
    python3 -m venv "$VENV_DIR" --system-site-packages || error "Failed to create venv"
    success "Venv created at $VENV_DIR"
fi

# Activate
source "$VENV_DIR/bin/activate"

# Upgrade pip silently
pip install --upgrade pip --quiet

# ── Python packages ───────────────────────────────────────────────────────────
header "4. Installing Python packages"

PACKAGES=(
    "fastapi"
    "uvicorn[standard]"
    "sse-starlette"
    "pywebview"
    "qtpy"
)

for pkg in "${PACKAGES[@]}"; do
    pkg_name="${pkg%%[*}"  # strip extras like [standard]
    if pip show "$pkg_name" &>/dev/null 2>&1; then
        success "$pkg_name already installed"
    else
        info "Installing $pkg..."
        pip install "$pkg" --quiet
        success "$pkg installed"
    fi
done

# ── Verify app files ──────────────────────────────────────────────────────────
header "5. Verifying app files"

REQUIRED_FILES=(
    "main.py"
    "static/index.html"
    "static/css/styles.css"
    "static/js/script.js"
)

ALL_OK=true
for f in "${REQUIRED_FILES[@]}"; do
    if [ -f "$SCRIPT_DIR/$f" ]; then
        success "$f found"
    else
        warn "$f missing — app may not work correctly"
        ALL_OK=false
    fi
done

# Check fonts (optional but expected)
for font in "static/fonts/Outfit-Regular.woff2" "static/fonts/Outfit-SemiBold.woff2" "static/fonts/Outfit-ExtraBold.woff2"; do
    if [ ! -f "$SCRIPT_DIR/$font" ]; then
        warn "Font missing: $font — UI will fall back to system sans-serif"
    fi
done

# Make launch.sh executable
if [ -f "$SCRIPT_DIR/launch.sh" ]; then
    chmod +x "$SCRIPT_DIR/launch.sh"
    success "launch.sh is executable"
fi

# ── Desktop entry ─────────────────────────────────────────────────────────────
header "6. Desktop entry"

mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/aeroget.desktop" << EOF
[Desktop Entry]
Name=AeroGet
Comment=Next-Generation Media Downloader
Exec=bash $SCRIPT_DIR/launch.sh
Icon=folder-download
Terminal=false
Type=Application
Categories=AudioVideo;Network;
Keywords=download;youtube;video;audio;yt-dlp;
EOF
success "Desktop entry written to $DESKTOP_DIR/aeroget.desktop"

# ── Launcher symlink ──────────────────────────────────────────────────────────
header "7. Launcher symlink"

mkdir -p "$HOME/.local/bin"
cat > "$BIN_LINK" << EOF
#!/usr/bin/env bash
exec bash "$SCRIPT_DIR/launch.sh" "\$@"
EOF
chmod +x "$BIN_LINK"
success "Launcher: $BIN_LINK"

if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    warn "~/.local/bin is not in your PATH."
    echo "    Add this to ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ── Shell alias ───────────────────────────────────────────────────────────────
header "8. Shell alias"

ALIAS_LINE="alias aeroget='bash $SCRIPT_DIR/launch.sh'"
ZSHRC="$HOME/.zshrc"
BASHRC="$HOME/.bashrc"

_add_alias() {
    local rc_file="$1"
    if [ -f "$rc_file" ]; then
        if grep -q "alias aeroget=" "$rc_file"; then
            info "alias aeroget already in $rc_file"
        else
            echo "" >> "$rc_file"
            echo "# AeroGet launcher" >> "$rc_file"
            echo "$ALIAS_LINE" >> "$rc_file"
            success "Added alias to $rc_file"
        fi
    fi
}

_add_alias "$ZSHRC"
_add_alias "$BASHRC"

# Source for current session hint
echo -e "    Run ${CYAN}source ~/.zshrc${NC} (or open a new terminal) to use the alias."

# ── Quick dependency test ─────────────────────────────────────────────────────
header "9. Sanity check"

source "$VENV_DIR/bin/activate"
python3 - <<'PYCHECK'
errors = []
try: import fastapi
except ImportError: errors.append("fastapi")
try: import uvicorn
except ImportError: errors.append("uvicorn")
try: import sse_starlette
except ImportError: errors.append("sse-starlette")
try: import webview
except ImportError: errors.append("pywebview")

if errors:
    print(f"  MISSING: {', '.join(errors)}")
else:
    print("  All Python packages OK")
PYCHECK

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✓ Setup complete!${NC}"
echo ""
echo -e "  Launch:     ${CYAN}bash $SCRIPT_DIR/launch.sh${NC}"
echo -e "  Or run:     ${CYAN}aeroget${NC}  (if ~/.local/bin is in PATH)"
echo -e "  Or search for 'AeroGet' in your app launcher"
echo ""
echo -e "  ${YELLOW}Note:${NC} Font files (Outfit-*.woff2) should be placed in ${CYAN}$SCRIPT_DIR/static/fonts/${NC}"
echo ""
