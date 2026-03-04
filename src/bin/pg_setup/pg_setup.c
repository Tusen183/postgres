/*-------------------------------------------------------------------------
 *
 * pg_setup.c
 *	  Simplified PostgreSQL database installation and initialization tool
 *
 * This tool provides a user-friendly interface for initializing PostgreSQL
 * database clusters, similar to MySQL setup. It integrates the functionality
 * of initdb and pg_ctl with interactive wizards and configuration templates.
 *
 * Portions Copyright (c) 1996-2023, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/bin/pg_setup/pg_setup.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres_fe.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "common/file_perm.h"
#include "common/logging.h"
#include "common/string.h"
#include "common/username.h"
#include "fe_utils/string_utils.h"
#include "getopt_long.h"
#include "libpq-fe.h"
#include "port.h"
#include "pqexpbuffer.h"


#ifdef HAVE_LIBREADLINE
#include <readline/readline.h>
#include <readline/history.h>
#endif


#define PG_SETUP_VERSION "1.0"


static char *pg_data = NULL;
static char *encoding = NULL;
static char *locale = NULL;
static char *lc_collate = NULL;
static char *lc_ctype = NULL;
static char *username = NULL;
static char *pwfilename = NULL;
static char *superuser_password = NULL;
static char *database_name = NULL;
static char *listen_addresses = NULL;
static int port = 5432;
static int max_connections = 100;
static const char *authmethodhost = NULL;
static const char *authmethodlocal = NULL;


static bool start_server = true;


typedef enum ProfileType
{
	PROFILE_NONE,
	PROFILE_DEVELOPMENT,
	PROFILE_PRODUCTION,
	PROFILE_TEST
} ProfileType;

static ProfileType profile = PROFILE_NONE;


static const char *progname;
static const char *argv0;
static bool debug = false;
static bool noclean = false;


static bool made_new_pgdata = false;
static bool found_existing_pgdata = false;
static bool setup_success = false;


static void initialize_defaults(void);
static void usage(void);
static void show_version(void);


static void check_data_directory(void);
static void check_encoding(void);
static void check_locale(void);
static void check_port(void);
static void check_username(void);
static void security_check(void);

static void run_interactive_wizard(void);
static char *prompt_for_string(const char *prompt, const char *default_value);
static char *prompt_for_password(const char *prompt);
static void show_config_summary(void);

static void do_setup(void);
static void run_initdb(void);
static void setup_postgresql_conf(void);
static void setup_pg_hba_conf(void);
static void start_database_server(void);
static void verify_connection(void);
static void create_initial_database(void);

static void do_rollback(void);
static void cleanup(void);

static char *find_other_exec_or_die(const char *argv0, const char *target, const char *versionstr);
static bool port_is_available(int port_num);
static char *get_system_locale(void);

static void
usage(void)
{
	printf(_("%s initializes a PostgreSQL database cluster.\n\n"), progname);
	printf(_("Usage:\n"));
	printf(_("  %s [OPTION]...\n"), progname);
	printf(_("\nOptions:\n"));
	printf(_("  -g, --generate-config=FILE   generate configuration file template\n"));
	printf(_("  -d, --debug                  generate lots of debugging output\n"));
	printf(_("  -n, --noclean                do not clean up after errors\n"));
	printf(_("  -V, --version                output version information, then exit\n"));
	printf(_("  -h, --help                   show this help, then exit\n"));
	printf(_("\nWith no options, %s runs an interactive setup wizard.\n"), progname);
	printf(_("\nReport bugs to <%s>.\n"), PACKAGE_BUGREPORT);
	printf(_("%s home page: <%s>\n"), PACKAGE_NAME, PACKAGE_URL);
}

static void
show_version(void)
{
	printf("pg_setup (PostgreSQL) %s\n", PG_SETUP_VERSION);
}

int
main(int argc, char *argv[])
{
	static struct option long_options[] = {
		{"help", no_argument, NULL, 'h'},
		{"version", no_argument, NULL, 'V'},
		{"debug", no_argument, NULL, 'd'},
		{"noclean", no_argument, NULL, 'n'},
		{NULL, 0, NULL, 0}
	};

	int	i,c,option_index;
	pg_logging_init(argv[0]);
	progname = get_progname(argv[0]);
	argv0 = argv[0];
	set_pglocale_pgservice(argv[0], PG_TEXTDOMAIN("pg_setup"));

	initialize_defaults();


	if (argc > 1)
	{
		if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-?") == 0)
		{
			usage();
			exit(0);
		}
		if (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-V") == 0)
		{
			show_version();
			exit(0);
		}
	}

	while ((c = getopt_long(argc, argv, "hV:dn",
							long_options, &option_index)) != -1)
	{
		switch (c)
		{
			case 'h':
				usage();
				exit(0);
			case 'V':
				show_version();
				exit(0);
			case 'd':
				debug = true;
				break;
			case 'n':
				noclean = true;
				break;
			default:
				pg_log_error_hint("Try \"%s --help\" for more information.", progname);
				exit(1);
		}
	}


	if (optind < argc)
	{
		pg_log_error("too many command-line arguments (first is \"%s\")",
					 argv[optind]);
		pg_log_error_hint("Try \"%s --help\" for more information.", progname);
		exit(1);
	}

	if(debug)
	{
		pg_logging_increase_verbosity();
	}


	pg_log_info("starting interactive setup wizard");
	run_interactive_wizard();
	show_config_summary();


	pg_log_debug("validating configuration");

	if (pg_data == NULL)
	{
		pg_log_error("data directory not specified");
		exit(1);
	}

	check_data_directory();
	check_encoding();
	check_locale();
	check_port();
	check_username();
	security_check();

	pg_log_debug("configuration validation completed successfully");

	printf(_("\n"));
	printf(_("===========================================\n"));
	printf(_("Starting PostgreSQL Database Setup\n"));
	printf(_("===========================================\n\n"));

	pg_log_info("beginning database setup");
	pg_log_info("data directory: %s", pg_data);


	do_setup();
	cleanup();

	return 0;
}

static void
initialize_defaults(void)
{
	encoding = pg_strdup("UTF8");
	locale = get_system_locale();
	listen_addresses = pg_strdup("localhost");
	port = 5432;
	max_connections = 100;
	authmethodhost = "scram-sha-256";
	authmethodlocal = "scram-sha-256";
	username = pg_strdup(get_user_name_or_exit(progname));
}

static void
check_data_directory(void)
{
	struct stat statbuf;

	if (pg_data == NULL)
	{
		pg_log_error("data directory not specified");
		pg_log_error_hint("Use -D option or set data_directory in configuration file");
		exit(1);
	}

	if (stat(pg_data, &statbuf) == 0)
	{
		found_existing_pgdata = true;

		if (!S_ISDIR(statbuf.st_mode))
		{
			pg_log_error("\"%s\" exists but is not a directory", pg_data);
			exit(1);
		}

		{
			DIR		   *dir;
			struct dirent *entry;
			bool		is_empty = true;

			dir = opendir(pg_data);
			if (dir == NULL)
			{
				pg_log_error("could not open directory \"%s\": %m", pg_data);
				exit(1);
			}

			while ((entry = readdir(dir)) != NULL)
			{
				if (strcmp(entry->d_name, ".") == 0 ||
					strcmp(entry->d_name, "..") == 0)
					continue;
				is_empty = false;
				break;
			}

			closedir(dir);

			if (!is_empty)
			{
				pg_log_error("directory \"%s\" exists but is not empty", pg_data);
				pg_log_error_hint("If you want to create a new database cluster, either remove or empty the directory \"%s\" or run pg_setup with a different data directory.", pg_data);
				exit(1);
			}
		}

		if ((statbuf.st_mode & 0777) != 0700)
		{
			pg_log_warning("directory \"%s\" has incorrect permissions", pg_data);
			pg_log_warning_hint("Permissions should be 0700. Will attempt to fix during installation.");
		}
	}
	else
	{
		if (errno != ENOENT)
		{
			pg_log_error("could not access directory \"%s\": %m", pg_data);
			exit(1);
		}

		pg_log_debug("data directory \"%s\" does not exist, will be created", pg_data);
	}
}

static void
check_encoding(void)
{
	static const char *valid_encodings[] = {
		"UTF8", "UTF-8",
		"LATIN1", "ISO-8859-1", "ISO_8859_1",
		"LATIN2", "ISO-8859-2", "ISO_8859_2",
		"LATIN3", "ISO-8859-3", "ISO_8859_3",
		"LATIN4", "ISO-8859-4", "ISO_8859_4",
		"LATIN5", "ISO-8859-9", "ISO_8859_9",
		"LATIN6", "ISO-8859-10", "ISO_8859_10",
		"LATIN7", "ISO-8859-13", "ISO_8859_13",
		"LATIN8", "ISO-8859-14", "ISO_8859_14",
		"LATIN9", "ISO-8859-15", "ISO_8859_15",
		"LATIN10", "ISO-8859-16", "ISO_8859_16",
		"SQL_ASCII",
		"EUC_JP", "EUC_CN", "EUC_KR", "EUC_TW",
		"SJIS", "BIG5", "GBK", "GB18030",
		"KOI8R", "KOI8U",
		"WIN866", "WIN874", "WIN1250", "WIN1251", "WIN1252", "WIN1253",
		"WIN1254", "WIN1255", "WIN1256", "WIN1257", "WIN1258",
		NULL
	};

	int			i;
	bool		found = false;

	if (encoding == NULL)
	{
		pg_log_error("encoding not specified");
		exit(1);
	}

	for (i = 0; valid_encodings[i] != NULL; i++)
	{
		if (pg_strcasecmp(encoding, valid_encodings[i]) == 0)
		{
			found = true;
			break;
		}
	}

	if (!found)
	{
		pg_log_error("invalid encoding name \"%s\"", encoding);
		pg_log_error_hint("Supported encodings include: UTF8, LATIN1, SQL_ASCII, EUC_JP, EUC_CN, EUC_KR, SJIS, BIG5, GBK, KOI8R, WIN1250, WIN1251, WIN1252, and others.");
		pg_log_error_hint("For a complete list, see PostgreSQL documentation on character sets.");
		exit(1);
	}

	pg_log_debug("encoding \"%s\" is valid", encoding);
}

static void
check_locale(void)
{
	if (locale != NULL && strlen(locale) == 0)
	{
		pg_log_error("locale cannot be empty");
		exit(1);
	}

	if (lc_collate != NULL && strlen(lc_collate) == 0)
	{
		pg_log_error("lc_collate cannot be empty");
		exit(1);
	}

	if (lc_ctype != NULL && strlen(lc_ctype) == 0)
	{
		pg_log_error("lc_ctype cannot be empty");
		exit(1);
	}

	if (debug)
	{
		if (locale != NULL)
			pg_log_info("locale: %s", locale);
		if (lc_collate != NULL)
			pg_log_info("lc_collate: %s", lc_collate);
		if (lc_ctype != NULL)
			pg_log_info("lc_ctype: %s", lc_ctype);
	}
}

static void
check_port(void)
{
	if (port < 1024 || port > 65535)
	{
		pg_log_error("invalid port number: %d", port);
		pg_log_error_hint("Port number must be between 1024 and 65535");
		exit(1);
	}

	if (!port_is_available(port))
	{
		pg_log_error("port %d is already in use", port);
		pg_log_error_hint("Please choose a different port number or stop the service using port %d", port);
		pg_log_error_hint("You can check which process is using the port with:");
		pg_log_error_hint("  lsof -i :%d    (on Unix/Linux)", port);
		pg_log_error_hint("  netstat -ano | findstr :%d    (on Windows)", port);
		exit(1);
	}

	pg_log_debug("port %d is valid and available", port);
}

static void
check_username(void)
{
	const char *p;
	int			len;

	if (username == NULL)
	{
		pg_log_error("username not specified");
		exit(1);
	}

	len = strlen(username);

	if (len == 0)
	{
		pg_log_error("username cannot be empty");
		exit(1);
	}

	if (len > 63)
	{
		pg_log_error("username \"%s\" is too long (maximum 63 characters)", username);
		exit(1);
	}

	if (!((username[0] >= 'a' && username[0] <= 'z') ||
		  (username[0] >= 'A' && username[0] <= 'Z') ||
		  username[0] == '_'))
	{
		pg_log_error("invalid username \"%s\"", username);
		pg_log_error_hint("Username must start with a letter (a-z, A-Z) or underscore (_)");
		exit(1);
	}

	for (p = username + 1; *p; p++)
	{
		if (!((*p >= 'a' && *p <= 'z') ||
			  (*p >= 'A' && *p <= 'Z') ||
			  (*p >= '0' && *p <= '9') ||
			  *p == '_' ||
			  *p == '$'))
		{
			pg_log_error("invalid username \"%s\"", username);
			pg_log_error_hint("Username can only contain letters (a-z, A-Z), digits (0-9), underscores (_), and dollar signs ($)");
			exit(1);
		}
	}

	pg_log_debug("username \"%s\" is valid", username);
}

static void
security_check(void)
{
	bool		has_security_issues = false;
	bool		has_trust_auth = false;
	bool		listen_all_interfaces = false;
	bool		no_password = false;

	pg_log_debug("performing security checks");
	if ((authmethodhost != NULL && strcmp(authmethodhost, "trust") == 0) ||
		(authmethodlocal != NULL && strcmp(authmethodlocal, "trust") == 0))
	{
		has_trust_auth = true;
		has_security_issues = true;

		pg_log_warning("trust authentication method is enabled");
		pg_log_warning_detail("Trust authentication allows connections without password verification.");
		pg_log_warning_hint("For production environments, use 'scram-sha-256' or 'md5' authentication instead.");

		if (authmethodhost != NULL && strcmp(authmethodhost, "trust") == 0)
			pg_log_info("  - Host connections (TCP/IP) use trust authentication");
		if (authmethodlocal != NULL && strcmp(authmethodlocal, "trust") == 0)
			pg_log_info("  - Local connections (Unix socket) use trust authentication");
	}

	if (listen_addresses != NULL &&
		(strcmp(listen_addresses, "0.0.0.0") == 0 ||
		 strcmp(listen_addresses, "*") == 0 ||
		 strstr(listen_addresses, "0.0.0.0") != NULL ||
		 strstr(listen_addresses, "*") != NULL))
	{
		listen_all_interfaces = true;
		has_security_issues = true;

		pg_log_warning("database is configured to listen on all network interfaces");
		pg_log_warning_detail("Listen address is set to '%s', which exposes the database to all network interfaces.",
							  listen_addresses);
		pg_log_warning_hint("For better security, specify explicit IP addresses or use 'localhost' for local-only access.");
	}

	if (superuser_password == NULL || strlen(superuser_password) == 0)
	{
		no_password = true;
		has_security_issues = true;

		pg_log_warning("no password set for database superuser '%s'", username);
		pg_log_warning_detail("A superuser account without a password can be accessed by anyone who can connect to the database.");
		pg_log_warning_hint("Set a strong password using the -W option or --pwfile option.");
	}

	if (has_trust_auth && listen_all_interfaces)
	{
		pg_log_warning("CRITICAL: insecure configuration detected!");
		pg_log_warning_detail("Trust authentication combined with listening on all interfaces allows anyone on the network to access your database without authentication.");
		pg_log_warning_hint("This configuration should NEVER be used in production environments.");

		if (profile == PROFILE_PRODUCTION)
		{
			pg_log_error("production profile does not allow trust authentication with public network access");
			pg_log_error_hint("Either change authentication method to 'scram-sha-256' or restrict listen_addresses to 'localhost'.");
			exit(1);
		}
	}

	if (has_trust_auth && no_password)
	{
		pg_log_warning("trust authentication is enabled and no superuser password is set");
		pg_log_warning_detail("This combination provides no authentication barrier for database access.");
		pg_log_warning_hint("Consider setting a password or using a more secure authentication method.");
	}

	if (listen_all_interfaces && no_password)
	{
		pg_log_warning("database is exposed to network without superuser password");
		pg_log_warning_detail("Anyone who can reach the database port can potentially gain access.");
		pg_log_warning_hint("Set a strong password for the superuser account.");
	}

	if (has_security_issues)
	{
		char		response[10];

		pg_log_info("security check completed with warnings");
		printf(_("\nSecurity warnings were detected in your configuration.\n"));
		printf(_("Do you want to continue with this configuration? (yes/no) "));
		fflush(stdout);

		if (fgets(response, sizeof(response), stdin) == NULL ||
			(strcmp(response, "yes\n") != 0 && strcmp(response, "y\n") != 0))
		{
			printf(_("Installation cancelled due to security concerns.\n"));
			exit(1);
		}
	}
	else
	{
		pg_log_debug("no security issues detected");
	}
}

/*
 * Interactive Wizard Functions
 */

