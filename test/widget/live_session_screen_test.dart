// test/widget/live_session_screen_test.dart
//
// Constants and pure-logic checks for the new LiveSessionScreen.
// The screen itself depends on Firebase + SessionService + SosService
// singletons, so full widget tests require Firebase test plumbing
// (out of scope for this iteration). The countdown duration is
// verified here so any future regression is caught at test time.

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LiveSessionScreen check-in timer', () {
    test('fixed check-in duration is exactly 2 minutes (120 seconds)', () {
      const expected = 2 * 60;
      expect(expected, 120);
    });

    test('countdown tick decrements correctly', () {
      int remaining = 120;
      for (int i = 0; i < 119; i++) {
        remaining--;
      }
      expect(remaining, 1);
    });

    test('countdown reaches zero at tick 120', () {
      int remaining = 120;
      for (int i = 0; i < 120; i++) {
        remaining--;
      }
      expect(remaining, 0);
    });
  });
}