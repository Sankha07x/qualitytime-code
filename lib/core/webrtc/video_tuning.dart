import 'quality_profile.dart';

/// Video limits per quality level (audio is untouched).
class VideoTuning {
  static int _pick(QualityLevel l, int low, int mid, int high) {
    switch (l.name) {
      case 'low':
        return low;
      case 'high':
        return high;
      default:
        return mid;
    }
  }

  static int maxBitrate(QualityLevel l) => _pick(l, 120000, 380000, 800000);
  static int minBitrate(QualityLevel l) => _pick(l, 40000, 120000, 250000);
  static int fps(QualityLevel l) => _pick(l, 15, 24, 30);
  static double scale(QualityLevel l) =>
      l.name == 'low' ? 3.0 : (l.name == 'high' ? 1.0 : 1.5);
}