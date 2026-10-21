/* Original Windows port: copyright (c) 2026 itsuki-hayashi.
 * SPDX-License-Identifier: Unlicense
 * Historical permissive grant retained; see LICENSES/Unlicense.txt. */
#include "config.h"
#include "dirent.h"
#include <stdarg.h>
#include <errno.h>
#include <string.h>
#undef open
#undef fopen
#undef stat
#undef _stat64
#undef unlink

static wchar_t *wide(const char *s) {
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, NULL, 0);
  wchar_t *w;
  if (!n) { errno = EILSEQ; return NULL; }
  w = malloc(n * sizeof(*w));
  if (!w) { errno = ENOMEM; return NULL; }
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, w, n);
  return w;
}
int rl_win_open(const char *s, int flags, ...) {
  int mode = 0, fd; va_list ap; wchar_t *w = wide(s);
  if (!w) return -1;
  if (flags & _O_CREAT) { va_start(ap, flags); mode = va_arg(ap, int); va_end(ap); }
  fd = _wopen(w, flags, mode); free(w); return fd;
}
FILE *rl_win_fopen(const char *s, const char *mode) {
  wchar_t *w = wide(s), *m = wide(mode); FILE *f = NULL;
  if (w && m) f = _wfopen(w, m);
  free(w); free(m); return f;
}
int rl_win_stat(const char *s, struct _stat64 *st) {
  wchar_t *w = wide(s); int r;
  if (!w) return -1;
  r = _wstat64(w, st); free(w); return r;
}
int rl_win_unlink(const char *s) {
  wchar_t *w = wide(s); int r;
  if (!w) return -1;
  r = _wunlink(w); free(w); return r;
}
int rl_win_ftruncate(int fd, long size) { return _chsize(fd, size); }
DIR *opendir(const char *s) {
  wchar_t *w = wide(s), *pattern; size_t n; DIR *d;
  if (!w) return NULL;
  n = wcslen(w);
  pattern = malloc((n + 3) * sizeof(*w));
  d = calloc(1, sizeof(*d));
  if (!pattern || !d) { free(w); free(pattern); free(d); errno = ENOMEM; return NULL; }
  wcscpy(pattern, w); free(w);
  if (n && pattern[n-1] != L'/' && pattern[n-1] != L'\\') pattern[n++] = L'\\';
  pattern[n++] = L'*'; pattern[n] = 0;
  d->handle = FindFirstFileW(pattern, &d->data); free(pattern);
  if (d->handle == INVALID_HANDLE_VALUE) { free(d); errno = ENOENT; return NULL; }
  d->first = 1; return d;
}
struct dirent *readdir(DIR *d) {
  if (!d->first && !FindNextFileW(d->handle, &d->data)) return NULL;
  d->first = 0;
  if (!WideCharToMultiByte(CP_UTF8, 0, d->data.cFileName, -1, d->entry.d_name, sizeof(d->entry.d_name), NULL, NULL)) return NULL;
  return &d->entry;
}
int closedir(DIR *d) { int r = FindClose(d->handle) ? 0 : -1; free(d); return r; }
int gettimeofday(struct timeval *tv, void *unused) {
  FILETIME ft; ULARGE_INTEGER t; (void)unused;
  GetSystemTimePreciseAsFileTime(&ft); t.LowPart = ft.dwLowDateTime; t.HighPart = ft.dwHighDateTime;
  t.QuadPart -= 116444736000000000ULL;
  tv->tv_sec = (time_t)(t.QuadPart / 10000000); tv->tv_usec = (long)((t.QuadPart / 10) % 1000000); return 0;
}
int wcwidth(uint32_t c) {
  WORD type;
  wchar_t w = (wchar_t)c;
  if (!c) return 0;
  if (c < 32 || (c >= 0x7f && c < 0xa0)) return -1;
  if (c <= 0xffff && GetStringTypeW(CT_CTYPE3, &w, 1, &type) && (type & (C3_NONSPACING | C3_DIACRITIC))) return 0;
  if ((c >= 0x1f3fb && c <= 0x1f3ff) || (c >= 0xe0100 && c <= 0xe01ef) || c == 0x200d) return 0;
  if ((c >= 0x1f300 && c <= 0x1faff) || (c >= 0x20000 && c <= 0x3fffd)) return 2;
  if (c >= 0x1100 && (c <= 0x115f || c == 0x2329 || c == 0x232a ||
      (c >= 0x2e80 && c <= 0xa4cf && c != 0x303f) || (c >= 0xac00 && c <= 0xd7a3) ||
      (c >= 0xf900 && c <= 0xfaff) || (c >= 0xfe10 && c <= 0xfe19) ||
      (c >= 0xfe30 && c <= 0xfe6f) || (c >= 0xff00 && c <= 0xff60) || (c >= 0xffe0 && c <= 0xffe6))) return 2;
  return 1;
}

