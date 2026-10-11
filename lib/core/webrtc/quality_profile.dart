enum QualityLevel { low, medium, high }

/// The lower of two levels (lower setting always wins).
QualityLevel lowerOf(QualityLevel a, QualityLevel b) =>
    a.index <= b.index ? a : b;

/// Numbers used for each level. Video is captured at 720p and scaled down.
class QualityProfile {
  static int audioBitrate(QualityLevel level) {
    switch (level) {
      case QualityLevel.low:
        return 16000;
      case QualityLevel.medium:
        return 32000;
      case QualityLevel.high:
        return 64000;
    }
  }

  static int videoBitrate(QualityLevel level) {
    switch (level) {
      case QualityLevel.low:
        return 150000;
      case QualityLevel.medium:
        return 500000;
      case QualityLevel.high:
        return 1200000;
    }
  }

  static int videoFps(QualityLevel level) {
    switch (level) {
      case QualityLevel.low:
        return 15;
      case QualityLevel.medium:
        return 24;
      case QualityLevel.high:
        return 30;
    }
  }

  /// 3.0 = 240p, 1.5 = 480p, 1.0 = 720p (when captured at 720 wide).
  static double videoScale(QualityLevel level) {
    switch (level) {
      case QualityLevel.low:
        return 3.0;
      case QualityLevel.medium:
        return 1.5;
      case QualityLevel.high:
        return 1.0;
    }
  }
}