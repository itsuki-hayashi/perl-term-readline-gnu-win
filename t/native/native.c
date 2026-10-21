#include "config.h"
#include "readline.h"
#include "history.h"
#include "rlprivate.h"
#include "dirent.h"
#include <assert.h>
#include <string.h>
#include <errno.h>

extern int tgetent(char *, const char *);
extern char *tgetstr(const char *, char **);
extern int tputs(const char *, int, int (*)(int));
static int output_count;
static int count_char(int c) { ++output_count; return c; }
static char *test_completion(const char *text, int state) {
  return state == 0 && !strncmp("apple", text, strlen(text)) ? _strdup("apple") : NULL;
}
static char *callback_line;
static void got_line(char *s) { callback_line = s; }

static void basic_tests(void) {
  char32_t cp; mbstate_t ps = {0}; char encoded[5] = {0};
  const char *emoji = "\xf0\x9f\x90\xaa";
  const char *filename = "native-\xe6\x97\xa5\xe6\x9c\xac.history";
  char *result; DIR *d; struct dirent *entry; int found = 0;
  int fd;
  _Static_assert(sizeof(size_t) == 8 && sizeof(ptrdiff_t) == 8,
                 "64-bit sizes and offsets required");
  _Static_assert(sizeof(int) == 4, "Readline int ABI must remain 32-bit");
  assert(rl_win_size_to_int(INT_MAX) == INT_MAX);
  assert(rl_win_diff_to_int(INT_MIN) == INT_MIN);
  assert(rl_win_diff_to_int(INT_MAX) == INT_MAX);
  assert(rl_win_mbresult((size_t)-1) == -1);
  assert(rl_win_mbresult((size_t)-2) == -2);
  assert(rl_win_mbresult(4) == 4);
  assert(rl_win_time_to_uint(UINT_MAX) == UINT_MAX);
  fd = rl_win_open("integer-io.tmp", _O_CREAT | _O_TRUNC | _O_RDWR | _O_BINARY,
                   _S_IREAD | _S_IWRITE);
  assert(fd >= 0);
  assert(lseek(fd, (int64_t)UINT_MAX + 1, SEEK_SET) == (int64_t)UINT_MAX + 1);
  errno = 0;
  assert(rl_win_read(fd, encoded, (size_t)INT_MAX + 1) == -1 && errno == EOVERFLOW);
  errno = 0;
  assert(rl_win_write(fd, encoded, (size_t)INT_MAX + 1) == -1 && errno == EOVERFLOW);
  assert(rl_win_ftruncate(fd, 0) == 0);
  assert(close(fd) == 0 && unlink("integer-io.tmp") == 0);
  assert(rl_win_mbrtoc32(&cp, emoji, 4, &ps) == 4 && cp == 0x1f42a);
  assert(rl_win_mbrtoc32(&cp, emoji, 2, &ps) == (size_t)-2);
  assert(rl_win_mbrtoc32(&cp, emoji + 2, 2, &ps) == 2 && cp == 0x1f42a);
  assert(rl_win_c32rtomb(encoded, cp, &ps) == 4 && !strcmp(encoded, emoji));
  assert(rl_win_mbrtoc32(&cp, "\xed\xa0\x80", 3, &ps) == (size_t)-1);
  assert(rl_win_mbrtoc32(&cp, "\xf4\x90\x80\x80", 4, &ps) == (size_t)-1);
  assert(wcwidth(0x301) == 0 && wcwidth(0x65e5) == 2 && wcwidth(0x1f42a) == 2);
  assert(tgetent(NULL, "win32") == 1 && !strcmp(tgetstr("ce", NULL), "\033[K"));
  assert(tputs("abc", 1, count_char) == 0 && output_count == 3);
  assert(tgetent(NULL, "dumb") == 0 && !tgetstr("ce", NULL));
  rl_instream = tmpfile(); rl_outstream = tmpfile(); assert(rl_instream && rl_outstream);
  fputs("first\nsecond\n", rl_instream); rewind(rl_instream);
  result = readline(""); assert(result && !strcmp(result, "first")); free(result);
  result = readline(""); assert(result && !strcmp(result, "second")); free(result);
  result = readline(""); assert(!result);
  clear_history(); add_history("one"); add_history(emoji);
  assert(write_history(filename) == 0); clear_history(); assert(read_history(filename) == 0);
  assert(history_length == 2 && !strcmp(history_list()[1]->line, emoji));
  assert(append_history(1, filename) == 0);
  assert(history_truncate_file(filename, 1) == 0);
  clear_history(); assert(read_history(filename) == 0 && history_length == 1);
  d = opendir("."); assert(d);
  while ((entry = readdir(d))) if (!strcmp(entry->d_name, filename)) found = 1;
  closedir(d); assert(found);
  result = rl_filename_completion_function("native-\xe6\x97\xa5", 0); assert(result && !strcmp(result, filename)); free(result);
  assert(unlink(filename) == 0);
  rl_replace_line("x\xf0\x9f\x90\xaa", 0); rl_point = rl_end;
  rl_rubout(1, 127); assert(!strcmp(rl_line_buffer, "x"));
  rl_replace_line("x\xe6\x97\xa5", 0); rl_point = rl_end;
  rl_rubout(1, 127); assert(!strcmp(rl_line_buffer, "x"));
  fclose(rl_instream); fclose(rl_outstream);
  rl_instream = tmpfile(); rl_outstream = tmpfile();
  fputs("callback\n", rl_instream); rewind(rl_instream);
  rl_callback_handler_install("", got_line);
  while (!callback_line) rl_callback_read_char();
  assert(!strcmp(callback_line, "callback")); free(callback_line);
  rl_callback_handler_remove();
  fclose(rl_instream); fclose(rl_outstream);
  puts("Native C tests passed");
}