static char *
prompt_for_string(const char *prompt, const char *default_value)
{
	char	   *input = NULL;
	char	   *result;
	char		prompt_buf[1024];

	if (default_value != NULL && strlen(default_value) > 0)
		snprintf(prompt_buf, sizeof(prompt_buf), "%s [%s]: ", prompt, default_value);
	else
		snprintf(prompt_buf, sizeof(prompt_buf), "%s: ", prompt);

#ifdef HAVE_LIBREADLINE
	/* Use readline for better user experience */
	input = readline(prompt_buf);

	/* readline returns NULL on EOF */
	if (input == NULL)
		return NULL;

	if (input[0] != '\0')
		add_history(input);
#else
	/* Fallback to fgets if readline not available */
	char		input_buf[1024];

	printf("%s", prompt_buf);
	fflush(stdout);

	if (fgets(input_buf, sizeof(input_buf), stdin) == NULL)
		return NULL;

	{
		char *p = strchr(input_buf, '\n');
		if (p)
			*p = '\0';
	}

	{
		char *p = strchr(input_buf, '\r');
		if (p)
			*p = '\0';
	}

	input = input_buf;
#endif

	/* Trim leading and trailing whitespace */
	{
		char *start = input;
		char *end;

		/* Skip leading whitespace */
		while (*start && isspace((unsigned char) *start))
			start++;

		/* If empty after trimming, use default */
		if (*start == '\0')
		{
#ifdef HAVE_LIBREADLINE
			free(input);  /* readline allocates with malloc */
#endif
			if (default_value != NULL)
				return pg_strdup(default_value);
			else
				return NULL;
		}

		/* Trim trailing whitespace */
		end = start + strlen(start) - 1;
		while (end > start && isspace((unsigned char) *end))
			*end-- = '\0';

		result = pg_strdup(start);
	}

#ifdef HAVE_LIBREADLINE
	free(input);  /* readline allocates with malloc */
#endif

	return result;
}

