#!/bin/bash
set -euo pipefail

# --- Paths ---
WORK_DIR="${BAYMAX_HOME:-/opt/tremor_detector}"
VENV_DIR="$WORK_DIR/hw"
MAIN_SCRIPT="acquisition_no_int_w_log.py"
KNOWN_GOOD_DIR="$WORK_DIR/known_good"
CHECKSUM_FILE="$KNOWN_GOOD_DIR/checksums.sha256"
PUBLIC_KEY="$WORK_DIR/public_key.pem"
RELEASE_ARCHIVE="$WORK_DIR/release.tar.gz"
RELEASE_SIG="$WORK_DIR/release.tar.gz.sig"
PY_FILES=(
    "acquisition_no_int_w_log.py"
    "mqtt_client.py"
    "device_logger.py"
    "fft_analysis.py"
)

# --- Move to working directory ---
if [ "$PWD" != "$WORK_DIR" ]; then
    echo "Changing to $WORK_DIR"
    cd "$WORK_DIR"
fi

# --- Activate virtual environment if not already active ---
if [ "${VIRTUAL_ENV:-}" != "$VENV_DIR" ]; then
    echo "Activating virtual environment: $VENV_DIR"
    source "$VENV_DIR/bin/activate"
fi

# --- Verify archive signature ---
verify_archive_signature() {
    if [ ! -f "$PUBLIC_KEY" ]; then
        echo "ERROR: Public key missing: $PUBLIC_KEY" >&2
        return 1
    fi
    if [ ! -f "$RELEASE_ARCHIVE" ]; then
        echo "ERROR: Release archive missing: $RELEASE_ARCHIVE" >&2
        return 1
    fi
    if [ ! -f "$RELEASE_SIG" ]; then
        echo "ERROR: Signature missing: $RELEASE_SIG" >&2
        return 1
    fi

    echo "Verifying archive signature..."
    if openssl dgst -sha256 -verify "$PUBLIC_KEY" -signature "$RELEASE_SIG" "$RELEASE_ARCHIVE" > /dev/null 2>&1; then
        echo "  OK: release.tar.gz signature valid"
        return 0
    else
        echo "  FAIL: invalid or forged signature" >&2
        return 1
    fi
}

# --- Promote current files to known good (no signature check) ---
promote() {
    echo "Promoting current files to known good..."
    mkdir -p "$KNOWN_GOOD_DIR"
    for f in "${PY_FILES[@]}"; do
        cp "$WORK_DIR/$f" "$KNOWN_GOOD_DIR/$f"
        echo "  Copied: $f"
    done
    cd "$KNOWN_GOOD_DIR"
    sha256sum "${PY_FILES[@]}" > checksums.sha256
    cd "$WORK_DIR"
    echo "Checksums updated. Known good is now:"
    cat "$CHECKSUM_FILE"
}

# --- Verify archive signature, extract, then promote ---
signed_promote() {
    if ! verify_archive_signature; then
        echo "ERROR: Archive signature invalid — promote aborted" >&2
        exit 1
    fi

    echo "Extracting release archive..."
    tar xzf "$RELEASE_ARCHIVE" -C "$WORK_DIR"

    promote
}

# --- Rollback to known good ---
rollback() {
    echo "WARNING: Rolling back to known good version..." >&2
    for f in "${PY_FILES[@]}"; do
        if [ -f "$KNOWN_GOOD_DIR/$f" ]; then
            cp "$KNOWN_GOOD_DIR/$f" "$WORK_DIR/$f"
            echo "  Restored: $f"
        else
            echo "  ERROR: No known good copy of $f found" >&2
        fi
    done
}

# --- Integrity check ---
check_integrity() {
    local failed=0

    # 1. SHA256 hash check — verify files match known good checksums
    if [ ! -f "$CHECKSUM_FILE" ]; then
        echo "ERROR: Checksum file missing: $CHECKSUM_FILE" >&2
        failed=1
    else
        echo "Checking SHA256 hashes..."
        if ! sha256sum --check "$CHECKSUM_FILE" --quiet 2>&1; then
            echo "ERROR: SHA256 mismatch — files may have been tampered with" >&2
            failed=1
        fi
    fi

    # 2. Python syntax check — verify files are not corrupted
    echo "Checking Python syntax..."
    for f in "${PY_FILES[@]}"; do
        if ! python3 -m py_compile "$f" 2>&1; then
            echo "ERROR: Syntax error in $f" >&2
            failed=1
        fi
    done

    [ $failed -eq 0 ] && echo "Integrity check passed" && return 0 || return 1
}

# --- Handle arguments ---
case "${1:-}" in
    promote)
        promote
        exit 0
        ;;
    signed_promote)
        signed_promote
        exit 0
        ;;
    *)
        ;;
esac

# --- Run integrity check ---
if ! check_integrity; then
    echo "ERROR: Integrity check failed — attempting rollback" >&2
    rollback
    echo "Re-checking integrity after rollback..."
    if ! check_integrity; then
        echo "ERROR: Rollback failed integrity check — aborting" >&2
        exit 1
    fi
    echo "Rollback successful — continuing with known good version"
fi

# --- Run ---
echo "Starting $MAIN_SCRIPT"
python3 "$MAIN_SCRIPT"