
#include "postgres.h"

#include <time.h>

#include "fmgr.h"
#include "miscadmin.h"
#include "nodes/nodeFuncs.h"
#include "nodes/parsenodes.h"
#include "nodes/print.h"
#include "optimizer/planner.h"
#include "parser/analyze.h"
#include "parser/parser.h"
#include "storage/fd.h"
#include "tcop/tcopprot.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/memutils.h"

PG_MODULE_MAGIC;

typedef enum VizStage
{
	VIZ_STAGE_PARSE = 0,
	VIZ_STAGE_ANALYZE = 1,
	VIZ_STAGE_PLAN = 2,
	VIZ_STAGE_EXECUTOR = 3,
	VIZ_STAGE_ALL = -1
} VizStage;

typedef char *(*FormatterFunc)(const void *node, const char *stage_name);

typedef struct Formatter
{
	const char *name;
	const char *description;
	FormatterFunc format;
	void (*cleanup)(void);
} Formatter;

typedef struct VizContext
{
	const void *node;
	VizStage stage;
	const Formatter *formatter;
	const char *stage_name;
} VizContext;

typedef struct VizConfig
{
	bool enabled;
	int output_format;
	int viz_stage;
	char *output_file;
} VizConfig;

static char *format_raw(const void *node, const char *stage_name);
static char *format_dot(const void *node, const char *stage_name);
static char *format_json(const void *node, const char *stage_name);
static char *format_xml(const void *node, const char *stage_name);

static Formatter formatters[] = {
	{
		.name = "raw",
		.description = "Raw nodeToString() output",
		.format = format_raw,
		.cleanup = NULL
	},
	{
		.name = "dot",
		.description = "Graphviz DOT format",
		.format = format_dot,
		.cleanup = NULL
	},
	{
		.name = "json",
		.description = "JSON format (future)",
		.format = format_json,
		.cleanup = NULL
	},
	{
		.name = "xml",
		.description = "XML format (future)",
		.format = format_xml,
		.cleanup = NULL
	},
	{NULL, NULL, NULL, NULL}
};

static const Formatter *
get_formatter_by_index(int index)
{
	int count = 0;

	while (formatters[count].name != NULL)
		count++;

	if (index < 0 || index >= count)
		return NULL;

	return &formatters[index];
}

static const Formatter *
get_formatter_by_name(const char *name)
{
	const Formatter *fmt;

	for (fmt = formatters; fmt->name != NULL; fmt++)
	{
		if (strcmp(fmt->name, name) == 0)
			return fmt;
	}

	return NULL;
}

static const char *stage_names[] = {
	"parse",
	"analyze",
	"plan",
	"executor",
	NULL
};

static const char *
get_stage_name(VizStage stage)
{
	if (stage < 0 || stage >= VIZ_STAGE_EXECUTOR + 1)
		return "unknown";

	return stage_names[stage];
}

static bool
is_stage_enabled(VizStage stage, const VizConfig *cfg)
{

	if (cfg->viz_stage == VIZ_STAGE_ALL)
		return true;

	return (cfg->viz_stage == stage);
}

static VizConfig config;

static post_parse_analyze_hook_type prev_post_parse_analyze_hook = NULL;
static planner_hook_type prev_planner_hook = NULL;

static struct config_enum_entry *
build_format_options(void)
{
	int count = 0;
	const Formatter *fmt;
	struct config_enum_entry *options;

	for (fmt = formatters; fmt->name != NULL; fmt++)
		count++;

	options = palloc((count + 1) * sizeof(struct config_enum_entry));

	for (int i = 0; i < count; i++)
	{
		options[i].name = formatters[i].name;
		options[i].val = i;
		options[i].hidden = false;
	}

	options[count].name = NULL;
	options[count].val = 0;
	options[count].hidden = false;

	return options;
}

static const struct config_enum_entry viz_stage_options[] = {
	{"parse", VIZ_STAGE_PARSE, false},
	{"analyze", VIZ_STAGE_ANALYZE, false},
	{"plan", VIZ_STAGE_PLAN, false},
	{"executor", VIZ_STAGE_EXECUTOR, false},
	{"all", VIZ_STAGE_ALL, false},
	{NULL, 0, false}
};

static char *visualize_node(const VizContext *ctx);
static void output_visualization(const char *content, const VizContext *ctx);
static bool write_to_file(const char *filepath, const char *content);

static void pgptv_post_parse_analyze_hook(ParseState *pstate, Query *query,
                                          JumbleState *jstate);