static char *
prompt_for_password(const char *prompt)
{
	char	   *password1;
	char	   *password2;
	int			max_attempts = 3;
	int			attempt;

	for (attempt = 0; attempt < max_attempts; attempt++)
	{
		password1 = simple_prompt(prompt, false);

		if (password1 == NULL || strlen(password1) == 0)
		{
			printf(_("No password entered. Please enter again.\n"));
			continue;
		}

		password2 = simple_prompt(_("Enter it again: "), false);

		if (password2 != NULL && strcmp(password1, password2) == 0)
		{
			/* Passwords match, return the password */
			char *result = pg_strdup(password1);

			memset(password1, 0, strlen(password1));
			memset(password2, 0, strlen(password2));
			free(password1);
			free(password2);

			return result;
		}

		/* Passwords don't match */
		printf(_("Passwords didn't match.\n"));

		/* Clear and free password buffers */
		if (password1)
		{
			memset(password1, 0, strlen(password1));
			free(password1);
		}
		if (password2)
		{
			memset(password2, 0, strlen(password2));
			free(password2);
		}

		if (attempt < max_attempts - 1)
			printf(_("Please try again.\n\n"));
	}

	/* Max attempts reached */
	pg_log_error("password confirmation failed after %d attempts", max_attempts);
	return NULL;
}

static void
show_config_summary(void)
{
	printf(_("\n"));
	printf(_("===========================================\n"));
	printf(_("PostgreSQL Setup - Configuration Summary\n"));
	printf(_("===========================================\n\n"));

	printf(_("Data Directory:\n"));
	printf(_("  Location: %s\n"), pg_data ? pg_data : "(not set)");
	printf(_("\n"));

	printf(_("Database Settings:\n"));
	printf(_("  Encoding: %s\n"), encoding ? encoding : "(default)");
	if (locale)
		printf(_("  Locale: %s\n"), locale);
	if (lc_collate)
		printf(_("  LC_COLLATE: %s\n"), lc_collate);
	if (lc_ctype)
		printf(_("  LC_CTYPE: %s\n"), lc_ctype);
	printf(_("\n"));

	printf(_("Superuser Account:\n"));
	printf(_("  Username: %s\n"), username ? username : "(not set)");
	printf(_("  Password: %s\n"),
		   superuser_password ? "****** (set)" : "(no password)");
	printf(_("\n"));

	printf(_("Initial Database:\n"));
	printf(_("  Database Name: %s\n"), database_name ? database_name : "(none)");
	printf(_("\n"));

	printf(_("Network Configuration:\n"));
	printf(_("  Listen Addresses: %s\n"), listen_addresses ? listen_addresses : "(default)");
	printf(_("  Port: %d\n"), port);
	printf(_("  Max Connections: %d\n"), max_connections);
	printf(_("\n"));

	printf(_("Authentication:\n"));
	printf(_("  Host Connections: %s\n"), authmethodhost ? authmethodhost : "(default)");
	printf(_("  Local Connections: %s\n"), authmethodlocal ? authmethodlocal : "(default)");
	printf(_("\n"));

	if (profile != PROFILE_NONE)
	{
		const char *profile_name;
		switch (profile)
		{
			case PROFILE_DEVELOPMENT:
				profile_name = "Development";
				break;
			case PROFILE_PRODUCTION:
				profile_name = "Production";
				break;
			case PROFILE_TEST:
				profile_name = "Test";
				break;
			default:
				profile_name = "None";
				break;
		}
		printf(_("Configuration Profile: %s\n"), profile_name);
		printf(_("\n"));
	}
	printf(_("===========================================\n\n"));
}

