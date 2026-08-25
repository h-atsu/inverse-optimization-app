# プロダクト仕様

## 1. 目的

高コストな実験・解析・シミュレーションに対して、既存の観測結果から次に評価すべき条件を提案するWebアプリを構築する。初期段階ではアルゴリズムの妥当性とask–tell操作の使いやすさを優先し、外部ユーザー向けのサービス機能は扱わない。

## 2. 想定利用者

- 初期利用者は開発者本人と許可された少人数
- ベイズ最適化の基本概念を理解し、自分で実験値を取得できる利用者
- 1つのStudyは作成者だけが閲覧・更新できる

## 3. 主要用語

- **Study**: 目的、変数、seed、アルゴリズム設定をまとめた最適化単位
- **Observation**: 実際に評価した変数値と目的値
- **Suggestion**: アプリが次の評価対象として提案した変数値
- **Job**: 候補生成などの非同期処理
- **ask**: 次のSuggestionを要求する操作
- **tell**: Suggestionに対する目的値をObservationとして返す操作

## 4. 基本ユースケース

### 4.1 Studyを作成する

1. Googleアカウントでログインする。
2. Study名、最小化または最大化、seedを設定する。
3. 各連続変数の名前、下限、上限を入力する。
4. Studyを作成する。

変数名はStudy内で一意とし、`objective`と`suggestion_id`は予約語とする。下限は上限より小さくなければならない。

### 4.2 初期観測を登録する

1. Studyの変数列と`objective`列を持つCSVをアップロードする。
2. アプリが全行を検証する。
3. すべて有効な場合だけObservationを一括登録する。

反復実験を扱えるよう、同じ変数値のObservationを複数登録できる。

### 4.3 次の候補を取得する

1. ユーザーが「次の候補を生成」を実行する。
2. APIはJobを作成し、画面は状態を定期取得する。
3. workerが観測データを読み、候補を1点生成する。
4. 完了後、画面に候補を表示する。
5. 候補を`suggestion_id`、変数列、空の`objective`列を持つCSVとしてダウンロードできる。

未処理のSuggestionがある間は、新しいSuggestionを生成しない。

### 4.4 実験結果を返す

1. ユーザーが提案された条件で実験する。
2. ダウンロードしたCSVの`objective`を記入する。
3. CSVをアップロードする。
4. Observationを登録し、対応するSuggestionを`observed`にする。

実験できなかった場合はSuggestionを`discarded`にできる。

## 5. CSV仕様

UTF-8のヘッダー付きCSVを受け付ける。列順は問わない。

初期観測の例:

```csv
temperature,pressure,objective
20.0,1.0,4.25
25.0,1.5,3.80
```

Suggestionに対する結果の例:

```csv
suggestion_id,temperature,pressure,objective
0195f000-0000-7000-8000-000000000000,22.4,1.3,3.51
```

検証規則:

- Studyで定義した全変数列と`objective`が必要
- 追加列はエラーとする。ただし`suggestion_id`は任意
- 値は有限の数値でなければならない
- 変数値は上下限内でなければならない
- `suggestion_id`がある場合、対象Studyの`pending`なSuggestionと一致しなければならない
- 1行でも不正なら全行を登録しない
- API再試行による重複登録は`Idempotency-Key`で防止する

安全のためHTTPアップロードサイズには設定可能な上限を持たせるが、変数数・Observation数には固定の業務上限を設けない。

## 6. 画面

- ログイン画面
- Study一覧
- Study作成
- Study詳細
  - 設定概要
  - CSVアップロード
  - Observation一覧
  - best-so-farグラフ
  - Suggestion生成とJob状態
  - Suggestion表示、CSVダウンロード、破棄

StreamlitはプロトタイプのUIとして使用し、ビジネスロジックは持たせない。すべてのデータ操作はFastAPI経由で行う。

## 7. 非機能要件

- seedと設定から候補生成を再現できる
- Jobの失敗理由と実行時間を確認できる
- 1 JobはCPUで30分以内。アプリ側のソフト上限は25分
- APIやworkerの再試行でObservationやSuggestionが重複しない
- ログにStudy IDとJob IDを含める
- 秘密情報をリポジトリやコンテナイメージへ保存しない

## 8. 将来拡張

- Google SheetsをObservationの同期元・書き戻し先として追加する
- Reactフロントエンドの画面機能を実装しCloudflareへ配備する（scaffoldだけ先行）
- 整数、カテゴリ、制約、多目的、バッチ候補へ対応する
- 近似GP、独自モデル、独自獲得関数を追加する
- Cloud Run Jobs、Vertex AI、Batchによる長時間・GPU処理へ対応する
