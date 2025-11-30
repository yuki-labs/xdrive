import 'dart:math';

/// Generates memorable room IDs for relay connections
class RoomIdGenerator {
  static final List<String> _words = [
    'alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel',
    'india', 'juliet', 'kilo', 'lima', 'mike', 'november', 'oscar', 'papa',
    'quebec', 'romeo', 'sierra', 'tango', 'uniform', 'victor', 'whiskey',
    'xray', 'yankee', 'zulu', 'apple', 'banana', 'cherry', 'dragon', 'eagle',
    'falcon', 'giraffe', 'horse', 'iguana', 'jaguar', 'kangaroo', 'lion',
    'monkey', 'ninja', 'ocean', 'penguin', 'quartz', 'rabbit', 'shark',
    'tiger', 'unicorn', 'viper', 'walrus', 'yeti', 'zebra'
  ];

  /// Generate a random room ID with 3 words
  /// Example: "alpha-bravo-charlie"
  static String generate() {
    final random = Random.secure();
    final word1 = _words[random.nextInt(_words.length)];
    final word2 = _words[random.nextInt(_words.length)];
    final word3 = _words[random.nextInt(_words.length)];
    return '$word1-$word2-$word3';
  }

  /// Validate a room ID format
  static bool isValid(String roomId) {
    final parts = roomId.toLowerCase().split('-');
    return parts.length == 3 && parts.every((p) => _words.contains(p));
  }
}