static void
run_interactive_wizard(void)
{
	char	   *input;
	char		default_data_dir[1024];

	printf(_("\n"));
	printf(_("===========================================\n"));
	printf(_("PostgreSQL Interactive Setup Wizard\n"));
	printf(_("===========================================\n\n"));

	printf(_("This wizard will guide you through the PostgreSQL database setup process.\n"));
	printf(_("Press Enter to accept default values shown in brackets.\n\n"));

	/*
	 * Data Directory
	 */
	if (pg_data == NULL)
	{
		/* Suggest a default data directory */
		snprintf(default_data_dir, sizeof(default_data_dir),
				 "/usr/local/pgsql/data");

		input = prompt_for_string(_("Data directory location"), default_data_dir);
		if (input != NULL)
			pg_data = input;
		else
			pg_data = pg_strdup(default_data_dir);
	}

	printf(_("\n"));
	input = prompt_for_string(_("Default encoding"), encoding);
	if (input != NULL)
		encoding = input;

	printf(_("\n"));
	printf(_("Locale settings (leave empty to use system default):\n"));
	input = prompt_for_string(_("  Locale"), locale ? locale : "");
	if (input != NULL && strlen(input) > 0)
		locale = input;

	printf(_("\n"));
	printf(_("Superuser account configuration:\n"));
	input = prompt_for_string(_("  Superuser name"), username);
	if (input != NULL)
		username = input;

    input = prompt_for_password(_("  Enter password for superuser: "));
    if (input != NULL)
        superuser_password = input;

	printf(_("\n"));
	printf(_("Initial database configuration:\n"));
	input = prompt_for_string(_("  Database name to create"), "postgres");
	if (input != NULL && strlen(input) > 0)
		database_name = input;
	else
		database_name = pg_strdup("postgres");

	printf(_("\n"));
	printf(_("Network configuration:\n"));
	input = prompt_for_string(_("  Listen addresses"), listen_addresses);
	if (input != NULL)
		listen_addresses = input;

	/* Port number */
	{
		char port_str[20];
		snprintf(port_str, sizeof(port_str), "%d", port);
		input = prompt_for_string(_("  Port number"), port_str);
		if (input != NULL)
		{
			int new_port = atoi(input);
			if (new_port > 0 && new_port <= 65535)
				port = new_port;
			else
				printf(_("Invalid port number, using default: %d\n"), port);
		}
	}

	/*
	 * Authentication Method
	 */
	printf(_("\n"));
	printf(_("Authentication method:\n"));
	printf(_("  Common methods: scram-sha-256 (secure), md5 (compatible), trust (no password)\n"));
	input = prompt_for_string(_("  Authentication method"), authmethodhost);
	if (input != NULL)
	{
		authmethodhost = input;
		authmethodlocal = pg_strdup(input);
	}
	printf(_("Configuration complete!\n"));
}


static bool
port_is_available(int port_num)
{
	int			sockfd;
	struct sockaddr_in addr;
	int			reuse = 1;
	bool		available = false;

	if (port_num < 1 || port_num > 65535)
	{
		pg_log_debug("invalid port number for availability check: %d", port_num);
		return false;
	}

	sockfd = socket(AF_INET, SOCK_STREAM, 0);
	if (sockfd < 0)
	{
		pg_log_debug("could not create socket for port check: %m");
		return false;
	}

	if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0)
	{
		pg_log_debug("could not set socket options: %m");
		close(sockfd);
		return false;
	}

	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);	/* 127.0.0.1 */
	addr.sin_port = htons(port_num);

	/* Try to bind to the port */
	if (bind(sockfd, (struct sockaddr *) &addr, sizeof(addr)) == 0)
	{
		/* Bind succeeded - port is available */
		available = true;

		pg_log_debug("port %d is available", port_num);
	}
	else
	{
		/* Bind failed - check why */
		if (errno == EADDRINUSE)
		{
			/* Port is already in use */
			available = false;

			pg_log_debug("port %d is already in use", port_num);
		}
		else if (errno == EACCES)
		{
			/* Permission denied (privileged port) */
			available = false;

			pg_log_debug("permission denied for port %d (may be privileged)", port_num);
		}
		else
		{
			/* Other error */
			available = false;

			pg_log_debug("could not bind to port %d: %m", port_num);
		}
	}

	close(sockfd);

	return available;
}

static char *
get_system_locale(void)
{
	char	   *locale_str = NULL;
	const char *env_locale;

	/*
	 * Check LC_ALL first - it overrides all other locale settings
	 */
	env_locale = getenv("LC_ALL");
	if (env_locale != NULL && strlen(env_locale) > 0)
	{
		locale_str = pg_strdup(env_locale);

		pg_log_debug("detected locale from LC_ALL: %s", locale_str);

		return locale_str;
	}

	/*
	 * Check LC_CTYPE - controls character classification and case conversion
	 * This is the most relevant for database encoding
	 */
	env_locale = getenv("LC_CTYPE");
	if (env_locale != NULL && strlen(env_locale) > 0)
	{
		locale_str = pg_strdup(env_locale);

		pg_log_debug("detected locale from LC_CTYPE: %s", locale_str);

		return locale_str;
	}

	/*
	 * Check LANG - the fallback locale setting
	 */
	env_locale = getenv("LANG");
	if (env_locale != NULL && strlen(env_locale) > 0)
	{
		locale_str = pg_strdup(env_locale);

		pg_log_debug("detected locale from LANG: %s", locale_str);

		return locale_str;
	}

	/*
	 * No locale environment variables found
	 * On most Unix systems, we can try to use the "C" locale as a fallback
	 */
	pg_log_debug("no locale environment variables found, using C locale");

	locale_str = pg_strdup("C");

	return locale_str;
}


/*
 * find_other_exec_or_die
 *
 * Finds another executable in the same directory as this program.
 * Dies with an error message if the executable is not found or has
 * the wrong version.
 *
 * This is a simplified version of the function from pg_ctl.c
 */
static char *
find_other_exec_or_die(const char *argv0, const char *target, const char *versionstr)
{
	int			ret;
	char	   *found_path;

	found_path = pg_malloc(MAXPGPATH);

	ret = find_other_exec(argv0, target, versionstr, found_path);

	if (ret < 0)
	{
		char		full_path[MAXPGPATH];

		if (find_my_exec(argv0, full_path) < 0)
			strlcpy(full_path, progname, sizeof(full_path));

		if (ret == -1)
		{
			pg_log_error("program \"%s\" is needed by %s but was not found in the same directory as \"%s\"",
						 target, progname, full_path);
		}
		else
		{
			pg_log_error("program \"%s\" was found by \"%s\" but was not the same version as %s",
						 target, full_path, progname);
		}
		exit(1);
	}

	return found_path;
}

