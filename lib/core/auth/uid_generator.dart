import 'dart:math';

/// Generates a memorable, unique public identity code for a user —
/// used for adding contacts instead of a phone number or email.
/// Format: word-word-##  e.g. "amber-falcon-17"
class UidGenerator {
  static const _words = [
    'amber', 'coral', 'ember', 'ivory', 'jade', 'onyx', 'pearl', 'sable',
    'falcon', 'otter', 'lynx', 'heron', 'raven', 'sparrow', 'panther', 'wolf',
    'swift', 'quiet', 'bold', 'calm', 'bright', 'quick', 'silent', 'lucky',
  ];

  static String generate() {
    final rand = Random.secure();
    final first = _words[rand.nextInt(_words.length)];
    final second = _words[rand.nextInt(_words.length)];
    final number = rand.nextInt(90) + 10; // 10-99
    return '$first-$second-$number';
  }
}
