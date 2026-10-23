import 'nutrition.dart';

/// Allgemeines Lebensmittel aus einem lokalen Katalog (BLS), Werte pro 100 g.
class LocalFood {
  const LocalFood({
    required this.code,
    required this.name,
    required this.per100Grams,
  });

  final String code;
  final String name;
  final NutritionTotals per100Grams;
}

/// Treffer einer lokalen Suche; [partial], wenn kein Treffer alle
/// Anfragewörter enthält.
class FoodSearchResult {
  const FoodSearchResult(this.foods, {this.partial = false});

  static const empty = FoodSearchResult([]);

  final List<LocalFood> foods;
  final bool partial;
}

/// Deutsche Suche über Lebensmittelnamen: Umlaute und ß gefaltet, Plural und
/// ein Tippfehler toleriert, zusammengesetzte Wörter zerlegt („Haferflocken“
/// findet „Hafer Flocken“). Kurze Wörter treffen nur ganze Wörter oder
/// Wortenden, damit „Ei“ nicht „Reis“ findet.
class FoodSearchIndex {
  FoodSearchIndex(List<LocalFood> foods)
    : _foods = List.unmodifiable(foods),
      _words = [for (final food in foods) _tokens(food.name)] {
    for (final words in _words) {
      _vocabulary.addAll(words);
    }
    for (final word in _vocabulary) {
      _byLength.putIfAbsent(word.length, () => []).add(word);
    }
  }

  static const maxResults = 20;
  static const _minPartLength = 3;
  static const _minTypoLength = 5;
  static const _pluralEndings = ['en', 'n', 's', 'e'];

  final List<LocalFood> _foods;
  final List<List<String>> _words;
  final Set<String> _vocabulary = {};
  final Map<int, List<String>> _byLength = {};

  int get length => _foods.length;

  FoodSearchResult search(String query, {int limit = maxResults}) {
    final terms = _tokens(query).toSet().toList();
    if (normalizeFoodText(query).replaceAll(' ', '').length < 2 ||
        terms.isEmpty) {
      return FoodSearchResult.empty;
    }
    final matchers = [for (final term in terms) _TermMatcher.of(term, this)];
    final hits = <_Hit>[];
    for (var index = 0; index < _foods.length; index++) {
      final words = _words[index];
      var matched = 0;
      var score = 0.0;
      for (final matcher in matchers) {
        final value = matcher.score(words);
        if (value > 0) {
          matched++;
          score += value;
        }
      }
      if (matched > 0) hits.add(_Hit(index, matched, score));
    }
    if (hits.isEmpty) return FoodSearchResult.empty;
    final best = hits.fold<int>(
      0,
      (max, hit) => hit.matched > max ? hit.matched : max,
    );
    final ranked = hits.where((hit) => hit.matched == best).toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final byLength = _foods[a.index].name.length.compareTo(
          _foods[b.index].name.length,
        );
        return byLength != 0 ? byLength : a.index.compareTo(b.index);
      });
    return FoodSearchResult(
      List.unmodifiable([
        for (final hit in ranked.take(limit)) _foods[hit.index],
      ]),
      partial: best < terms.length,
    );
  }

  /// Wörter des Katalogs mit höchstens einer Abweichung zu [term].
  Set<String> _typoNeighbours(String term) => {
    for (var length = term.length - 1; length <= term.length + 1; length++)
      for (final word in _byLength[length] ?? const <String>[])
        if (_withinOneEdit(term, word)) word,
  };

  /// Zerlegt [term] in möglichst wenige Wörter des Katalogs (je mindestens
  /// drei Buchstaben); null, wenn das nicht in mindestens zwei Teile geht.
  List<String>? _split(String term) {
    if (term.length < _minPartLength * 2) return null;
    final best = List<List<String>?>.filled(term.length + 1, null);
    best[0] = const [];
    for (var end = _minPartLength; end <= term.length; end++) {
      for (var start = 0; start <= end - _minPartLength; start++) {
        final prefix = best[start];
        if (prefix == null) continue;
        final part = term.substring(start, end);
        // Das ganze Wort ist kein Teil; gesucht sind mindestens zwei.
        if (part.length == term.length || !_vocabulary.contains(part)) {
          continue;
        }
        final candidate = [...prefix, part];
        final current = best[end];
        if (current == null || candidate.length < current.length) {
          best[end] = candidate;
        }
      }
    }
    final parts = best[term.length];
    return parts == null || parts.length < 2 ? null : parts;
  }
}

