# アーキテクチャ

この文書はv1の目標アーキテクチャを示す。現時点で実装済みなのは各applicationのscaffold、ローカル依存サービスのCompose構成、GCP APIを管理するTerraform基盤までであり、API、worker、最適化コア、Cloud Run構成は後続Stepで実装する。

## 1. 設計原則

- 最適化コアをWeb、DB、ジョブ基盤から独立させる。
- DB上のJobを状態の正本とし、キュー製品固有のIDや結果形式を公開しない。
- ローカルとGCPで同じユースケースとworker handlerを使用し、JobDispatcherだけを差し替える。
- StreamlitとReactは独立applicationとし、FastAPI以外を直接参照しない。
- Streamlitはv1のprototype、React/Viteは将来の正式frontendとする。
- 学習済みモデルではなく、入力データ・設定・seedを保存して再計算可能にする。

## 2. 論理コンポーネント

```text
Browser
  |
  +--> Streamlit prototype --+
  |                          |
  +--> React web ------------+
                             v
FastAPI application
  |---------------------> PostgreSQL
  |
  v
JobDispatcher
  | local: Celery/Redis
  | cloud: Cloud Tasks
  v
Worker handler ----------> Optimization core
  |                             |
  +-----------------------------+
                |
                v
            PostgreSQL
```

### frontend

- `web-streamlit/`と`web/`は依存関係を共有しない独立application
- localでは`API_BASE_URL`を介してFastAPIへ接続
- v1はStreamlitでGoogle OIDCログインとメール許可リストを提供
- ReactはVite/TypeScriptのscaffoldだけを先行作成し、機能移行はv1完了後
- フォーム、CSV、グラフ、Job polling
- backend packageをimportせず、FastAPI以外へデータを永続化しない

### application API

- ユーザー認証tokenの検証、許可リスト、所有者認可
- 入力検証、トランザクション
- Study、Observation、Suggestion、Jobのユースケース
- JobDispatcherへの投入

### optimization core

- 配列とドメイン型だけを入力として扱う
- GP学習、posterior、獲得関数、候補探索
- ベンチマーク関数と評価runner

### worker

- Job IDを受け取り、DBから入力を取得する
- 実行権を冪等に確保する
- 隔離した子プロセスで最適化を実行する
- 結果または失敗をDBへ記録する

## 3. ask–tellデータフロー

1. frontendがFastAPIへSuggestion生成を要求する。
2. APIは未処理Suggestionと実行中Jobがないことを確認する。
3. APIは`queued` Jobを作成し、commit後にdispatcherへjob IDを渡す。
4. workerはJobを`running`へ遷移させ、StudyとObservationを読み込む。
5. 観測が初期設計数未満ならSobol、以降はGPと獲得関数で候補を生成する。
6. workerはSuggestionを`pending`で保存し、Jobを`succeeded`へ遷移させる。
7. frontendはJobをpollingし、完了後にSuggestionを表示する。
8. 結果CSVの登録時にObservationを追加し、Suggestionを`observed`にする。

Job作成後にキュー投入が失敗した場合は、APIがJobを`failed`へ更新する。将来Outboxパターンが必要になる規模までは、DB作成とdispatcher呼び出しを明示的に補償する。

## 4. ローカル構成

devcontainerは使用せず、applicationはホスト、PostgreSQLとRedisはDocker Composeで実行する。

- mise: uv、Node.js、pnpmのversionだけを管理
- uv: Python 3.12を必要に応じて導入
- uv: `backend/`と`web-streamlit/`の独立したPython仮想環境・依存関係・lock file
- pnpm: `web/`のReact/Vite依存関係とlock file
- native process: FastAPI/Uvicorn、Streamlit、React/Vite、Celery worker
- Docker Compose: PostgreSQL 17とRedis 8だけをcontainerで起動
- PostgreSQL: named volumeへ永続化し、開発DBとtest DBを分ける
- Redis: Celery broker/backendとして使用し、永続化しない

Composeのportは`127.0.0.1`だけへ公開する。現時点では標準commandを直接使用し、繰り返しが増えた操作だけをmise taskへ追加する。通常停止ではnamed volumeを保持し、volume削除は開発DBを明示的に初期化し直す場合だけ行う。

ローカル認証は`AUTH_MODE=development`で明示的な開発ユーザーを注入し、本番の認証無効化設定とは混同しない。

## 5. GCP構成

リージョンは`asia-northeast1`を既定とする。

- 公開Cloud Run: Streamlit
- IAM非公開Cloud Run: FastAPI（v1のStreamlit構成）
- IAM非公開Cloud Run: worker、concurrency 1
- Cloud Tasks: workerへのOIDC認証付きHTTP task
- 外部managed PostgreSQL: Neon Freeを第一候補、Supabase Freeを代替候補とする
- Secret Manager: DB、OIDC client、cookie secret
- Artifact Registry: SHAタグのコンテナイメージ
- Cloud Logging/Monitoring: 構造化ログとエラー監視

Cloud TasksのHTTP handler上限は30分であるため、workerは25分で子プロセスを停止し、後処理を完了して応答する。30分を超える処理はv1対象外とし、将来Cloud Run Jobs等へ分離する。

PostgreSQLへはproviderのTLS対応接続文字列とpooler endpointを使用する。接続文字列はSecret Managerへ保存し、frontendには渡さず、API、worker、migrationだけが参照する。Cloud Runのscale-outで接続数を使い切らないよう、各instanceのconnection poolを小さく設定する。frontend、API、worker、migrationには別々のサービスアカウントを使用する。

