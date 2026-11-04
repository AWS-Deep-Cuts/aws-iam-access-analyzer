#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

# AWS Deep Cuts - IAM Access Analyzer ハンズオンの事前準備
# このスクリプトは、AWS のリソースを 1 つも作成しません。CloudShell のホームディレクトリに、次のファイルを作成するだけです。
#   handson.env            REGION・ACCOUNT_ID・START_TIME の 3 つの変数。手順 2 以降で source して使う
#   .analyzers-before.txt  実行の時点で東京リージョンにあったアナライザーの名前の一覧。cleanup.sh が比べる
#   .venv/                 公式の検証ツール cfn-policy-validator 0.0.37 を入れた Python の仮想環境。手順 6 で使う
# 呼び出す AWS の API は、STS の GetCallerIdentity と、Access Analyzer の ListAnalyzers だけです。
# どちらも、カスタムポリシーチェックの料金の対象ではありません。

readonly REGION="ap-northeast-1"
readonly VALIDATOR_VERSION="0.0.37"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly ENV_FILE="${SCRIPT_DIR}/handson.env"
readonly BEFORE_FILE="${SCRIPT_DIR}/.analyzers-before.txt"
readonly VENV_DIR="${SCRIPT_DIR}/.venv"
# 手順 8 で CloudTrail のイベントを照会する開始の時刻。UTC の ISO 8601
START_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly START_TIME

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS Deep Cuts - IAM Access Analyzer 事前準備"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── [1/4] 前提の確認 ─────────────────────────────────────────
echo "[1/4] 前提を確認..."
if [[ -f "${ENV_FILE}" ]]; then
  echo "❌ Error: ${ENV_FILE} が既に存在します。前回の環境が残っています。" >&2
  echo "   先に bash ./cleanup.sh を実行してください。" >&2
  exit 1
fi
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) || {
  echo "❌ Error: AWS の認証情報を取得できません。CloudShell で実行しているか確認してください。" >&2
  exit 1
}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CURRENT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [[ "${CURRENT_REGION}" != "${REGION}" ]]; then
  echo "⚠️  CloudShell のリージョンが ${REGION} ではありません。現在のリージョン: ${CURRENT_REGION:-未設定}"
  echo "   ハンズオンのコマンドは --region ${REGION} を付けて実行するため、このまま進められます。"
  echo "   手順 8 の CloudTrail のコンソールは、東京リージョンで開いてください。"
fi
if ! aws accessanalyzer check-no-public-access --generate-cli-skeleton input >/dev/null 2>&1; then
  echo "❌ Error: この AWS CLI は check-no-public-access コマンドに対応していません。現在の版: $(aws --version 2>&1 | cut -d' ' -f1)" >&2
  echo "   AWS CLI 2.16.6 以降が必要です。README の「前提条件」の手順で更新してから、もう一度実行してください。" >&2
  exit 1
fi
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
  echo "❌ Error: Python 3.8 以降が必要です。現在の版: $(python3 --version 2>&1 || echo 'python3 が見つかりません')" >&2
  exit 1
fi
echo "  あなた: ${CALLER_ARN}"
echo "  アカウント: ${ACCOUNT_ID} / リージョン: ${REGION}"
echo "  AWS CLI: $(aws --version 2>&1 | cut -d' ' -f1) / $(python3 --version 2>&1)"
echo ""

# ─── [2/4] 既にあるアナライザーの記録 ─────────────────────────
echo "[2/4] 既にあるアナライザーを記録..."
# アナライザーが 1 つも無いアカウントでは、空のファイルになる。これは正常
# 一覧の取得に失敗したときは、空のファイルと区別できるように、1 行目に LIST_FAILED と書く
if NAMES=$(aws accessanalyzer list-analyzers --region "${REGION}" \
      --query 'analyzers[].name' --output text 2>/dev/null); then
  printf '%s\n' "${NAMES}" | tr '\t' '\n' | sed -e '/^[[:space:]]*$/d' -e '/^None$/d' > "${BEFORE_FILE}"
  COUNT=$(wc -l < "${BEFORE_FILE}" | tr -d ' ')
  echo "  東京リージョンのアナライザー: ${COUNT} 個。名前を .analyzers-before.txt に保存しました。"
else
  echo "LIST_FAILED" > "${BEFORE_FILE}"
  echo "  ⚠️  アナライザーの一覧を取得できませんでした。access-analyzer:ListAnalyzers の権限を確認してください。"
  echo "     ハンズオンはこのまま進められます。後片付けでは、アナライザーが増えていないかを比べられません。"
fi
echo ""

# ─── [3/4] 公式の検証ツールのインストール ────────────────────
echo "[3/4] 公式の検証ツール cfn-policy-validator ${VALIDATOR_VERSION} をインストール..."
readonly USER_VALIDATOR="${HOME}/.local/bin/cfn-policy-validator"
if python3 -m venv "${VENV_DIR}" >/dev/null 2>&1; then
  # --no-cache-dir: ダウンロードしたパッケージを ~/.cache/pip に残さない。CloudShell のホームディレクトリは残り続けるため
  "${VENV_DIR}/bin/pip" install --quiet --disable-pip-version-check --no-cache-dir "cfn-policy-validator==${VALIDATOR_VERSION}"
  if ! "${VENV_DIR}/bin/cfn-policy-validator" --help >/dev/null 2>&1; then
    echo "❌ Error: cfn-policy-validator を起動できませんでした。" >&2
    exit 1
  fi
  echo "  インストールしました: ${VENV_DIR}"
elif [[ -x "${USER_VALIDATOR}" ]]; then
  # 仮想環境を作成できない環境で、README の代わりの方法で pip3 install --user --no-cache-dir を実行済みの場合
  rm -rf -- "${VENV_DIR:?}"
  echo "  ⚠️  Python の仮想環境を作成できませんでした。代わりに ${USER_VALIDATOR} を使います。"
  echo "     手順 6 では、source .venv/bin/activate の代わりに、export PATH=\"\$HOME/.local/bin:\$PATH\" を実行してください。"
else
  rm -rf -- "${VENV_DIR:?}"
  echo "❌ Error: Python の仮想環境を作成できませんでした。" >&2
  echo "   次のコマンドで、公式の検証ツールをホームディレクトリにインストールしてから、もう一度 bash ./setup.sh を実行してください。" >&2
  echo "     pip3 install --user --no-cache-dir \"cfn-policy-validator==${VALIDATOR_VERSION}\"" >&2
  echo "   詳しくは、README の手順 1 の「仮想環境を作成できない場合」を確認してください。" >&2
  exit 1
fi
echo "  CloudFormation のテンプレートはデプロイしません。検証ツールは、手順 6 でテンプレートを読むだけです。"
echo ""

# ─── [4/4] handson.env の保存 ─────────────────────────────────
echo "[4/4] handson.env を保存..."
# export を付けるのは、source ./handson.env の後に実行する bash puzzle/solve.sh のような
# 別のプロセスにも REGION を渡すため
cat > "${ENV_FILE}" <<EOF
export REGION="${REGION}"
export ACCOUNT_ID="${ACCOUNT_ID}"
export START_TIME="${START_TIME}"
EOF
echo "  保存しました: ${ENV_FILE}"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ セットアップが完了しました！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "AWS のリソースは作成していません。"
echo ""
echo "次のステップ:"
echo "  source ./handson.env"
echo ""
echo "続けて、README の手順 1 の「この手順で確かめること」で、既にあるアナライザーを一覧にしてください。"
