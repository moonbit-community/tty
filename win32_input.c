#include <moonbit.h>
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#endif

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_read_console_input_record(
#ifdef _WIN32
  HANDLE fd,
#else
  intptr_t fd,
#endif
  int32_t *event_type,
  int32_t *key_down,
  int32_t *repeat_count,
  int32_t *virtual_key_code,
  int32_t *unicode_char,
  int32_t *control_key_state,
  int32_t *focus_set
) {
  if (event_type == NULL || key_down == NULL || repeat_count == NULL ||
      virtual_key_code == NULL || unicode_char == NULL ||
      control_key_state == NULL || focus_set == NULL) {
#ifdef _WIN32
    SetLastError(ERROR_INVALID_PARAMETER);
#else
    errno = EINVAL;
#endif
    return -1;
  }

  *event_type = 0;
  *key_down = 0;
  *repeat_count = 0;
  *virtual_key_code = 0;
  *unicode_char = 0;
  *control_key_state = 0;
  *focus_set = 0;

#ifdef _WIN32
  INPUT_RECORD record;
  DWORD count = 0;
  if (!PeekConsoleInputW(fd, &record, 1, &count)) {
    return -1;
  }
  if (count == 0) {
    return 0;
  }
  if (!ReadConsoleInputW(fd, &record, 1, &count)) {
    return -1;
  }
  if (count == 0) {
    return 0;
  }

  *event_type = (int32_t)record.EventType;
  switch (record.EventType) {
  case KEY_EVENT:
    *key_down = record.Event.KeyEvent.bKeyDown ? 1 : 0;
    *repeat_count = (int32_t)record.Event.KeyEvent.wRepeatCount;
    *virtual_key_code = (int32_t)record.Event.KeyEvent.wVirtualKeyCode;
    *unicode_char = (int32_t)record.Event.KeyEvent.uChar.UnicodeChar;
    *control_key_state = (int32_t)record.Event.KeyEvent.dwControlKeyState;
    break;
  case FOCUS_EVENT:
    *focus_set = record.Event.FocusEvent.bSetFocus ? 1 : 0;
    break;
  default:
    break;
  }
  return 1;
#else
  (void)fd;
  errno = ENOSYS;
  return -1;
#endif
}