static void
run_initdb(void)
{
	char	   *initdb_path;
	char	   *cmd;
	PQExpBufferData buf;
	int			result;

	if (pg_data == NULL)
	{
		pg_log_error("data directory not specified");
		exit(1);
	}

	/* Find initdb executable */
	initdb_path = find_other_exec_or_die(argv0, "initdb",
										 "initdb (PostgreSQL) " PG_VERSION "\n");

	pg_log_debug("found initdb at: %s", initdb_path);

	initPQExpBuffer(&buf);

	appendPQExpBuffer(&buf, "\"%s\"", initdb_path);

	appendPQExpBuffer(&buf, " -D \"%s\"", pg_data);

	if (encoding != NULL)
		appendPQExpBuffer(&buf, " -E %s", encoding);

	if (locale != NULL)
		appendPQExpBuffer(&buf, " --locale=%s", locale);

	if (lc_collate != NULL)
		appendPQExpBuffer(&buf, " --lc-collate=%s", lc_collate);

	if (lc_ctype != NULL)
		appendPQExpBuffer(&buf, " --lc-ctype=%s", lc_ctype);

	if (username != NULL)
		appendPQExpBuffer(&buf, " -U %s", username);

	if (authmethodhost != NULL || authmethodlocal != NULL)
	{
		/* If both are the same, use -A */
		if (authmethodhost != NULL && authmethodlocal != NULL &&
			strcmp(authmethodhost, authmethodlocal) == 0)
		{
			appendPQExpBuffer(&buf, " -A %s", authmethodhost);
		}
		else
		{
			/* Use separate options */
			if (authmethodhost != NULL)
				appendPQExpBuffer(&buf, " --auth-host=%s", authmethodhost);
			if (authmethodlocal != NULL)
				appendPQExpBuffer(&buf, " --auth-local=%s", authmethodlocal);
		}
	}

	/* Handle password */
	if (superuser_password != NULL && strlen(superuser_password) > 0)
	{
		char		pwfilepath[MAXPGPATH];
		FILE	   *pwfile;

		snprintf(pwfilepath, sizeof(pwfilepath), "/tmp/pg_setup_pw_%d.tmp", getpid());

		pwfile = fopen(pwfilepath, "w");
		if (pwfile == NULL)
		{
			pg_log_error("could not create password file \"%s\": %m", pwfilepath);
			exit(1);
		}

		if (fprintf(pwfile, "%s\n", superuser_password) < 0)
		{
			pg_log_error("could not write to password file \"%s\": %m", pwfilepath);
			fclose(pwfile);
			unlink(pwfilepath);
			exit(1);
		}

		fclose(pwfile);

		if (chmod(pwfilepath, 0600) != 0)
		{
			pg_log_error("could not set permissions on password file \"%s\": %m", pwfilepath);
			unlink(pwfilepath);
			exit(1);
		}

		appendPQExpBuffer(&buf, " --pwfile=\"%s\"", pwfilepath);

		pg_log_debug("created temporary password file: %s", pwfilepath);
	}
	else if (pwfilename != NULL)
	{
		/* User provided a password file */
		appendPQExpBuffer(&buf, " --pwfile=\"%s\"", pwfilename);
	}

	cmd = buf.data;

	pg_log_debug("executing: %s", cmd);
	pg_log_info("initializing database cluster...");

	fflush(NULL);
	result = system(cmd);

	if (superuser_password != NULL && strlen(superuser_password) > 0)
	{
		char		pwfilepath[MAXPGPATH];

		snprintf(pwfilepath, sizeof(pwfilepath), "/tmp/pg_setup_pw_%d.tmp", getpid());
		unlink(pwfilepath);

		pg_log_debug("removed temporary password file");
	}

	if (result != 0)
	{
		pg_log_error("database cluster initialization failed");
		pg_log_error_hint("Check the initdb output above for details.");
		termPQExpBuffer(&buf);

		/* Perform rollback if needed */
		do_rollback();

		exit(1);
	}

	termPQExpBuffer(&buf);
	pg_free(initdb_path);

	pg_log_info("database cluster initialized successfully");
}

static void
setup_postgresql_conf(void)
{
	char		conf_file[MAXPGPATH];
	FILE	   *infile;
	FILE	   *outfile;
	char		line[1024];
	char		tmpfile[MAXPGPATH];
	bool		found_listen_addresses = false;
	bool		found_port = false;
	bool		found_max_connections = false;

	if (pg_data == NULL)
	{
		pg_log_error("data directory not specified");
		exit(1);
	}

	snprintf(conf_file, sizeof(conf_file), "%s/postgresql.conf", pg_data);

	pg_log_debug("configuring postgresql.conf: %s", conf_file);

	if (access(conf_file, F_OK) != 0)
	{
		pg_log_error("postgresql.conf not found: %s", conf_file);
		pg_log_error_hint("Make sure initdb has been run successfully.");
		do_rollback();
		exit(1);
	}

	infile = fopen(conf_file, "r");
	if (infile == NULL)
	{
		pg_log_error("could not open postgresql.conf for reading: %m");
		do_rollback();
		exit(1);
	}

	snprintf(tmpfile, sizeof(tmpfile), "%s/postgresql.conf.tmp", pg_data);
	outfile = fopen(tmpfile, "w");
	if (outfile == NULL)
	{
		pg_log_error("could not create temporary file: %m");
		fclose(infile);
		do_rollback();
		exit(1);
	}

	/* Process the configuration file line by line */
	while (fgets(line, sizeof(line), infile) != NULL)
	{
		char	   *trimmed = line;
		bool		replaced = false;

		/* Skip leading whitespace */
		while (*trimmed && isspace((unsigned char) *trimmed))
			trimmed++;

		if (*trimmed == '#')
		{
			trimmed++;
			/* Skip whitespace after # */
			while (*trimmed && isspace((unsigned char) *trimmed))
				trimmed++;
		}

		if (strncmp(trimmed, "listen_addresses", 16) == 0)
		{
			char *p = trimmed + 16;

			/* Skip whitespace and = */
			while (*p && (isspace((unsigned char) *p) || *p == '='))
				p++;

			/* This is a listen_addresses line */
			if (!found_listen_addresses && listen_addresses != NULL)
			{
				fprintf(outfile, "listen_addresses = '%s'\t\t# Modified by pg_setup\n",
						listen_addresses);
				found_listen_addresses = true;
				replaced = true;

				pg_log_debug("set listen_addresses = '%s'", listen_addresses);
			}
		}
		else if (strncmp(trimmed, "port", 4) == 0)
		{
			char *p = trimmed + 4;

			if (*p && !isspace((unsigned char) *p) && *p != '=')
			{
				/* Not the port setting, write original line */
				fputs(line, outfile);
				continue;
			}

			/* This is a port line */
			if (!found_port)
			{
				fprintf(outfile, "port = %d\t\t\t\t# Modified by pg_setup\n", port);
				found_port = true;
				replaced = true;

				pg_log_debug("set port = %d", port);
			}
		}
		else if (strncmp(trimmed, "max_connections", 15) == 0)
		{
			char *p = trimmed + 15;

			/* Skip whitespace and = */
			while (*p && (isspace((unsigned char) *p) || *p == '='))
				p++;

			/* This is a max_connections line */
			if (!found_max_connections)
			{
				fprintf(outfile, "max_connections = %d\t\t\t# Modified by pg_setup\n",
						max_connections);
				found_max_connections = true;
				replaced = true;

				pg_log_debug("set max_connections = %d", max_connections);
			}
		}

		if (!replaced)
		{
			fputs(line, outfile);
		}
	}

	if (!found_listen_addresses && listen_addresses != NULL)
	{
		fprintf(outfile, "\n# Added by pg_setup\n");
		fprintf(outfile, "listen_addresses = '%s'\n", listen_addresses);

		pg_log_debug("appended listen_addresses = '%s'", listen_addresses);
	}

	if (!found_port)
	{
		if (!found_listen_addresses)
			fprintf(outfile, "\n# Added by pg_setup\n");
		fprintf(outfile, "port = %d\n", port);

		pg_log_debug("appended port = %d", port);
	}

	if (!found_max_connections)
	{
		if (!found_listen_addresses && !found_port)
			fprintf(outfile, "\n# Added by pg_setup\n");
		fprintf(outfile, "max_connections = %d\n", max_connections);

		pg_log_debug("appended max_connections = %d", max_connections);
	}

	fclose(infile);
	fclose(outfile);

	/* Replace original file with modified version */
	if (rename(tmpfile, conf_file) != 0)
	{
		pg_log_error("could not rename temporary file to postgresql.conf: %m");
		unlink(tmpfile);
		exit(1);
	}

	pg_log_info("postgresql.conf configured successfully");
}

