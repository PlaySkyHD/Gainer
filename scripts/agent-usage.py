"""Zeigt den Verbrauch einer Claude-Code-Session und ihrer Subagents (nur lesend).

Aufruf (Pfad ohne .jsonl, Unterordner subagents/ liegt daneben):

    python3 -I scripts/agent-usage.py ~/.claude/projects/<repo-slug>/<session-id>

Pro Transkript (Hauptsession und subagents/*.jsonl): Modell, Turns, Ø- und Max-Kontext,
Cache-Neuaufbauten über 100k Token, Tool-Ergebnisse über 20.000 Zeichen und Anteil am
Gesamtgewicht. Danach Gewicht pro Modell und pro Stunde (UTC).

Gewicht = Input + Cache-Writes + 0,1 * Cache-Reads + 5 * Output (Token). Das ist eine
grobe Näherung für die Last auf das Kontingent, keine Abrechnung. Nachrichten-IDs werden
dedupliziert, weil eine Antwort in mehreren Zeilen des Transkripts stehen kann.

Beispiel (gekürzt):

    Gewicht gesamt 58.1M, 36 Transkripte
    Gewicht  Anteil  Turns  Ø-Ktx  Max-Ktx  Neuaufb.  Große  Modell   Transkript
      24.3M  41.9%    415   434k     717k        12     20  opus    agent-a32a1bcb4007545a2
"""
import collections
import glob
import json
import os
import sys

REBUILD_TOKENS = 100_000
BIG_RESULT_CHARS = 20_000


def weight(usage):
    """Grobe Näherung der Kontingentlast, siehe Modul-Docstring."""
    return (
        (usage.get("input_tokens") or 0)
        + (usage.get("cache_creation_input_tokens") or 0)
        + 0.1 * (usage.get("cache_read_input_tokens") or 0)
        + 5 * (usage.get("output_tokens") or 0)
    )


def context_size(usage):
    return sum(
        usage.get(key) or 0
        for key in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
    )


def analyse(path):
    """Liest ein Transkript und gibt Kennzahlen und Gewicht pro Stunde zurück."""
    seen = set()
    contexts = []
    per_hour = collections.Counter()
    models = collections.Counter()
    total_weight = 0.0
    rebuilds = 0
    big_results = 0
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            message = record.get("message") or {}
            if record.get("type") == "user" and isinstance(message.get("content"), list):
                for part in message["content"]:
                    if isinstance(part, dict) and part.get("type") == "tool_result":
                        if len(json.dumps(part.get("content"))) > BIG_RESULT_CHARS:
                            big_results += 1
            usage = message.get("usage")
            if not usage:
                continue
            message_id = message.get("id") or record.get("uuid")
            if message_id in seen:
                continue
            seen.add(message_id)
            contexts.append(context_size(usage))
            if (usage.get("cache_creation_input_tokens") or 0) > REBUILD_TOKENS:
                rebuilds += 1
            current = weight(usage)
            total_weight += current
            per_hour[(record.get("timestamp") or "")[:13]] += current
            if message.get("model"):
                models[message["model"]] += current
    return {
        "turns": len(contexts),
        "avg_context": sum(contexts) / len(contexts) if contexts else 0,
        "max_context": max(contexts, default=0),
        "rebuilds": rebuilds,
        "big_results": big_results,
        "weight": total_weight,
        "per_hour": per_hour,
        "model": models.most_common(1)[0][0] if models else "-",
        "models": models,
    }


def short_model(name):
    for family in ("opus", "sonnet", "haiku"):
        if family in name:
            return family
    return name[:12]


def main():
    if len(sys.argv) != 2:
        sys.exit("Aufruf: python3 -I scripts/agent-usage.py <pfad-zur-session-ohne-.jsonl>")
    root = sys.argv[1].removesuffix(".jsonl")
    paths = [root + ".jsonl"] + sorted(glob.glob(os.path.join(root, "subagents", "*.jsonl")))
    paths = [path for path in paths if os.path.isfile(path)]
    if not paths:
        sys.exit("Keine Transkripte gefunden.")

    results = []
    for path in paths:
        name = "main" if path == root + ".jsonl" else os.path.basename(path).removesuffix(".jsonl")
        results.append((name, analyse(path)))

    total = sum(result["weight"] for _, result in results) or 1.0
    per_hour = collections.Counter()
    per_model = collections.Counter()
    for _, result in results:
        per_hour.update(result["per_hour"])
        per_model.update(result["models"])

    print(f"Gewicht gesamt {total / 1e6:.1f}M, {len(results)} Transkripte")
    print("Gewicht  Anteil  Turns  Ø-Ktx  Max-Ktx  Neuaufb.  Große  Modell   Transkript")
    for name, result in sorted(results, key=lambda item: -item[1]["weight"]):
        print(
            f"{result['weight'] / 1e6:6.1f}M {result['weight'] / total:6.1%} "
            f"{result['turns']:6d} {result['avg_context'] / 1e3:5.0f}k {result['max_context'] / 1e3:7.0f}k "
            f"{result['rebuilds']:9d} {result['big_results']:6d}  "
            f"{short_model(result['model']):7} {name[:40]}"
        )

    print("\nModellanteil:")
    for model, value in per_model.most_common():
        print(f"  {short_model(model):8} {value / total:6.1%}")

    print("\nGewicht pro Stunde (UTC):")
    for hour, value in sorted(per_hour.items()):
        print(f"  {hour or '?':13} {value / 1e6:6.2f}M {'#' * int(value / total * 100)}")


if __name__ == "__main__":
    main()
