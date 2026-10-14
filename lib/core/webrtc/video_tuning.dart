import 'quality_profile.dart';

/// Video limits per quality level (audio is untouched).
class VideoTuning {
  static int _pick(QualityLevel l, int low, int mid, int high, int extreme) {
    switch (l) {
      case QualityLevel.low:
        return low;
      case QualityLevel.medium:
        return mid;
      case QualityLevel.high:
        return high;
      case QualityLevel.extreme:
        return extreme;
    }
  }

  static int maxBitrate(QualityLevel l) =>
      _pick(l, 120000, 380000, 800000, 8000000);
  static int minBitrate(QualityLevel l) =>
      _pick(l, 40000, 120000, 250000, 1000000);
  static int fps(QualityLevel l) => _pick(l, 15, 24, 30, 60);
  static double scale(QualityLevel l) {
    switch (l) {
      case QualityLevel.low:
        return 3.0;
      case QualityLevel.medium:
        return 1.5;
      case QualityLevel.high:
        return 1.0;
      case QualityLevel.extreme:
        return 1.0;
    }
  }
}