static PlannedStmt *pgptv_planner_hook(Query *parse, const char *query_string,
                                       int cursorOptions, ParamListInfo boundParams);

static char *visualize_query_tree(Query *query, VizConfig *config);
static char *convert_nodestring_to_dot(const char *node_str);

void
_PG_init(void)
{
	struct config_enum_entry *format_options;

	if (!process_shared_preload_libraries_in_progress)
		return;

	format_options = build_format_options();

	DefineCustomBoolVariable(
	    "pg_tree_viz.enabled",
	    "Enable tree visualization",
	    "When enabled, visualizes query trees at configured stages",
	    &config.enabled,
	    false,
	    PGC_USERSET,
	    0,
	    NULL,
	    NULL,
	    NULL);

	DefineCustomEnumVariable(
	    "pg_tree_viz.output_format",
	    "Output format for tree visualization",
	    "Available formats: raw, dot, json, xml",
	    &config.output_format,
	    0,
	    format_options,
	    PGC_USERSET,
	    0,
	    NULL, NULL, NULL);

	DefineCustomEnumVariable(
	    "pg_tree_viz.viz_stage",
	    "Which processing stage(s) to visualize",
	    "Valid values: parse, analyze, plan, executor, all",
	    &config.viz_stage,
	    VIZ_STAGE_ANALYZE,
	    viz_stage_options,
	    PGC_USERSET,
	    0,
	    NULL, NULL, NULL);

	DefineCustomStringVariable(
	    "pg_tree_viz.output_file",
	    "Output file path for tree visualization",
	    "Relative paths are resolved relative to data directory. "
	    "Set to empty string or NULL for NOTICE output.",
	    &config.output_file,
	    "pg_tree_viz.log",
	    PGC_USERSET,
	    0,
	    NULL, NULL, NULL);

	prev_post_parse_analyze_hook = post_parse_analyze_hook;
	post_parse_analyze_hook = pgptv_post_parse_analyze_hook;

	prev_planner_hook = planner_hook;
	planner_hook = pgptv_planner_hook;
}

static char *
format_raw(const void *node, const char *stage_name)
{
	StringInfoData buf;
	char *node_str;
	char *pretty_str;

	if (node == NULL)
		return NULL;

	initStringInfo(&buf);

	appendStringInfo(&buf, "=== Stage: %s ===\n\n", stage_name);

	node_str = nodeToString(node);
	pretty_str = pretty_format_node_dump(node_str);
	pfree(node_str);

	appendStringInfoString(&buf, pretty_str);
	pfree(pretty_str);

	return buf.data;
}

static char *
format_dot(const void *node, const char *stage_name)
{
	char *node_str;
	char *dot_str;

	if (node == NULL)
		return NULL;

	node_str = nodeToString(node);

	dot_str = convert_nodestring_to_dot(node_str);
	pfree(node_str);

	return dot_str;
}

static char *
format_json(const void *node, const char *stage_name)
{
	StringInfoData buf;
	char *node_str;

	if (node == NULL)
		return NULL;

	initStringInfo(&buf);

	appendStringInfoString(&buf, "{\n");
	appendStringInfo(&buf, "  \"stage\": \"%s\",\n", stage_name);
	appendStringInfoString(&buf, "  \"format\": \"json\",\n");
	appendStringInfoString(&buf, "  \"tree\": ");

	node_str = nodeToString(node);

	appendStringInfo(&buf, "\"%s\"\n", node_str);
	pfree(node_str);

	appendStringInfoString(&buf, "}\n");

	return buf.data;
}

