# アルゴリズム設計

この文書はStep 2で実装する最適化コアの目標設計である。現時点の`backend/`はpackage scaffoldのみで、ここに記載するBoTorch adapterやbenchmark runnerは未実装である。

## 1. 対象問題

v1では次の問題を扱う。

```text
minimize または maximize f(x)
subject to lower_i <= x_i <= upper_i
x_i は連続値
```

目的関数はアプリ内で直接実行しない。ユーザーがObservationを登録し、アプリが次の評価点を1点提案する。ベンチマーク時だけ既知のテスト関数を自動評価する。

## 2. レイヤー境界

### SurrogateModel

役割:

- Observationからsurrogate modelを学習する
- 任意の点に対するposteriorの統計量を返す
- 実装固有オブジェクトをアプリ層へ公開しない

想定インターフェース:

```python
class SurrogateModel(ABC):
    def fit(self, dataset: Dataset, context: RunContext) -> None: ...
    def predict_posterior(self, points: Array) -> Posterior: ...
```

### AcquisitionStrategy

役割:

- 学習済みSurrogateModelと探索範囲から次の候補を1点生成する
- 獲得関数の種類と、その最大化方法をadapter内部へ閉じ込める

```python
class AcquisitionStrategy(ABC):
    def propose(
        self,
        model: SurrogateModel,
        dataset: Dataset,
        space: SearchSpace,
        context: RunContext,
    ) -> Candidate: ...
```

### Initializer

観測数が十分でない場合の初期候補を生成する。v1ではseed付きSobolを使い、既存Observationおよびpending Suggestionとの重複を避ける。

### BenchmarkFunction / BenchmarkRunner

- `BenchmarkFunction`: 次元、境界、最適値、評価関数を提供する
- `BenchmarkRunner`: 同一初期点と予算でBOとbaselineを実行し、指標を集計する

## 3. v1 BoTorch adapter

- tensor dtype: `torch.float64`
- device: CPU
- 入力: 各変数の上下限から`[0, 1]^d`へ正規化
- 出力: 学習時に標準化
- model: `SingleTaskGP`
- likelihood: 学習可能な同分散Gaussian noise
- fitting: exact marginal log likelihood
- acquisition: `LogExpectedImprovement`
- candidate count: `q=1`
- 最小化: 学習前に目的値を符号反転し、内部は常に最大化として扱う
- acquisition optimization: BoTorchの標準optimizerを使用し、seedを明示する

具体的なoptimizer反復数やraw sample数は性能測定前に固定しない。Step 2で小規模ベンチマークを行い、再現性・実行時間とともに設定値を文書へ追記して確定する。

## 4. 初期設計

- 必要観測数は`max(3, 2 * dimension + 1)`とする。
- 必要数に達するまでは、askごとにSobol候補を1点返す。
- ユーザーが十分な初期ObservationをCSV登録済みなら、直ちにGPを利用する。
- pending Suggestionが存在する間は新しい候補を生成しない。

## 5. 再現性

Studyの基準seedに加え、各Jobで実際に使用したseedを保存する。次を明示的に設定する。

- Pythonの乱数seed
- NumPyの乱数seed
- PyTorchの乱数seed
- Sobol生成seed
- acquisition optimizationに渡すseed

同じライブラリ版、CPU環境、Observation順序、設定、seedで候補が再現することを目標とする。異なるPyTorch/BoTorch版をまたぐbit-level一致は保証せず、依存バージョンをlock fileで固定する。

## 6. タイムアウトと数値エラー

- 変数数・Observation数で固定拒否しない。
- 最適化処理は子プロセスで実行する。
- 25分で子プロセスを終了し、Jobを`timed_out`にする。
- NaN、非正定値、optimizer失敗は分類したエラーとしてJobへ保存する。
- 数値jitterなどの安全な内部再試行は回数を制限し、結果のwarningへ記録する。
- タイムアウト時に不完全なSuggestionを保存しない。

## 7. ベンチマーク

### 対象

- Branin 2D: 30評価
- Hartmann 6D: 60評価
- seed数: 10
- baseline: 同一seed、同一初期点、同一評価予算のSobol探索

### 指標

- 各iterationのbest-so-far
- final simple regret
- 候補生成時間
- モデル学習時間
- timeoutおよび失敗数

受入基準は、両関数でBOのmedian final simple regretがSobol baselineを下回ることとする。CIでは少数seed・短い予算のsmoke testだけを実行し、完全ベンチマークは手動または定期workflowで実行する。

### 出力

- 1実行1行のCSV
- 設定、環境、集約統計を含むJSON
- 失敗時にもseed、iteration、例外分類を残す

## 8. 将来の自作実装

BoTorch型をAPI・DB・ユースケースへ漏らさない。独自GPへ移行するときは`SurrogateModel`を、独自候補探索へ移行するときは`AcquisitionStrategy`を追加する。互換性テストには同じBenchmarkRunnerを使用する。