static void inject(WCHAR c, WORD vk, DWORD modifiers) {
  INPUT_RECORD r = {0}; DWORD count;
  r.EventType = KEY_EVENT; r.Event.KeyEvent.bKeyDown = TRUE;
  r.Event.KeyEvent.wRepeatCount = 1; r.Event.KeyEvent.wVirtualKeyCode = vk;
  r.Event.KeyEvent.wVirtualScanCode = (WORD)MapVirtualKeyW(vk, MAPVK_VK_TO_VSC);
  r.Event.KeyEvent.uChar.UnicodeChar = c; r.Event.KeyEvent.dwControlKeyState = modifiers;
  assert(WriteConsoleInputW(GetStdHandle(STD_INPUT_HANDLE), &r, 1, &count));
  r.Event.KeyEvent.bKeyDown = FALSE;
  assert(WriteConsoleInputW(GetStdHandle(STD_INPUT_HANDLE), &r, 1, &count));
}
static volatile sig_atomic_t interrupted;
static void on_interrupt(int sig) { (void)sig; ++interrupted; }
static void console_tests(const char *logpath) {
  FILE *log = freopen(logpath, "w", stderr); char *s; DWORD before_in, before_out, after;
  UINT cp_in = GetConsoleCP(), cp_out = GetConsoleOutputCP();
  assert(log);
  setvbuf(log, NULL, _IONBF, 0);
  assert(GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), &before_in));
  assert(GetConsoleMode(GetStdHandle(STD_OUTPUT_HANDLE), &before_out));
  rl_instream = fopen("CONIN$", "r"); rl_outstream = fopen("CONOUT$", "w");
  assert(rl_instream && rl_outstream); rl_terminal_name = "win32";
  {
    SMALL_RECT rect = {0, 0, 59, 19}; INPUT_RECORD r = {0}; DWORD count; int rows, cols;
    assert(SetConsoleWindowInfo(GetStdHandle(STD_OUTPUT_HANDLE), TRUE, &rect));
    r.EventType = WINDOW_BUFFER_SIZE_EVENT; r.Event.WindowBufferSizeEvent.dwSize.X = 60;
    r.Event.WindowBufferSizeEvent.dwSize.Y = 20;
    assert(WriteConsoleInputW(GetStdHandle(STD_INPUT_HANDLE), &r, 1, &count));
    rl_initialize();
    rl_win_available(rl_instream, 0);
    rl_get_screen_size(&rows, &cols); fprintf(log, "resize: %d rows, %d columns\n", rows, cols); assert(rows == 20 && cols == 60);
  }
  inject('a', 'A', 0); inject('c', 'C', 0); inject(0, VK_LEFT, 0); inject('b', 'B', 0); inject('\r', VK_RETURN, 0);
  s = readline("test> "); assert(s && !strcmp(s, "abc")); free(s);
  inject(0x65e5, 0, 0); inject(0xd83d, 0, 0); inject(0xdc2a, 0, 0); inject(0, VK_HOME, 0);
  inject('x', 'X', 0); inject('\r', VK_RETURN, 0);
  s = readline("utf8> "); assert(s && !strcmp(s, "x\xe6\x97\xa5\xf0\x9f\x90\xaa")); free(s);
  clear_history(); add_history("previous");
  inject(0, VK_UP, 0); inject(0, VK_HOME, 0); inject(0, VK_DELETE, 0); inject('\r', VK_RETURN, 0);
  s = readline("history> "); assert(s && !strcmp(s, "revious")); free(s);
  rl_completion_entry_function = test_completion;
  inject('a', 'A', 0); inject('p', 'P', 0); inject('\t', VK_TAB, 0); inject('\r', VK_RETURN, 0);
  s = readline("complete> "); assert(s && !strcmp(s, "apple ")); free(s);
  rl_completion_entry_function = NULL;
  {
    const char *paste = "\033[200~pasted text\033[201~\r";
    while (*paste) { inject((WCHAR)*paste, 0, 0); ++paste; }
    s = readline("paste> "); assert(s && !strcmp(s, "pasted text")); free(s);
  }
  {
    CONSOLE_SCREEN_BUFFER_INFO before, after; int i;
    assert(GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &before));
    for (i = 0; i < 130; ++i) inject('x', 'X', 0);
    inject('\r', VK_RETURN, 0);
    s = readline("wrap> "); assert(s && strlen(s) == 130); free(s);
    assert(GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &after));
    assert(after.dwCursorPosition.Y >= before.dwCursorPosition.Y + 2);
  }
  signal(SIGINT, on_interrupt);
  inject(3, 'C', LEFT_CTRL_PRESSED); inject('z', 'Z', 0); inject('\r', VK_RETURN, 0);
  s = readline("interrupt> "); assert(interrupted == 1 && s && !strcmp(s, "z")); free(s);
  inject(4, 'D', LEFT_CTRL_PRESSED); s = readline("eof> "); assert(!s);
  callback_line = NULL;
  inject('o', 'O', 0); inject('k', 'K', 0); inject('\r', VK_RETURN, 0);
  rl_callback_handler_install("callback> ", got_line);
  while (!callback_line) rl_callback_read_char();
  assert(!strcmp(callback_line, "ok")); free(callback_line); rl_callback_handler_remove();
  assert(GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), &after) && before_in == after);
  assert(GetConsoleMode(GetStdHandle(STD_OUTPUT_HANDLE), &after) && before_out == after);
  assert(GetConsoleCP() == cp_in && GetConsoleOutputCP() == cp_out);
  fprintf(log, "Native console tests passed\n"); fclose(log);
}
static void perl_console_tests(const char *logpath) {
  const wchar_t *perl = _wgetenv(L"RL_TEST_PERL");
  const wchar_t *test = _wgetenv(L"RL_TEST_SCRIPT");
  wchar_t wlog[32768], command[32768];
  STARTUPINFOW si = { sizeof(si) };
  PROCESS_INFORMATION pi;
  DWORD code;
  assert(perl && test);
  MultiByteToWideChar(CP_UTF8, 0, logpath, -1, wlog, 32768);
  inject(0x65e5, 0, 0); inject(0xd83d, 0, 0); inject(0xdc2a, 0, 0);
  inject(0, VK_HOME, 0); inject('x', 'X', 0); inject('\r', VK_RETURN, 0);
  inject(0, VK_UP, 0); inject(0, VK_HOME, 0); inject(0, VK_DELETE, 0); inject('\r', VK_RETURN, 0);
  inject('o', 'O', 0); inject('k', 'K', 0); inject('\r', VK_RETURN, 0);
  assert(swprintf(command, 32768, L"\"%ls\" \"%ls\" \"%ls\"", perl, test, wlog) > 0);
  assert(CreateProcessW(perl, command, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi));
  assert(WaitForSingleObject(pi.hProcess, 60000) == WAIT_OBJECT_0);
  assert(GetExitCodeProcess(pi.hProcess, &code) && code == 0);
  CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
}
static void debugger_tests(void) {
  const wchar_t *perl = _wgetenv(L"RL_TEST_PERL");
  const char *cmd = "p do { open my $f, '>', 'debugger-backend.log' or die $!; print $f $DB::term->ReadLine; close $f; 1 }\rq\r";
  FILE *f; char backend[80] = {0};
  assert(perl);
  _putenv_s("PERL_RL", "GnuWin32"); _putenv_s("TERM", "win32"); _putenv_s("INPUTRC", "NUL");
  while (*cmd) { inject((WCHAR)*cmd, 0, 0); ++cmd; }
  assert(_wspawnl(_P_WAIT, perl, perl, L"-d", L"-e", L"0", NULL) == 0);
  f = fopen("debugger-backend.log", "r"); assert(f);
  assert(fgets(backend, sizeof(backend), f)); fclose(f);
  assert(!strcmp(backend, "Term::ReadLine::GnuWin32"));
}
static void perlsh_tests(void) {
  const wchar_t *launcher = _wgetenv(L"RL_TEST_PERLSH");
  const wchar_t *shell = _wgetenv(L"COMSPEC");
  wchar_t command[32768]; char cwd[32768], home[32768], expected[32768], actual[32768];
  int scenario; FILE *f;
  assert(launcher && shell && getcwd(cwd, sizeof(cwd)));
  snprintf(home, sizeof(home), "%s/perlsh test home", cwd);
  assert(_mkdir(home) == 0 || errno == EEXIST);
  snprintf(expected, sizeof(expected), "%s/.perlshrc", home);
  f = fopen(expected, "w"); assert(f);
  fputs("$PerlSh::PS1 = ''; sub main::afterinit { open my $f, '>', 'perlsh-config-loaded.log' or die $!; print $f 'loaded'; close $f; } 1;\n", f);
  fclose(f);
  _putenv_s("PERL_RL", "GnuWin32"); _putenv_s("TERM", "win32"); _putenv_s("INPUTRC", "NUL");
  for (scenario = 0; scenario < 3; ++scenario) {
    STARTUPINFOW si = {sizeof(si)}; PROCESS_INFORMATION pi; DWORD code;
    const char *input = "open my $f, '>', 'perlsh-startup-result.log' or die $!; print $f $PerlSh::HISTFILE; close $f; PerlSh::quit()\r";
    _putenv_s("HOME", scenario == 0 ? home : "");
    _putenv_s("USERPROFILE", scenario == 2 ? "" : scenario == 0 ? "missing-profile" : home);
    if (scenario == 2) {
      char drive[3] = {home[0], ':', 0};
      _putenv_s("HOMEDRIVE", drive); _putenv_s("HOMEPATH", home + 2);
    }
    while (*input) { inject((WCHAR)*input, 0, 0); ++input; }
    swprintf(command, 32768, L"\"%ls\" /d /s /c \"\"%ls\"\"", shell, launcher);
    assert(CreateProcessW(shell, command, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi));
    if (WaitForSingleObject(pi.hProcess, 15000) != WAIT_OBJECT_0) { TerminateProcess(pi.hProcess, 1); exit(1); }
    assert(GetExitCodeProcess(pi.hProcess, &code) && code == 0);
    CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
    f = fopen("perlsh-startup-result.log", "r"); assert(f);
    assert(fgets(actual, sizeof(actual), f)); fclose(f);
    snprintf(expected, sizeof(expected), "%s/.perlsh_history", home);
    assert(!strcmp(actual, expected));
    f = fopen(expected, "r"); assert(f); fclose(f);
    f = fopen("perlsh-config-loaded.log", "r"); assert(f); fclose(f);
    assert(unlink("perlsh-startup-result.log") == 0);
    assert(unlink("perlsh-config-loaded.log") == 0);
  }
  f = fopen("perlsh-tests.log", "w"); assert(f);
  fputs("perlsh.bat passed: HOME, USERPROFILE, HOMEDRIVE/HOMEPATH; startup config, evaluation, history, exit\n", f);
  fclose(f);
}
int main(int argc, char **argv) {
  if (argc == 3 && !strcmp(argv[1], "--console-child")) { console_tests(argv[2]); return 0; }
  if (argc == 3 && !strcmp(argv[1], "--perl-child")) { perl_console_tests(argv[2]); return 0; }
  if (argc == 3 && !strcmp(argv[1], "--debugger-child")) { debugger_tests(); return 0; }
  if (argc == 3 && !strcmp(argv[1], "--perlsh-child")) { perlsh_tests(); return 0; }
  if (argc == 1) basic_tests();
  {
    wchar_t exe[32768], cmd[32768]; STARTUPINFOW si = {sizeof(si)}; PROCESS_INFORMATION pi;
    DWORD code;
    assert(GetModuleFileNameW(NULL, exe, 32768));
    int debugger = argc > 1 && !strcmp(argv[1], "--debugger");
    int perlsh = argc > 1 && !strcmp(argv[1], "--perlsh");
    swprintf(cmd, 32768, L"\"%ls\" %ls %ls", exe,
        argc == 1 ? L"--console-child" : debugger ? L"--debugger-child" : perlsh ? L"--perlsh-child" : L"--perl-child",
        argc == 1 ? L"console-tests.log" : L"perl-console-tests.log");
    si.dwFlags = STARTF_USESHOWWINDOW; si.wShowWindow = SW_HIDE;
    assert(CreateProcessW(exe, cmd, NULL, NULL, FALSE, CREATE_NEW_CONSOLE, NULL, NULL, &si, &pi));
    if (WaitForSingleObject(pi.hProcess, 30000) != WAIT_OBJECT_0) { TerminateProcess(pi.hProcess, 1); fputs("Console test timed out\n", stderr); return 1; }
    GetExitCodeProcess(pi.hProcess, &code); CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
    if (code) { fprintf(stderr, "Console test failed: %lu\n", code); return 1; }
    puts(argc == 1 ? "Native console tests passed" : debugger ? "Perl debugger integration passed" : perlsh ? "perlsh.bat integration passed" : "Perl console tests passed");
  }
  return 0;
}
