/* Original Windows port: copyright (c) 2026 itsuki-hayashi.
 * SPDX-License-Identifier: Unlicense
 * Historical permissive grant retained; see LICENSES/Unlicense.txt. */
#include "config.h"
#include "readline.h"
#include "rlprivate.h"
#include <string.h>
#include <errno.h>

static HANDLE input_handle, output_handle;
static DWORD input_mode, output_mode;
static UINT input_cp, output_cp;
static int prepped, output_saved, output_owned, registered;
static unsigned char pending[64];
static int pending_pos, pending_len, repeats;
static WCHAR high_surrogate;

static HANDLE stream_handle(FILE *f) { return (HANDLE)_get_osfhandle(_fileno(f)); }
HANDLE rl_win_output_handle(FILE *f, int *owned) {
  HANDLE h = stream_handle(f); DWORD mode;
  *owned = 0;
  if (GetConsoleMode(h, &mode)) return h;
  /* fopen("CONOUT$", "w") provides write access only. Console inspection
     APIs require read access too; reopen the active output buffer. */
  if (GetLastError() == ERROR_ACCESS_DENIED && GetFileType(h) == FILE_TYPE_CHAR) {
    HANDLE console = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (console != INVALID_HANDLE_VALUE) { *owned = 1; return console; }
  }
  return h;
}
static BOOL WINAPI control_event(DWORD event) {
  if (event == CTRL_CLOSE_EVENT || event == CTRL_LOGOFF_EVENT || event == CTRL_SHUTDOWN_EVENT || event == CTRL_BREAK_EVENT) rl_win_deprep();
  return FALSE; /* Leave application control handling in place. */
}
void rl_win_prep(void) {
  DWORD mode;
  if (prepped || !rl_instream) return;
  input_handle = stream_handle(rl_instream);
  if (!GetConsoleMode(input_handle, &input_mode)) { _rl_echoing_p = 0; return; }
  output_handle = rl_win_output_handle(rl_outstream, &output_owned);
  output_saved = GetConsoleMode(output_handle, &output_mode) != 0;
  input_cp = GetConsoleCP(); output_cp = GetConsoleOutputCP();
  mode = (input_mode | ENABLE_WINDOW_INPUT | ENABLE_EXTENDED_FLAGS) &
      ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT | ENABLE_QUICK_EDIT_MODE);
  if (!SetConsoleMode(input_handle, mode)) {
    if (output_owned) { CloseHandle(output_handle); output_owned = 0; }
    return;
  }
  prepped = 1;
  if (output_saved) SetConsoleMode(output_handle, output_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
  SetConsoleCP(CP_UTF8); SetConsoleOutputCP(CP_UTF8);
  if (!registered) { atexit(rl_win_deprep); registered = 1; }
  SetConsoleCtrlHandler(control_event, TRUE);
  _rl_echoing_p = output_saved;
  RL_SETSTATE(RL_STATE_TERMPREPPED);
  if (_rl_enable_bracketed_paste && output_saved) fputs("\033[?2004h", rl_outstream);
  fflush(rl_outstream);
}
void rl_win_deprep(void) {
  if (!prepped) return;
  if (_rl_enable_bracketed_paste && output_saved) fputs("\033[?2004l", rl_outstream);
  fflush(rl_outstream);
  SetConsoleMode(input_handle, input_mode);
  if (output_saved) SetConsoleMode(output_handle, output_mode);
  if (output_owned) { CloseHandle(output_handle); output_owned = 0; }
  SetConsoleCP(input_cp); SetConsoleOutputCP(output_cp);
  SetConsoleCtrlHandler(control_event, FALSE);
  prepped = 0; high_surrogate = 0;
  RL_UNSETSTATE(RL_STATE_TERMPREPPED);
}
int rl_win_available(FILE *stream, int usec) {
  DWORD mode, count, bytes; INPUT_RECORD rec; HANDLE h = stream_handle(stream);
  ULONGLONG deadline = GetTickCount64() + (usec <= 0 ? 0 : ((unsigned int)usec + 999) / 1000);
  if (pending_pos < pending_len || repeats) return 1;
  if (GetConsoleMode(h, &mode)) {
    for (;;) {
      ULONGLONG now = GetTickCount64();
      DWORD wait = now < deadline ? (DWORD)(deadline - now) : 0;
      if (WaitForSingleObject(h, wait) != WAIT_OBJECT_0) return 0;
      if (!PeekConsoleInputW(h, &rec, 1, &count) || !count) return 0;
      if (rec.EventType == KEY_EVENT && rec.Event.KeyEvent.bKeyDown &&
          (rec.Event.KeyEvent.uChar.UnicodeChar || (rec.Event.KeyEvent.wVirtualKeyCode >= VK_PRIOR && rec.Event.KeyEvent.wVirtualKeyCode <= VK_DELETE))) return 1;
      ReadConsoleInputW(h, &rec, 1, &count);
      if (rec.EventType == WINDOW_BUFFER_SIZE_EVENT) rl_resize_terminal();
    }
  }
  if (GetFileType(h) == FILE_TYPE_PIPE) return PeekNamedPipe(h, NULL, 0, NULL, &bytes, NULL) && bytes > 0;
  return GetFileType(h) == FILE_TYPE_DISK;
}
int rl_win_getc(FILE *stream) {
  DWORD mode, count; INPUT_RECORD rec; KEY_EVENT_RECORD *key;
  HANDLE h = stream_handle(stream); WCHAR wc[2]; int nw; const char *seq;
  if (!GetConsoleMode(h, &mode)) return fgetc(stream);
  for (;;) {
    if (pending_pos < pending_len) return pending[pending_pos++];
    if (repeats > 0) { --repeats; pending_pos = 0; continue; }
    if (WaitForSingleObject(h, 50) == WAIT_TIMEOUT) {
      RL_CHECK_SIGNALS();
      if (rl_signal_event_hook) rl_signal_event_hook();
      if (rl_event_hook) rl_event_hook();
      continue;
    }
    if (!ReadConsoleInputW(h, &rec, 1, &count)) { errno = EIO; return EOF; }
    if (rec.EventType == WINDOW_BUFFER_SIZE_EVENT) { rl_resize_terminal(); continue; }
    if (rec.EventType != KEY_EVENT || !rec.Event.KeyEvent.bKeyDown) continue;
    key = &rec.Event.KeyEvent; seq = NULL; pending_pos = pending_len = 0;
    wc[0] = key->uChar.UnicodeChar;
    if (wc[0] == 3) { raise(SIGINT); RL_CHECK_SIGNALS(); continue; }
    if (!wc[0]) {
      int ctrl = (key->dwControlKeyState & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED)) != 0;
      switch (key->wVirtualKeyCode) {
      case VK_UP: seq = "\033[A"; break; case VK_DOWN: seq = "\033[B"; break;
      case VK_RIGHT: seq = ctrl ? "\033[1;5C" : "\033[C"; break;
      case VK_LEFT: seq = ctrl ? "\033[1;5D" : "\033[D"; break;
      case VK_HOME: seq = "\033[H"; break; case VK_END: seq = "\033[F"; break;
      case VK_DELETE: seq = "\033[3~"; break; case VK_INSERT: seq = "\033[2~"; break;
      case VK_PRIOR: seq = "\033[5~"; break; case VK_NEXT: seq = "\033[6~"; break;
      default: continue;
      }
      pending_len = (int)strlen(seq); memcpy(pending, seq, pending_len);
    } else {
      if (wc[0] >= 0xd800 && wc[0] <= 0xdbff) { high_surrogate = wc[0]; continue; }
      nw = 1;
      if (high_surrogate) { wc[1] = wc[0]; wc[0] = high_surrogate; high_surrogate = 0; nw = 2; }
      if ((key->dwControlKeyState & (LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED)) &&
          !(key->dwControlKeyState & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED))) pending[pending_len++] = 27;
      pending_len += WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wc, nw,
          (char *)pending + pending_len, sizeof(pending) - pending_len, NULL, NULL);
    }
    repeats = key->wRepeatCount > 0 ? key->wRepeatCount - 1 : 0;
  }
}
