/* Original Windows port: copyright (c) 2026 itsuki-hayashi.
 * SPDX-License-Identifier: Unlicense
 * Historical permissive grant retained; see LICENSES/Unlicense.txt. */
/* Native MSVC configuration. No POSIX emulation runtime is required. */
#ifndef RL_MSVC_CONFIG_H
#define RL_MSVC_CONFIG_H
#ifndef READLINE_LIBRARY
#define READLINE_LIBRARY
#endif
#define _CRT_SECURE_NO_WARNINGS 1
#define _CRT_NONSTDC_NO_WARNINGS 1
#define WIN32_LEAN_AND_MEAN 1
#define NOMINMAX 1
#define _WIN32_WINNT 0x0a00
#define PROTOTYPES 1
#define __PROTOTYPES 1
#define RL_LIBRARY_VERSION "8.3"
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STDARG_H 1
#define HAVE_STDBOOL_H 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_MEMORY_H 1
#define HAVE_FCNTL_H 1
#define HAVE_DIRENT_H 1
#define HAVE_WCHAR_H 1
#define HAVE_WCTYPE_H 1
#define HAVE_MBSTATE_T 1
#define HAVE_WCHAR_T 1
#define HAVE_WCTYPE_T 1
#define HAVE_WINT_T 1
#define HAVE_ISWCTYPE 1
#define HAVE_ISWLOWER 1
#define HAVE_ISWUPPER 1
#define HAVE_MBSRTOWCS 1
#define HAVE_MBRTOWC 1
#define HAVE_MBRLEN 1
#define HAVE_TOWLOWER 1
#define HAVE_TOWUPPER 1
#define HAVE_WCWIDTH 1
#define HAVE_WCRTOMB 1
#define HAVE_WCSLEN 1
#define HAVE_WCSNLEN 1
#define HAVE_MEMMOVE 1
#define HAVE_ISASCII 1
#define HAVE_ISXDIGIT 1
#define HAVE_STRPBRK 1
#define HAVE_STRCOLL 1
#define HAVE_SETLOCALE 1
#define HAVE_VSNPRINTF 1
#define HAVE_PUTENV 1
#define TERMIOS_MISSING 1
#define MUST_REINSTALL_SIGHANDLERS 1
#define restrict __restrict
#include "compat.h"
#endif
