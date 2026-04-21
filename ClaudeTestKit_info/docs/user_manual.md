# ClaudeTestKit ユーザーマニュアル

## 概要

ClaudeTestKit は、ClaudeRuntime および ClaudeOrchestrator のランタイム・セキュリティカーネルをテストするための装置パッケージです。Mock Provider / Mock Adapter によるシミュレーション環境を提供し、シナリオ定義・実行・検証を一貫したインターフェースで行えます。

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

## ClaudeOrchestrator 連携テスト

[ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) は、複数の worker agent が分担してタスクを処理し、Reducer が成果物をまとめて Committer が最終的にノートブックへ書き込む、マルチエージェント実行フレームワークです。ClaudeTestKit はこのオーケストレーションフローを Mock 環境でテストするための関数群を提供します（spec §13 対応）。

### アーキテクチャ概要

ClaudeOrchestrator のテストでは以下のコンポーネントをそれぞれ Mock に置き換えます。

| コンポーネント      | Mock 関数                    | 役割                                   |
|--------------------|------------------------------|----------------------------------------|
| Planner            | `CreateMockPlanner`          | タスク分解仕様を固定値で返す           |
| Worker Adapter     | `CreateMockWorkerAdapter`    | 各 worker の応答・proposal を制御する  |
| Reducer            | `CreateMockReducer`          | artifact 統合結果を固定値で返す        |
| Committer Adapter  | `CreateMockCommitter`        | ノートブック書き込みを安全にスタブ化する |
| Query 関数         | `CreateMockQueryFunction`    | LLM 呼び出しを固定 JSON 応答で代替する |

---

### `CreateMockPlanner`

固定の taskSpec を返す mock planner を作成します。

**シグネチャ**
```
CreateMockPlanner[taskSpec_Association]
```

- `taskSpec` — `"Tasks"` キーを持つ Association。各タスクは `"TaskId"`・`"Goal"`・`"OutputSchema"`・`"DependsOn"` 等のキーを持ちます。

**例**
```wolfram
planner = CreateMockPlanner[<|
  "Tasks" -> {
    <|"TaskId" -> "t1", "Role" -> "Explore", "Goal" -> "構造を調べる",
      "OutputSchema" -> {"Summary"}, "DependsOn" -> {}|>,
    <|"TaskId" -> "t2", "Role" -> "Draft",  "Goal" -> "内容を書く",
      "OutputSchema" -> {"Body"},    "DependsOn" -> {"t1"}|>
  }
|>];
```

---

### `CreateMockWorkerAdapter`

役割・タスク・依存 artifact を受け取り、固定応答を返す mock worker adapter を作成します。

**シグネチャ**
```
CreateMockWorkerAdapter[role, task, depArtifacts, opts___Rule]
```

| オプション          | 説明                                                    |
|--------------------|---------------------------------------------------------|
| `"Response"`       | worker の固定応答（文字列または Association）           |
| `"ProposedHeld"`   | `HoldComplete[...]` で proposal を強制指定              |
| `"ArtifactPayload"`| 抽出される artifact payload（Association）              |

**例**
```wolfram
workerAdapter = CreateMockWorkerAdapter[
  "Explore", task, {},
  "ArtifactPayload" -> <|"Summary" -> "ノートブックには 3 つのセクションがある"|>
];
```

---

### `CreateMockReducer`

artifact リストを無視して固定 payload を返す mock reducer を作成します。

**シグネチャ**
```
CreateMockReducer[payload_Association]
```

**例**
```wolfram
reducer = CreateMockReducer[<|
  "Body" -> "統合されたコンテンツ",
  "Slides" -> {<|"Title" -> "まとめ", "Body" -> "...|>"}
|>];
```

---

### `CreateMockCommitter`

ノートブックへの実ファイル書き込みを行わず、Metadata にコミット記録のみを残す mock committer adapter を作成します。

**シグネチャ**
```
CreateMockCommitter[targetNotebook, reducedArtifact]
```

- `targetNotebook` — 書き込み先ノートブックオブジェクト（またはそのスタブ）
- `reducedArtifact` — Reducer が生成した統合 artifact

**例**
```wolfram
committer = CreateMockCommitter[mockNb, reducedArtifact];
```

---

### `CreateMockQueryFunction`

固定 JSON 応答を順番に返す mock query 関数を作成します。LLM planner / worker のテスト用です。

**シグネチャ**
```
CreateMockQueryFunction[responses_List]
```

- `responses` — JSON 文字列のリスト。順番に返され、使い切ると最後の応答を繰り返します。

**例**
```wolfram
queryFn = CreateMockQueryFunction[{
  "{\"Tasks\": [{\"TaskId\": \"t1\", \"Goal\": \"調査する\"}]}",
  "{\"Summary\": \"調査完了\"}"
}];
```

