#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

# AWS Deep Cuts - IAM Access Analyzer ハンズオンの手順 7 の任意の手順
# N クイーン問題の置き方を、指定したアクセスのチェック CheckAccessNotGranted で 1 行ずつ決めます。
#   1. 問題全体を 1 回チェックする。PASS なら置き方は無いため、ここで終わる
#   2. 1 行目から順に、決めた行の --fix と、試す列の --fix を並べて make-queens.py で try.json を作り、チェックする
#      列 1〜N-1 を順に試し、FAIL になった列に決める。どの列も PASS なら、呼び出さずに N 列目に決める
#   3. 決めた置き方を、IAM のポリシーシミュレーター SimulateCustomPolicy で評価して、判定を表示する
# チェックの呼び出しは最大 N×(N-1)+1 回です。東京リージョンで 1 回 $0.002 かかります。
# AWS のリソースは作成しません。作業ファイルは puzzle/try.json だけで、cleanup.sh が削除します。
#
# 使い方: hands-on ディレクトリで source ./handson.env を実行してから、bash puzzle/solve.sh 4

REGION="${REGION:?REGION が空です。先に hands-on ディレクトリで source ./handson.env を実行してください。}"
readonly REGION
readonly N="${1:-4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly MAKE="${SCRIPT_DIR}/make-queens.py"
readonly TRY="${SCRIPT_DIR}/try.json"

# 5 クイーンは、ポリシーが約 8.9 KB になり、チェックが受け付けるかを確かめていないため、3 か 4 だけを受け付ける
if [[ ! "${N}" =~ ^[34]$ ]]; then
  echo "❌ Error: 盤の大きさは 3 か 4 で指定してください。指定された値: ${N}" >&2
  exit 1
fi

readonly MAX_CALLS=$(( N * (N - 1) + 1 ))
cost() { awk -v n="$1" 'BEGIN { printf "%.3f", n * 0.002 }'; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS Deep Cuts - ${N} クイーン問題を Access Analyzer で解く"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  指定したアクセスのチェックを、リージョン ${REGION} で最大 ${MAX_CALLS} 回呼び出します。料金は最大 \$$(cost "${MAX_CALLS}") です。"
echo "  最後に、IAM のポリシーシミュレーターを 1 回呼び出します。"
read -r -p "  Enter で始めます。中止するときは Ctrl+C を押します: " _

# 問題全体のポリシーのファイルの場所を標準出力に書く。
# リポジトリの queens-N.json があればそれを使い、無ければ try.json に作る
full_policy() {
  if [[ -f "${SCRIPT_DIR}/queens-${N}.json" ]]; then
    echo "${SCRIPT_DIR}/queens-${N}.json"
  else
    python3 "${MAKE}" "${N}" > "${TRY}"
    echo "${TRY}"
  fi
}

# 引数のポリシーのファイルで、指定したアクセスのチェックを呼び出し、PASS か FAIL を変数 RESULT に入れる
CALLS=0
RESULT=""
check() {
  CALLS=$(( CALLS + 1 ))
  RESULT=$(aws accessanalyzer check-access-not-granted \
    --policy-document "file://$1" \
    --access '[{"actions":["s3:GetObject"]}]' \
    --policy-type IDENTITY_POLICY \
    --region "${REGION}" --query result --output text)
}

echo ""
check "$(full_policy)"
echo "  ${CALLS} 回目: 問題全体 → ${RESULT}"
if [[ "${RESULT}" == "PASS" ]]; then
  echo ""
  echo "✅ PASS: Access Analyzer は、${N} クイーン問題の置き方は無いと答えました。"
  echo "   チェックの呼び出し: ${CALLS} 回、\$$(cost "${CALLS}")"
  exit 0
fi

# 決めた行の --fix の引数と、決めた列の一覧
declare -a FIX_ARGS=()
declare -a PLACEMENT=()
for (( row = 1; row <= N; row++ )); do
  decided=""
  for (( col = 1; col <= N - 1; col++ )); do
    python3 "${MAKE}" "${N}" ${FIX_ARGS[@]+"${FIX_ARGS[@]}"} --fix "${row}=${col}" > "${TRY}"
    check "${TRY}"
    echo "  ${CALLS} 回目: ${row} 行目=${col} 列 → ${RESULT}"
    if [[ "${RESULT}" == "FAIL" ]]; then
      decided="${col}"
      break
    fi
  done
  if [[ -z "${decided}" ]]; then
    decided="${N}"
    echo "  ${row} 行目は 1〜$(( N - 1 )) 列がすべて PASS だったため、呼び出さずに ${N} 列目に決めます。"
  fi
  FIX_ARGS+=(--fix "${row}=${decided}")
  PLACEMENT+=("${decided}")
done

PLACEMENT_TEXT=$(IFS=,; echo "${PLACEMENT[*]}")
echo ""
echo "  決めた置き方: ${PLACEMENT_TEXT}"
echo "  チェックの呼び出し: ${CALLS} 回、\$$(cost "${CALLS}")"
echo ""

# 決めた置き方を、問題全体のポリシーに対して、ポリシーシミュレーターで評価する
declare -a CONTEXT=()
for (( row = 1; row <= N; row++ )); do
  CONTEXT+=("ContextKeyName='aws:PrincipalTag/r${row}',ContextKeyValues='${PLACEMENT[row - 1]}',ContextKeyType=string")
done
DECISION=$(aws iam simulate-custom-policy \
  --policy-input-list "file://$(full_policy)" \
  --action-names s3:GetObject \
  --context-entries "${CONTEXT[@]}" \
  --query 'EvaluationResults[0].EvalDecision' --output text)
echo "  ポリシーシミュレーターの判定: ${DECISION}"
echo ""
if [[ "${DECISION}" == "allowed" ]]; then
  echo "✅ 置き方 ${PLACEMENT_TEXT} は、Allow のステートメント Board に一致し、どの Deny のステートメントにも一致しませんでした。"
else
  echo "⚠️  置き方 ${PLACEMENT_TEXT} の判定が allowed ではありません。README のトラブルシューティングを確認してください。" >&2
  exit 1
fi
