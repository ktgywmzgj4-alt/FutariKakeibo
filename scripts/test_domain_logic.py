#!/usr/bin/env python3
"""Linuxで実行できる、Swiftの純粋ロジックと同じ受入条件のスモークテスト。"""

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Expense:
    amount: int
    payer: str
    split: str = "equally"


def settlement(expenses: list[Expense], first: str, second: str):
    shared = [item for item in expenses if item.split == "equally"]
    balance = sum(
        item.amount // 2 if item.payer == first else -(item.amount // 2)
        for item in shared
        if item.payer in (first, second)
    )
    if balance > 0:
        return second, first, balance
    if balance < 0:
        return first, second, abs(balance)
    return None, None, 0


def receipt_total(lines: list[str]):
    def amounts(line: str):
        normalized = line.replace(",", "").replace("，", "").replace("¥", "").replace("￥", "")
        return [int(value) for value in re.findall(r"(?<!\d)(\d{1,7})(?!\d)", normalized)]

    keywords = ("合計", "総計", "お会計", "お支払", "grand total", "total")
    preferred = [line for line in lines if any(word in line.lower() for word in keywords)]
    if preferred:
        for line in reversed(preferred):
            values = amounts(line)
            if values:
                return max(values)
    values = [value for line in lines for value in amounts(line) if 1 <= value <= 9_999_999]
    return max(values) if values else None


def merged_expense_ids(
    local_ids: set[str],
    remote_ids: set[str],
    local_deleted_ids: set[str],
    remote_deleted_ids: set[str],
):
    deleted_ids = local_deleted_ids | remote_deleted_ids
    return (local_ids | remote_ids) - deleted_ids


def run():
    assert settlement(
        [
            Expense(8_000, "A"),
            Expense(2_000, "B"),
            Expense(20_000, "B", "personal"),
        ],
        "A",
        "B",
    ) == ("B", "A", 3_000)
    assert settlement([Expense(5_000, "A"), Expense(5_000, "B")], "A", "B") == (None, None, 0)
    assert settlement([Expense(1_001, "A")], "A", "B") == ("B", "A", 500)
    assert receipt_total(["TEL 0521234567", "小計 4500", "合計 ￥4,950"]) == 4_950
    assert receipt_total(["商品 120", "商品 880"]) == 880
    # 片方が古い支出を保持していても、CloudKit側の削除印が復活を防ぐ。
    assert merged_expense_ids({"stale", "local"}, {"remote"}, set(), {"stale"}) == {
        "local",
        "remote",
    }
    print("domain logic smoke tests: 6 passed")


if __name__ == "__main__":
    run()
