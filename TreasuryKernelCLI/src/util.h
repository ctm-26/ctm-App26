#ifndef TREASURY_UTIL_H
#define TREASURY_UTIL_H

#include <stddef.h>
#include <stdint.h>

/* Parse a money string into integer cents.
   Accepts: "42.18", "-42.18", "(42.18)", "$42.18", "1,234.56", "  -$1,234.56  ".
   Returns 0 on success, -1 on parse failure.
   Output is signed; parentheses imply negative. */
int util_parse_amount(const char *s, int64_t *out_cents);

/* Format integer cents into a fixed buffer ("-1234.56"). */
void util_format_amount(int64_t cents, char *buf, size_t buflen);

/* Normalize a date string into ISO YYYY-MM-DD in out[11].
   Accepts: YYYY-MM-DD, YYYY/MM/DD, MM/DD/YYYY, MM-DD-YYYY, M/D/YY, M/D/YYYY.
   Returns 0 on success, -1 on failure. */
int util_normalize_date(const char *in, char out[11]);

/* In-place trim of leading/trailing ASCII whitespace. Returns s. */
char *util_trim(char *s);

/* Case-insensitive substring search. */
int util_contains_ci(const char *haystack, const char *needle);

/* Lower-case ASCII copy. */
void util_str_lower(char *s);

/* Safe duplicate (xstrdup); aborts on OOM. */
char *util_xstrdup(const char *s);

/* Validate "YYYY-MM" string. Returns 0 if valid. */
int util_valid_year_month(const char *s);

#endif
