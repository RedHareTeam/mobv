"""Validate the synthetic Day 2 VOC fixtures against policy v1.0."""

from __future__ import annotations

import csv
from collections import Counter
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
INPUT_COLUMNS = [
    "voc_id", "received_at", "channel", "platform", "app_version", "screen", "user_text"
]
GOLD_COLUMNS = [
    "voc_id", "gold_category", "gold_product_area", "gold_priority",
    "gold_owner", "gold_sla", "gold_review_flags", "gold_needs_review",
    "gold_reason",
]
CATEGORIES = {"BUG", "USABILITY", "REQUEST", "ACCOUNT", "POLICY", "INFORMATION", "ETC"}
AREAS = {
    "AUTH", "APPOINTMENT", "DATE_COORDINATION", "MAP_LOCATION",
    "RECOMMENDATION", "VOTING", "HISTORY", "COMMON",
}
OWNERS = {"DEVELOPMENT", "DESIGN_UX", "PRODUCT", "OPERATIONS", "POLICY_SECURITY", "NEEDS_TRIAGE"}
CHANNELS = {"beta_form", "in_app", "email", "store_review", "usability_test"}
PLATFORMS = {"android", "ios", "web", "unknown"}
SCREENS = {
    "login", "home", "appointment", "date_coordination", "map",
    "recommendation", "voting", "history", "common", "unknown",
}
FLAGS = {
    "HIGH_PRIORITY", "PRIVACY_SECURITY", "MULTI_ISSUE", "AMBIGUOUS",
    "INVALID_OUTPUT", "RULE_OVERRIDE", "LOW_CONFIDENCE", "PERSONAL_DATA",
    "PROMPT_INJECTION",
}
SLA = {"P0": "즉시 확인", "P1": "당일", "P2": "3영업일 이내", "P3": "5영업일 이내"}


def read_csv(path: Path, columns: list[str], count: int) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == columns, f"{path.name}: unexpected columns {reader.fieldnames}"
        rows = list(reader)
    assert len(rows) == count, f"{path.name}: expected {count} rows, got {len(rows)}"
    assert all(None not in row and all(value is not None for value in row.values()) for row in rows), path.name
    ids = [row["voc_id"] for row in rows]
    assert len(ids) == len(set(ids)), f"{path.name}: duplicate ID"
    return rows


def validate_split(name: str, count: int) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    inputs = read_csv(DATA / f"{name}_voc.csv", INPUT_COLUMNS, count)
    gold = read_csv(DATA / f"{name}_gold.csv", GOLD_COLUMNS, count)
    assert [row["voc_id"] for row in inputs] == [row["voc_id"] for row in gold], f"{name}: ID/order mismatch"

    for source, label in zip(inputs, gold):
        voc_id = source["voc_id"]
        assert voc_id and source["user_text"].strip(), voc_id
        date.fromisoformat(source["received_at"])
        assert source["channel"] in CHANNELS, voc_id
        assert source["platform"] in PLATFORMS, voc_id
        assert source["screen"] in SCREENS, voc_id
        assert source["app_version"].strip(), voc_id
        assert label["gold_category"] in CATEGORIES, voc_id
        assert label["gold_product_area"] in AREAS, voc_id
        assert label["gold_priority"] in SLA, voc_id
        assert label["gold_owner"] in OWNERS, voc_id
        assert label["gold_sla"] == SLA[label["gold_priority"]], voc_id
        assert label["gold_reason"].strip(), voc_id
        flag_list = label["gold_review_flags"].split("|") if label["gold_review_flags"] else []
        flags = set(flag_list)
        assert len(flags) == len(flag_list) and flags <= FLAGS, voc_id
        assert label["gold_needs_review"] in {"true", "false"}, voc_id
        if label["gold_priority"] in {"P0", "P1"}:
            assert "HIGH_PRIORITY" in flags, voc_id
        else:
            assert "HIGH_PRIORITY" not in flags, voc_id
        expected_review = bool(flags) or label["gold_owner"] == "NEEDS_TRIAGE" or label["gold_category"] == "ETC"
        assert (label["gold_needs_review"] == "true") == expected_review, voc_id

    return inputs, gold


def main() -> None:
    development, development_gold = validate_split("development", 30)
    evaluation, evaluation_gold = validate_split("evaluation", 20)
    assert not ({row["voc_id"] for row in development} & {row["voc_id"] for row in evaluation})
    all_gold = development_gold + evaluation_gold
    priorities = Counter(row["gold_priority"] for row in all_gold)
    flags = Counter(flag for row in all_gold for flag in row["gold_review_flags"].split("|") if flag)
    assert priorities["P0"] + priorities["P1"] >= 6
    assert flags["MULTI_ISSUE"] >= 3
    assert flags["AMBIGUOUS"] >= 2
    assert flags["PERSONAL_DATA"] >= 2
    assert flags["PROMPT_INJECTION"] >= 1

    for name, rows in (("development", development_gold), ("evaluation", evaluation_gold)):
        print(f"{name}: {len(rows)} rows")
        for column in ("gold_category", "gold_product_area", "gold_priority"):
            print(f"  {column}: {dict(sorted(Counter(row[column] for row in rows).items()))}")
        print(f"  review: {sum(row['gold_needs_review'] == 'true' for row in rows)}")
    print(f"exception flags: {dict(sorted(flags.items()))}")
    print("PASS: schema, parsing, IDs, allowed values, SLA, review logic, coverage")


if __name__ == "__main__":
    main()
