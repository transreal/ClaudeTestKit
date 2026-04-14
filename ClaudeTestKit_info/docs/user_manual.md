# ClaudeTestKit ユーザーマニュアル

## 概要

ClaudeTestKit は、ClaudeRuntime のランタイム・セキュリティカーネルをテストするための装置パッケージです。Mock Provider / Mock Adapter によるシミュレーション環境を提供し、シナリオ定義・実行・検証を一貫したインターフェースで行えます。

本マニュアルでは各パブリック関数の使い方を機能カテゴリ別に説明します。インストール方法は `setup.md` を参照してください。

---

## バージョン情報

### `$ClaudeTestKitVersion`

現在ロードされている ClaudeTestKit のバージョン文字列を返します。

```wolfram
$ClaudeTestKitVersion
(* "1.0.0" などのバージョン文字列 *)
```

---

## Mock プロバイダー・アダプター

テスト用の疑似 LLM プロバイダーおよびアダプターを構築するための関数群です。実際の API 呼び出しを行わず、固定応答でランタイムの動作を検証できます。

---

### `CreateMockProvider`

固定応答を順番に返す Mock LLM Provider を作成します。

**シグネチャ**
```
CreateMockProvider[responses_List]
```

- `responses` — プロバイダーが順番に返すテキスト応答のリスト。

**例**
```wolfram
provider = CreateMockProvider[{
  "NBCellRead[nb, 1]",
  "NBCellWrite[nb, 2, \"Hello\"]"
}];
```

最初の呼び出しで `"NBCellRead[nb, 1]"` を返し、次の呼び出しで `"NBCellWrite[nb, 2, \"Hello\"]"` を返します。応答リストを使い切った後は最後の応答を繰り返します。

---

### `CreateMockAdapter`

すべての Adapter インターフェース関数の Mock 実装を返します。許可・拒否ルール、実行結果、継続回数の上限を細かく制御できます。

**シグネチャ**
```
CreateMockAdapter[opts___Rule]
```

| オプション           | 説明                                           |
|---------------------|------------------------------------------------|
| `"Provider"`        | `CreateMockProvider` の返り値                  |
| `"AllowedHeads"`    | 実行を許可する関数ヘッドのリスト               |
| `"DenyHeads"`       | 実行を拒否する関数ヘッドのリスト               |
| `"ApprovalHeads"`   | ユーザー承認が必要な関数ヘッドのリスト         |
| `"ExecutionResults"`| 実行ステップごとの結果リスト                   |
| `"MaxContinuations"`| 継続ループの最大回数                           |

**例**
```wolfram
adapter = CreateMockAdapter[
  "Provider"         -> CreateMockProvider[{"NBCellRead[nb, 1]"}],
  "AllowedHeads"     -> {NBCellRead},
  "DenyHeads"        -> {DeleteFile, RunProcess},
  "ExecutionResults" -> {"cell content here"},
  "MaxContinuations" -> 3
];
```

---

### `CreateMockTransactionAdapter`

トランザクション処理専用の Mock Adapter を返します。トランザクションのコミット・ロールバック動作のテストに使用します。

**シグネチャ**
```
CreateMockTransactionAdapter[opts___Rule]
```

オプションは `CreateMockAdapter` と同様です。

**例**
```wolfram
txAdapter = CreateMockTransactionAdapter[
  "Provider"         -> CreateMockProvider[{"CommitTransaction[]"}],
  "AllowedHeads"     -> {CommitTransaction},
  "MaxContinuations" -> 2
];
```

---

## シナリオ実行

シナリオとは、入力・アダプター・プロファイル・アサーションをひとまとめにした `Association` です。`RunClaudeScenario` に渡すことで、実行からアサーション評価まで一括処理できます。

---

### `RunClaudeScenario`

シナリオ定義を受け取り、ClaudeRuntime を通じて実行し、結果と trace を返します。

**シグネチャ**
```
RunClaudeScenario[scenario_Association]
```

シナリオの必須キー：

