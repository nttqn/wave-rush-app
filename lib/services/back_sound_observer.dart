import 'package:flutter/widgets.dart';

import 'sound_service.dart';

/// Plays the "back" sound whenever a screen is popped, however it happened:
/// the on-screen back arrow, Android's system back, or a MENU button. Buttons
/// that navigate back therefore pass `sound: null` so they don't also play
/// their own click. Dialogs/sheets are ignored (only page routes count).
class BackSoundObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) SoundService.instance.play(SoundEffect.back);
  }
}
