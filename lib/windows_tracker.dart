import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

class WindowsTracker {
  /// Returns the executable name of the currently active window (e.g., "game.exe").
  /// Returns null if unable to resolve or if no window is active.
  static String? getActiveExecutableName() {
    // 1. Get foreground window handle
    final hwnd = GetForegroundWindow();
    if (hwnd == 0) return null;

    // 2. Get Process ID attached to window
    final processIdPtr = calloc<DWORD>();
    try {
      GetWindowThreadProcessId(hwnd, processIdPtr);
      final processId = processIdPtr.value;
      if (processId == 0) return null;

      // 3. Open Process handle to query name
      final hProcess = OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION,
        FALSE,
        processId,
      );
      if (hProcess == 0) return null;

      try {
        // 4. Query executable path
        final bufferSizePtr = calloc<DWORD>()..value = MAX_PATH;
        final nameBuffer = calloc<WCHAR>(MAX_PATH);

        try {
          final result = QueryFullProcessImageName(
            hProcess,
            0,
            nameBuffer.cast<Utf16>(),
            bufferSizePtr,
          );

          if (result != 0) {
            final fullPath = nameBuffer.cast<Utf16>().toDartString();
            return p
                .basename(fullPath)
                .toLowerCase(); // e.g., "cyberpunk2077.exe"
          }
        } finally {
          free(bufferSizePtr);
          free(nameBuffer);
        }
      } finally {
        CloseHandle(hProcess);
      }
    } finally {
      free(processIdPtr);
    }

    return null;
  }
}
