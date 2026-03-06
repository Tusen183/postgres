# Build Scripts

This directory contains build scripts for PostgreSQL with DocumentDB extensions.

## Scripts Overview

- **build_dependency.sh** - Install system and library dependencies
- **build.sh** - Build PostgreSQL and extensions

## build_dependency.sh

Dependency installation script for PostgreSQL with DocumentDB.

### Quick Start

```bash
# Install all dependencies
./scripts/build_dependency.sh

# Install for specific PostgreSQL version
./scripts/build_dependency.sh --pg-version 16

# Install only system packages
./scripts/build_dependency.sh --system-only

# Install only libraries
./scripts/build_dependency.sh --libs-only
```

### Usage

```
Usage: ./scripts/build_dependency.sh [OPTIONS]

OPTIONS:
    -h, --help              Show help message
    -v, --pg-version VER    PostgreSQL version (default: 16)
    -r, --root PATH         Installation root directory (default: /tmp/install_setup)
    --system-only           Install only system dependencies
    --libs-only             Install only library dependencies
```

### What Gets Installed

#### System Dependencies
- Build tools: gcc, g++, make, cmake, pkg-config
- PostgreSQL build deps: bison, flex, libreadline-dev, zlib1g-dev
- PostGIS deps: libgeos-dev, libproj-dev, libgdal-dev
- Other: git, curl, wget, openssl

#### Library Dependencies
- **libbson** - BSON library for DocumentDB
- **Intel Decimal Math Library** - High-precision decimal arithmetic
- **PCRE2** - Regular expression library
- **citus_indent** - Code formatting tool

### Examples

```bash
# Install all dependencies for PostgreSQL 16
./scripts/build_dependency.sh --pg-version 16

# Install only system packages (no libraries)
./scripts/build_dependency.sh --system-only

# Install libraries to custom location
./scripts/build_dependency.sh --root /opt/pg-deps
```

## build.sh

Main build script for compiling PostgreSQL and DocumentDB extensions.

### Quick Start

```bash
# Build everything with defaults
./scripts/build.sh

# Build with custom prefix
./scripts/build.sh --prefix $HOME/pgsql

# Debug build
./scripts/build.sh --type debug

# Clean build
./scripts/build.sh --clean
```

### Usage

```
Usage: ./scripts/build.sh [OPTIONS]

OPTIONS:
    -h, --help              Show help message
    -v, --pg-version VER    PostgreSQL version (default: 16)
    -p, --prefix PATH       Installation prefix (default: $HOME/pgsql)
    -j, --jobs NUM          Number of parallel jobs (default: nproc)
    -t, --type TYPE         Build type: release|debug (default: release)
    --clean                 Clean build (make clean before build)
    --pg-only               Build PostgreSQL only (skip extensions)
    --ext-only              Build extensions only (skip PostgreSQL)
```

### Examples

#### Build everything
```bash
./scripts/build.sh
```

#### Build with 8 parallel jobs
```bash
./scripts/build.sh --jobs 8
```

#### Debug build with custom prefix
```bash
./scripts/build.sh --type debug --prefix $HOME/pgsql-debug
```

#### Build only PostgreSQL
```bash
./scripts/build.sh --pg-only
```

#### Build only extensions (PostgreSQL already installed)
```bash
./scripts/build.sh --ext-only
```

#### Clean rebuild
```bash
./scripts/build.sh --clean
```

### Environment Variables

You can also use environment variables:

```bash
# Set PostgreSQL version
export PGVERSION=16

# Set installation prefix
export PREFIX=$HOME/pgsql

# Set number of jobs
export JOBS=8

# Set build type
export BUILD_TYPE=debug

# Run build
./scripts/build.sh
```

### What Gets Built

The script builds:

1. **PostgreSQL Core** - The main PostgreSQL database server
2. **DocumentDB** - MongoDB-compatible API for PostgreSQL
3. **pg_cron** - Job scheduler for PostgreSQL
4. **pgvector** - Vector similarity search extension
5. **rum** - RUM access method (advanced indexing)
6. **PostGIS** - Spatial database extension (if GEOS is installed)

## Complete Build Workflow

### Step 1: Install Dependencies

```bash
# Install all dependencies
./scripts/build_dependency.sh --pg-version 16
```

### Step 2: Build PostgreSQL and Extensions

```bash
# Build with custom prefix
./scripts/build_dependency.sh --prefix $HOME/pgvm/pg16-ddb/install --jobs 8
```

### Step 3: Setup Environment

```bash
# Add PostgreSQL to PATH
export PATH=$HOME/pgvm/pg16-ddb/install/bin:$PATH

# Add to ~/.bashrc for persistence
echo 'export PATH=$HOME/pgvm/pg16-ddb/install/bin:$PATH' >> ~/.bashrc
```

### Step 4: Initialize Database

```bash
# Initialize database cluster
initdb -D $HOME/pgvm/pg16-ddb/data

# Configure DocumentDB (edit postgresql.conf)
echo "shared_preload_libraries = 'pg_cron,pg_documentdb_core,pg_documentdb,pg_documentdb_extended_rum'" \
    >> $HOME/pgvm/pg16-ddb/data/postgresql.conf
```

### Step 5: Start PostgreSQL

```bash
# Start server
pg_ctl -D $HOME/pgvm/pg16-ddb/data -l logfile start

# Create database
createdb mydb

# Connect and create extension
psql mydb -c "CREATE EXTENSION documentdb CASCADE;"
```

## Troubleshooting

### Dependency Installation Issues

#### apt-get fails
```bash
# Update package lists
sudo apt-get update

# Fix broken packages
sudo apt-get install -f
```

#### Permission denied
```bash
# Run with sudo
sudo ./scripts/build_dependency.sh
```

### Build Issues

#### Configure fails
Make sure dependencies are installed:
```bash
./scripts/build_dependency.sh --system-only
```

#### Extension build fails
Make sure PostgreSQL is installed and `pg_config` is in PATH:
```bash
which pg_config
export PATH=$HOME/pgsql/bin:$PATH
```

#### PostGIS skipped
Install GEOS library:
```bash
sudo apt-get install libgeos-dev
```

#### Permission denied during install
Use a prefix you have write access to:
```bash
./scripts/build.sh --prefix $HOME/pgsql
```

## Directory Structure

```
scripts/
├── build_dependency.sh   # Dependency installation script
├── build.sh              # Main build script
└── README.md             # This file
```

## Contributing

When adding new build scripts:
1. Make them executable: `chmod +x scripts/your-script.sh`
2. Add usage documentation
3. Follow the existing error handling patterns
4. Test on clean environment
