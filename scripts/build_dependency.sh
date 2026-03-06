#!/bin/bash

# Build dependencies for PostgreSQL with DocumentDB
# This script installs system dependencies and DocumentDB-specific libraries

set -e
set -u

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
PG_VERSION=${PGVERSION:-16}
INSTALL_ROOT=${INSTALL_ROOT:-/tmp/install_setup}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCUMENTDB_SCRIPTS="$PROJECT_ROOT/contrib/documentdb/scripts"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install dependencies for PostgreSQL with DocumentDB

OPTIONS:
    -h, --help              Show this help message
    -v, --pg-version VER    PostgreSQL version (default: $PG_VERSION)
    -r, --root PATH         Installation root directory (default: $INSTALL_ROOT)
    --system-only           Install only system dependencies
    --libs-only             Install only library dependencies

EXAMPLES:
    # Install all dependencies
    $0

    # Install for PostgreSQL 16
    $0 --pg-version 16

    # Install only system packages
    $0 --system-only

    # Install only libraries
    $0 --libs-only

ENVIRONMENT VARIABLES:
    PGVERSION               PostgreSQL version (default: 16)
    INSTALL_ROOT            Installation root directory

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
SYSTEM_ONLY=0
LIBS_ONLY=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -v|--pg-version)
            PG_VERSION="$2"
            shift 2
            ;;
        -r|--root)
            INSTALL_ROOT="$2"
            shift 2
            ;;
        --system-only)
            SYSTEM_ONLY=1
            shift
            ;;
        --libs-only)
            LIBS_ONLY=1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Export environment
export PGVERSION=$PG_VERSION
export INSTALL_DEPENDENCIES_ROOT=$INSTALL_ROOT
export LC_ALL=en_US.UTF-8
export LANGUAGE=en_US
export LC_COLLATE=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export LANG=en_US.UTF-8

log_info "Dependency Installation Configuration:"
log_info "  PostgreSQL Version: $PG_VERSION"
log_info "  Installation Root: $INSTALL_ROOT"
log_info "  DocumentDB Scripts: $DOCUMENTDB_SCRIPTS"

# Install system dependencies
install_system_deps() {
    log_info "Installing system dependencies..."

    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        wget \
        curl \
        sudo \
        gnupg2 \
        lsb-release \
        tzdata \
        build-essential \
        pkg-config \
        cmake \
        git \
        locales \
        gcc \
        gdb \
        libipc-run-perl \
        unzip \
        apt-transport-https \
        bison \
        flex \
        libreadline-dev \
        zlib1g-dev \
        libkrb5-dev \
        software-properties-common \
        libtool \
        libicu-dev \
        libssl-dev \
        openssl

    log_info "Generating locale..."
    sudo locale-gen en_US.UTF-8

    log_info "Installing PostGIS dependencies..."
    sudo apt-get install -qy \
        libproj-dev \
        libxml2-dev \
        libjson-c-dev \
        libgdal-dev \
        libgeos++-dev \
        libgeos-dev \
        libprotobuf-c-dev \
        protobuf-c-compiler

    log_info "Installing PostGIS documentation tools..."
    sudo apt-get install -qy \
        xsltproc \
        docbook-xsl \
        docbook-xml \
        libxml2-utils

    log_info "System dependencies installed successfully!"
}

# Install library dependencies
install_lib_deps() {
    log_info "Installing library dependencies..."

    mkdir -p "$INSTALL_ROOT"

    # Copy setup scripts
    log_info "Setting up installation scripts..."
    cp "$DOCUMENTDB_SCRIPTS/setup_versions.sh" "$INSTALL_ROOT/"
    cp "$DOCUMENTDB_SCRIPTS/utils.sh" "$INSTALL_ROOT/"

    # Install libbson
    log_info "Installing libbson..."
    cp "$DOCUMENTDB_SCRIPTS/install_setup_libbson.sh" "$INSTALL_ROOT/"
    sudo INSTALL_DEPENDENCIES_ROOT=$INSTALL_ROOT MAKE_PROGRAM=cmake \
        "$INSTALL_ROOT/install_setup_libbson.sh"

    # Install Intel Decimal Math Library
    log_info "Installing Intel Decimal Math Library..."
    cp "$DOCUMENTDB_SCRIPTS/install_setup_intel_decimal_math_lib.sh" "$INSTALL_ROOT/"
    sudo INSTALL_DEPENDENCIES_ROOT=$INSTALL_ROOT \
        "$INSTALL_ROOT/install_setup_intel_decimal_math_lib.sh"

    # Install PCRE2
    log_info "Installing PCRE2..."
    cp "$DOCUMENTDB_SCRIPTS/install_setup_pcre2.sh" "$INSTALL_ROOT/"
    sudo INSTALL_DEPENDENCIES_ROOT=$INSTALL_ROOT \
        "$INSTALL_ROOT/install_setup_pcre2.sh"

    # Install citus_indent
    log_info "Installing citus_indent..."
    cp "$DOCUMENTDB_SCRIPTS/install_citus_indent.sh" "$INSTALL_ROOT/"
    sudo INSTALL_DEPENDENCIES_ROOT=$INSTALL_ROOT \
        "$INSTALL_ROOT/install_citus_indent.sh"

    log_info "Library dependencies installed successfully!"
}

# Main installation process
main() {
    log_info "Starting dependency installation..."

    if [ ! -d "$DOCUMENTDB_SCRIPTS" ]; then
        log_error "DocumentDB scripts directory not found: $DOCUMENTDB_SCRIPTS"
        log_error "Please ensure DocumentDB is cloned in contrib/documentdb"
        exit 1
    fi

    if [ $LIBS_ONLY -eq 0 ]; then
        install_system_deps
    fi

    if [ $SYSTEM_ONLY -eq 0 ]; then
        install_lib_deps
    fi

    log_info "========================================="
    log_info "Dependency installation completed!"
    log_info "========================================="
    log_info "Installation root: $INSTALL_ROOT"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Run ./scripts/build.sh to build PostgreSQL and extensions"
    log_info "  2. Initialize database with initdb"
    log_info "  3. Configure postgresql.conf for DocumentDB"
}

# Run main
main
