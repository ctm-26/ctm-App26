#include "util.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char *util_trim(char *s)
{
	if (!s) return s;
	while (*s && isspace((unsigned char)*s)) s++;
	size_t n = strlen(s);
	while (n > 0 && isspace((unsigned char)s[n - 1])) s[--n] = '\0';
	return s;
}

void util_str_lower(char *s)
{
	for (; s && *s; ++s) *s = (char)tolower((unsigned char)*s);
}

int util_contains_ci(const char *haystack, const char *needle)
{
	if (!haystack || !needle || !*needle) return 0;
	size_t hl = strlen(haystack), nl = strlen(needle);
	if (nl > hl) return 0;
	for (size_t i = 0; i + nl <= hl; ++i) {
		size_t j = 0;
		while (j < nl &&
		       tolower((unsigned char)haystack[i + j]) ==
		           tolower((unsigned char)needle[j]))
			j++;
		if (j == nl) return 1;
	}
	return 0;
}

char *util_xstrdup(const char *s)
{
	if (!s) return NULL;
	size_t n = strlen(s) + 1;
	char *p = malloc(n);
	if (!p) {
		fprintf(stderr, "treasury: out of memory\n");
		exit(2);
	}
	memcpy(p, s, n);
	return p;
}

int util_parse_amount(const char *s, int64_t *out_cents)
{
	if (!s || !out_cents) return -1;
	char buf[64];
	size_t bi = 0;
	int negative = 0, saw_digit = 0, in_decimal = 0, decimals = 0;

	for (const char *p = s; *p; ++p) {
		unsigned char c = (unsigned char)*p;
		if (isspace(c) || c == '$' || c == ',') continue;
		if (c == '(') { negative = 1; continue; }
		if (c == ')') continue;
		if (c == '+') continue;
		if (c == '-') { negative = !negative; continue; }
		if (c == '.') {
			if (in_decimal) return -1;
			in_decimal = 1;
			continue;
		}
		if (!isdigit(c)) return -1;
		if (bi + 1 >= sizeof buf) return -1;
		buf[bi++] = (char)c;
		saw_digit = 1;
		if (in_decimal) {
			decimals++;
			if (decimals > 2) return -1;
		}
	}
	if (!saw_digit) return -1;
	buf[bi] = '\0';

	while (decimals < 2) { buf[bi++] = '0'; decimals++; buf[bi] = '\0'; }

	char *end = NULL;
	long long v = strtoll(buf, &end, 10);
	if (!end || *end != '\0') return -1;
	if (negative) v = -v;
	*out_cents = (int64_t)v;
	return 0;
}

void util_format_amount(int64_t cents, char *buf, size_t buflen)
{
	int negative = cents < 0;
	uint64_t abs_v = negative ? (uint64_t)(-(cents + 1)) + 1 : (uint64_t)cents;
	uint64_t whole = abs_v / 100;
	uint64_t frac  = abs_v % 100;
	snprintf(buf, buflen, "%s%llu.%02llu",
	         negative ? "-" : "",
	         (unsigned long long)whole,
	         (unsigned long long)frac);
}

static int is_leap(int y)
{
	return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
}

static int days_in_month(int y, int m)
{
	static const int d[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
	if (m < 1 || m > 12) return 0;
	if (m == 2) return is_leap(y) ? 29 : 28;
	return d[m - 1];
}

static int valid_ymd(int y, int m, int d)
{
	if (y < 1900 || y > 2999) return 0;
	if (m < 1 || m > 12) return 0;
	int dim = days_in_month(y, m);
	return d >= 1 && d <= dim;
}

int util_normalize_date(const char *in, char out[11])
{
	if (!in || !out) return -1;
	char tmp[32];
	size_t n = 0;
	for (const char *p = in; *p && n + 1 < sizeof tmp; ++p) {
		if (!isspace((unsigned char)*p)) tmp[n++] = *p;
	}
	tmp[n] = '\0';
	if (n == 0) return -1;

	int y = 0, m = 0, d = 0;

	if (n == 10 && tmp[4] == '-' && tmp[7] == '-' &&
	    sscanf(tmp, "%4d-%2d-%2d", &y, &m, &d) == 3) {
		if (!valid_ymd(y, m, d)) return -1;
		snprintf(out, 11, "%04d-%02d-%02d", y, m, d);
		return 0;
	}
	if (n == 10 && tmp[4] == '/' && tmp[7] == '/' &&
	    sscanf(tmp, "%4d/%2d/%2d", &y, &m, &d) == 3) {
		if (!valid_ymd(y, m, d)) return -1;
		snprintf(out, 11, "%04d-%02d-%02d", y, m, d);
		return 0;
	}
	if ((n == 10 || n == 8 || n == 9) &&
	    (tmp[1] == '/' || tmp[2] == '/' || tmp[1] == '-' || tmp[2] == '-')) {
		int a = 0, b = 0, c = 0;
		char sep = (strchr(tmp, '/') != NULL) ? '/' : '-';
		char fmt[] = "%d?%d?%d";
		fmt[2] = sep;
		fmt[5] = sep;
		if (sscanf(tmp, fmt, &a, &b, &c) == 3) {
			if (c < 100) c += (c < 70) ? 2000 : 1900;
			int mm = a, dd = b, yy = c;
			if (!valid_ymd(yy, mm, dd)) return -1;
			char tmp_out[64];
			snprintf(tmp_out, sizeof tmp_out, "%04d-%02d-%02d", yy, mm, dd);
			memcpy(out, tmp_out, 10);
			out[10] = '\0';
			return 0;
		}
	}
	return -1;
}

int util_valid_year_month(const char *s)
{
	if (!s || strlen(s) != 7) return -1;
	if (s[4] != '-') return -1;
	int y = 0, m = 0;
	if (sscanf(s, "%4d-%2d", &y, &m) != 2) return -1;
	if (y < 1900 || y > 2999) return -1;
	if (m < 1 || m > 12) return -1;
	return 0;
}
