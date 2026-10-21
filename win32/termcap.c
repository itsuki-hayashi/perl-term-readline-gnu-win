/* Original Windows port: copyright (c) 2026 Itsuki Hayashi.
 * SPDX-License-Identifier: Unlicense
 * Historical permissive grant retained; see LICENSES/Unlicense.txt. */
/* A deliberately bounded VT terminal description, not a terminfo database. */
#include "config.h"
#include <string.h>
struct cap { const char *id, *value; };
static const struct cap caps[] = {
  {"cr", "\r"}, {"ce", "\033[K"}, {"cl", "\033[H\033[2J"}, {"cd", "\033[J"},
  {"ho", "\033[H"}, {"le", "\b"}, {"nd", "\033[C"}, {"up", "\033[A"},
  {"dc", "\033[P"}, {"ku", "\033[A"}, {"kd", "\033[B"}, {"kr", "\033[C"}, {"kl", "\033[D"},
  {"kh", "\033[H"}, {"@7", "\033[F"}, {"kH", "\033[F"}, {"kD", "\033[3~"}, {"kI", "\033[2~"},
  {"kP", "\033[5~"}, {"kN", "\033[6~"}, {"so", "\033[7m"}, {"se", "\033[27m"},
  {"us", "\033[4m"}, {"ue", "\033[24m"}, {"md", "\033[1m"}, {"me", "\033[0m"},
  {"vs", "\033[?25h"}, {"ve", "\033[?25h"}, {"vi", "\033[?25l"},
  {"BE", "\033[?2004h"}, {"BD", "\033[?2004l"}, {"PS", "\033[200~"}, {"PE", "\033[201~"},
  {NULL, NULL}
};
static int enabled;
int tgetent(char *buffer, const char *term) {
  (void)buffer;
  enabled = term && (!strcmp(term, "xterm") || !strncmp(term, "xterm-", 6) ||
      !strcmp(term, "vt100") || !strcmp(term, "ansi") || !strcmp(term, "win32"));
  return enabled;
}
char *tgetstr(const char *id, char **area) {
  const struct cap *c; char *r;
  if (!enabled) return NULL;
  for (c = caps; c->id; ++c) if (!strcmp(c->id, id)) {
    if (!area || !*area) return (char *)c->value;
    r = *area; strcpy(r, c->value); *area += strlen(r) + 1; return r;
  }
  return NULL;
}
int tgetflag(const char *id) { return enabled && (!strcmp(id, "am") || !strcmp(id, "xn") || !strcmp(id, "km")); }
int tgetnum(const char *id) { return enabled ? (!strcmp(id, "co") ? 80 : !strcmp(id, "li") ? 24 : -1) : -1; }
char *tgoto(const char *cap, int col, int row) { (void)cap; (void)col; (void)row; return NULL; }
int tputs(const char *s, int lines, int (*put)(int)) {
  (void)lines;
  if (!s) return 0;
  while (*s) { if (put((unsigned char)*s++) == EOF) return EOF; }
  return 0;
}