static char *
format_xml(const void *node, const char *stage_name)
{
	StringInfoData buf;
	char *node_str;

	if (node == NULL)
		return NULL;

	initStringInfo(&buf);

	appendStringInfoString(&buf, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
	appendStringInfo(&buf, "<tree stage=\"%s\" format=\"xml\">\n", stage_name);

	node_str = nodeToString(node);
	appendStringInfo(&buf, "  <content><![CDATA[%s]]></content>\n", node_str);
	pfree(node_str);

	appendStringInfoString(&buf, "</tree>\n");

	return buf.data;
}

static char *
visualize_node(const VizContext *ctx)
{
	char *result;

	if (ctx == NULL || ctx->node == NULL || ctx->formatter == NULL)
		return NULL;

	result = ctx->formatter->format(ctx->node, ctx->stage_name);

	return result;
}

static void
output_visualization(const char *content, const VizContext *ctx)
{
	if (content == NULL)
		return;

	if (config.output_file != NULL && config.output_file[0] != '\0')
	{
		bool success = write_to_file(config.output_file, content);

		if (!success)
		{

			ereport(WARNING,
			        (errmsg("failed to write to file: %s", config.output_file),
			         errhint("falling back to NOTICE output")));

			ereport(NOTICE,
			        (errmsg("Tree Visualization [%s]:\n%s",
			                ctx->stage_name, content)));
		}
	}
	else
	{

		ereport(NOTICE,
		        (errmsg("Tree Visualization [%s]:\n%s",
		                ctx->stage_name, content)));
	}
}

static void
pgptv_post_parse_analyze_hook(ParseState *pstate, Query *query, JumbleState *jstate)
{
	const Formatter *formatter;
	VizContext ctx;
	char *result;

	if (prev_post_parse_analyze_hook)
		prev_post_parse_analyze_hook(pstate, query, jstate);

	if (!config.enabled)
		return;

	if (!is_stage_enabled(VIZ_STAGE_ANALYZE, &config))
		return;

	if (query->commandType == CMD_UTILITY)
		return;

	formatter = get_formatter_by_index(config.output_format);
	if (formatter == NULL)
		return;

	ctx.node = query;
	ctx.stage = VIZ_STAGE_ANALYZE;
	ctx.formatter = formatter;
	ctx.stage_name = get_stage_name(VIZ_STAGE_ANALYZE);

	PG_TRY();
	{
		result = visualize_node(&ctx);
		if (result)
		{
			output_visualization(result, &ctx);
			pfree(result);
		}
	}
	PG_CATCH();
	{
		ereport(WARNING,
		        (errmsg("error during tree visualization"),
		         errdetail("visualization failed but query execution will continue")));
		FlushErrorState();
	}
	PG_END_TRY();
}

static PlannedStmt *
pgptv_planner_hook(Query *parse, const char *query_string,
                   int cursorOptions, ParamListInfo boundParams)
{
	PlannedStmt *result;
	const Formatter *formatter;
	VizContext ctx;
	char *viz_result;

	if (prev_planner_hook)
		result = prev_planner_hook(parse, query_string, cursorOptions, boundParams);
	else
		result = standard_planner(parse, query_string, cursorOptions, boundParams);

	if (!config.enabled)
		return result;

	if (!is_stage_enabled(VIZ_STAGE_PLAN, &config))
		return result;

	formatter = get_formatter_by_index(config.output_format);
	if (formatter == NULL)
		return result;

	ctx.node = result;
	ctx.stage = VIZ_STAGE_PLAN;
	ctx.formatter = formatter;
	ctx.stage_name = get_stage_name(VIZ_STAGE_PLAN);

	PG_TRY();
	{
		viz_result = visualize_node(&ctx);
		if (viz_result)
		{
			output_visualization(viz_result, &ctx);
			pfree(viz_result);
		}
	}
	PG_CATCH();
	{
		ereport(WARNING,
		        (errmsg("error during tree visualization"),
		         errdetail("visualization failed but query execution will continue")));
		FlushErrorState();
	}
	PG_END_TRY();

	return result;
}

void
_PG_fini(void)
{

	post_parse_analyze_hook = prev_post_parse_analyze_hook;
	planner_hook = prev_planner_hook;
}

typedef struct NodeStackEntry
{
	int node_id;
	char *field_name;
} NodeStackEntry;

static char *
convert_nodestring_to_dot(const char *node_str)
{
	StringInfoData dot;
	StringInfoData node_label;
	const char *p = node_str;
	int node_id = 0;
	int current_node_id = 0;
	int depth = 0;
	NodeStackEntry *node_stack;
	int stack_top = -1;
	int stack_size = 1000;
	bool in_node = false;
	bool in_list = false;
	int list_depth = 0;

	initStringInfo(&dot);
	initStringInfo(&node_label);

	node_stack = (NodeStackEntry *)palloc(sizeof(NodeStackEntry) * stack_size);

	appendStringInfoString(&dot, "digraph ParseTree {\n");
	appendStringInfoString(&dot, "  rankdir=TB;\n");
	appendStringInfoString(&dot, "  node [shape=box];\n");

	while (*p != '\0')
	{
		if (*p == '{' && !in_list)
		{

			const char *type_start;
			int type_len;

			depth++;
			p++;

			while (*p == ' ' || *p == '\t' || *p == '\n')
				p++;

			type_start = p;

			while (*p != ' ' && *p != ':' && *p != '}' && *p != '\0' &&
			       *p != '\t' && *p != '\n')
				p++;

			type_len = p - type_start;

			if (type_len > 0)
			{

				node_id++;
				current_node_id = node_id;
				in_node = true;

				resetStringInfo(&node_label);
				appendStringInfo(&node_label, "%.*s", type_len, type_start);

				while (*p == ' ' || *p == '\t' || *p == '\n')
					p++;
			}
		}
		else if (*p == '}' && !in_list)
		{

			if (in_node)
			{

				appendStringInfo(&dot, "  n%d [label=\"%s\"];\n",
				                 current_node_id, node_label.data);

				if (stack_top >= 0)
				{
					NodeStackEntry parent = node_stack[stack_top];

					appendStringInfo(&dot, "  n%d -> n%d [label=\"%s\"];\n",
					                 parent.node_id, current_node_id,
					                 parent.field_name);

					pfree(parent.field_name);
					stack_top--;
				}

				in_node = false;
			}

			depth--;
			p++;
		}
		else if (*p == '(' && in_node)
		{

			in_list = true;
			list_depth = 1;
			p++;

			while (*p != '\0' && list_depth > 0)
			{
				if (*p == '(')
					list_depth++;
				else if (*p == ')')
					list_depth--;
				p++;
			}

			in_list = false;
		}
		else if (*p == ':' && in_node && !in_list)
		{

			const char *field_start;
			int field_len;

			p++;

			while (*p == ' ' || *p == '\t' || *p == '\n')
				p++;

			field_start = p;

			while (*p != ' ' && *p != '\0' && *p != '\t' && *p != '\n')
				p++;

			field_len = p - field_start;

			if (field_len > 0)
			{

				while (*p == ' ' || *p == '\t' || *p == '\n')
					p++;

				if (*p == '{')
				{

					char *field_name = (char *)palloc(field_len + 1);

					memcpy(field_name, field_start, field_len);
					field_name[field_len] = '\0';

					stack_top++;
					if (stack_top >= stack_size)
					{

						stack_size *= 2;
						node_stack = (NodeStackEntry *)repalloc(
						    node_stack, sizeof(NodeStackEntry) * stack_size);
					}

					node_stack[stack_top].node_id = current_node_id;
					node_stack[stack_top].field_name = field_name;

				}
				else if (*p == '(')
				{

					in_list = true;
					list_depth = 1;
					p++;

					while (*p != '\0' && list_depth > 0)
					{
						if (*p == '(')
							list_depth++;
						else if (*p == ')')
							list_depth--;
						p++;
					}

					in_list = false;
				}
				else
				{

					const char *value_start;
					int value_len;

					value_start = p;

					while (*p != ' ' && *p != ':' && *p != '}' && *p != '\0' &&
					       *p != '\t' && *p != '\n')
						p++;

					value_len = p - value_start;

					if (value_len > 0)
					{

						if (value_len > 50)
							value_len = 50;

						appendStringInfo(&node_label, "\\n%.*s: %.*s",
						                 field_len, field_start, value_len,
						                 value_start);
					}
				}
			}
		}
		else
		{

			p++;
		}
	}

	appendStringInfoString(&dot, "}\n");

	pfree(node_stack);
	pfree(node_label.data);

	return dot.data;
}

static bool
write_to_file(const char *filepath, const char *content)
{
	FILE *file = NULL;
	bool success = false;
	char *full_path = NULL;
	time_t now;
	struct tm *tm_info;
	char timestamp[64];

	if (filepath[0] != '/')
	{

		full_path = psprintf("%s/%s", DataDir, filepath);
	}
	else
	{

		full_path = pstrdup(filepath);
	}

	PG_TRY();
	{

		file = AllocateFile(full_path, "a");
		if (file == NULL)
		{
			ereport(WARNING,
			        (errcode_for_file_access(),
			         errmsg("could not open file \"%s\" for writing: %m",
			                full_path)));
			pfree(full_path);
			return false;
		}

		now = time(NULL);
		tm_info = localtime(&now);
		strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", tm_info);

		fprintf(file, "\n========================================\n");
		fprintf(file, "Timestamp: %s\n", timestamp);
		fprintf(file, "========================================\n");
		fprintf(file, "%s\n", content);
		fprintf(file, "========================================\n\n");

		fflush(file);

		success = true;
	}
	PG_CATCH();
	{

		ereport(WARNING, (errmsg("error writing to file \"%s\"", full_path)));
		success = false;

		FlushErrorState();
	}
	PG_END_TRY();

	if (file != NULL)
		FreeFile(file);

	pfree(full_path);

	return success;
}

static char *
visualize_query_tree(Query *query, VizConfig *cfg)
{
	const Formatter *formatter;
	VizContext ctx;

	formatter = get_formatter_by_index(cfg->output_format);
	if (formatter == NULL)
		return NULL;

	ctx.node = query;
	ctx.stage = VIZ_STAGE_ANALYZE;
	ctx.formatter = formatter;
	ctx.stage_name = get_stage_name(VIZ_STAGE_ANALYZE);

	return visualize_node(&ctx);
}

PG_FUNCTION_INFO_V1(pg_tree_viz_parse);
Datum
pg_tree_viz_parse(PG_FUNCTION_ARGS)
{
	text *query_arg;
	char *query_str;
	char *format_str;
	List *raw_parsetree_list;
	RawStmt *raw_stmt;
	const Formatter *formatter;
	VizContext ctx;
	char *result;
	text *result_text;

	if (PG_ARGISNULL(0))
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
		                errmsg("query parameter cannot be NULL")));

	query_arg = PG_GETARG_TEXT_PP(0);
	query_str = text_to_cstring(query_arg);

	if (PG_ARGISNULL(1))
		format_str = "raw";
	else
	{
		text *format_arg = PG_GETARG_TEXT_PP(1);
		format_str = text_to_cstring(format_arg);
	}

	formatter = get_formatter_by_name(format_str);
	if (formatter == NULL)
		ereport(ERROR,
		        (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
		         errmsg("invalid format: %s", format_str),
		         errhint("Valid formats are: raw, dot, json, xml")));

	raw_parsetree_list = raw_parser(query_str, RAW_PARSE_DEFAULT);

	if (raw_parsetree_list == NIL)
		ereport(ERROR,
		        (errcode(ERRCODE_SYNTAX_ERROR), errmsg("empty query string")));

	raw_stmt = (RawStmt *)linitial(raw_parsetree_list);

	ctx.node = raw_stmt->stmt;
	ctx.stage = VIZ_STAGE_PARSE;
	ctx.formatter = formatter;
	ctx.stage_name = get_stage_name(VIZ_STAGE_PARSE);

	result = visualize_node(&ctx);

	if (result == NULL)
		PG_RETURN_NULL();

	result_text = cstring_to_text(result);
	pfree(result);

	PG_RETURN_TEXT_P(result_text);
}

