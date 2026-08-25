# 開発・デプロイ方針

この文書は、現時点で利用できる開発手順と、後続Stepで採用する方針を区別して記載する。未実装のAPI、worker、migration、deployment imageは将来形として扱う。

## 1. 開発ツール

- Python 3.12
- miseによるuv、Node.js、pnpmのversion管理
- backendとweb-streamlitそれぞれのuvによる依存関係・lock file管理
- Node.js 22、pnpm、React 19、Vite 8、TypeScript
- srcレイアウト
- pytest
- Ruff
- tyによるPython型チェック
- Alembic
- SQLAlchemy 2.x ORM（API schemaはPydanticと分離）
- psycopg 3（DB実装時に追加予定）
- Docker Composeで起動するPostgreSQL 17とRedis 8
- Docker Compose（ローカルのPostgreSQLとRedisに使用）
- Docker / BuildKit（後続Stepでdeployment imageとCIに使用）

v1のDBアクセスは同期`Session`を使用する。FastAPIの規模では十分であり、APIとworkerで同じrepository実装を使いやすく、`AsyncSession`固有のsession lifecycleやimplicit I/Oを初期段階へ持ち込まずに済む。必要性を計測してからasync化を判断する。

## 2. ディレクトリ境界

```text
backend/
  src/inverse_optimization/
    api/              FastAPI routesとschema（予定）
    application/      use caseとport（予定）
    domain/           エンティティと値オブジェクト（予定）
    optimization/     基底クラスとBoTorch adapter（予定）
    infrastructure/   DB、queue、認証adapter（予定）
    worker/           共通job handler（予定）
  migrations/         Alembic migration（予定）
  tests/              （予定）
  pyproject.toml
  uv.lock
web-streamlit/
  app.py              prototype frontend
  api_client.py        （予定）
  pyproject.toml
  uv.lock
web/
  src/                React/Vite正式frontendのscaffold
  package.json
  pnpm-lock.yaml
infra/                  単一GCP projectのTerraform root module
docs/
docker/postgres/init/
compose.yaml
mise.toml
```

3 applicationはworkspace化せず、それぞれがdependencyとlock fileを所有する。StreamlitとReactはbackendをimportせず、HTTP APIだけを利用する。実装時には過度に細かいpackage分割を避け、必要になった境界だけを作る。

## 3. ローカル開発

現時点で利用できる操作:

- `mise install`で必要なtoolを導入できる
- backend/web-streamlitでは`uv sync`、webでは`pnpm install`を各projectで直接実行できる
- `docker compose up --detach --wait`でPostgreSQLとRedisを起動できる
- `docker compose ps`で状態確認、`docker compose down`で停止できる
- StreamlitとReact/Viteのscaffoldを各projectの標準commandで個別に起動できる
- repository rootのpre-commit設定から、各Python projectのlock、Ruff、ty、webのoxlint、Terraform fmtを実行できる

FastAPI、worker、Alembic migration、統合テストは未実装であり、Step 1の残作業とする。

PostgreSQLはDocker named volumeへ永続化し、RedisはCeleryのbroker/backend用途なので永続化しない。初回volume作成時に開発用DBとintegration test用DBを作成する。両serviceのportはlocalhostだけへ公開する。

サービスの想定port:

- Streamlit: `8501`
- FastAPI: `8000`
- React/Vite: `5173`
- PostgreSQL: `5432`
- Redis: `6379`（localhostだけでlisten）

Flowerはデバッグに有用だが必須サービスにはせず、必要になった時点で追加する。mise taskも反復するcommandが明確になってから追加する。

## 4. 設定とsecret

- 設定は環境変数と型付きSettings classから読み込む
- `.env.example`には名前と説明だけを置き、実secretを含めない
- ローカルOIDCを使用しない場合は、明示的なdevelopment auth modeと固定開発メールを設定する
- productionでdevelopment auth modeが有効なら起動を失敗させる
- 正式React版のBearer token検証とresource認可はFastAPIで行い、webへclient secretや認可規則を持たせない
- managed PostgreSQLの接続文字列、OAuth client secret、cookie secretはSecret Managerを使用する

## 5. テスト階層

### unit

- DB、ネットワーク、BoTorchの重量処理を必要に応じて境界で置き換える
- ドメイン制約、状態遷移、配列変換、seedを高速に検証する

### integration

- PostgreSQLを使用してrepository、transaction、partial unique indexを検証する
- FastAPI TestClientでAPIとCSV処理を検証する
- dispatcher contractをローカル実装とGCP実装で共通テストする

### end-to-end

- local環境でStudy作成からtellまでを一巡する
- 外部のGoogleログインを除くフローは自動化する

### benchmark

- CI smokeと完全ベンチマークを分離する
- benchmark結果を通常のunit test snapshotとして固定しない

## 6. GCPデプロイ

`infra/`を単一root moduleとしてapplication resourceを管理する。Terraform CLIはグローバル導入を前提とし、miseでは管理しない。stateは当面localとし、GitHub Actions導入前にremote backendへ移す。Google OAuth consent/clientはbootstrap手順として扱う。

GitHub Actionsの想定順序:

1. lint、型チェック、unit/integration test
2. Workload Identity FederationでGCP認証
3. Docker imageをcommit SHAでbuildしArtifact Registryへpush
4. Terraform validate/plan/apply
5. managed PostgreSQLへ接続するmigration用Cloud Run JobでAlembic upgrade
6. frontend、API、workerを追跡可能な各image digestで更新
7. health checkと認証済み内部smoke test

`latest`だけに依存せず、デプロイしたimage digestを追跡可能にする。DB migrationは後方互換なexpand/contract方式を原則とし、サービス更新前に適用しても旧revisionが動作するようにする。

deployment imageはlocal環境から独立させ、miseを含めない。`backend/Dockerfile`はAPIとworkerのtargetを持ち、`web-streamlit/Dockerfile`と`web/Dockerfile`はfrontendごとに独立させる。これらのDockerfileは未実装である。BoTorch/PyTorchはworker targetだけに含める形へStep 2で分離する。CIではLinux上のPostgreSQL・Redis service containerを使ってintegration testを実行する。

## 7. Observability

- JSON構造化ログ
- request ID、owner、Study ID、Job ID、attemptを可能な範囲で付与
- secret、OIDC token、CSV全内容、目的値の大量出力は禁止
- Job duration、queue latency、成功・失敗・timeout数をmetricsとして保存
- GCPではCloud Loggingのエラーとstale Jobを監視対象にする

## 8. 実装開始前の確認事項

- Stepごとの担当者と変更対象
- package名`inverse_optimization`とapplication内の用語の整合性
- miseとDocker Composeが利用可能で、local PostgreSQL・Redisを起動できること
- deployment imageをbuildする環境またはCIでDocker / BuildKitが利用可能であること
- GCP Step開始時のproject ID、請求先、予算、ドメイン
- GitHub repositoryとWorkload Identity Federationの管理者
