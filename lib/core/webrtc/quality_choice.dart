import 'quality_profile.dart';

/// What the user picks on the quality sheet.
enum QualityChoice { auto, low, medium, high }

/// Turns a user choice into a real level.
/// Auto = Medium normally, Low while the network looks weak.
QualityLevel resolveChoice(QualityChoice choice, {required bool weak}) {
  switch (choice) {
    case QualityChoice.low:
      return QualityLevel.low;
    case QualityChoice.medium:
      return QualityLevel.medium;
    case QualityChoice.high:
      return QualityLevel.high;
    case QualityChoice.auto:
      return weak ? QualityLevel.low : QualityLevel.medium;
  }
}