PG_FUNCTION_INFO_V1(pg_tree_viz_query);
Datum
pg_tree_viz_query(PG_FUNCTION_ARGS)
{
	text *query_arg;
	char *query_str;
	char *format_str;
	List *raw_parsetree_list;
	RawStmt *raw_stmt;
	Query *query;
	VizConfig local_config;
	const Formatter *formatter;
	char *result;
	text *result_text;

	if (PG_ARGISNULL(0))
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
		                errmsg("query parameter cannot be NULL")));

	query_arg = PG_GETARG_TEXT_PP(0);
	query_str = text_to_cstring(query_arg);

	if (PG_ARGISNULL(1))
		format_str = "raw";
	else
	{
		text *format_arg = PG_GETARG_TEXT_PP(1);
		format_str = text_to_cstring(format_arg);
	}

	formatter = get_formatter_by_name(format_str);
	if (formatter == NULL)
		ereport(ERROR,
		        (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
		         errmsg("invalid format: %s", format_str),
		         errhint("Valid formats are: raw, dot, json, xml")));

	raw_parsetree_list = raw_parser(query_str, RAW_PARSE_DEFAULT);

	if (raw_parsetree_list == NIL)
		ereport(ERROR,
		        (errcode(ERRCODE_SYNTAX_ERROR), errmsg("empty query string")));

	raw_stmt = (RawStmt *)linitial(raw_parsetree_list);

	query = parse_analyze_fixedparams(raw_stmt, query_str, NULL, 0, NULL);

	local_config.output_format = formatter - formatters;
	local_config.output_file = NULL;

	result = visualize_query_tree(query, &local_config);

	if (result == NULL)
		PG_RETURN_NULL();

	result_text = cstring_to_text(result);
	pfree(result);

	PG_RETURN_TEXT_P(result_text);
}