---

### `RunClaudeOrchestrationScenario`

ClaudeOrchestrator のオーケストレーションフロー全体をシナリオとして実行し、結果を返します。

**シグネチャ**
```
RunClaudeOrchestrationScenario[scenario_Association]
```

シナリオのキー：

| キー                      | 説明                                                      |
|--------------------------|-----------------------------------------------------------|
| `"Planner"`              | `CreateMockPlanner` の返り値                              |
| `"WorkerAdapterBuilder"` | `(role, task, depArtifacts) -> adapter` の関数            |
| `"Reducer"`              | `CreateMockReducer` の返り値                              |
| `"CommitterAdapterBuilder"` | `(nb, artifact) -> adapter` の関数                    |
| `"Input"`                | ユーザー入力テキスト                                      |
| `"TargetNotebook"`       | 書き込み先ノートブック（スタブ可）                        |
| `"Assertions"`           | 実行後に評価するアサーション関数のリスト                  |

**例**
```wolfram
result = RunClaudeOrchestrationScenario[<|
  "Planner"              -> planner,
  "WorkerAdapterBuilder" -> Function[{role, task, deps},
    CreateMockWorkerAdapter[role, task, deps,
      "ArtifactPayload" -> <|"Body" -> "生成コンテンツ"|>]],
  "Reducer"              -> reducer,
  "CommitterAdapterBuilder" -> Function[{nb, art}, CreateMockCommitter[nb, art]],
  "Input"                -> "レポートを作成してください",
  "TargetNotebook"       -> mockNb,
  "Assertions"           -> {
    AssertNoWorkerNotebookMutation[#] &,
    AssertSingleCommitterWrites[#] &
  }
|>];
```

---

## ClaudeOrchestrator 用アサーション関数

---

### `AssertNoWorkerNotebookMutation`

オーケストレーション結果の中で、いずれの worker も `NotebookWrite` / `CreateNotebook` を実行していないことを検証します。ノートブック書き込みは committer のみが行うという原則を守るためのアサーションです。

**シグネチャ**
```
AssertNoWorkerNotebookMutation[orchestrationResult_Association]
```

**例**
```wolfram
AssertNoWorkerNotebookMutation[result]
(* True — worker がノートブックを直接変更していない場合 *)
```

---

### `AssertArtifactsRespectDependencies`

`DependsOn` で指定された先行 artifact が、依存する artifact より先に生成されていることを検証します。

**シグネチャ**
```
AssertArtifactsRespectDependencies[orchestrationResult_Association, tasksSpec_Association]
```

**例**
```wolfram
AssertArtifactsRespectDependencies[result, taskSpec]
(* True — t1 の artifact が t2 より先に生成されている場合 *)
```

---

### `AssertSingleCommitterWrites`

ノートブック書き込み proposal が committer runtime のみから提案されていることを検証します。

**シグネチャ**
```
AssertSingleCommitterWrites[orchestrationResult_Association]
```

**例**
```wolfram
AssertSingleCommitterWrites[result]
(* True — 書き込み proposal が committer 由来のみの場合 *)
```

---

### `AssertReducerDeterministic`

同じ artifacts リストに対して reducer が複数回同じ結果を返すことを検証します。

**シグネチャ**
```
AssertReducerDeterministic[reducer, artifacts_List]
```

**例**
```wolfram
AssertReducerDeterministic[reducer, {artifact1, artifact2}]
(* True — 複数回呼び出して同一結果の場合 *)
```

---

### `AssertNoCrossWorkerStateAssumption`

worker の proposal 群の中に、他の worker の Mathematica 変数を参照する兆候がないことを検証します。worker 間のステート共有はアーキテクチャ違反であるため、このアサーションで検出します。

**シグネチャ**
```
AssertNoCrossWorkerStateAssumption[orchestrationResult_Association]
```

**例**
```wolfram
AssertNoCrossWorkerStateAssumption[result]
(* True — セッション変数的な参照が検出されない場合 *)
```

---

### `AssertTaskOutputMatchesSchema`

artifact の payload が、タスク定義の `OutputSchema` を満たすことを検証します（`ClaudeValidateArtifact` のアサーション版）。

**シグネチャ**
```
AssertTaskOutputMatchesSchema[artifact_Association, outputSchema_List]
```

**例**
```wolfram
AssertTaskOutputMatchesSchema[artifact, {"Summary", "Body"}]
(* True — payload に "Summary" と "Body" キーが存在する場合 *)
```

---

### `AssertArtifactHasSchemaWarnings`

artifact に `"SchemaWarnings"` キーが存在することを検証します。スキーマ不整合の検出テストに使用します。

