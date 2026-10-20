"""Compare the draft output with development labels only.

The evaluation gold file is intentionally never opened here.
"""

from __future__ import annotations

import csv
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: Path) -> dict[str, dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return {row["voc_id"]: row for row in csv.DictReader(handle)}


def main() -> None:
    actual = read(ROOT / "output" / "classified_voc.csv")
    gold = read(ROOT / "data" / "development_gold.csv")
    if set(actual) != set(gold):
        raise SystemExit("개발 정답과 분류 결과의 VOC ID가 다릅니다")
    checks = {
        "category": ("rule_category", "gold_category"),
        "product_area": ("product_area", "gold_product_area"),
        "priority": ("rule_priority", "gold_priority"),
        "owner": ("rule_owner", "gold_owner"),
        "needs_review": ("needs_review", "gold_needs_review"),
    }
    matches: Counter[str] = Counter()
    for voc_id, expected in gold.items():
        differences = []
        for name, (actual_field, gold_field) in checks.items():
            got, want = actual[voc_id][actual_field], expected[gold_field]
            if got == want:
                matches[name] += 1
            else:
                differences.append(f"{name} {got}->{want}")
        if differences:
            print(f"{voc_id}: {', '.join(differences)}")
    print(f"개발 세트 {len(gold)}건 일치 수: " + ", ".join(f"{name}={matches[name]}" for name in checks))
    print("결정적 규칙 초안의 개발용 비교이며 AI 성능 또는 최종 평가 결과가 아닙니다.")


if __name__ == "__main__":
    main()
