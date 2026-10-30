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

class ActiveGroupCallInfo {
  final String groupId;
  final String groupName;
  final String emoji;
  final int color;
  final String mode;
  final bool video;
  final int Function() getSeconds;
  final VoidCallback onReturn;
  final Future<void> Function() onEnd;

  const ActiveGroupCallInfo({
    required this.groupId,
    required this.groupName,
    required this.emoji,
    required this.color,
    required this.mode,
    required this.video,
    required this.getSeconds,
    required this.onReturn,
    required this.onEnd,
  });
}

/// Keeps track of the running call and of a minimized one.
class ActiveCall {
  /// The connected call (set by the controller).
  static CallController? running;

  /// Not null while the call screen is minimized (shows the green bar).
  static final current = ValueNotifier<ActiveCallInfo?>(null);

  /// Not null while a group call is minimized.
  static final currentGroup = ValueNotifier<ActiveGroupCallInfo?>(null);

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