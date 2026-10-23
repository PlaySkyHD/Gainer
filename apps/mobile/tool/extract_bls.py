#!/usr/bin/env python3
"""Erzeugt assets/food/bls_4_0.json aus dem offiziellen BLS-4.0-Download.

Nutzung (aus apps/mobile):
    python3 -I tool/extract_bls.py <BLS_4_0_2025_DE.zip>

Download: https://www.blsdb.de/download (Max Rubner-Institut, CC BY 4.0).
Das ZIP wird nicht eingecheckt, nur das erzeugte Asset. Es braucht nur die
Python-Standardbibliothek.
"""

from __future__ import annotations

import io
import json
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

WORKBOOK = "BLS_4_0_2025_DE/BLS_4_0_Daten_2025_DE.xlsx"
EXPECTED_ROWS = 7140
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}

# Spalte -> erwarteter Anfang des Kopfes. Ein anderes Layout bricht ab.
HEADERS = {
    "A": "BLS Code",
    "B": "Lebensmittelbezeichnung",
    "G": "ENERCC ",
    "M": "PROT625 ",
    "S": "CHO ",
    "P": "FAT ",
    "V": "FIBT ",
    "DQ": "NACL ",
}
# Reihenfolge im Asset: kcal, Eiweiß, Kohlenhydrate, Fett, Ballaststoffe, Salz.
NUTRIENT_COLUMNS = ("G", "M", "S", "P", "V", "DQ")


def _cells(row: ET.Element, strings: list[str]) -> dict[str, str]:
    cells: dict[str, str] = {}
    for cell in row:
        value = cell.find("m:v", NS)
        if value is None or value.text is None:
            continue
        column = "".join(char for char in cell.attrib["r"] if char.isalpha())
        cells[column] = strings[int(value.text)] if cell.get("t") == "s" else value.text
    return cells


def _number(raw: str | None) -> float | None:
    """Unbekannt bleibt null: Strich, leer, Spur (TR) und Werte mit „<“."""
    if raw is None:
        return None
    text = raw.strip()
    if text in ("", "-", "TR") or text.startswith("<"):
        return None
    value = round(float(text), 2)
    return int(value) if value == int(value) else value


def extract(archive: Path) -> dict:
    with zipfile.ZipFile(archive) as outer:
        workbook = outer.read(WORKBOOK)
    with zipfile.ZipFile(io.BytesIO(workbook)) as inner:
        strings = [
            "".join(item.itertext())
            for item in ET.fromstring(inner.read("xl/sharedStrings.xml"))
        ]
        sheet = inner.read("xl/worksheets/sheet1.xml")

    foods: list[list] = []
    rows = 0
    skipped = 0
    for _, row in ET.iterparse(io.BytesIO(sheet), events=("end",)):
        if row.tag != f"{{{NS['m']}}}row":
            continue
        cells = _cells(row, strings)
        if row.attrib["r"] == "1":
            for column, prefix in HEADERS.items():
                if not cells.get(column, "").startswith(prefix):
                    raise ValueError(f"Unerwarteter Kopf in Spalte {column}: {cells.get(column)!r}")
        else:
            rows += 1
            values = [_number(cells.get(column)) for column in NUTRIENT_COLUMNS]
            if values[0] is None:
                skipped += 1
            else:
                foods.append([cells["A"].strip(), cells["B"].strip(), *values])
        row.clear()

    if rows != EXPECTED_ROWS:
        raise ValueError(f"Erwartet {EXPECTED_ROWS} Lebensmittel, gefunden {rows}")
    if skipped:
        print(f"{skipped} Lebensmittel ohne kcal ausgelassen", file=sys.stderr)
    return {
        "source": "Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0",
        "url": "https://doi.org/10.25826/Data20251217-134202-0",
        "license": "CC BY 4.0",
        "version": "4.0",
        "fields": ["code", "name", "kcal", "protein", "carbs", "fat", "fiber", "salt"],
        "foods": foods,
    }


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("Nutzung: python3 -I tool/extract_bls.py <BLS_4_0_2025_DE.zip>")
    target = Path(__file__).resolve().parents[1] / "assets" / "food" / "bls_4_0.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    data = extract(Path(sys.argv[1]))
    target.write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(f"{len(data['foods'])} Lebensmittel nach {target} geschrieben")


if __name__ == "__main__":
    main()