/* Keep a Unicode scalar rather than truncating supplementary characters to
   MSVC's 16-bit wchar_t. mbstate_t is copied, never type-punned. */
struct utf8_state { uint32_t value; unsigned char need, total; };
_Static_assert(sizeof(struct utf8_state) <= sizeof(mbstate_t), "mbstate_t too small");
size_t rl_win_mbrtoc32(char32_t *out, const char *s, size_t n, mbstate_t *state) {
  static mbstate_t fallback;
  struct utf8_state st = {0}; size_t i = 0; unsigned char c;
  if (!state) state = &fallback;
  if (!s) { memset(state, 0, sizeof(*state)); return 0; }
  memcpy(&st, state, sizeof(st));
  if (!n) return (size_t)-2;
  if (!st.need) {
    c = (unsigned char)s[i++];
    if (c < 0x80) { if (out) *out = c; return c ? 1 : 0; }
    if (c >= 0xc2 && c <= 0xdf) { st.value = c & 31; st.need = 1; st.total = 2; }
    else if (c >= 0xe0 && c <= 0xef) { st.value = c & 15; st.need = 2; st.total = 3; }
    else if (c >= 0xf0 && c <= 0xf4) { st.value = c & 7; st.need = 3; st.total = 4; }
    else goto invalid;
  }
  while (st.need && i < n) {
    c = (unsigned char)s[i++];
    if ((c & 0xc0) != 0x80) goto invalid;
    st.value = (st.value << 6) | (c & 63); --st.need;
  }
  if (st.need) { memcpy(state, &st, sizeof(st)); return (size_t)-2; }
  if (st.value > 0x10ffff || (st.value >= 0xd800 && st.value <= 0xdfff) ||
      (st.total == 2 && st.value < 0x80) || (st.total == 3 && st.value < 0x800) ||
      (st.total == 4 && st.value < 0x10000)) goto invalid;
  if (out) *out = st.value;
  memset(state, 0, sizeof(*state)); return i;
invalid:
  memset(state, 0, sizeof(*state)); errno = EILSEQ; return (size_t)-1;
}
size_t rl_win_mbrlen(const char *s, size_t n, mbstate_t *ps) { return rl_win_mbrtoc32(NULL, s, n, ps); }
size_t rl_win_c32rtomb(char *s, char32_t c, mbstate_t *ps) {
  if (ps) memset(ps, 0, sizeof(*ps));
  if (!s) return 1;
  if (c < 0x80) { s[0] = (char)c; return 1; }
  if (c < 0x800) { s[0] = (char)(0xc0 | (c >> 6)); s[1] = (char)(0x80 | (c & 63)); return 2; }
  if (c >= 0xd800 && c <= 0xdfff) { errno = EILSEQ; return (size_t)-1; }
  if (c < 0x10000) { s[0] = (char)(0xe0 | (c >> 12)); s[1] = (char)(0x80 | ((c >> 6) & 63)); s[2] = (char)(0x80 | (c & 63)); return 3; }
  if (c <= 0x10ffff) { s[0] = (char)(0xf0 | (c >> 18)); s[1] = (char)(0x80 | ((c >> 12) & 63)); s[2] = (char)(0x80 | ((c >> 6) & 63)); s[3] = (char)(0x80 | (c & 63)); return 4; }
  errno = EILSEQ; return (size_t)-1;
}
int rl_win_rename(const char *a, const char *b) {
  wchar_t *wa = wide(a), *wb = wide(b); int r = -1;
  if (wa && wb) r = MoveFileExW(wa, wb, MOVEFILE_REPLACE_EXISTING) ? 0 : -1;
  free(wa); free(wb); if (r) errno = EACCES; return r;
}
