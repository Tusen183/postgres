#!/bin/bash

# Build script for PostgreSQL with DocumentDB
# This script builds PostgreSQL and DocumentDB extensions

set -e
set -u

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
PG_VERSION=${PGVERSION:-16}
PREFIX=${PREFIX:-$HOME/pgsql}
JOBS=${JOBS:-$(nproc)}
BUILD_TYPE=${BUILD_TYPE:-release}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build PostgreSQL with DocumentDB extensions

OPTIONS:
    -h, --help              Show this help message
    -v, --pg-version VER    PostgreSQL version (default: $PG_VERSION)
    -p, --prefix PATH       Installation prefix (default: $PREFIX)
    -j, --jobs NUM          Number of parallel jobs (default: $JOBS)
    -t, --type TYPE         Build type: release|debug (default: $BUILD_TYPE)
    --clean                 Clean build (make clean before build)
    --pg-only               Build PostgreSQL only (skip extensions)
    --ext-only              Build extensions only (skip PostgreSQL)

EXAMPLES:
    # Build everything with defaults
    $0

    # Build with custom prefix and 8 jobs
    $0 --prefix /opt/pgsql --jobs 8

    # Debug build
    $0 --type debug

    # Clean build
    $0 --clean

    # Build only PostgreSQL
    $0 --pg-only

    # Build only extensions
    $0 --ext-only

ENVIRONMENT VARIABLES:
    PGVERSION               PostgreSQL version (default: 16)
    PREFIX                  Installation prefix
    JOBS                    Number of parallel jobs
    BUILD_TYPE              Build type (release|debug)

EOF
    exit 0
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
CLEAN_BUILD=0
PG_ONLY=0
EXT_ONLY=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -v|--pg-version)
            PG_VERSION="$2"
            shift 2
            ;;
        -p|--prefix)
            PREFIX="$2"
            shift 2
            ;;
        -j|--jobs)
            JOBS="$2"
            shift 2
            ;;
        -t|--type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=1
            shift
            ;;
        --pg-only)
            PG_ONLY=1
            shift
            ;;
        --ext-only)
            EXT_ONLY=1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate build type
if [[ "$BUILD_TYPE" != "release" && "$BUILD_TYPE" != "debug" ]]; then
    log_error "Invalid build type: $BUILD_TYPE (must be 'release' or 'debug')"
    exit 1
fi

# Export environment
export PGVERSION=$PG_VERSION
export PATH="$PREFIX/bin:$PATH"

log_info "Build Configuration:"
log_info "  PostgreSQL Version: $PG_VERSION"
log_info "  Installation Prefix: $PREFIX"
log_info "  Parallel Jobs: $JOBS"
log_info "  Build Type: $BUILD_TYPE"
log_info "  Project Root: $PROJECT_ROOT"

# Build PostgreSQL
build_postgres() {
    log_info "Building PostgreSQL..."

    cd "$PROJECT_ROOT"

    if [ $CLEAN_BUILD -eq 1 ]; then
        log_info "Cleaning previous build..."
        make clean || true
    fi

    # Configure if needed
    if [ ! -f "GNUmakefile" ] || [ $CLEAN_BUILD -eq 1 ]; then
        log_info "Configuring PostgreSQL..."

        CONFIGURE_OPTS="--prefix=$PREFIX"

        if [ "$BUILD_TYPE" = "debug" ]; then
            CONFIGURE_OPTS="$CONFIGURE_OPTS --enable-debug --enable-cassert CFLAGS='-O0 -g3'"
        else
            CONFIGURE_OPTS="$CONFIGURE_OPTS CFLAGS='-O2'"
        fi

        ./configure $CONFIGURE_OPTS
    fi

    log_info "Compiling PostgreSQL with $JOBS jobs..."
    make -j$JOBS

    log_info "Installing PostgreSQL..."
    make install

    log_info "PostgreSQL build completed!"
}

# Build DocumentDB and extensions
build_extensions() {
    log_info "Building contrib extensions..."

    cd "$PROJECT_ROOT"

    if [ $CLEAN_BUILD -eq 1 ]; then
        log_info "Cleaning contrib extensions..."
        make -C contrib clean || true
    fi

    log_info "Building and installing all contrib extensions (except PostGIS)..."
    make -C contrib -j$JOBS
    make -C contrib install

    log_info "All contrib extensions build completed!"

    if [ -d "$PROJECT_ROOT/contrib/postgis" ]; then
        if ! command -v geos-config &> /dev/null; then
            log_warn "PostGIS requires GEOS library (geos-config not found), skipping..."
            log_warn "To install GEOS: sudo apt-get install libgeos-dev (Debian/Ubuntu) or sudo yum install geos-devel (RHEL/CentOS)"
        else
            log_info "Building PostGIS..."
            cd "$PROJECT_ROOT/contrib/postgis"

            if [ $CLEAN_BUILD -eq 1 ]; then
                log_info "Cleaning PostGIS..."
                make distclean || true
            fi

            if [ ! -f "configure" ]; then
                log_info "Running PostGIS autogen..."
                ./autogen.sh
            fi

            log_info "Configuring PostGIS..."
            ./configure \
                --prefix="$PREFIX" \
                --with-pgconfig="$PREFIX/bin/pg_config"

            log_info "Creating placeholder comment files for PostGIS..."
            mkdir -p doc
            for comment_file in postgis_comments.sql raster_comments.sql topology_comments.sql sfcgal_comments.sql tiger_geocoder_comments.sql; do
                if [ ! -f "doc/$comment_file" ]; then
                    echo "-- PostGIS comments placeholder" > "doc/$comment_file"
                    echo "-- This file is generated during documentation build" >> "doc/$comment_file"
                fi
            done

            log_info "Compiling PostGIS..."
            make -j$JOBS
            make install

            log_info "Installing PostGIS extension files..."
            make -C extensions install

            log_info "PostGIS build completed!"
        fi
    else
        log_warn "PostGIS directory not found, skipping..."
    fi
}

# Main build process
main() {
    log_info "Starting build process..."

    if [ $EXT_ONLY -eq 0 ]; then
        build_postgres
    fi

    if [ $PG_ONLY -eq 0 ]; then
        build_extensions
    fi

    log_info "========================================="
    log_info "Build completed successfully!"
    log_info "========================================="
    log_info "PostgreSQL installed to: $PREFIX"
    log_info "Add to PATH: export PATH=$PREFIX/bin:\$PATH"
    log_info ""
    log_info "To initialize database:"
    log_info "  initdb -D /path/to/data"
    log_info ""
    log_info "To start PostgreSQL:"
    log_info "  pg_ctl -D /path/to/data -l logfile start"
}

# Run main
main