**シグネチャ**
```
AssertArtifactHasSchemaWarnings[artifact_Association]
```

**例**
```wolfram
AssertArtifactHasSchemaWarnings[artifact]
(* True — artifact["SchemaWarnings"] が存在する場合 *)
```

---

## ClaudeOrchestrator 用アサーション一覧

| 関数 | 目的 |
|------|------|
| `AssertNoWorkerNotebookMutation[result]` | worker がノートブックを直接書き込んでいないことを確認 |
| `AssertArtifactsRespectDependencies[result, spec]` | DependsOn の順序で artifact が生成されたことを確認 |
| `AssertSingleCommitterWrites[result]` | 書き込み proposal が committer のみから来ることを確認 |
| `AssertReducerDeterministic[reducer, artifacts]` | reducer が決定論的であることを確認 |
| `AssertNoCrossWorkerStateAssumption[result]` | worker 間のステート参照がないことを確認 |
| `AssertTaskOutputMatchesSchema[artifact, schema]` | artifact payload がスキーマを満たすことを確認 |
| `AssertArtifactHasSchemaWarnings[artifact]` | SchemaWarnings キーが存在することを確認 |

---

## スライドテスト (Phase 33)

ClaudeOrchestrator のスライド生成フロー（Phase 33）に対応するテスト関数群です。Committer の fallback 動作、コンテンツベースのスライド検出、スタイルサニタイズ・intent 検出をそれぞれ独立して検証できます。

---

### T05: Committer fallback テスト

#### `RunT05CommitFallbackTests`

Committer の LLM プロンプト生成・fallback ロジックを単体テストし、PASS/FAIL サマリを返します。対象は `iExtractSlidesFromPayload` / `iCellFromSlideItem` / `iBuildCommitterHint` / `iDeterministicSlideCommit`（guard）です。

```wolfram
RunT05CommitFallbackTests[]
```

#### `AssertT05SlideExtraction`

`iExtractSlidesFromPayload` が代表的な 5 ケース（`Slides` キー・`Sections` キー・reducer ネストリスト・単一スライド Association・fallback generic）で封じたスライドリストを返すことを検証します。

#### `AssertT05CellFromItem`

`iCellFromSlideItem` が Title / Body / Code を持つ item を 3 個の `Cell[_, _]`（Title / Text / Input）に展開すること、また空 Association を 1 Cell に fallback することを検証します。

#### `AssertT05CommitHintStructure`

`iBuildCommitterHint` が「COMMITTER ROLE」・「NotebookWrite[EvaluationNotebook[], Cell[...]]」・「ReducedArtifact.Payload」の 3 つのマーカーをすべて含むプロンプト的なテキストを返すことを検証します。

#### `AssertT05FallbackGuards`

`iDeterministicSlideCommit` が正しくガードすることを検証します。NotebookObject 以外では `Status == "NotANotebook"`、空 payload では `Status == "NoSlides"`、不正引数では `Status == "Failed"` となることを確認します。

---

### T06: コンテンツベースのスライド検出テスト

#### `RunT06SlideContentTests`

コンテンツベースのスライド検出と SlideDraft / SlideOutline 形式の Cell 展開を単体テストします。

#### `AssertT06ContentBasedDetection`

`iExtractSlidesFromPayload` が `SlideOutline` / `SlideDraft` キー（T05 では拾えなかったもの）や、全く無関係なキー名でも slide-like なリストを正しく拾うことを検証します。

#### `AssertT06SlideDraftExpansion`

`iCellFromSlideItem` が SlideDraft 形式（`item["Cells"] = {<|"Style"->..., "Content"->...|>, ...}`）を内部 Cell リストにそのまま展開することを検証します。

#### `AssertT06SlideOutlineExpansion`

`iCellFromSlideItem` が SlideOutline 形式（Title + Subtitle + BodyOutline）を適切なスタイルの Cell に展開することを検証します。

---

### T07: スライド intent 検出・スタイルサニタイズテスト

#### `RunT07SlideIntentTests`

スライド intent 検出とスタイルサニタイズの単体テストを実行します。

#### `AssertT07StyleSanitization`

`iSanitizeCellStyle` が (a) 有効なスタイルはそのまま返す、(b) `"Subsection (title slide)"` は `"Subsection"` に落とす、(c) `"Subsection + Item/Subitem 群"` は `"Subsection"` に落とす、(d) 完全に不明なものは `"Text"` に落とす、ことを検証します。

#### `AssertT07SlideIntentDetection`

`iDetectSlideIntent` が (a) 「30 ページのスライド」を `IsSlide=True, PageCount=30` と認識、(b) 「10-page presentation」を `IsSlide=True, PageCount=10` と認識、(c) 全角数字「３０ページ」も 30 と認識、(d) スライド無関係の入力は `IsSlide=False`、となることを検証します。

