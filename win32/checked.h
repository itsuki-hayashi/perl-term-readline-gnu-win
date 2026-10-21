/* Copyright (c) 2026 itsuki-hayashi.
 * SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef RL_WIN_CHECKED_H
#define RL_WIN_CHECKED_H
#include <stdint.h>
#include <stddef.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

/* Readline's public indexes and buffer sizes are int, including on LLP64.
 * Treat an unrepresentable internal size like an allocation failure rather
 * than letting a truncated index corrupt memory. Perl inputs are checked
 * separately and report recoverable exceptions before entering Readline. */
static __inline void rl_win_size_overflow(void)
{
  fputs("readline: size exceeds the supported integer range\n", stderr);
  abort();
}
static __inline int rl_win_size_to_int(size_t n)
{
  if (n > INT_MAX) rl_win_size_overflow();
  return (int)n;
}
static __inline int rl_win_diff_to_int(ptrdiff_t n)
{
  if (n < INT_MIN || n > INT_MAX) rl_win_size_overflow();
  return (int)n;
}
static __inline unsigned int rl_win_time_to_uint(int64_t n)
{
  if (n < 0 || n > UINT_MAX) rl_win_size_overflow();
  return (unsigned int)n;
}
/* C multibyte conversions reserve the two largest size_t values for errors.
 * Preserve those sentinels; a plain range check would abort on invalid UTF-8. */
static __inline int rl_win_mbresult(size_t n)
{
  if (n == (size_t)-1) return -1;
  if (n == (size_t)-2) return -2;
  return rl_win_size_to_int(n);
}
#endif
