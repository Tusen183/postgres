# Configuration File Setup Functions

This document describes the implementation of `setup_postgresql_conf()` and `setup_pg_hba_conf()` functions for task 9.3.

## Overview

These functions modify PostgreSQL configuration files after `initdb` has created the database cluster:

- **setup_postgresql_conf()**: Modifies `postgresql.conf` to set network and connection parameters
- **setup_pg_hba_conf()**: Modifies `pg_hba.conf` to set authentication rules

## Requirements

These functions implement requirements:
- **4.6**: Write listen_addresses and port to postgresql.conf
- **5.3**: Modify authentication rules in pg_hba.conf  
- **5.4**: Configure authentication for local and host connections

## Function: setup_postgresql_conf()

### Purpose
Modifies `postgresql.conf` to configure network and connection settings.

### Parameters Modified
1. **listen_addresses**: Controls which network interfaces the server listens on
   - Default: 'localhost'
   - Can be set to specific IP addresses, '*', or '0.0.0.0'

2. **port**: The TCP port number for the server
   - Default: 5432
   - Valid range: 1024-65535

3. **max_connections**: Maximum number of concurrent connections
   - Default: 100
   - Can be adjusted based on profile (development: 20, test: 10)

### Implementation Details

The function:
1. Opens the existing `postgresql.conf` file created by initdb
2. Reads the file line by line
3. Identifies lines containing the target parameters (even if commented out)
4. Replaces those lines with uncommented, configured values
5. Appends any missing parameters at the end of the file
6. Writes to a temporary file and then renames it to replace the original

### Example Transformation

**Before:**
```
#listen_addresses = 'localhost'		# what IP address(es) to listen on;
#port = 5432				# (change requires restart)
#max_connections = 100			# (change requires restart)
```

**After (with listen_addresses='0.0.0.0', port=5433, max_connections=200):**
```
listen_addresses = '0.0.0.0'		# Modified by pg_setup
port = 5433				# Modified by pg_setup
max_connections = 200			# Modified by pg_setup
```

### Error Handling

The function will exit with an error if:
- Data directory is not specified
- postgresql.conf file is not found
- File cannot be opened for reading or writing
- Temporary file cannot be created or renamed

## Function: setup_pg_hba_conf()

### Purpose
Modifies `pg_hba.conf` to configure authentication methods for database connections.

### Authentication Methods Modified

1. **Local connections** (Unix domain socket):
   - Controlled by `authmethodlocal` variable
   - Default: scram-sha-256
   - Common values: peer, trust, scram-sha-256, md5

2. **Host connections** (TCP/IP):
   - Controlled by `authmethodhost` variable
   - Default: scram-sha-256
   - Common values: trust, scram-sha-256, md5

### Implementation Details

The function:
1. Opens the existing `pg_hba.conf` file created by initdb
2. Reads the file line by line
3. Identifies lines starting with "local" or "host" (connection type)
4. Parses each line to find the METHOD field (last field)
5. Replaces the method with the configured value
6. Preserves all other fields (database, user, address)
7. Writes to a temporary file and then renames it to replace the original

### HBA File Format

The pg_hba.conf file uses this format:
```
TYPE  DATABASE  USER  ADDRESS  METHOD
```

Where:
- **TYPE**: Connection type (local, host, hostssl, hostnossl)
- **DATABASE**: Database name(s) or "all"
- **USER**: User name(s) or "all"
- **ADDRESS**: IP address/range (for host connections only)
- **METHOD**: Authentication method

### Example Transformation

**Before:**
```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
```

**After (with authmethodlocal='trust', authmethodhost='md5'):**
```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust	# Modified by pg_setup
host    all             all             127.0.0.1/32            md5	# Modified by pg_setup
host    all             all             ::1/128                 md5	# Modified by pg_setup
```

### Error Handling

The function will exit with an error if:
- Data directory is not specified
- pg_hba.conf file is not found
- File cannot be opened for reading or writing
- Temporary file cannot be created or renamed

## Security Considerations

### Trust Authentication Warning
When using `trust` authentication method:
- No password verification is performed
- Anyone who can connect to the server can access the database
- Should only be used in development/testing environments
- The `security_check()` function will warn about this configuration

### Network Exposure Warning
When setting `listen_addresses` to '0.0.0.0' or '*':
- Database is exposed to all network interfaces
- Combined with trust authentication, this is a critical security risk
- The `security_check()` function will warn about this configuration
- In production profile, this combination is blocked

## Testing

### Unit Tests
Located in `test_config_setup.c`:
- Tests configuration parameter parsing logic
- Tests HBA line parsing logic
- Tests file handling edge cases

Run with:
```bash
gcc -o test_config_setup src/bin/pg_setup/test_config_setup.c
./test_config_setup
```

### Integration Tests
Located in `test_config_integration.sh`:
- Tests actual file modification with realistic configuration files
- Verifies that settings are updated correctly
- Verifies that other settings are preserved
- Tests both postgresql.conf and pg_hba.conf modifications

Run with:
```bash
chmod +x src/bin/pg_setup/test_config_integration.sh
./src/bin/pg_setup/test_config_integration.sh
```

## Usage in pg_setup

These functions are called as part of the main installation flow:

```c
static void
do_setup(void)
{
    /* ... */
    
    /* Initialize database cluster */
    run_initdb();
    
    /* Configure postgresql.conf */
    setup_postgresql_conf();
    
    /* Configure pg_hba.conf */
    setup_pg_hba_conf();
    
    /* ... */
}
```

They should be called after `run_initdb()` has successfully created the database cluster, and before starting the database server.

## Future Enhancements

Possible improvements for future versions:

1. **Backup original files**: Create .bak copies before modification
2. **More parameters**: Support additional postgresql.conf parameters (shared_buffers, work_mem, etc.)
3. **Advanced HBA rules**: Support more complex authentication rules (specific databases, users, addresses)
4. **Validation**: Validate configuration values before writing
5. **Rollback support**: Integrate with the rollback mechanism for error recovery

## References

- PostgreSQL Documentation: [Server Configuration](https://www.postgresql.org/docs/current/runtime-config.html)
- PostgreSQL Documentation: [Client Authentication](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)
- Requirements: 4.6, 5.3, 5.4 in `.kiro/specs/pg-setup-tool/requirements.md`
- Design: Section on configuration file setup in `.kiro/specs/pg-setup-tool/design.md`