#### `AssertT07InnerCellFromSpecSanitize`

`iInnerCellFromSpec` が Style が冗長（`"Subsection (title slide)"` 等）な場合に必ず有効な Mathematica cell style 名称に落とすことを検証します。

#### `AssertT07DefaultPlannerSlideAware`

`iDefaultPlanner` が入力に「30 ページのスライド」等が含まれる場合、単一 Explore ではなく Explore + Draft の 2 タスク分解を返し、Draft の `OutputSchema` に `"SlideDraft"` を含むことを検証します。

#### `AssertT07WorkerPromptSlideHint`

`iWorkerBuildSystemPrompt` がスライド必合いのタスク（Goal/Schema に slide / SlideDraft を含む）に対して `"T07 SLIDE-MODE"` 印字を含む拡張 prompt を返すことを検証します。

#### `AssertT07bResolveTargetNotebookLogic`

`iResolveTargetNotebook` が (a) スライド意図ありの入力で `Intent.IsSlide=True` を返す、(b) スライド無関係の入力で `Intent.IsSlide=False` を返す、ことを軸に検証します。`CreateDocument` は実ノートブックが必要なため、ヘッドレスになると `None` に fallback するケースはここでは検証しません。

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

## ClaudeOrchestrator 典型的なテストワークフロー

```wolfram
(* 1. Planner を用意する *)
planner = CreateMockPlanner[<|
  "Tasks" -> {
    <|"TaskId" -> "t1", "Role" -> "Explore",
      "Goal"   -> "ノートブック構造を調べる",
      "OutputSchema" -> {"Summary"}, "DependsOn" -> {}|>,
    <|"TaskId" -> "t2", "Role" -> "Draft",
      "Goal"   -> "レポートを書く",
      "OutputSchema" -> {"Body"}, "DependsOn" -> {"t1"}|>
  }
|>];

(* 2. Reducer・Committer を用意する *)
reducer   = CreateMockReducer[<|"Body" -> "統合コンテンツ"|>];

(* 3. オーケストレーションシナリオを実行する *)
result = RunClaudeOrchestrationScenario[<|
  "Planner"              -> planner,
  "WorkerAdapterBuilder" -> Function[{role, task, deps},
    CreateMockWorkerAdapter[role, task, deps,
      "ArtifactPayload" -> <|"Summary" -> "調査完了", "Body" -> "内容"|>]],
  "Reducer"              -> reducer,
  "CommitterAdapterBuilder" -> Function[{nb, art}, CreateMockCommitter[nb, art]],
  "Input"                -> "レポートを作成してください",
  "TargetNotebook"       -> None,
  "Assertions"           -> {
    AssertNoWorkerNotebookMutation[#] &,
    AssertSingleCommitterWrites[#] &,
    AssertArtifactsRespectDependencies[#, planner] &
  }
|>];

(* 4. 結果を確認する *)
result["Passed"]
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

### ClaudeRuntime 用

| 関数 | 目的 |
|------|------|
| `AssertNoSecretLeak[trace, secrets]` | 秘密文字列の漏洩がないことを確認 |
| `AssertValidationDenied[trace]` | 禁止操作が正しく拒否されることを確認 |
| `AssertOutcome[trace, outcome]` | 最終 outcome が期待値と一致することを確認 |
| `AssertBudgetNotExceeded[state]` | budget 超過がないことを確認 |
| `AssertEventSequence[trace, types]` | イベント型の出現順序を確認 |

### ClaudeOrchestrator 用

| 関数 | 目的 |
|------|------|
| `AssertNoWorkerNotebookMutation[result]` | worker がノートブックを直接書き込んでいないことを確認 |
| `AssertArtifactsRespectDependencies[result, spec]` | DependsOn の順序で artifact が生成されたことを確認 |
| `AssertSingleCommitterWrites[result]` | 書き込み proposal が committer のみから来ることを確認 |
| `AssertReducerDeterministic[reducer, artifacts]` | reducer が決定論的であることを確認 |
| `AssertNoCrossWorkerStateAssumption[result]` | worker 間のステート参照がないことを確認 |
| `AssertTaskOutputMatchesSchema[artifact, schema]` | artifact payload がスキーマを満たすことを確認 |
| `AssertArtifactHasSchemaWarnings[artifact]` | SchemaWarnings キーが存在することを確認 |

---

## 関連パッケージ

- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) — テスト対象のランタイム本体
- [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) — マルチエージェント実行フレームワーク（テスト対象）
- [NBAccess](https://github.com/transreal/NBAccess) — ノートブックアクセス API