import 'package:shared_preferences/shared_preferences.dart';
import '../../core/webrtc/quality_choice.dart';

class ContactQuality {
  final QualityChoice audio;
  final QualityChoice video;
  const ContactQuality(this.audio, this.video);
}

/// Saved audio/video quality per friend, stored on this phone only.
class ContactQualityPrefs {
  ContactQualityPrefs._();

  static QualityChoice _parse(String? s) {
    for (final c in QualityChoice.values) {
      if (c.name == s) return c;
    }
    return QualityChoice.auto;
  }

  /// Null = nothing saved for this friend.
  static Future<ContactQuality?> get(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final p = await SharedPreferences.getInstance();
      final a = p.getString('cq_a_$uid');
      final v = p.getString('cq_v_$uid');
      if (a == null && v == null) return null;
      return ContactQuality(_parse(a), _parse(v));
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(String uid, ContactQuality q) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('cq_a_$uid', q.audio.name);
      await p.setString('cq_v_$uid', q.video.name);
    } catch (_) {}
  }
}