class _Hit {
  const _Hit(this.index, this.matched, this.score);
  final int index;
  final int matched;
  final double score;
}

/// Bewertet ein Anfragewort gegen die Wörter eines Namens.
class _TermMatcher {
  _TermMatcher(this.variants, this.typos, this.parts);

  factory _TermMatcher.of(String term, FoodSearchIndex index) {
    final variants = <String>{term};
    for (final ending in FoodSearchIndex._pluralEndings) {
      if (term.endsWith(ending) && term.length - ending.length >= 4) {
        variants.add(term.substring(0, term.length - ending.length));
      }
    }
    final parts = index._split(term);
    final direct = variants.any(
      (variant) => index._vocabulary.any((word) => word.contains(variant)),
    );
    final typos =
        !direct &&
            parts == null &&
            term.length >= FoodSearchIndex._minTypoLength
        ? index._typoNeighbours(term)
        : const <String>{};
    return _TermMatcher(variants.toList(), typos, parts);
  }

  final List<String> variants;
  final Set<String> typos;
  final List<String>? parts;

  double score(List<String> words) {
    var best = 0.0;
    for (final variant in variants) {
      final value = _bestWordScore(variant, words);
      if (value > best) best = value;
    }
    for (var i = 0; i < words.length; i++) {
      if (typos.contains(words[i])) {
        final value = 3.0 + (i == 0 ? 1 : 0);
        if (value > best) best = value;
      }
    }
    final compound = _compoundScore(words);
    return compound > best ? compound : best;
  }

  /// Gewichteter Schnitt der Teile; das Grundwort (letzter Teil) zählt
  /// doppelt. Alle Teile müssen treffen.
  double _compoundScore(List<String> words) {
    final parts = this.parts;
    if (parts == null) return 0;
    var sum = 0.0;
    var firstWord = false;
    for (var p = 0; p < parts.length; p++) {
      var partBest = 0.0;
      for (var i = 0; i < words.length; i++) {
        final value = _wordScore(parts[p], words[i]).toDouble();
        if (value > partBest) partBest = value;
        if (value > 0 && i == 0) firstWord = true;
      }
      if (partBest == 0) return 0;
      sum += p == parts.length - 1 ? partBest * 2 : partBest;
    }
    return sum / (parts.length + 1) + (firstWord ? 1 : 0);
  }

  static double _bestWordScore(String variant, List<String> words) {
    var best = 0.0;
    for (var i = 0; i < words.length; i++) {
      final value = _wordScore(variant, words[i]);
      if (value == 0) continue;
      final total = value + (i == 0 ? 1.0 : 0.0);
      if (total > best) best = total;
    }
    return best;
  }

  /// 4 ganzes Wort, 3 Wortende, 2 Wortanfang, 1 im Wort. Unter drei
  /// Buchstaben nur ganzes Wort oder Wortende.
  static int _wordScore(String term, String word) {
    if (word == term) return 4;
    if (word.endsWith(term)) return 3;
    if (term.length < 3) return 0;
    if (word.startsWith(term)) return 2;
    return word.contains(term) ? 1 : 0;
  }
}

/// Kleinschreibung, ß → ss, Umlaute und Akzente gefaltet, getippte ae/oe/ue
/// wie Umlaute; alles außer Buchstaben und Ziffern wird zu Leerzeichen.
String normalizeFoodText(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_folds[char] ?? char);
  }
  return buffer
      .toString()
      .replaceAll('ae', 'a')
      .replaceAll('oe', 'o')
      .replaceAll('ue', 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

List<String> _tokens(String value) => [
  for (final word in normalizeFoodText(value).split(' '))
    if (word.isNotEmpty) word,
];

const _folds = {
  'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss', 'à': 'a', 'á': 'a', 'â': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'î': 'i', 'ï': 'i', //
  'ó': 'o', 'ô': 'o', 'ú': 'u', 'û': 'u', 'ç': 'c', 'ñ': 'n',
};

/// Levenshtein-Abstand höchstens 1, in linearer Zeit.
bool _withinOneEdit(String a, String b) {
  if (a == b) return true;
  final lengthDiff = a.length - b.length;
  if (lengthDiff.abs() > 1) return false;
  final (shorter, longer) = a.length <= b.length ? (a, b) : (b, a);
  var i = 0;
  var j = 0;
  var edits = 0;
  while (i < shorter.length && j < longer.length) {
    if (shorter.codeUnitAt(i) == longer.codeUnitAt(j)) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (shorter.length == longer.length) i++;
    j++;
  }
  return edits + (longer.length - j) + (shorter.length - i) <= 1;
}