| キー            | 説明                                           |
|----------------|------------------------------------------------|
| `"Name"`       | シナリオの識別名                               |
| `"Input"`      | ユーザー入力テキスト                           |
| `"Adapter"`    | `CreateMockAdapter` で作成した adapter         |
| `"Profile"`    | 実行プロファイル（`<|"MaxTokens" -> 1000, ...|>` 等）|
| `"Assertions"` | 実行後に評価するアサーション関数のリスト       |

**例**
```wolfram
result = RunClaudeScenario[<|
  "Name"       -> "基本読み取りテスト",
  "Input"      -> "セル1を読んでください",
  "Adapter"    -> CreateMockAdapter[
    "Provider"         -> CreateMockProvider[{"NBCellRead[nb, 1]"}],
    "AllowedHeads"     -> {NBCellRead},
    "ExecutionResults" -> {"content of cell 1"},
    "MaxContinuations" -> 2
  ],
  "Profile"    -> <|"MaxTokens" -> 500|>,
  "Assertions" -> {
    AssertOutcome[#, "Completed"] &,
    AssertNoSecretLeak[#, {"apikey123"}] &
  }
|>];
```

戻り値は `<|"Passed" -> True/False, "Trace" -> ..., "Results" -> ...|>` 形式の Association です。

---

### `$ClaudeTestScenarios`

パッケージに組み込まれた標準テストシナリオの Association です。キーはシナリオ名、値はシナリオ定義です。

**例**
```wolfram
Keys[$ClaudeTestScenarios]
(* {"SecretLeakTest", "AccessViolationTest", "BudgetExceededTest", ...} *)

(* 個別シナリオの確認 *)
$ClaudeTestScenarios["SecretLeakTest"]
```

---

### `RunAllClaudeTests`

`$ClaudeTestScenarios` の全シナリオを順番に実行し、結果を `Dataset` として返します。

**シグネチャ**
```
RunAllClaudeTests[]
```

**例**
```wolfram
results = RunAllClaudeTests[];
results
(* Dataset[{<|"Name" -> "SecretLeakTest", "Passed" -> True, ...|>, ...}] *)

(* 失敗したテストのみ抽出 *)
results[Select[Not[#Passed]&]]
```

---

## トレース操作

ClaudeRuntime の実行 trace にはタイムスタンプ・セッション ID などの非決定的な値が含まれます。`NormalizeClaudeTrace` でこれらを除去することで、期待値（golden）との比較が可能になります。

---

### `NormalizeClaudeTrace`

trace からタイムスタンプ・ID などの非決定的フィールドを除去し、golden 比較に適した形式に変換します。

**シグネチャ**
```
NormalizeClaudeTrace[trace_List]
```

**例**
```wolfram
normalized = NormalizeClaudeTrace[result["Trace"]];

(* golden ファイルと比較 *)
golden = Import["golden_trace.wl"];
normalized === golden
```

正規化後の trace にはイベント型・コマンド名・結果ステータスのみが残り、時刻依存のフィールドはすべてプレースホルダーに置き換えられます。

---

## アサーション関数

`RunClaudeScenario` の `"Assertions"` リストに渡す関数群です。すべて `trace` または `runtimeState` を引数に取り、検証に失敗した場合はエラーメッセージとともに `False` を返します。

---

### `AssertNoSecretLeak`

trace および実行結果の中に、指定した秘密文字列が一切含まれないことを検証します。

**シグネチャ**
```
AssertNoSecretLeak[trace_List, secrets_List]
```

**例**
```wolfram
AssertNoSecretLeak[result["Trace"], {"sk-ant-api03-xxxx", "my-password"}]
(* True — 秘密が漏れていない場合 *)
```

trace 内のすべてのイベントを文字列化し、各秘密が部分文字列として現れないかを検査します。

---

### `AssertValidationDenied`

trace 中に `Deny` または `FatalFailure` イベントが存在することを検証します。拒否されるべき操作が正しく拒否されているかの確認に使用します。

**シグネチャ**
```
AssertValidationDenied[trace_List]
```