static void
setup_pg_hba_conf(void)
{
	char		hba_file[MAXPGPATH];
	FILE	   *infile;
	FILE	   *outfile;
	char		line[1024];
	char		tmpfile[MAXPGPATH];
	bool		modified = false;

	if (pg_data == NULL)
	{
		pg_log_error("data directory not specified");
		exit(1);
	}

	snprintf(hba_file, sizeof(hba_file), "%s/pg_hba.conf", pg_data);

	pg_log_debug("configuring pg_hba.conf: %s", hba_file);

	if (access(hba_file, F_OK) != 0)
	{
		pg_log_error("pg_hba.conf not found: %s", hba_file);
		pg_log_error_hint("Make sure initdb has been run successfully.");
		exit(1);
	}

	infile = fopen(hba_file, "r");
	if (infile == NULL)
	{
		pg_log_error("could not open pg_hba.conf for reading: %m");
		exit(1);
	}

	snprintf(tmpfile, sizeof(tmpfile), "%s/pg_hba.conf.tmp", pg_data);
	outfile = fopen(tmpfile, "w");
	if (outfile == NULL)
	{
		pg_log_error("could not create temporary file: %m");
		fclose(infile);
		exit(1);
	}

	/* Process the HBA file line by line */
	while (fgets(line, sizeof(line), infile) != NULL)
	{
		char	   *trimmed = line;
		char	   *p;
		bool		replaced = false;

		/* Skip leading whitespace */
		while (*trimmed && isspace((unsigned char) *trimmed))
			trimmed++;

		if (*trimmed == '#' || *trimmed == '\0')
		{
			fputs(line, outfile);
			continue;
		}


		if (strncmp(trimmed, "local", 5) == 0)
		{
			/* Local connection line */
			p = trimmed + 5;

			/* Make sure it's followed by whitespace */
			if (*p && isspace((unsigned char) *p))
			{
				/* This is a local connection rule */
				/* Format: local   DATABASE  USER  METHOD */

				/* Find the METHOD field (last field) */
				char *last_word = NULL;
				char *scan = p;

				/* Skip to find the last word (the method) */
				while (*scan)
				{
					/* Skip whitespace */
					while (*scan && isspace((unsigned char) *scan))
						scan++;

					if (*scan && !isspace((unsigned char) *scan))
					{
						last_word = scan;
						/* Skip non-whitespace */
						while (*scan && !isspace((unsigned char) *scan) && *scan != '\n' && *scan != '\r')
							scan++;
					}
				}

				if (last_word != NULL && authmethodlocal != NULL)
				{
					/* Replace the method */
					size_t prefix_len = last_word - line;
					fwrite(line, 1, prefix_len, outfile);

					fprintf(outfile, "%s", authmethodlocal);

					fprintf(outfile, "\t# Modified by pg_setup\n");

					replaced = true;
					modified = true;

					pg_log_debug("updated local connection auth method to: %s", authmethodlocal);
				}
			}
		}
		else if (strncmp(trimmed, "host", 4) == 0)
		{
			/* Host connection line */
			p = trimmed + 4;

			/* Make sure it's followed by whitespace */
			if (*p && isspace((unsigned char) *p))
			{
				/* This is a host connection rule */

				/* Find the METHOD field (last field) */
				char *last_word = NULL;
				char *scan = p;

				/* Skip to find the last word (the method) */
				while (*scan)
				{
					/* Skip whitespace */
					while (*scan && isspace((unsigned char) *scan))
						scan++;

					if (*scan && !isspace((unsigned char) *scan))
					{
						last_word = scan;
						/* Skip non-whitespace */
						while (*scan && !isspace((unsigned char) *scan) && *scan != '\n' && *scan != '\r')
							scan++;
					}
				}

				if (last_word != NULL && authmethodhost != NULL)
				{
					/* Replace the method */
					size_t prefix_len = last_word - line;
					fwrite(line, 1, prefix_len, outfile);

					fprintf(outfile, "%s", authmethodhost);

					fprintf(outfile, "\t# Modified by pg_setup\n");

					replaced = true;
					modified = true;

					pg_log_debug("updated host connection auth method to: %s", authmethodhost);
				}
			}
		}

		if (!replaced)
		{
			fputs(line, outfile);
		}
	}

	fclose(infile);
	fclose(outfile);

	/* Replace original file with modified version */
	if (rename(tmpfile, hba_file) != 0)
	{
		pg_log_error("could not rename temporary file to pg_hba.conf: %m");
		unlink(tmpfile);
		exit(1);
	}

	if (modified)
		pg_log_info("pg_hba.conf configured successfully");
	else pg_log_debug("pg_hba.conf: no changes needed");
}

static void
start_database_server(void)
{
	char	   *pg_ctl_path;
	char	   *cmd;
	PQExpBufferData buf;
	char		logfile[MAXPGPATH];
	int			result;

	if (pg_data == NULL)
	{
		pg_log_error("data directory not specified");
		exit(1);
	}

	/* Find pg_ctl executable */
	pg_ctl_path = find_other_exec_or_die(argv0, "pg_ctl",
										 "pg_ctl (PostgreSQL) " PG_VERSION "\n");

	pg_log_debug("found pg_ctl at: %s", pg_ctl_path);

	snprintf(logfile, sizeof(logfile), "%s/logfile", pg_data);

	initPQExpBuffer(&buf);

	appendPQExpBuffer(&buf, "\"%s\"", pg_ctl_path);

	appendPQExpBufferStr(&buf, " start");

	appendPQExpBuffer(&buf, " -D \"%s\"", pg_data);

	/* Wait for server to start */
	appendPQExpBufferStr(&buf, " -w");

	appendPQExpBufferStr(&buf, " -t 60");

	/* Specify log file */
	appendPQExpBuffer(&buf, " -l \"%s\"", logfile);

	cmd = buf.data;

	pg_log_debug("executing: %s", cmd);
	pg_log_info("starting database server...");

	fflush(NULL);
	result = system(cmd);

	if (result != 0)
	{
		pg_log_error("database server start failed");
		pg_log_error_hint("Check the log file at \"%s\" for details.", logfile);
		pg_log_error_hint("Common issues:");
		pg_log_error_hint("  - Port %d may already be in use", port);
		pg_log_error_hint("  - Check postgresql.conf for configuration errors");
		pg_log_error_hint("  - Ensure proper file permissions on data directory");
		termPQExpBuffer(&buf);
		do_rollback();
		exit(1);
	}

	termPQExpBuffer(&buf);
	pg_free(pg_ctl_path);

	pg_log_info("database server started successfully");
	pg_log_info("server is listening on port %d", port);
	pg_log_info("log file: %s", logfile);
}

