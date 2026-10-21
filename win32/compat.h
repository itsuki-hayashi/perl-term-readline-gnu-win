/* Original Windows port: copyright (c) 2026 Itsuki Hayashi.
 * SPDX-License-Identifier: Unlicense
 * Historical permissive grant retained; see LICENSES/Unlicense.txt. */
#ifndef RL_WIN_COMPAT_H
/* Integer-safety additions copyright (c) 2026 Itsuki Hayashi,
 * licensed GPL-3.0-or-later; original portions retain the grant above. */
#define RL_WIN_COMPAT_H
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
#include <io.h>
#include <direct.h>
#include <process.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <wchar.h>
#include <wctype.h>
#include <uchar.h>
#include <signal.h>
#include <fcntl.h>
#include <windows.h>
#include "checked.h"
typedef intptr_t ssize_t;
typedef int uid_t;
typedef int gid_t;
typedef int mode_t;
#define getpid _getpid
#define isatty _isatty
#define fileno _fileno
#define read rl_win_read
#define write rl_win_write
#define close _close
#define lseek _lseeki64
#define fstat _fstat64
#define access _access
#define getcwd _getcwd
#define chdir _chdir
#define unlink rl_win_unlink
#define open rl_win_open
#define fopen rl_win_fopen
#define stat _stat64
#define _stat64(path, buf) rl_win_stat(path, buf)
#define ftruncate rl_win_ftruncate
#define getuid() 0
#define getgid() 0
#define kill(pid, sig) raise(sig)
#define HAVE_GETTIMEOFDAY 1
#define HAVE_TIMEVAL 1
struct timeval { time_t tv_sec; long tv_usec; };
int gettimeofday(struct timeval *, void *);
int rl_win_open(const char *, int, ...);
FILE *rl_win_fopen(const char *, const char *);
int rl_win_stat(const char *, struct _stat64 *);
int rl_win_unlink(const char *);
int rl_win_ftruncate(int, int64_t);
ssize_t rl_win_read(int, void *, size_t);
ssize_t rl_win_write(int, const void *, size_t);
int wcwidth(uint32_t);
#define WCHAR_T_BROKEN 1
#undef MB_CUR_MAX
#define MB_CUR_MAX 4
#define mbrtoc32 rl_win_mbrtoc32
#define c32rtomb rl_win_c32rtomb
#define mbrlen rl_win_mbrlen
size_t rl_win_mbrtoc32(char32_t *, const char *, size_t, mbstate_t *);
size_t rl_win_c32rtomb(char *, char32_t, mbstate_t *);
size_t rl_win_mbrlen(const char *, size_t, mbstate_t *);
#define towlower(c) ((uint32_t)(c) > 0xffff ? (uint32_t)(c) : (uint32_t)(towlower)((wint_t)(c)))
#define towupper(c) ((uint32_t)(c) > 0xffff ? (uint32_t)(c) : (uint32_t)(towupper)((wint_t)(c)))
#undef iswlower
#undef iswupper
#undef iswalnum
#undef iswcntrl
#undef iswgraph
#define iswlower(c) ((uint32_t)(c) <= 0xffff && (iswlower)((wint_t)(c)))
#define iswupper(c) ((uint32_t)(c) <= 0xffff && (iswupper)((wint_t)(c)))
#define iswalnum(c) ((uint32_t)(c) <= 0xffff && (iswalnum)((wint_t)(c)))
#define iswcntrl(c) ((uint32_t)(c) <= 0xffff && (iswcntrl)((wint_t)(c)))
#define iswgraph(c) ((uint32_t)(c) > 0xffff || (iswgraph)((wint_t)(c)))
int rl_win_rename(const char *, const char *);
void rl_win_prep(void);
void rl_win_deprep(void);
int rl_win_getc(FILE *);
int rl_win_available(FILE *, int);
HANDLE rl_win_output_handle(FILE *, int *);
#endif
