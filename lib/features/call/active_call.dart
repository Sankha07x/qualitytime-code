import 'dart:async';
import 'package:flutter/foundation.dart';
import 'call_controller.dart';

class ActiveCallInfo {
  final CallController controller;
  final String name;
  final String? photo;
  final bool video;

  const ActiveCallInfo({
    required this.controller,
    required this.name,
    required this.photo,
    required this.video,
  });
}

/// Keeps track of the running call and of a minimized one.
class ActiveCall {
  /// The connected call (set by the controller).
  static CallController? running;

  /// Not null while the call screen is minimized (shows the green bar).
  static final current = ValueNotifier<ActiveCallInfo?>(null);

  static Completer<bool>? _completer;

  /// Completes true when the user returns to the call, false when it ended.
  static Future<bool> minimize(
    CallController controller, {
    required String name,
    String? photo,
    required bool video,
  }) {
    final c = Completer<bool>();
    _completer = c;

    void onPhase() {
      if (controller.phase.value == CallPhase.ended && !c.isCompleted) {
        controller.endCall(notifyPeer: false);
        c.complete(false);
      }
    }

    controller.phase.addListener(onPhase);
    current.value = ActiveCallInfo(
      controller: controller,
      name: name,
      photo: photo,
      video: video,
    );
    onPhase();
    return c.future.whenComplete(() {
      controller.phase.removeListener(onPhase);
      current.value = null;
      _completer = null;
    });
  }

  static void returnToCall() {
    final c = _completer;
    if (c != null && !c.isCompleted) c.complete(true);
  }

  static Future<void> hangUp() async {
    await current.value?.controller.endCall();
  }

  /// End button on the notification (works minimized or not).
  static Future<void> hangUpRunning() async {
    await running?.endCall();
  }
}