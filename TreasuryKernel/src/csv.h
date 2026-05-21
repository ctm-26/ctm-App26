#ifndef TREASURY_CSV_H
#define TREASURY_CSV_H

#include <stdio.h>

#define CSV_MAX_FIELDS 64

typedef struct {
	FILE *fp;
	char *line_buf;
	size_t line_cap;
	char *fields[CSV_MAX_FIELDS];
	int field_count;
	long line_number;
} csv_reader;

/* Open a CSV file for reading. Returns 0 on success. */
int csv_open(csv_reader *r, const char *path);

/* Read next row. Fills r->fields and r->field_count.
   Returns: 1 row read, 0 EOF, -1 error. */
int csv_next(csv_reader *r);

/* Free all resources. */
void csv_close(csv_reader *r);

#endif
