#!/usr/bin/env python3
"""
Generate MacBar Localizable.strings files for languages with speaking population >= 5 million.

Data source:
- language_data.population_data.LANGUAGE_SPEAKING_POPULATION

Translation source:
- deep_translator.GoogleTranslator

Notes:
- For languages not directly supported by translator, fallback language mappings are used.
- Menu will only show languages with generated localization resources.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import time
from pathlib import Path
from typing import Dict, List, Tuple

from deep_translator import GoogleTranslator
from language_data.population_data import LANGUAGE_SPEAKING_POPULATION as POPULATION
from langcodes import Language

ROOT = Path(__file__).resolve().parents[1]
RESOURCES_DIR = ROOT / "Sources" / "MacBar" / "Resources"
EN_STRINGS_PATH = RESOURCES_DIR / "en.lproj" / "Localizable.strings"
CACHE_PATH = ROOT / "scripts" / ".translation_cache.json"
MANUAL_OVERRIDES_DIR = ROOT / "scripts" / "manual_overrides"

# Explicit language fallback mappings for high-population codes not supported directly
# by the translator API. The target is another app language code that does have a
# translated resource generated directly from English.
FALLBACK_LANGUAGE_MAP: Dict[str, str] = {
    # Chinese varieties
    "zh": "zh-Hans",
    "yue": "zh-Hant",
    "wuu": "zh-Hans",
    "hsn": "zh-Hans",
    "nan": "zh-Hant",
    "hak": "zh-Hant",
    "gan": "zh-Hans",
    "ii": "zh-Hans",
    # Arabic dialects / close Arabic-script variants
    "aeb": "ar",
    "apc": "ar",
    "apd": "ar",
    "arq": "ar",
    "ary": "ar",
    "arz": "ar",
    "dcc": "ar",
    "shi": "ar",
    "zgh": "ar",
    "cop": "ar",
    # Indo-Aryan varieties
    "lah": "pa",
    "skr": "pa",
    "awa": "hi",
    "bgc": "hi",
    "mag": "hi",
    "mwr": "hi",
    "hne": "hi",
    "bjj": "hi",
    "wtm": "hi",
    "knn": "hi",
    "sat": "hi",
    "rkt": "bn",
    "syl": "bn",
    # Thai varieties
    "nod": "th",
    "sou": "th",
    "tts": "th",
    # Germanic dialects
    "bar": "de",
    "gsw": "de",
    "vmf": "de",
    "nds": "de",
    # Malay/Indonesian cluster
    "mad": "id",
    "min": "id",
    "bew": "id",
    "ban": "id",
    # African languages and creoles (closest practical fallback)
    "bem": "sw",
    "luy": "sw",
    "luo": "sw",
    "rn": "sw",
    "suk": "sw",
    "ki": "sw",
    "nso": "zu",
    "tn": "zu",
    "dyu": "fr",
    "ff": "fr",
    "fuv": "ha",
    "kmb": "pt",
    "lua": "fr",
    "man": "fr",
    "mos": "fr",
    "wo": "fr",
    "umb": "pt",
    # Other
    "hil": "fil",
    "ks": "ur",
    "bal": "fa",
    "nb": "no",
    "pcm": "en",
    "tpi": "en",
}

SCRIPT_FALLBACK_MAP: Dict[str, str] = {
    "Arab": "ar",
    "Armn": "hy",
    "Beng": "bn",
    "Cyrl": "ru",
    "Deva": "hi",
    "Ethi": "am",
    "Geor": "ka",
    "Grek": "el",
    "Gujr": "gu",
    "Guru": "pa",
    "Hans": "zh-Hans",
    "Hant": "zh-Hant",
    "Hebr": "he",
    "Khmr": "km",
    "Knda": "kn",
    "Laoo": "lo",
    "Mlym": "ml",
    "Mong": "mn",
    "Orya": "or",
    "Sinh": "si",
    "Taml": "ta",
    "Telu": "te",
    "Thai": "th",
}


def parse_strings_file(path: Path) -> List[Tuple[str, str]]:
    pattern = re.compile(r'^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";\s*$')

    entries: List[Tuple[str, str]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue
        match = pattern.match(line)
        if not match:
            continue
        key = unescape_strings(match.group(1))
        value = unescape_strings(match.group(2))
        entries.append((key, value))
    return entries


def unescape_strings(value: str) -> str:
    return (
        value.replace(r"\\", "\\")
        .replace(r'\"', '"')
        .replace(r"\n", "\n")
    )


def escape_strings(value: str) -> str:
    return (
        value.replace("\\", r"\\")
        .replace('"', r'\"')
        .replace("\n", r"\n")
    )


def google_code_to_app_code(google_code: str) -> str:
    mapping = {
        "iw": "he",
        "jw": "jv",
        "zh-CN": "zh-Hans",
        "zh-TW": "zh-Hant",
        "tl": "fil",
    }
    normalized = google_code.replace("_", "-")
    return mapping.get(normalized, normalized)


def app_code_to_google_code(app_code: str, google_supported: Dict[str, str]) -> str:
    reverse_map = {
        "he": "iw",
        "jv": "jw",
        "zh-Hans": "zh-CN",
        "zh-Hant": "zh-TW",
        "fil": "tl",
    }

    if app_code in reverse_map:
        return reverse_map[app_code]

    if app_code in google_supported.values():
        return app_code

    raise KeyError(f"No Google code mapping for app code: {app_code}")


def languages_over_5m() -> List[str]:
    # Keep base language codes only (no territory/script subtags) from CLDR population data.
    base_codes = [
        code
        for code, pop in POPULATION.items()
        if "-" not in code and pop >= 5_000_000
    ]
    return sorted(set(base_codes))


def resolve_language_mapping(
    language_codes: List[str],
    directly_supported_app_codes: set[str],
) -> Dict[str, str]:
    mapping: Dict[str, str] = {}

    for code in language_codes:
        if code in directly_supported_app_codes:
            mapping[code] = code
            continue

        if code in FALLBACK_LANGUAGE_MAP:
            mapping[code] = FALLBACK_LANGUAGE_MAP[code]
            continue

        # Try macrolanguage (when available)
        preferred_macro = Language.get(code).prefer_macrolanguage().language
        if preferred_macro in directly_supported_app_codes:
            mapping[code] = preferred_macro
            continue

        # Script-based fallback
        script = Language.get(code).maximize().script
        if script in SCRIPT_FALLBACK_MAP:
            mapping[code] = SCRIPT_FALLBACK_MAP[script]
            continue

        # Last-resort fallback
        mapping[code] = "en"

    # Add both Chinese scripts explicitly for better UX coverage.
    mapping.setdefault("zh-Hans", "zh-Hans")
    mapping.setdefault("zh-Hant", "zh-Hant")

    return mapping


def protect_placeholders(text: str) -> Tuple[str, Dict[str, str]]:
    replacements: Dict[str, str] = {}

    def repl(match: re.Match[str]) -> str:
        token = f"__PH_{len(replacements)}__"
        replacements[token] = match.group(0)
        return token

    protected = re.sub(r"%(@|\d+\$@)", repl, text)
    return protected, replacements


def restore_placeholders(text: str, replacements: Dict[str, str]) -> str:
    restored = text
    for token, value in replacements.items():
        restored = restored.replace(token, value)
        restored = restored.replace(token.lower(), value)
    return restored


def normalize_translated_text(value: str) -> str:
    # Some providers append line breaks around translated fragments.
    return value.replace("\r", "").strip()


def translate_values(
    source_values: List[str],
    target_google_code: str,
    max_retries: int = 3,
) -> List[str]:
    if target_google_code == "en":
        return source_values

    protected_values: List[str] = []
    placeholder_maps: List[Dict[str, str]] = []

    for value in source_values:
        protected, replacements = protect_placeholders(value)
        protected_values.append(protected)
        placeholder_maps.append(replacements)

    # Translate in chunks to keep payload reasonable.
    translated_values: List[str] = ["" for _ in source_values]
    chunk_size = 35

    translator = GoogleTranslator(source="en", target=target_google_code)

    for start in range(0, len(protected_values), chunk_size):
        end = min(start + chunk_size, len(protected_values))
        chunk = protected_values[start:end]

        payload_lines = [f"@@@{i}@@@{text}" for i, text in enumerate(chunk, start=start)]
        payload = "\n".join(payload_lines)

        last_error: Exception | None = None
        for attempt in range(max_retries):
            try:
                translated_payload = translator.translate(payload)
                break
            except Exception as exc:  # noqa: BLE001
                last_error = exc
                sleep_seconds = 1.0 * (attempt + 1)
                time.sleep(sleep_seconds)
        else:
            raise RuntimeError(
                f"Failed translating chunk {start}-{end} to {target_google_code}: {last_error}"
            )

        parts = re.split(r"@{2,3}\s*(\d+)\s*@{2,3}", translated_payload)
        if len(parts) < 3:
            raise RuntimeError(
                f"Unexpected translation format for {target_google_code}: {translated_payload[:160]}"
            )

        for idx in range(1, len(parts) - 1, 2):
            str_index = int(parts[idx])
            translated_text = normalize_translated_text(parts[idx + 1])
            translated_values[str_index] = translated_text

        # Politeness delay to reduce throttling.
        time.sleep(0.2)

    restored_values: List[str] = []
    for i, value in enumerate(translated_values):
        restored_values.append(
            normalize_translated_text(restore_placeholders(value, placeholder_maps[i]))
        )

    return restored_values


def write_strings_file(path: Path, entries: List[Tuple[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f'"{escape_strings(k)}" = "{escape_strings(v)}";' for k, v in entries]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def remove_generated_localizations(resources_dir: Path) -> None:
    for child in resources_dir.iterdir():
        if child.is_dir() and child.name.endswith(".lproj"):
            shutil.rmtree(child)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--threshold", type=int, default=5_000_000, help="Population threshold")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not EN_STRINGS_PATH.exists():
        raise FileNotFoundError(f"English strings not found: {EN_STRINGS_PATH}")

    source_entries = parse_strings_file(EN_STRINGS_PATH)
    keys = [k for k, _ in source_entries]
    source_values = [v for _, v in source_entries]

    google_supported = GoogleTranslator().get_supported_languages(as_dict=True)
    directly_supported_app_codes = {
        google_code_to_app_code(code) for code in google_supported.values()
    }

    all_codes = [
        code
        for code, pop in POPULATION.items()
        if "-" not in code and pop >= args.threshold
    ]
    all_codes = sorted(set(all_codes))

    mapping = resolve_language_mapping(all_codes, directly_supported_app_codes)

    # Ensure base app languages are present.
    mapping["en"] = "en"
    mapping.setdefault("zh-Hans", "zh-Hans")

    unique_targets = sorted(set(mapping.values()))

    print(f"Languages over threshold: {len(all_codes)}")
    print(f"Generated app localizations: {len(mapping)}")
    print(f"Unique translation targets: {len(unique_targets)}")

    target_translations: Dict[str, List[str]] = {}
    if CACHE_PATH.exists():
        try:
            cached = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
            if isinstance(cached, dict):
                for key, values in cached.items():
                    if (
                        isinstance(key, str)
                        and isinstance(values, list)
                        and len(values) == len(source_values)
                    ):
                        target_translations[key] = [str(v) for v in values]
        except Exception:  # noqa: BLE001
            pass

    for target_app_code in unique_targets:
        if target_app_code in target_translations:
            print(f"[translate] {target_app_code} (cached)")
            continue

        if target_app_code == "en":
            target_translations[target_app_code] = source_values
            print("[translate] en (source passthrough)")
            CACHE_PATH.write_text(
                json.dumps(target_translations, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            continue

        google_code = app_code_to_google_code(target_app_code, google_supported)
        print(f"[translate] {target_app_code} via {google_code}")
        target_translations[target_app_code] = translate_values(source_values, google_code)
        CACHE_PATH.write_text(
            json.dumps(target_translations, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    if args.dry_run:
        return

    remove_generated_localizations(RESOURCES_DIR)

    for app_code, source_app_code in sorted(mapping.items()):
        translated_values = [
            normalize_translated_text(value) for value in target_translations[source_app_code]
        ]
        entries = list(zip(keys, translated_values, strict=True))
        strings_path = RESOURCES_DIR / f"{app_code}.lproj" / "Localizable.strings"
        write_strings_file(strings_path, entries)

    # Keep explicit zh-Hans/zh-Hant entries available.
    if "zh-Hans" not in mapping:
        zh_hans_entries = list(zip(keys, target_translations["zh-Hans"], strict=True))
        write_strings_file(RESOURCES_DIR / "zh-Hans.lproj" / "Localizable.strings", zh_hans_entries)

    if "zh-Hant" not in mapping:
        zh_hant_entries = list(zip(keys, target_translations["zh-Hant"], strict=True))
        write_strings_file(RESOURCES_DIR / "zh-Hant.lproj" / "Localizable.strings", zh_hant_entries)

    # Apply curated manual overrides (if present).
    if MANUAL_OVERRIDES_DIR.exists():
        for override in sorted(MANUAL_OVERRIDES_DIR.glob("*.strings")):
            code = override.stem
            target_path = RESOURCES_DIR / f"{code}.lproj" / "Localizable.strings"
            target_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(override, target_path)

    print("Generation complete.")


if __name__ == "__main__":
    main()
