import 'exercise_catalog_model.dart';

/// Englische und umgangssprachliche Begriffe auf die Wortstämme des Katalogs.
const _synonyms = {
  'bench': 'bankdruecken',
  'benchpress': 'bankdruecken',
  'squat': 'kniebeugen',
  'squats': 'kniebeugen',
  'deadlift': 'kreuzheben',
  'row': 'rudern',
  'rows': 'rudern',
  'curl': 'curls',
  'fly': 'fliegende',
  'flys': 'fliegende',
  'flies': 'fliegende',
  'pulldown': 'latziehen',
  'pullup': 'klimmzuege',
  'pullups': 'klimmzuege',
  'chinup': 'klimmzuege',
  'dip': 'dips',
  'lunge': 'ausfallschritte',
  'lunges': 'ausfallschritte',
  'calf': 'wadenheben',
  'raise': 'heben',
  'lateral': 'seitheben',
  'pushup': 'liegestuetze',
  'pushups': 'liegestuetze',
  'liegestuetz': 'liegestuetze',
  'dumbbell': 'kurzhantel',
  'barbell': 'langhantel',
  'cable': 'kabelzug',
  'kabel': 'kabelzug',
  'machine': 'maschine',
  'kh': 'kurzhantel',
  'lh': 'langhantel',
};

const _stopwords = {
  'am',
  'an',
  'auf',
  'der',
  'die',
  'das',
  'im',
  'in',
  'mit',
  'und',
  'zum',
  'zur',
  'fuer',
  'the',
  'with',
  'on',
};

/// Equipment allein reicht nicht für einen Treffer.
const _weakTokens = {
  'kurzhantel',
  'langhantel',
  'kabelzug',
  'maschine',
  'sz',
  'stange',
  'smith',
  'koerpergewicht',
  'kettlebell',
  'sitzend',
  'stehend',
  'liegend',
  'einarmig',
  'griff',
  'enger',
  'eng',
  'breit',
};

List<String> _tokens(String value) {
  final normalized = value
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll('-', '');
  return [
    for (final token in normalized.split(RegExp('[^a-z0-9]+')))
      if (token.isNotEmpty && !_stopwords.contains(token))
        _synonyms[token] ?? token,
  ];
}

/// Ähnlichkeit zweier Wörter von 0 bis 1: gleich, enthalten (Anteil der
/// Länge) oder gemeinsamer Anfang ab sechs Zeichen.
double _similarity(String a, String b) {
  if (a == b) return 1;
  final shorter = a.length < b.length ? a : b;
  final longer = identical(shorter, a) ? b : a;
  if (shorter.length >= 5 && longer.contains(shorter)) {
    return shorter.length / longer.length;
  }
  var prefix = 0;
  while (prefix < shorter.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  if (prefix >= 6 || (prefix == shorter.length && shorter.length >= 4)) {
    return prefix / longer.length;
  }
  return 0;
}

double _best(String token, List<String> others) {
  var best = 0.0;
  for (final other in others) {
    final value = _similarity(token, other);
    if (value > best) best = value;
  }
  return best;
}

/// Sucht die Katalogübung, deren Name am besten zu [name] passt, und nur
/// solche mit Muskelangaben. Ohne ausreichend ähnlichen Namen: `null`.
CatalogExercise? suggestMuscleSource(
  String name,
  Iterable<CatalogExercise> candidates,
) {
  final query = _tokens(name);
  if (query.isEmpty) return null;
  CatalogExercise? best;
  var bestScore = 0.0;
  for (final candidate in candidates) {
    if (candidate.primaryMuscles.isEmpty) continue;
    final tokens = _tokens(candidate.name);
    if (tokens.isEmpty) continue;
    var queryScore = 0.0;
    var strong = false;
    for (final token in query) {
      final value = _best(token, tokens);
      queryScore += value;
      if (value >= 0.6 && !_weakTokens.contains(token)) strong = true;
    }
    if (!strong) continue;
    var candidateScore = 0.0;
    for (final token in tokens) {
      candidateScore += _best(token, query);
    }
    final score =
        queryScore / query.length + 0.5 * candidateScore / tokens.length;
    if (score > bestScore ||
        (score == bestScore &&
            best != null &&
            candidate.name.length < best.name.length)) {
      best = candidate;
      bestScore = score;
    }
  }
  return bestScore >= 0.75 ? best : null;
}
