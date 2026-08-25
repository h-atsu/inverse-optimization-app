# ロードマップ

## 1. 運用ルール

各Stepの開始前に、以下をこの文書へ追記してから実装する。

- ユーザー担当
- Codex担当
- 変更対象ファイルまたはmodule
- 受入確認方法
- 意思決定が必要な項目

完了時にテスト結果、既知の問題、設計文書の更新先を記録する。複数Stepを無断でまとめて実装しない。

## 2. 進捗

| Step | 内容 | 状態 | 担当 | 完了条件 |
|---|---|---|---|---|
| 0 | 設計文書 | Done | Codex作成、共同レビュー | Step 1を判断なしで開始できる |
| 1 | 開発基盤 | In progress | Codex: scaffold、ユーザー: local実行確認 | mise setup、local service、sync、lint、型、test成功 |
| 2 | 最適化コア | Not started | 未定 | 再現可能な候補とbenchmark出力 |
| 3 | DBとFastAPI | Not started | 未定 | APIだけでask–tellを一巡 |
| 4 | 非同期Job | Not started | 未定 | Celeryで非同期候補生成 |
| 5 | Streamlit UI | Not started | 未定 | ブラウザでask–tellを一巡 |
| 6 | GCP配備 | Not started（基盤のみ先行） | 未定 | 許可Googleアカウントで利用可能 |
| 7 | 品質確認 | Not started | 未定 | 完全benchmarkと文書更新 |

## 3. Step 0 — 設計文書

成果物:

- README
- プロダクト仕様
- アーキテクチャ
- アルゴリズム設計
- API・データモデル
- 開発・デプロイ方針
- ロードマップ

レビュー観点:

- ask–tellの操作が想定用途に合うか
- CSVの列とエラー規則が使いやすいか
- 基底クラスの責務が将来の自作実装に十分か
- CeleryとCloud Tasksを分離する判断が妥当か
- Google認証と所有者分離が初期用途に過剰・不足でないか
- managed PostgreSQL Free planの制限と停止条件を許容できるか

Step 0完了後に状態を`Done`へ変更する。レビュー前にStep 1を開始しない。

## 4. Step 1 — 開発基盤

確定した方針と分担:

- Codex担当: 独立project scaffold、品質設定、PostgreSQL/Redis Compose、React/Vite初期化
- ユーザー担当: `mise install`、dependency sync、local起動、検証command実行
- 決定済み: SQLAlchemy、PostgreSQL/Redis Compose、React/Vite（Next.jsなし）、FastAPI側の認証・認可。型チェックはStep 1既定としてtyを採用

受入条件:

- 新規checkout相当の環境で`mise install`と`uv sync`が成功する
- `pnpm install`とReact production buildが成功する
- Docker ComposeでPostgreSQLとRedisの起動・停止ができる
- PostgreSQLとRedisのhealth checkが成功する
- FastAPI、Streamlit、workerの最小プロセスを起動できる
- lint、型チェック、pytestが成功する

## 5. Step 2 — 最適化コア

大きく一括実装せず、次の順でレビューする。

1. ドメイン型と基底クラス
2. Sobol initializer
3. BoTorch Exact GP adapter
4. LogEI candidate generation
5. BenchmarkFunctionとrunner

ユーザーがアルゴリズム実装へ参加する場合、1または5を独立担当にしやすい。具体的な担当はStep 2開始時に決める。

## 6. Step 3 — DBとFastAPI

1. schemaとmigration
2. repositoryとtransaction
3. Study API
4. CSV import
5. 同期的なSuggestion生成でask–tellを検証

非同期化前にユースケースを同期実行で確認し、Step 4のqueue問題とAPI問題を分離する。

## 7. Step 4 — 非同期Job

1. Job状態機械とdispatcher port
2. Celery/Redis adapter
3. 共通worker handlerと冪等性
4. 子プロセスtimeout
5. Cloud Tasks adapter contract

## 8. Step 5 — Streamlit UI

1. API clientとdevelopment auth
2. Study一覧・作成
3. CSV importとObservation表示
4. Job pollingとSuggestion操作
5. Google OIDCと許可リスト

## 9. Step 6 — GCP

先行済み: GCP project、`infra/`の単一Terraform root module、必要APIの有効化resource。Cloud Run等のapplication resourceは未実装。

1. GCP bootstrapと費用確認
2. Terraform基盤
3. Artifact RegistryとCloud Run
4. managed PostgreSQL migration
5. Cloud Tasks/IAM
6. GitHub Actions
7. Google OIDCとend-to-end確認

## 10. Step 7 — 品質と次期計画

- Branin 30評価、Hartmann 6D 60評価を各10 seedで実行
- Sobol baselineとのmedian final simple regret比較
- 制限、運用手順、費用、既知の問題を記録
- Google Sheets、React/Cloudflare、混合変数、多目的、近似GP、長時間Jobの順序を再決定

## 11. 保留事項

| 項目 | 決定時期 | 現在の既定案 |
|---|---|---|
| 型チェックツール | 決定済み | ty |
| acquisition optimizer設定 | Step 2 | benchmark後に固定 |
| cloud PostgreSQL provider | Step 6 | Neon Freeを第一候補、Supabase Freeを代替候補 |
| DB mapping | 決定済み | SQLAlchemy 2.x ORM + Pydantic、同期Session |
| GCP project/domain | Step 6 | `asia-northeast1`、domain未定 |
| Google Sheets同期方式 | v2計画 | DBを正本とするimport/export adapter |

## 12. 変更履歴

- 2026-08-25: Step 0文書を初版作成。実装は未開始。
- 2026-08-25: cloud DBをCloud SQLからFree枠のmanaged PostgreSQLへ変更。Neonを第一候補、Supabaseを代替候補とした。
- 2026-08-25: DB mappingにSQLAlchemy 2.x ORM、Pydantic API schema、同期Sessionを採用した。
- 2026-08-25: devcontainerと常用Composeを外し、miseでapp・PostgreSQL・Redisをnative実行するlocal開発方針を採用した。Dockerはdeployment imageとCIで使用する。
- 2026-08-25: backend、Streamlit prototype、React/Vite webを独立projectとしてroot直下へ配置し、uv workspaceを使用しない方針を採用した。
- 2026-08-25: 正式React版でもユーザーtoken検証、許可リスト、所有者認可をFastAPIへ集約し、Next.js BFFを設けない方針を採用した。
- 2026-08-25: Step 1を開始し、各applicationのscaffoldを作成した。FastAPI/workerの最小プロセスとapplication health endpointは未実装。
- 2026-08-26: PostgreSQLとRedisのnative mise管理を廃止し、両serviceだけをDocker Composeで管理する方針へ変更した。local task namespaceは`deps:*`とした。
- 2026-08-26: miseは現在必要なtool versionだけを管理し、taskは反復するcommandが明確になってから追加する方針へ簡素化した。
- 2026-08-26: GCP project `inverse-optimization-app`を作成し、環境分割なしのTerraform root moduleを`infra/`直下に置く方針を採用した。
- 2026-08-26: Streamlit projectを役割が分かる`web-streamlit/`へ移動し、pre-commitを独立project構成へ対応させた。