Free planの停止条件、容量、compute時間、connection数は変更され得るため、Step 6着手時に再確認する。NeonとSupabaseのどちらを選んでもapplicationからは標準PostgreSQLとして扱い、provider固有APIへの依存は認証やstorageが必要になるまで導入しない。

## 6. 認証・認可

- 認証・認可の最終的な責務はFastAPIへ集約する。
- FastAPIは`email_verified`、メール許可リスト、Study所有者を検証し、全データ操作を正規化済みの認証ユーザーメールで絞り込む。
- v1のStreamlitはGoogle OIDCでユーザーを認証し、自身のサービスアカウントでIAM非公開FastAPI向けID tokenを取得する。
- v1ではCloud Run IAMを信頼境界とし、Streamlitが確認済みユーザー情報を内部headerで伝える。FastAPIは外部から同headerを受け付けない。
- Cloud Tasksは専用サービスアカウントのOIDC tokenでworkerを呼び出す。

正式React版では、ブラウザがGoogle系OIDC providerから得たユーザーtokenを`Authorization: Bearer`でFastAPIへ送る。FastAPIは署名、issuer、audience、有効期限、`email_verified`を検証してから同じ認可処理を行う。この段階ではFastAPIのCloud Run IAMによるブラウザ遮断を外し、application認証、厳格なCORS、rate limitを公開境界とする。workerは引き続きIAM非公開とする。Streamlit向け内部headerを公開APIの認証として流用しない。

これによりReact側へ認可ロジックやsecretを置かず、Viteのstatic SPAからAPIを直接利用できる。Google Identity ServicesとFirebase Authenticationのどちらをtoken issuerとして使うかはReact移行時に決定する。

## 7. 障害と再試行

- Job状態: `queued`, `running`, `succeeded`, `failed`, `timed_out`
- 一時障害だけを最大3回再試行する。
- 入力エラーや数値計算の確定的失敗はJobへ記録し、キューには成功応答する。
- 完了済みJobの再配送は副作用なしで成功応答する。
- 長時間`running`のJobは開始時刻と実行attemptを使ってstale判定する。
- workerはSuggestion保存とJob完了を同一DB transactionで行う。

## 8. Decision Log

| ID | 決定 | 理由 | 状態 |
|---|---|---|---|
| ADR-001 | v1 UIにStreamlitを使用 | ask–tellとアルゴリズム検証を早く反復するため | Accepted |
| ADR-002 | 最適化実装にBoTorch/GPyTorchを使用 | モデル・獲得関数を拡張でき、独自抽象層のadapterとして利用できるため | Accepted |
| ADR-003 | DBのJobを状態の正本とする | CeleryとCloud Tasksの差をAPIから隠すため | Accepted |
| ADR-004 | ローカルはCelery、GCPはCloud Tasks | ローカルの開発容易性とクラウドのscale-to-zeroを両立するため | Accepted |
| ADR-005 | Cloudflareはv1計算基盤に使わない | Python数値計算スタックと長時間処理はGCPコンテナの方が適するため | Accepted |
| ADR-006 | モデル成果物を保存しない | v1では設定・観測・seedからの再現性を優先するため | Accepted |
| ADR-007 | v1のcloud DBはCloud SQLではなくFree枠のmanaged PostgreSQLを使用 | 個人開発で固定費を避けつつ、localとcloudでPostgreSQL互換性を保つため | Accepted |
| ADR-008 | DB実装はSQLAlchemy 2.x ORMとPydantic API schemaを分離し、同期Sessionから開始 | 複雑な制約とtransactionを明示し、domain/API/永続化の境界を保ちながらv1の実装量を抑えるため | Accepted |
| ADR-009 | localはmiseでapp・PostgreSQL・Redisをnative実行し、devcontainerを使用しない | 個人開発環境の常時負荷とfile mount overheadを減らし、将来のReact開発も同じtool管理へ統合するため | Superseded by ADR-013 |
| ADR-010 | `backend/`、`web-streamlit/`、`web/`を独立projectとしてroot直下へ置き、uv workspaceを使用しない | frontend間の置換をHTTP API境界だけで行い、Streamlit削除時にbackend依存関係を変更しないため | Accepted |
| ADR-011 | 正式frontendの初期scaffoldはReact + Vite + TypeScriptとし、Next.jsを採用しない | 認証後dashboard中心でSSR・SEO・Server Componentsが不要で、FastAPIが認証境界を担うため、static SPAの方がruntimeとdeploymentを単純化できる | Accepted |
| ADR-012 | ユーザー認証、許可リスト、resource所有者認可をFastAPIへ集約する | StreamlitとReactで同じ認可規則を使い、frontendの置換や将来のAPI client追加でsecurity logicを複製しないため | Accepted |
| ADR-013 | local applicationはホストで実行し、PostgreSQLとRedisだけをDocker Composeで管理する | devcontainerのoverheadを避けながら、native source buildの依存問題をなくし、middleware環境を再現可能にするため | Accepted |
| ADR-014 | GCPは単一project `inverse-optimization-app`とし、Terraformを`infra/`直下の単一root moduleにする | 個人開発では環境分割とmodule階層の運用負荷が利点を上回るため | Accepted |

## 9. 未決事項

- Neon FreeとSupabase Freeの最終選択（Step 6着手時に最新制限を比較）
- React移行時のuser token issuer（Google Identity ServicesまたはFirebase Authentication）
- OAuth consent screenとTerraform state bucketのbootstrap所有者
- 本番用ドメインの有無
