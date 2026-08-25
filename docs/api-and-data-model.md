# API・データモデル

この文書はStep 3以降で実装するAPIと永続化モデルの目標仕様である。現時点ではFastAPI route、DB schema、migrationは未実装である。

## 1. API方針

- ベースパスは`/v1`とする。
- JSONのキーはsnake_caseとする。
- IDはUUIDとする。
- 日時はUTCのISO 8601形式とする。
- 非同期処理の作成は`202 Accepted`とJobを返す。
- エラーは`code`、`message`、任意の`details`を持つ共通形式とする。
- CSV登録系は`Idempotency-Key` headerを必須とする。

## 2. API一覧

| Method | Path | 用途 |
|---|---|---|
| `GET` | `/health/live` | プロセス生存確認 |
| `GET` | `/health/ready` | DB等を含む受付可否 |
| `POST` | `/v1/studies` | Study作成 |
| `GET` | `/v1/studies` | 所有Study一覧 |
| `GET` | `/v1/studies/{study_id}` | Study詳細 |
| `POST` | `/v1/studies/{study_id}/observations:import` | 観測CSV登録 |
| `GET` | `/v1/studies/{study_id}/observations` | 観測一覧 |
| `POST` | `/v1/studies/{study_id}/suggestion-jobs` | 候補生成Job作成 |
| `GET` | `/v1/jobs/{job_id}` | Job状態取得 |
| `GET` | `/v1/studies/{study_id}/suggestions/current` | pending Suggestion取得 |
| `POST` | `/v1/studies/{study_id}/suggestions/{suggestion_id}:discard` | Suggestion破棄 |
| `GET` | `/v1/studies/{study_id}/suggestions/{suggestion_id}.csv` | 結果入力用CSV取得 |

ページングが必要な一覧は`limit`と`cursor`を採用する。初期実装でもresponse shapeに`items`と`next_cursor`を持たせる。

## 3. Study作成

例:

```json
{
  "name": "material experiment",
  "direction": "minimize",
  "seed": 42,
  "parameters": [
    {"name": "temperature", "type": "continuous", "lower": 10.0, "upper": 50.0},
    {"name": "pressure", "type": "continuous", "lower": 0.5, "upper": 2.0}
  ]
}
```

`type`はv1では`continuous`だけを受け付けるが、将来の混合変数対応のためwire形式には残す。parameter順序は正規化・CSV出力・配列変換で使用するため保存する。

## 4. Job response

```json
{
  "id": "0195f000-0000-7000-8000-000000000000",
  "study_id": "0195f000-0000-7000-8000-000000000001",
  "kind": "generate_suggestion",
  "status": "queued",
  "attempt": 0,
  "created_at": "2026-08-25T09:00:00Z",
  "started_at": null,
  "finished_at": null,
  "error": null
}
```

状態遷移:

```text
queued -> running -> succeeded
                  -> failed
                  -> timed_out
queued ----------> failed      # dispatch失敗
```

終端状態から別状態へは遷移しない。再配送されたworkerは終端状態を確認して副作用なしで終了する。

## 5. データモデル

### Study

- `id`: UUID、主キー
- `owner_email`: 正規化済みメール
- `name`
- `direction`: `minimize | maximize`
- `seed`
- `algorithm_name`
- `algorithm_config`: JSON
- `created_at`, `updated_at`

### ParameterDefinition

Studyに属する順序付き定義。将来の型追加とDB検索を考慮し、v1でも独立tableとする。

- `id`, `study_id`
- `position`
- `name`
- `parameter_type`: v1は`continuous`
- `lower`, `upper`

`study_id + name`と`study_id + position`をuniqueにする。

### Observation

- `id`, `study_id`
- `suggestion_id`: nullable、Suggestion由来なら設定
- `values`: JSON object
- `objective`: double precision
- `source`: `csv | benchmark`
- `import_batch_id`: nullable
- `created_at`

同一`values`の重複は許可する。`suggestion_id`はuniqueとし、1つのSuggestionが複数回tellされることを防ぐ。

### Suggestion

- `id`, `study_id`, `job_id`
- `values`: JSON object
- `status`: `pending | observed | discarded`
- `seed`
- `created_at`, `resolved_at`

Studyごとに`pending`を最大1件とする。PostgreSQLのpartial unique indexで保証する。

### Job

- `id`, `study_id`
- `kind`: v1は`generate_suggestion`
- `status`
- `seed`, `attempt`
- `created_at`, `started_at`, `finished_at`
- `heartbeat_at`
- `error_code`, `error_message`
- `metrics`: JSON

### ImportBatch

- `id`, `study_id`
- `idempotency_key`
- `content_sha256`
- `row_count`
- `created_at`

`study_id + idempotency_key`をuniqueにする。同じキー・同じpayloadの再送は元の結果を返し、同じキー・異なるpayloadは`409 Conflict`とする。

## 6. 整合性とtransaction

- Study作成とParameterDefinition登録は同一transaction
- CSVは全行検証後、ImportBatch・Observation・Suggestion更新を同一transaction
- SuggestionとJob成功更新は同一transaction
- Job作成後のdispatch失敗はJobを`failed`へ補償更新
- owner条件をrepository queryへ必ず含め、存在しない場合と所有者違いはいずれも`404`とする

## 7. エラーコード

- `validation_error`: JSONまたはCSVが不正
- `study_not_found`
- `pending_suggestion_exists`
- `suggestion_not_pending`
- `idempotency_conflict`
- `job_dispatch_failed`
- `optimization_failed`
- `optimization_timed_out`
- `service_unavailable`

内部例外やstack traceはresponseへ含めず、構造化ログに記録する。
