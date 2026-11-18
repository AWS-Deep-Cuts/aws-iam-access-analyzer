#!/usr/bin/env python3
"""N クイーン問題を IAM ポリシーに変換して、標準出力に書き出す。

使い方:
  python3 puzzle/make-queens.py 4                    # 4 クイーンのポリシー
  python3 puzzle/make-queens.py 4 --fix 1=2          # 1 行目のクイーンを 2 列目に固定
  python3 puzzle/make-queens.py 4 --fix 1=2 --fix 2=4  # --fix は繰り返して指定できる

出力の形（行番号を README の説明に使うため、変えない）:
  1 行目: 見出し  2 行目: Allow の Board  3 行目以降: 1 行に 1 つの Deny  最終行: ]}
"""
import argparse
import itertools
import json
import sys


def key(row):
    return f"aws:PrincipalTag/r{row}"


def queens(n, fix):
    board = {key(r): ([str(fix[r])] if r in fix else [str(c) for c in range(1, n + 1)])
             for r in range(1, n + 1)}
    statements = [{"Sid": "Board", "Effect": "Allow", "Action": "s3:GetObject", "Resource": "*",
                   "Condition": {"StringEquals": board}}]
    for i, j in itertools.combinations(range(1, n + 1), 2):
        d = j - i
        for a in range(1, n + 1):
            bad = [str(b) for b in range(1, n + 1) if b == a or abs(a - b) == d]
            statements.append({"Sid": f"Row{i}Col{a}VsRow{j}", "Effect": "Deny",
                               "Action": "s3:GetObject", "Resource": "*",
                               "Condition": {"StringEquals": {key(i): str(a), key(j): bad}}})
    lines = ['{"Version":"2012-10-17","Statement":[']
    lines += [json.dumps(s, separators=(",", ":")) + ("," if k < len(statements) - 1 else "")
              for k, s in enumerate(statements)]
    lines += ["]}"]
    return "\n".join(lines) + "\n"


def parse_fix(values, n):
    fix = {}
    for v in values:
        try:
            row, col = (int(x) for x in v.split("=", 1))
        except ValueError:
            sys.exit(f"エラー: --fix は 行=列 の形で指定してください（例: --fix 1=2）。指定された値: {v}")
        if not (1 <= row <= n and 1 <= col <= n):
            sys.exit(f"エラー: 行と列は 1〜{n} で指定してください。指定された値: {v}")
        if row in fix:
            sys.exit(f"エラー: {row} 行目を 2 回指定しています。")
        fix[row] = col
    return fix


def main():
    parser = argparse.ArgumentParser(description="N クイーン問題を IAM ポリシーに変換する")
    parser.add_argument("n", type=int, help="盤の大きさ。3 か 4")
    parser.add_argument("--fix", action="append", default=[], metavar="行=列",
                        help="その行のクイーンを、その列に固定する。繰り返して指定できる")
    args = parser.parse_args()
    # 5 クイーンは、ポリシーが約 8.9 KB になり、チェックが受け付けるかを確かめていないため、3 か 4 だけを受け付ける
    if not 3 <= args.n <= 4:
        sys.exit("エラー: 盤の大きさは 3 か 4 で指定してください。")
    sys.stdout.write(queens(args.n, parse_fix(args.fix, args.n)))


if __name__ == "__main__":
    main()
