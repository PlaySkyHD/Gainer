/// Art einer Notiz im Coach-Gedächtnis; [wireName] steht im API-Vertrag.
enum CoachMemoryCategory {
  goal('goal', 'Ziel', 'Ziele'),
  preference('preference', 'Vorliebe', 'Vorlieben'),
  intolerance('intolerance', 'Unverträglichkeit', 'Unverträglichkeiten'),
  injury('injury', 'Verletzung', 'Verletzungen'),
  other('other', 'Sonstiges', 'Sonstiges');

  const CoachMemoryCategory(this.wireName, this.label, this.pluralLabel);

  final String wireName;
  final String label;

  /// Überschrift der Gruppe im Gedächtnis-Screen.
  final String pluralLabel;

  /// Null bei unbekannten Werten, etwa von einem neueren Server.
  static CoachMemoryCategory? fromWire(Object? value) {
    for (final category in values) {
      if (category.wireName == value) return category;
    }
    return null;
  }
}

/// Höchstlänge einer Notiz, gemessen mit [coachMemoryTextLength].
const coachMemoryMaxTextLength = 200;

/// Länge einer Notiz, wie der Server sie prüft: getrimmt und in
/// UTF-16-Einheiten (`string.Length` dort, `String.length` hier). Ein Emoji
/// zählt deshalb meist zwei.
int coachMemoryTextLength(String text) => text.trim().length;

/// True, wenn [text] als Notiz gespeichert werden kann.
bool isValidCoachMemoryText(String text) {
  final length = coachMemoryTextLength(text);
  return length >= 1 && length <= coachMemoryMaxTextLength;
}

/// Eine vom Nutzer bestätigte oder angelegte Notiz für den Coach.
class ApiCoachMemory {
  const ApiCoachMemory({
    required this.id,
    required this.category,
    required this.text,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.version,
    this.unknownCategory,
  });

  /// Eine unbekannte Kategorie (etwa von einem neueren Server) wird zu
  /// „Sonstiges“: Der Coach liest die Notiz, also muss der Nutzer sie sehen
  /// und löschen können. Der Wire-Wert bleibt in [unknownCategory] erhalten.
  factory ApiCoachMemory.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final text = json['text'];
    final category = json['category'];
    final created = DateTime.tryParse(json['createdAtUtc'] as String? ?? '');
    final updated = DateTime.tryParse(json['updatedAtUtc'] as String? ?? '');
    if (id is! String ||
        text is! String ||
        category is! String ||
        created == null ||
        updated == null) {
      throw const FormatException('Invalid coach memory.');
    }
    final known = CoachMemoryCategory.fromWire(category);
    return ApiCoachMemory(
      id: id,
      category: known ?? CoachMemoryCategory.other,
      text: text,
      createdAtUtc: created.toUtc(),
      updatedAtUtc: updated.toUtc(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      unknownCategory: known == null ? category : null,
    );
  }

  final String id;

  /// Angezeigte Kategorie; bei unbekanntem Wire-Wert „Sonstiges“.
  final CoachMemoryCategory category;

  /// Wire-Wert einer Kategorie, die die App nicht kennt, sonst null. Ändert
  /// der Nutzer die Kategorie nicht, geht dieser Wert unverändert zurück.
  final String? unknownCategory;
  final String text;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int version;
}

/// Alle Notizen des Kontos, neueste zuerst, und die Höchstzahl.
class ApiCoachMemoryList {
  const ApiCoachMemoryList({required this.items, required this.maxEntries});

  factory ApiCoachMemoryList.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid coach memory list.');
    }
    return ApiCoachMemoryList(
      items: [
        for (final item in items)
          if (item is Map<String, dynamic>) ApiCoachMemory.fromJson(item),
      ],
      maxEntries: (json['maxEntries'] as num?)?.toInt() ?? 50,
    );
  }

  final List<ApiCoachMemory> items;
  final int maxEntries;
}

/// Vorschlag des Coaches; gespeichert wird erst nach „Merken“.
class ApiCoachMemorySuggestion {
  const ApiCoachMemorySuggestion({required this.category, required this.text});

  final CoachMemoryCategory category;
  final String text;

  /// Liest die Vorschläge einer Antwort. Fehlt das Feld (älterer Server) oder
  /// ist ein Eintrag unbrauchbar, wird er ausgelassen.
  static List<ApiCoachMemorySuggestion> listFromJson(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map<String, dynamic>)
          if ((CoachMemoryCategory.fromWire(item['category']), item['text'])
              case (final CoachMemoryCategory category, final String text)
              when text.trim().isNotEmpty)
            ApiCoachMemorySuggestion(category: category, text: text.trim()),
    ];
  }
}
