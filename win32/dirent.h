/* Original Windows port: copyright (c) 2026 itsuki-hayashi.
 * SPDX-License-Identifier: Unlicense
 * Historical permissive grant retained; see LICENSES/Unlicense.txt. */
#ifndef RL_WIN_DIRENT_H
#define RL_WIN_DIRENT_H
#include <windows.h>
struct dirent { char d_name[32768 * 3]; };
typedef struct rl_win_dir {
  HANDLE handle;
  WIN32_FIND_DATAW data;
  int first;
  struct dirent entry;
} DIR;
DIR *opendir(const char *);
struct dirent *readdir(DIR *);
int closedir(DIR *);
#endif
