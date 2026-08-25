# Inverse Optimization App

高コストな実験やシミュレーションを対象に、ベイズ最適化で次の実験条件を提案するWebアプリです。

初期バージョンでは、ユーザーが実験設定と観測値を登録し、アプリが次の候補を1点提案する逐次的な ask–tell ワークフローを提供します。まずFastAPIとStreamlitでコア機能を検証し、将来はReactフロントエンドやGoogle Sheets連携へ拡張します。

## 現在の状態

- 現在のフェーズ: **Step 1 — 開発基盤**
- 実装状況: backendのPython package、StreamlitとReact/Viteのscaffold、PostgreSQL/Redis Compose、GCP APIを管理するTerraform root moduleを初期化済み
- 次の作業: FastAPIとworkerの最小プロセス、health endpoint、テストを追加し、Step 1の受入条件を満たす

## v1の対象

- 連続変数、単目的、上下限制約
- 最小化と最大化
- 1回につき1候補を提案するask–tell方式
- CSVによる観測値の一括登録
- Exact Gaussian ProcessとExpected Improvement系の獲得関数
- CPUで30分以内のジョブ
- Googleアカウント認証とメール許可リスト
- ローカル開発とGCPデプロイ

## v1の対象外

- 整数・カテゴリ変数、制約付き・多目的・バッチ最適化
- ユーザーコードの実行
- GPUおよび30分を超えるジョブ
- Google Sheetsとの直接同期
- Reactによる画面機能の実装およびCloudflareへの配備（scaffoldだけ先行）
- 学習済みモデル成果物の保存

## ドキュメント

- [プロダクト仕様](docs/product-specification.md)
- [アーキテクチャ](docs/architecture.md)
- [アルゴリズム設計](docs/algorithm-design.md)
- [API・データモデル](docs/api-and-data-model.md)
- [開発・デプロイ方針](docs/development.md)
- [ロードマップ](docs/roadmap.md)

## ディレクトリ

```text
backend/       FastAPI、worker、最適化コア、DB
web-streamlit/ v1の一時的なprototype frontend
web/           将来の正式frontend（React + Vite、scaffoldのみ）
infra/         GCP Terraform設定
docs/          設計文書
```

3つのapplicationは依存関係を共有せず、HTTP APIだけを境界にする。Pythonのuv workspaceは使用しない。認証・許可リスト・データ所有者の認可はFastAPIへ集約するため、正式frontendもNext.jsではなくReact/Viteのstatic SPAから始める。

VS CodeまたはCursorでは`.code-workspace`を開く。multi-root workspaceにより、backendとStreamlitはそれぞれの`.venv`を使用し、webはproject内のTypeScriptを使用する。これはeditor上の分離だけで、package workspaceは構成しない。

## ローカルセットアップ

前提はmiseとDocker Composeとする。applicationはホストで実行し、PostgreSQLとRedisだけをComposeで起動する。devcontainerは使用しない。

```bash
cp .env.example .env
mise trust
mise install
(cd backend && uv sync)
(cd web-streamlit && uv sync)
(cd web && pnpm install)
docker compose up --detach --wait
```

各projectは次のlock fileを個別に管理する。

- `backend/uv.lock`
- `web-streamlit/uv.lock`
- `web/pnpm-lock.yaml`

現時点で起動可能なfrontendは、別terminalから直接起動する。

```bash
(cd web-streamlit && uv run streamlit run app.py)
(cd web && pnpm dev)
```

確認先:

- Streamlit: `http://127.0.0.1:8501`
- React: `http://127.0.0.1:5173`

依存サービスの確認と停止:

```bash
docker compose ps
docker compose down
```

`docker compose up --detach --wait`はPostgreSQLとRedisがhealth checkを通過するまで待機する。依存サービスのlogは`docker compose logs --follow postgres redis`で確認できる。PostgreSQLのデータはDocker named volumeに保持される。`docker compose down --volumes`はDBデータも削除するため、通常の停止には使用しない。繰り返しが増えたcommandだけを、必要になった時点でmise taskへ追加する。

## Deployment image（未実装）

Dockerfileは後続Stepで追加する。追加後はrepository rootをbuild contextとし、次の構成でimageを分離する。

```bash
docker build -f backend/Dockerfile --target api -t inverseopt-api:local .
docker build -f backend/Dockerfile --target worker -t inverseopt-worker:local .
docker build -f web-streamlit/Dockerfile -t inverseopt-streamlit:local .
docker build -f web/Dockerfile -t inverseopt-web:local .
```

Docker imageはdeploymentとLinux互換性の確認用であり、通常のlocal developmentには使用しない。

## GCP infrastructure

単一GCP project `inverse-optimization-app`向けのTerraform設定を`infra/`へ配置する。Terraform CLIはグローバルにインストール済みであることを前提とし、miseでは管理しない。初期化と確認手順は[infra/README.md](infra/README.md)を参照する。

## 進め方

各ステップの開始前に作業候補を分割し、ユーザーとCodexの担当を相談して決めます。実装、テスト、文書更新を1つの単位としてレビューし、合意後に次のステップへ進みます。
