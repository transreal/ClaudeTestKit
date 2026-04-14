# ClaudeTestKit API リファレンス

ClaudeRuntime / Security Kernel のテスト装置。MockProvider・MockAdapter・ScenarioRunner・トレース検証アサーションを提供する。

## バージョン情報

### $ClaudeTestKitVersion
型: String
パッケージバージョン文字列。

## Mock プロバイダ・アダプタ

### CreateMockProvider[responses] → Association
固定応答を順番に返す mock provider を作成する。responses は文字列のリスト。
例: `CreateMockProvider[{"NBCellRead[nb, 3]", "NBCellWrite[nb, 4, \"result\"]"}]`

### CreateMockAdapter[opts]
全 adapter 関数の mock 実装を返す。ClaudeRuntime に渡すアダプタとして使用する。
→ Association（adapter 関数群を含む）
Options: `"Provider" -> None` (CreateMockProvider の返り値), `"AllowedHeads" -> {}` (許可するシンボル頭部のリスト), `"DenyHeads" -> {}` (拒否するシンボル頭部のリスト), `"ApprovalHeads" -> {}` (承認要求を発生させる頭部のリスト), `"ExecutionResults" -> {}` (実行結果の固定値リスト), `"MaxContinuations" -> Infinity` (継続回数上限)
例:
```
adapter = CreateMockAdapter[
  "Provider" -> CreateMockProvider[{"NBCellRead[nb, 1]"}],
  "AllowedHeads" -> {NBCellRead, NBCellWrite},
  "DenyHeads" -> {DeleteFile},
  "MaxContinuations" -> 3
]
```

### CreateMockTransactionAdapter[opts]
トランザクション操作用の mock adapter を返す。CreateMockAdapter と同じ Options を受け付ける。
→ Association（transaction 対応 adapter 関数群を含む）

## シナリオ実行

### RunClaudeScenario[scenario] → Association
シナリオ定義を実行し、trace・outcome・アサーション結果を含む Association を返す。
scenario キー: `"Name"` (シナリオ名文字列), `"Input"` (ユーザー入力文字列), `"Adapter"` (CreateMockAdapter の返り値), `"Profile"` (セキュリティプロファイル), `"Assertions"` (アサーション関数のリスト)
→ `<|"Name" -> ..., "Passed" -> True|False, "Trace" -> ..., "Outcome" -> ..., "FailedAssertions" -> {...}|>`
例:
```
RunClaudeScenario[<|
  "Name" -> "ReadOnly test",
  "Input" -> "セル1を読んで",
  "Adapter" -> adapter,
  "Profile" -> "ReadOnly",
  "Assertions" -> {AssertValidationDenied, AssertNoSecretLeak[#, {"apikey"}]&}
|>]
```

### $ClaudeTestScenarios
型: Association
組み込みテストシナリオの Association。キーはシナリオ名文字列、値は RunClaudeScenario に渡せるシナリオ定義。

### RunAllClaudeTests[] → Dataset
全組み込みシナリオを実行し、各シナリオの名前・合否・失敗理由を Dataset で返す。

## トレース正規化

### NormalizeClaudeTrace[trace] → List
trace からタイムスタンプ・一時 ID・セッション ID 等の非決定的フィールドを除去し、golden comparison に使える形に変換する。差分テストや snapshot テストで使用する。

## アサーション

アサーション関数は検証が通れば `True` を、失敗すれば失敗理由を示す文字列または `False` を返す。`RunClaudeScenario` の `"Assertions"` リストに渡して使う。

### AssertNoSecretLeak[trace, secrets] → True | String
trace 内のすべてのテキスト表現に secrets 内の文字列が含まれないことを検証する。secrets は `{"apikey123", "password"}` 形式のリスト。いずれかが含まれる場合は漏洩した文字列を含むエラー文字列を返す。

### AssertValidationDenied[trace] → True | String
trace 中に `Deny` または `FatalFailure` イベントが存在することを検証する。deny されるべきシナリオ（禁止操作・権限不足）のテストに使う。

### AssertOutcome[trace, expectedOutcome] → True | String
trace の最終 outcome が expectedOutcome と一致することを検証する。expectedOutcome は `"Success"`, `"Denied"`, `"Error"` 等の文字列。

### AssertBudgetNotExceeded[runtimeState] → True | String
runtimeState 内の全 budget（ターン数・トークン数等）が設定上限以内であることを検証する。

### AssertEventSequence[trace, expectedTypes] → True | String
trace のイベント型列が expectedTypes の部分列を含むことを検証する。expectedTypes は `{"ToolCall", "ToolResult", "FinalResponse"}` 形式のシンボル名文字列リスト。順序は保持されるが連続している必要はない。
例: `AssertEventSequence[trace, {"ValidationRequest", "Deny"}]`