static void
verify_connection(void)
{
	PGconn	   *conn;
	PQExpBufferData conninfo;
	char	   *host;
	const char *dbname = "postgres";
	PGresult   *res;

	pg_log_debug("verifying database connection");

	initPQExpBuffer(&conninfo);

	/* Determine host to connect to */
	if (listen_addresses != NULL)
	{
		if (strcmp(listen_addresses, "*") == 0 ||
			strcmp(listen_addresses, "0.0.0.0") == 0)
		{
			host = "localhost";
		}
		else if (strstr(listen_addresses, ",") != NULL)
		{
			/* Multiple addresses, use the first one */
			char *addr_copy = pg_strdup(listen_addresses);
			char *comma = strchr(addr_copy, ',');
			if (comma)
				*comma = '\0';

			/* Trim whitespace */
			host = addr_copy;
			while (*host && isspace((unsigned char) *host))
				host++;

			if (strcmp(host, "*") == 0 || strcmp(host, "0.0.0.0") == 0)
				host = "localhost";
		}
		else
		{
			/* Single address */
			host = listen_addresses;
			if (strcmp(host, "*") == 0 || strcmp(host, "0.0.0.0") == 0)
				host = "localhost";
		}
	}
	else
	{
		host = "localhost";
	}

	appendPQExpBuffer(&conninfo, "host=%s port=%d dbname=%s user=%s",
					  host, port, dbname, username ? username : "postgres");

	if (superuser_password != NULL && strlen(superuser_password) > 0)
	{
		appendPQExpBuffer(&conninfo, " password=%s", superuser_password);
	}

	appendPQExpBufferStr(&conninfo, " connect_timeout=10");

	pg_log_debug("connection string: host=%s port=%d dbname=%s user=%s",
					host, port, dbname, username ? username : "postgres");

	/* Attempt to connect */
	pg_log_info("verifying connection to database...");
	conn = PQconnectdb(conninfo.data);

	if (PQstatus(conn) != CONNECTION_OK)
	{
		pg_log_error("connection to database failed: %s", PQerrorMessage(conn));
		pg_log_error_hint("Possible causes:");
		pg_log_error_hint("  - Server may not be fully started yet");
		pg_log_error_hint("  - Authentication settings in pg_hba.conf may be incorrect");
		pg_log_error_hint("  - Password may be required but not provided");
		pg_log_error_hint("  - Port %d may be blocked by firewall", port);

		PQfinish(conn);
		termPQExpBuffer(&conninfo);
		exit(1);
	}

	pg_log_debug("connection established successfully");

	res = PQexec(conn, "SELECT version()");

	if (PQresultStatus(res) != PGRES_TUPLES_OK)
	{
		pg_log_error("query execution failed: %s", PQerrorMessage(conn));
		PQclear(res);
		PQfinish(conn);
		termPQExpBuffer(&conninfo);
		exit(1);
	}

	if (PQntuples(res) > 0)
	{
		char *version = PQgetvalue(res, 0, 0);
		pg_log_debug("server version: %s", version);
	}

	PQclear(res);

	/* Connection verified successfully */
	pg_log_info("connection verified successfully");
	printf("\n");
	pg_log_info("===========================================");
	pg_log_info("Database Setup Complete!");
	pg_log_info("===========================================");
	printf("\n");
	pg_log_info("Connection Information:");
	pg_log_info("  Host: %s", host);
	pg_log_info("  Port: %d", port);
	pg_log_info("  Database: %s", database_name ? database_name : "postgres");
	pg_log_info("  User: %s", username ? username : "postgres");
	printf("\n");
	pg_log_info("To connect to your database, use:");
	pg_log_info("  psql -h %s -p %d -U %s -d %s",
				host, port, username ? username : "postgres",
				database_name ? database_name : "postgres");
	printf("\n");

	/* Clean up */
	PQfinish(conn);
	termPQExpBuffer(&conninfo);
}

static void
create_initial_database(void)
{
	PGconn	   *conn;
	PQExpBufferData conninfo;
	PQExpBufferData query;
	char	   *host;
	const char *dbname = "postgres";
	PGresult   *res;

	if (database_name == NULL || strlen(database_name) == 0)
	{
		pg_log_debug("no initial database name specified, skipping database creation");
		return;
	}

	pg_log_debug("creating initial database: %s", database_name);

	initPQExpBuffer(&conninfo);

	if (listen_addresses != NULL)
	{
		if (strcmp(listen_addresses, "*") == 0 ||
			strcmp(listen_addresses, "0.0.0.0") == 0)
		{
			host = "localhost";
		}
		else if (strstr(listen_addresses, ",") != NULL)
		{
			char *addr_copy = pg_strdup(listen_addresses);
			char *comma = strchr(addr_copy, ',');
			if (comma)
				*comma = '\0';

			host = addr_copy;
			while (*host && isspace((unsigned char) *host))
				host++;

			if (strcmp(host, "*") == 0 || strcmp(host, "0.0.0.0") == 0)
				host = "localhost";
		}
		else
		{
			host = listen_addresses;
			if (strcmp(host, "*") == 0 || strcmp(host, "0.0.0.0") == 0)
				host = "localhost";
		}
	}
	else
	{
		host = "localhost";
	}

	appendPQExpBuffer(&conninfo, "host=%s port=%d dbname=%s user=%s",
					  host, port, dbname, username ? username : "postgres");

	if (superuser_password != NULL && strlen(superuser_password) > 0)
	{
		appendPQExpBuffer(&conninfo, " password=%s", superuser_password);
	}

	appendPQExpBufferStr(&conninfo, " connect_timeout=10");

	pg_log_debug("connecting to postgres database to create initial database");
	conn = PQconnectdb(conninfo.data);

	if (PQstatus(conn) != CONNECTION_OK)
	{
		pg_log_error("connection to database failed: %s", PQerrorMessage(conn));
		pg_log_error_hint("Could not create initial database '%s'", database_name);
		PQfinish(conn);
		termPQExpBuffer(&conninfo);
		exit(1);
	}

	pg_log_debug("connection established, creating database");

	initPQExpBuffer(&query);
	appendPQExpBuffer(&query, "CREATE DATABASE %s", database_name);

	res = PQexec(conn, query.data);

	if (PQresultStatus(res) != PGRES_COMMAND_OK)
	{
		char *sqlstate = PQresultErrorField(res, PG_DIAG_SQLSTATE);

		if (sqlstate && strcmp(sqlstate, "42P04") == 0)
		{
			pg_log_warning("database \"%s\" already exists, skipping creation", database_name);
		}
		else
		{
			pg_log_error("could not create database \"%s\": %s",
						 database_name, PQerrorMessage(conn));
			PQclear(res);
			PQfinish(conn);
			termPQExpBuffer(&conninfo);
			termPQExpBuffer(&query);
			exit(1);
		}
	}
	else
	{
		pg_log_info("database \"%s\" created successfully", database_name);
	}

	/* Clean up */
	PQclear(res);
	PQfinish(conn);
	termPQExpBuffer(&conninfo);
	termPQExpBuffer(&query);
}

