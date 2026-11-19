#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

# AWS Deep Cuts - IAM Access Analyzer ハンズオンの後片付け
# このハンズオンは AWS のリソースを作成しません。そのため、このスクリプトは AWS のリソースを削除しません。
#   [1/3] 東京リージョンのアナライザーの一覧を、setup.sh が保存した .analyzers-before.txt と比べ、増えた名前を表示する。
#         増えたアナライザーは自動では削除しない。誰が何のために作ったかを、スクリプトは判断できないため
#   [2/3] setup.sh とハンズオンが作成した作業ファイルを削除する。[1/3] で確認が必要な項目があったときは、
#         もう一度実行したときに比べられるように、.analyzers-before.txt を残す
#   [3/3] 結果を表示する
# 何度実行しても、AWS には何も変更を加えません。

readonly REGION="ap-northeast-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly ENV_FILE="${SCRIPT_DIR}/handson.env"
readonly BEFORE_FILE="${SCRIPT_DIR}/.analyzers-before.txt"
readonly VENV_DIR="${SCRIPT_DIR}/.venv"
readonly TRY_FILE="${SCRIPT_DIR}/puzzle/try.json"
readonly LIST_COMMAND="aws accessanalyzer list-analyzers --region ${REGION} --query 'analyzers[].[name, type, status, managedBy]' --output table"
WARN=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS Deep Cuts - IAM Access Analyzer 後片付け"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── [1/3] アナライザーの確認。削除はしない ─────────────────
echo "[1/3] アナライザーを確認..."
if NAMES=$(aws accessanalyzer list-analyzers --region "${REGION}" \
      --query 'analyzers[].name' --output text 2>/dev/null); then
  CURRENT=$(printf '%s\n' "${NAMES}" | tr '\t' '\n' | sed -e '/^[[:space:]]*$/d' -e '/^None$/d')
  if [[ ! -f "${BEFORE_FILE}" ]] || [[ "$(head -n 1 "${BEFORE_FILE}")" == "LIST_FAILED" ]]; then
    # 後片付けを済ませた後にもう一度実行した場合や、setup.sh が一覧を取得できなかった場合
    echo "  ℹ️  setup.sh の実行の時点のアナライザーの一覧が無いため、増えたかどうかを比べられません。"
    echo "     東京リージョンの今のアナライザーは、次のとおりです。何も表示されなければ、アナライザーはありません。"
    printf '%s\n' "${CURRENT}" | sed -e '/^$/d' -e 's/^/       /'
    echo "     種類と管理元は、次のコマンドで確認できます。手順 1 の一覧と比べてください。"
    echo "       ${LIST_COMMAND}"
  else
    # 今の一覧のうち、.analyzers-before.txt に無い名前。ファイルが空のときは、今の一覧がすべて残る
    ADDED=$(printf '%s\n' "${CURRENT}" | grep -F -x -v -f "${BEFORE_FILE}" || true)
    if [[ -z "${ADDED}" ]]; then
      echo "  アナライザーは、手順 1 のときと同じです。"
    else
      WARN=1
      echo "  ⚠️  手順 1 のときには無かったアナライザーがあります。このスクリプトは削除しません。"
      while IFS= read -r name; do
        [[ -z "${name}" ]] && continue
        echo ""
        echo "     名前: ${name}"
        case "${name}" in
          AnalyzerCreatedByCfnIAMPolicyValidator)
            echo "     公式の検証ツールの validate コマンドが作成したアナライザーです。手順どおりに進めた場合は作成されません。" ;;
          _AccessAnalyzerForSecurityHub*)
            echo "     AWS Security Hub が作成したアナライザーです。Security Hub が使うため、削除しないでください。"
            continue ;;
          *)
            echo "     誰が何のために作成したかを確かめてから、削除するかを決めてください。" ;;
        esac
        echo "     不要であることを確かめた場合は、次のコマンドで削除できます。削除は取り消せません。"
        echo "       aws accessanalyzer delete-analyzer --analyzer-name ${name} --region ${REGION}"
      done <<< "${ADDED}"
      echo ""
      echo "     種類と管理元は、次のコマンドで確認できます。"
      echo "       ${LIST_COMMAND}"
    fi
  fi
else
  echo "  ⚠️  アナライザーの一覧を取得できませんでした。"
  echo "     access-analyzer:ListAnalyzers の権限を確認してから、README の手順 9 の「この手順で確かめること」（書籍では手順 9-3）のコマンドを実行してください。"
  WARN=1
fi
echo ""

# ─── [2/3] 作業ファイルの削除 ─────────────────────────────────
echo "[2/3] 作業ファイルを削除..."
for f in "${VENV_DIR}" "${TRY_FILE}" "${ENV_FILE}" "${BEFORE_FILE}"; do
  # 確認が必要な項目があるときは、アナライザーの一覧の記録を残す。もう一度実行したときに、同じ一覧と比べるため
  if [[ "${f}" == "${BEFORE_FILE}" && "${WARN}" -ne 0 && -e "${f}" ]]; then
    echo "  残す: ${f#"${SCRIPT_DIR}"/}。アナライザーを確かめた後に、もう一度 bash ./cleanup.sh を実行すると、この一覧と比べます。"
    continue
  fi
  if [[ -e "${f}" ]]; then
    rm -rf -- "${f:?}"
    echo "  削除: ${f#"${SCRIPT_DIR}"/}"
  else
    echo "  対象なし: ${f#"${SCRIPT_DIR}"/}"
  fi
done
if [[ -x "${HOME}/.local/bin/cfn-policy-validator" ]]; then
  echo "  ℹ️  ホームディレクトリに、公式の検証ツールがインストールされています。不要であれば、次のコマンドで削除してください。"
  echo "       pip3 uninstall cfn-policy-validator"
fi
echo ""

# ─── [3/3] 結果 ───────────────────────────────────────────────
echo "[3/3] 確認..."
echo "  このハンズオンは AWS のリソースを作成していません。"
echo "  カスタムポリシーチェックの料金は呼び出しごとにかかり、後から増えることはありません。"
echo ""
if [[ "${WARN}" -ne 0 ]]; then
  echo "⚠️  確認が必要な項目があります。上の ⚠️ の行を読んでください。"
  echo "   README の手順 9 の「この手順で確かめること」（書籍では手順 9-3）で、アナライザーの一覧を手順 1 と比べてください。"
  exit 1
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 後片付けが完了しました！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "README の手順 9 の「この手順で確かめること」で、アナライザーの一覧を手順 1 と比べてください。"