**例**
```wolfram
(* DeleteFile のような禁止操作が拒否されることを確認 *)
AssertValidationDenied[result["Trace"]]
(* True — Deny または FatalFailure イベントが存在する場合 *)
```

---

### `AssertOutcome`

実行の最終 outcome が期待値と一致することを検証します。

**シグネチャ**
```
AssertOutcome[trace_List, expectedOutcome_String]
```

典型的な `expectedOutcome` の値：`"Completed"`、`"Denied"`、`"BudgetExceeded"`、`"Error"`

**例**
```wolfram
AssertOutcome[result["Trace"], "Completed"]
(* True — 実行が正常完了した場合 *)
```

---

### `AssertBudgetNotExceeded`

runtime state の全 budget（トークン数・継続回数・コスト等）が設定上限を超えていないことを検証します。

**シグネチャ**
```
AssertBudgetNotExceeded[runtimeState_Association]
```

**例**
```wolfram
AssertBudgetNotExceeded[result["RuntimeState"]]
(* True — 全 budget が上限内の場合 *)
```

---

### `AssertEventSequence`

trace のイベント型列が、指定した期待イベント型のリストを **部分列として含む** ことを検証します。

**シグネチャ**
```
AssertEventSequence[trace_List, expectedTypes_List]
```

**例**
```wolfram
AssertEventSequence[
  result["Trace"],
  {"RequestReceived", "ValidationPassed", "Executed", "Completed"}
]
(* True — 上記イベントが指定順で trace に現れる場合 *)
```

`expectedTypes` は連続している必要はなく、順序どおりに含まれていれば合格です。

---

## 典型的なテストワークフロー

以下に、一連のテストを記述する代表的なパターンを示します。

```wolfram
(* 1. Mock Provider を用意する *)
provider = CreateMockProvider[{
  "NBCellRead[nb, 1]",
  "NBCellRead[nb, 2]"
}];

(* 2. Mock Adapter を構成する *)
adapter = CreateMockAdapter[
  "Provider"         -> provider,
  "AllowedHeads"     -> {NBCellRead},
  "DenyHeads"        -> {DeleteFile},
  "ExecutionResults" -> {"result1", "result2"},
  "MaxContinuations" -> 5
];

(* 3. シナリオを定義して実行する *)
result = RunClaudeScenario[<|
  "Name"    -> "読み取り専用テスト",
  "Input"   -> "セル1とセル2を読んでください",
  "Adapter" -> adapter,
  "Profile" -> <|"MaxTokens" -> 1000|>,
  "Assertions" -> {
    AssertOutcome[#, "Completed"] &,
    AssertNoSecretLeak[#, {"secret-key"}] &,
    AssertEventSequence[#, {"RequestReceived", "Executed"}] &
  }
|>];

(* 4. 結果を確認する *)
result["Passed"]   (* True/False *)
result["Trace"]    (* 詳細 trace *)
```

---

## 組み込みテストの実行

パッケージに付属する標準シナリオをすべて実行するには、以下のように呼び出します。

```wolfram
(* 全テストを実行 *)
allResults = RunAllClaudeTests[];

(* 合格数・不合格数を集計 *)
<|
  "Passed" -> Length[allResults[Select[#Passed &]]],
  "Failed" -> Length[allResults[Select[Not[#Passed] &]]]
|>

(* 不合格シナリオの名前を確認 *)
Normal[allResults[Select[Not[#Passed] &], "Name"]]
```

---

## アサーション関数一覧

| 関数 | 目的 |
|------|------|
| `AssertNoSecretLeak[trace, secrets]` | 秘密文字列の漏洩がないことを確認 |
| `AssertValidationDenied[trace]` | 禁止操作が正しく拒否されることを確認 |
| `AssertOutcome[trace, outcome]` | 最終 outcome が期待値と一致することを確認 |
| `AssertBudgetNotExceeded[state]` | budget 超過がないことを確認 |
| `AssertEventSequence[trace, types]` | イベント型の出現順序を確認 |

---

## 関連パッケージ

- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) — テスト対象のランタイム本体
- [NBAccess](https://github.com/transreal/NBAccess) — ノートブックアクセス API