static void
do_setup(void)
{
	time_t		start_time;
	time_t		step_start_time;
	time_t		step_end_time;
	int			step_num = 0;
	int			total_steps;

	total_steps = 3;
	if (start_server)
	{
		total_steps += 2;
		if (database_name != NULL && strlen(database_name) > 0)
			total_steps += 1;
	}

	pg_log_debug("beginning setup process");


	start_time = time(NULL);

	step_num++;
	printf(_("\n[%d/%d] Initializing database cluster...\n"), step_num, total_steps);
	pg_log_info("step %d/%d: initializing database cluster", step_num, total_steps);

	step_start_time = time(NULL);
	run_initdb();
	step_end_time = time(NULL);

	printf(_("  ✓ Database cluster initialized (%ld seconds)\n"),
		   (long)(step_end_time - step_start_time));
	pg_log_debug("step %d completed in %ld seconds", step_num,
					(long)(step_end_time - step_start_time));

	step_num++;
	printf(_("\n[%d/%d] Configuring postgresql.conf...\n"), step_num, total_steps);
	pg_log_info("step %d/%d: configuring postgresql.conf", step_num, total_steps);

	step_start_time = time(NULL);
	setup_postgresql_conf();
	step_end_time = time(NULL);

	printf(_("  ✓ postgresql.conf configured (%ld seconds)\n"),
		   (long)(step_end_time - step_start_time));
	pg_log_debug("step %d completed in %ld seconds", step_num,
					(long)(step_end_time - step_start_time));

	step_num++;
	printf(_("\n[%d/%d] Configuring pg_hba.conf...\n"), step_num, total_steps);
	pg_log_info("step %d/%d: configuring pg_hba.conf", step_num, total_steps);

	step_start_time = time(NULL);
	setup_pg_hba_conf();
	step_end_time = time(NULL);

	printf(_("  ✓ pg_hba.conf configured (%ld seconds)\n"),
		   (long)(step_end_time - step_start_time));
	pg_log_debug("step %d completed in %ld seconds", step_num,
					(long)(step_end_time - step_start_time));

	if (start_server)
	{
		step_num++;
		printf(_("\n[%d/%d] Starting database server...\n"), step_num, total_steps);
		pg_log_info("step %d/%d: starting database server", step_num, total_steps);

		step_start_time = time(NULL);
		start_database_server();
		step_end_time = time(NULL);

		printf(_("  ✓ Database server started (%ld seconds)\n"),
			   (long)(step_end_time - step_start_time));
		pg_log_debug("step %d completed in %ld seconds", step_num,
						(long)(step_end_time - step_start_time));

		step_num++;
		printf(_("\n[%d/%d] Verifying database connection...\n"), step_num, total_steps);
		pg_log_info("step %d/%d: verifying database connection", step_num, total_steps);

		step_start_time = time(NULL);
		verify_connection();
		step_end_time = time(NULL);

		printf(_("  ✓ Connection verified (%ld seconds)\n"),
			   (long)(step_end_time - step_start_time));
		pg_log_debug("step %d completed in %ld seconds", step_num,
						(long)(step_end_time - step_start_time));

		if (database_name != NULL && strlen(database_name) > 0)
		{
			step_num++;
			printf(_("\n[%d/%d] Creating initial database...\n"), step_num, total_steps);
			pg_log_info("step %d/%d: creating initial database '%s'", step_num, total_steps, database_name);

			step_start_time = time(NULL);
			create_initial_database();
			step_end_time = time(NULL);

			printf(_("  ✓ Database '%s' created (%ld seconds)\n"),
				   database_name, (long)(step_end_time - step_start_time));
			pg_log_debug("step %d completed in %ld seconds", step_num,
							(long)(step_end_time - step_start_time));
		}
	}
	else
	{
		printf(_("\n"));
		printf(_("===========================================\n"));
		printf(_("Database Setup Complete!\n"));
		printf(_("===========================================\n\n"));

		printf(_("Database cluster has been initialized successfully.\n"));
		printf(_("Data directory: %s\n\n"), pg_data);

		printf(_("To start the database server, run:\n"));
		printf(_("  pg_ctl -D \"%s\" start\n\n"), pg_data);

		printf(_("After starting the server, you can connect with:\n"));
		printf(_("  psql -h localhost -p %d -U %s -d postgres\n\n"),
			   port, username ? username : "postgres");

		pg_log_info("database cluster initialized successfully");
		pg_log_info("server not started (use --start to start automatically)");
	}

	setup_success = true;

	{
		time_t end_time = time(NULL);
		long total_seconds = (long)(end_time - start_time);

		printf(_("\nTotal setup time: %ld seconds\n"), total_seconds);

		pg_log_info("setup completed successfully in %ld seconds", total_seconds);
	}
}

static void
do_rollback(void)
{
	bool		should_rollback = false;
	char		response[10];

	if (noclean)
	{
		pg_log_warning("rollback disabled (--noclean option specified)");
		pg_log_info("data directory \"%s\" has been left in place for debugging",
					pg_data ? pg_data : "(unknown)");
		return;
	}

	printf(_("\nSetup failed. Do you want to rollback the changes? (yes/no) "));
	fflush(stdout);

	if (fgets(response, sizeof(response), stdin) != NULL)
	{
		char *p = strchr(response, '\n');
		if (p)
			*p = '\0';

		if (pg_strcasecmp(response, "yes") == 0 || pg_strcasecmp(response, "y") == 0)
		{
			should_rollback = true;
		}
	}

	if (!should_rollback)
	{
		pg_log_info("rollback cancelled by user");
		pg_log_info("data directory \"%s\" has been left in place",
					pg_data ? pg_data : "(unknown)");
		return;
	}

	pg_log_info("rolling back changes...");
	if (pg_data != NULL)
	{
		char	   *pg_ctl_path;
		char	   *cmd;
		PQExpBufferData buf;
		int			result;

		pg_ctl_path = pg_malloc(MAXPGPATH);
		if (find_other_exec(progname, "pg_ctl", "pg_ctl (PostgreSQL) " PG_VERSION "\n",
							pg_ctl_path) >= 0)
		{
			initPQExpBuffer(&buf);
			appendPQExpBuffer(&buf, "\"%s\" stop -D \"%s\" -m immediate > /dev/null 2>&1",
							  pg_ctl_path, pg_data);
			cmd = buf.data;

			pg_log_debug("attempting to stop server: %s", cmd);

			result = system(cmd);

			if (result == 0)
			{
				pg_log_info("stopped database server");
			}
			else
			{
				pg_log_error("server was not running or stop failed (this is OK)");
			}
			termPQExpBuffer(&buf);
		}
		pg_free(pg_ctl_path);
	}

	if (made_new_pgdata && pg_data != NULL)
	{
		pg_log_debug("removing data directory \"%s\"", pg_data);

		if (!rmtree(pg_data, true))
		{
			pg_log_error("failed to remove data directory \"%s\"", pg_data);
			pg_log_error_hint("You may need to manually remove the directory:");
			pg_log_error_hint("  rm -rf \"%s\"", pg_data);
			pg_log_error_hint("Or on Windows:");
			pg_log_error_hint("  rmdir /s /q \"%s\"", pg_data);
			return;
		}

		pg_log_info("removed data directory \"%s\"", pg_data);
	}
	else if (found_existing_pgdata && pg_data != NULL)
	{
		pg_log_warning("data directory \"%s\" existed before setup", pg_data);
		pg_log_warning_hint("The directory may contain partial initialization.");
		pg_log_warning_hint("You may want to manually inspect or remove it.");
	}

	made_new_pgdata = false;
	setup_success = false;

	pg_log_info("rollback completed successfully");
}

static void
cleanup(void)
{
	pg_log_debug("performing cleanup");
	if (superuser_password != NULL)
	{
		memset(superuser_password, 0, strlen(superuser_password));
		pg_free(superuser_password);
		superuser_password = NULL;
	}

	if (pg_data != NULL && made_new_pgdata)
	{
		/* Only free if we allocated it */
	}
	pg_log_debug("cleanup completed");
}
