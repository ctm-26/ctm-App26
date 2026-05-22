#include "csv.h"

#include <stdlib.h>
#include <string.h>

int csv_open(csv_reader *r, const char *path)
{
	memset(r, 0, sizeof *r);
	r->fp = fopen(path, "r");
	if (!r->fp) return -1;
	r->line_cap = 1024;
	r->line_buf = malloc(r->line_cap);
	if (!r->line_buf) {
		fclose(r->fp);
		r->fp = NULL;
		return -1;
	}
	return 0;
}

void csv_close(csv_reader *r)
{
	if (!r) return;
	if (r->fp) { fclose(r->fp); r->fp = NULL; }
	free(r->line_buf);
	r->line_buf = NULL;
}

/* Read one logical CSV record into r->line_buf as a single contiguous buffer.
   Supports quoted fields with embedded newlines and "" escapes.
   Returns 1 on success, 0 on EOF, -1 on error. */
static int read_record(csv_reader *r)
{
	size_t used = 0;
	int in_quotes = 0;
	int saw_any = 0;
	int c;
	while ((c = fgetc(r->fp)) != EOF) {
		saw_any = 1;
		if (used + 2 >= r->line_cap) {
			size_t new_cap = r->line_cap * 2;
			char *nb = realloc(r->line_buf, new_cap);
			if (!nb) return -1;
			r->line_buf = nb;
			r->line_cap = new_cap;
		}
		if (c == '"') {
			r->line_buf[used++] = (char)c;
			in_quotes = !in_quotes;
			if (!in_quotes) {
				int peek = fgetc(r->fp);
				if (peek == '"') {
					r->line_buf[used++] = '"';
					in_quotes = 1;
				} else if (peek != EOF) {
					ungetc(peek, r->fp);
				}
			}
			continue;
		}
		if ((c == '\n' || c == '\r') && !in_quotes) {
			if (c == '\r') {
				int peek = fgetc(r->fp);
				if (peek != '\n' && peek != EOF) ungetc(peek, r->fp);
			}
			break;
		}
		r->line_buf[used++] = (char)c;
	}
	r->line_buf[used] = '\0';
	if (!saw_any) return 0;
	return 1;
}

/* Split the buffered record (with quotes already preserved) into fields. */
static int split_fields(csv_reader *r)
{
	r->field_count = 0;
	char *p = r->line_buf;
	while (*p || r->field_count == 0) {
		if (r->field_count >= CSV_MAX_FIELDS) return -1;
		char *field_start = p;
		int in_quotes = 0;
		char *write = p;
		if (*p == '"') {
			in_quotes = 1;
			field_start = ++p;
			write = p;
			while (*p) {
				if (*p == '"') {
					if (*(p + 1) == '"') {
						*write++ = '"';
						p += 2;
					} else {
						p++;
						in_quotes = 0;
						break;
					}
				} else {
					*write++ = *p++;
				}
			}
			*write = '\0';
		} else {
			while (*p && *p != ',') p++;
		}
		if (!in_quotes && *p == ',') {
			char *terminator = p;
			r->fields[r->field_count++] = field_start;
			*terminator = '\0';
			p++;
			if (!*p) {
				/* trailing comma -> empty last field */
				if (r->field_count < CSV_MAX_FIELDS) {
					r->fields[r->field_count++] = p;
				}
				break;
			}
		} else if (!*p) {
			r->fields[r->field_count++] = field_start;
			break;
		} else {
			/* Stray content after closed quote — treat as part of field. */
			r->fields[r->field_count++] = field_start;
			break;
		}
	}
	return 0;
}

int csv_next(csv_reader *r)
{
	if (!r || !r->fp) return -1;
	for (;;) {
		int rc = read_record(r);
		if (rc <= 0) return rc;
		r->line_number++;
		/* Skip purely empty lines. */
		int only_ws = 1;
		for (char *p = r->line_buf; *p; ++p) {
			if (*p != ' ' && *p != '\t') { only_ws = 0; break; }
		}
		if (only_ws) continue;
		if (split_fields(r) != 0) return -1;
		return 1;
	}
}
