# ClaudeTestKit

ClaudeRuntime / ClaudeOrchestrator / セキュリティカーネルのテスト装置パッケージです。MockProvider・MockAdapter・MockPlanner・MockWorkerAdapter・ScenarioRunner・トレース検証アサーションを提供します。

## 設計思想と実装の概要

ClaudeTestKit は、[ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) および [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) のランタイムおよびセキュリティカーネルを体系的にテストするために設計されたテスト装置です。

### なぜこの設計か

ClaudeRuntime のテストには根本的なジレンマがあります。すべてを Mock で置き換えてしまうと、最も重要なセキュリティカーネルの動作そのものを検証できなくなります。ClaudeTestKit はこの問題に対し「Mock は LLM プロバイダーと Adapter インターフェース層に限定し、セキュリティカーネルの核心部分はできる限り本物の [NBAccess](https://github.com/transreal/NBAccess) パブリック API を通じてテストする」という設計原則を採用しています。

これにより、実際の運用環境に近い条件でセキュリティ境界・許可/拒否ルール・秘密漏洩防止・予算制限といった重要な不変条件を検証することができます。

ClaudeOrchestrator のテストにおいては、Planner・Worker・Reducer・Committer という各ロールを個別に Mock 化することで、マルチエージェントのオーケストレーションフロー全体の正確性を検証できます。

### 主要な設計構造

**Mock レイヤー（`CreateMockProvider` / `CreateMockAdapter`）**
固定応答を順番に返す MockProvider と、全 Adapter インターフェース関数の Mock 実装を提供します。`AllowedHeads`・`DenyHeads`・`ApprovalHeads` の三分類によって、許可・拒否・承認待ちの各シナリオを精密に制御できます。`CreateMockTransactionAdapter` はさらにトランザクションの各フェーズ（Snapshot・ShadowApply・StaticCheck・ReloadCheck・TestPhase・Commit・Rollback）に個別の失敗注入（fault injection）ができる設計になっており、ロールバック動作の検証も可能です。

**オーケストレーション Mock レイヤー（`CreateMockPlanner` / `CreateMockWorkerAdapter` / `CreateMockReducer` / `CreateMockCommitter`）**
ClaudeOrchestrator のマルチエージェントフローを構成する各ロールに対応した Mock 実装を提供します。`CreateMockPlanner` は固定タスク仕様を返す Planner Mock を、`CreateMockWorkerAdapter` はロール別の Worker Mock を、`CreateMockReducer` は固定 payload を返す Reducer Mock を、`CreateMockCommitter` は実ファイル書き込みを伴わない Committer Mock を生成します。これらを組み合わせることで、実際の LLM 呼び出しなしにオーケストレーション全体の動作を検証できます。

**シナリオ実行エンジン（`RunClaudeScenario` / `RunClaudeOrchestrationScenario`）**
`RunClaudeScenario` はシングルエージェント向けのシナリオ実行エンジンで、ClaudeRuntime のターン実行からアサーション評価まで一括処理します。`RunClaudeOrchestrationScenario` は ClaudeOrchestrator のマルチエージェントフロー（Planner → Worker × N → Reducer → Committer）に対応したオーケストレーション専用の実行エンジンで、各ロールに Mock を注入してシナリオ全体を検証します。

**トレース正規化（`NormalizeClaudeTrace`）**
タイムスタンプ・セッション ID・一時 ID 等の非決定的フィールドを除去し、ゴールデン比較（スナップショットテスト）に使える形に変換します。これにより再現可能な差分テストが実現します。

**アサーション体系**
シングルエージェント向けの `AssertNoSecretLeak`・`AssertValidationDenied`・`AssertOutcome`・`AssertBudgetNotExceeded`・`AssertEventSequence` に加え、ClaudeOrchestrator 向けの `AssertNoWorkerNotebookMutation`・`AssertArtifactsRespectDependencies`・`AssertSingleCommitterWrites`・`AssertReducerDeterministic`・`AssertNoCrossWorkerStateAssumption`・`AssertTaskOutputMatchesSchema`・`AssertArtifactHasSchemaWarnings` といったオーケストレーション専用のアサーション関数が用意されています。

**組み込みシナリオ集（`$ClaudeTestScenarios` / `RunAllClaudeTests`）**
PermitSimple（正常系）・DenyForbiddenHead（禁止 head 拒否）・NeedsApproval（承認待ち）・TextOnly（テキスト応答）・NoSecretLeak（秘密漏洩防止）・Continuation（マルチターン継続）の 6 シナリオが組み込まれており、`RunAllClaudeTests[]` で一括実行して Dataset 形式の結果を得られます。

---

## 詳細説明

### 動作環境

| 項目 | 要件 |
|------|------|
| Mathematica / Wolfram Engine | 13.0 以降 |
| [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) | 最新版（必須） |
| [NBAccess](https://github.com/transreal/NBAccess) | 最新版（必須） |
| [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) | 最新版（オーケストレーションテスト使用時） |

外部ツールや API キーは ClaudeTestKit 単体の使用には不要です。ClaudeRuntime のセキュリティカーネルをテストする場合は、ClaudeRuntime 側の設定（API キー等）を先に完了させてください。ClaudeOrchestrator のオーケストレーションフローをテストする場合は、ClaudeOrchestrator も同じ `$packageDirectory` に配置してください。

> **注意**: 本パッケージは Windows 11 上での動作を想定しています。macOS / Linux では、パス区切り文字やシェルコマンドを適宜読み替えてください。

---

### インストール

#### 1. `$packageDirectory` の確認

```mathematica
$packageDirectory
```

未定義の場合は [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) または [claudecode](https://github.com/transreal/claudecode) パッケージを先にインストールしてください。

#### 2. ファイルの配置

[ClaudeTestKit リポジトリ](https://github.com/transreal/ClaudeTestKit) から `ClaudeTestKit.wl` をダウンロードし、`$packageDirectory` に直接配置します。サブディレクトリには置かないでください。

```
<$packageDirectory>\
    ClaudeTestKit.wl   ← ここに配置
```

#### 3. 依存パッケージの確認

同じく `$packageDirectory` に以下が配置されていることを確認してください。

- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime)
- [NBAccess](https://github.com/transreal/NBAccess)
- [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator)（オーケストレーションテスト使用時）

#### 4. `$Path` への追加

claudecode を使用している場合は自動で設定されます。手動で設定する場合は以下を実行してください。

```mathematica
If[!MemberQ[$Path, $packageDirectory],
  AppendTo[$Path, $packageDirectory]
]
```

**注意**: `$packageDirectory` そのものを追加してください。`AppendTo[$Path, "C:\\...\\ClaudeTestKit"]` のようなパッケージ固有のパスを追加するのは誤りです。

#### 5. パッケージの読み込み

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeTestKit`", "ClaudeTestKit.wl"]
]
```

---

### クイックスタート

以下の手順で、インストール直後からテストを実行できます。

**バージョン確認:**
```mathematica
$ClaudeTestKitVersion
(* "2026-04-11T6" 等のバージョン文字列が返ります *)
```

**全組み込みテストの一括実行:**
```mathematica
results = RunAllClaudeTests[]
(* Dataset 形式で全シナリオの結果が返ります *)
```

**MockProvider・MockAdapter の基本パターン:**
```mathematica
(* 1. 固定応答を返す MockProvider を作成 *)
provider = CreateMockProvider[{
  "```mathematica\nNBCellRead[nb, 1]\n```",
  "処理が完了しました。"
}];

(* 2. MockAdapter を作成（許可/拒否ルールを設定） *)
adapter = CreateMockAdapter[
  "Provider"         -> provider,
  "AllowedHeads"     -> {NBCellRead, NBCellWrite},
  "DenyHeads"        -> {DeleteFile, RunProcess},
  "ExecutionResults" -> {"セル1の内容"},
  "MaxContinuations" -> 1
];

(* 3. シナリオを定義して実行 *)
result = RunClaudeScenario[<|
  "Name"       -> "基本読み取りテスト",
  "Input"      -> "セル 1 を読んで",
  "Adapter"    -> adapter,
  "Profile"    -> "default",
  "Assertions" -> {
    <|"Name" -> "秘密漏洩なし",
      "Check" -> Function[{st, tr},
        TrueQ[AssertNoSecretLeak[tr, {}]]]|>
  }
|>];

result["Status"]        (* "Done" *)
result["AllPassed"]     (* True *)
```

**オーケストレーションシナリオの基本パターン:**
```mathematica
(* ClaudeOrchestrator のマルチエージェントフローをテスト *)
orchestrationResult = RunClaudeOrchestrationScenario[<|
  "Planner"               -> CreateMockPlanner[<|
    "Tasks" -> {<|"TaskId" -> "t1", "Goal" -> "セルを分析する"|>}
  |>],
  "WorkerAdapterBuilder"  -> Function[{role, task, deps},
    CreateMockWorkerAdapter[role, task, deps,
      "Response" -> "分析完了しました。"
    ]
  ],
  "Reducer"               -> CreateMockReducer[<|"Summary" -> "完了"|>],
  "CommitterAdapterBuilder" -> Function[nb, CreateMockCommitter[nb, <||>]],
  "Input"                 -> "ノートブックを分析して",
  "TargetNotebook"        -> None,
  "Assertions"            -> {AssertSingleCommitterWrites, AssertReducerDeterministic}
|>];
```

---

### 主な機能

| 関数 / 変数 | 説明 |
|---|---|
| `CreateMockProvider[responses]` | 固定応答を順番に返す Mock LLM Provider を作成します。応答リストを使い切った後は最後の応答を繰り返します。 |
| `CreateMockAdapter[opts]` | 全 Adapter インターフェース関数の Mock 実装を返します。`AllowedHeads`・`DenyHeads`・`ApprovalHeads`・`ExecutionResults`・`MaxContinuations` を設定できます。 |
| `CreateMockTransactionAdapter[opts]` | トランザクション処理専用の Mock Adapter を返します。`FailAtPhase`・`FailCount` オプションで特定フェーズへの失敗注入が可能です。 |
| `CreateMockPlanner[taskSpec]` | 固定タスク仕様を返す Mock Planner を作成します。ClaudeOrchestrator の Planner ロールのテストに使用します。 |
| `CreateMockWorkerAdapter[role, task, depArtifacts, opts]` | ロール別の Mock Worker Adapter を返します。`Response`・`ProposedHeld`・`ArtifactPayload` を設定できます。 |
| `CreateMockReducer[payload]` | artifacts を無視して固定 payload を返す Mock Reducer を作成します。 |
| `CreateMockCommitter[targetNotebook, reducedArtifact]` | 実ファイル書き込みを行わない Mock Committer Adapter を返します。commit record を Metadata に記録します。 |
| `CreateMockQueryFunction[responses]` | 固定応答を順番に返す Mock Query 関数を作成します。LLM Planner / Worker のテストに使用します。 |
| `RunClaudeScenario[scenario]` | シナリオ Association を受け取り、ClaudeRuntime を通じて実行し、Trace・Status・AssertionResults を含む結果 Association を返します。 |
| `RunClaudeOrchestrationScenario[scenario]` | ClaudeOrchestrator のマルチエージェントフロー（Planner → Worker × N → Reducer → Committer）を Mock で実行し、結果を返します。 |
| `$ClaudeTestScenarios` | 組み込みテストシナリオの Association（PermitSimple・DenyForbiddenHead・NeedsApproval・TextOnly・NoSecretLeak・Continuation の 6 種類）。 |
| `RunAllClaudeTests[]` | 全組み込みシナリオを実行し、名前・合否・詳細を Dataset 形式で返します。 |
| `NormalizeClaudeTrace[trace]` | Trace からタイムスタンプ・ID 等の非決定的フィールドを除去し、ゴールデン比較に使える形に変換します。 |
| `AssertNoSecretLeak[trace, secrets]` | Trace 内に secrets リストの文字列が含まれないことを検証します。 |
| `AssertValidationDenied[trace]` | Trace 中に `Deny` または `FatalFailure` イベントが存在することを検証します。 |
| `AssertOutcome[trace, expectedOutcome]` | Trace の最終 outcome が期待値と一致することを検証します。 |
| `AssertBudgetNotExceeded[runtimeState]` | runtimeState 内の全 budget が設定上限以内であることを検証します。 |
| `AssertEventSequence[trace, expectedTypes]` | Trace のイベント型列が expectedTypes の部分列を含むことを検証します。 |
| `AssertNoWorkerNotebookMutation[orchestrationResult]` | Worker のいずれも NotebookWrite / CreateNotebook を実行していないことを検証します（ClaudeOrchestrator 向け）。 |
| `AssertArtifactsRespectDependencies[orchestrationResult, tasksSpec]` | DependsOn の先行 artifact が後続より先に生成されていることを検証します（ClaudeOrchestrator 向け）。 |
| `AssertSingleCommitterWrites[orchestrationResult]` | Notebook 書き込み proposal が Committer Runtime のみから提案されたことを検証します（ClaudeOrchestrator 向け）。 |
| `AssertReducerDeterministic[reducer, artifacts]` | 同じ artifacts に対して Reducer を複数回呼び出し、結果が一致することを検証します（ClaudeOrchestrator 向け）。 |
| `AssertNoCrossWorkerStateAssumption[orchestrationResult]` | Worker proposal 群に他 Worker の Mathematica 変数を参照する兆候がないことを検証します（ClaudeOrchestrator 向け）。 |
| `AssertTaskOutputMatchesSchema[artifact, outputSchema]` | artifact payload が outputSchema を満たすことを検証します（ClaudeOrchestrator 向け）。 |
| `AssertArtifactHasSchemaWarnings[artifact]` | artifact に SchemaWarnings キーが存在することを検証します（ClaudeOrchestrator 向け）。 |
| `$ClaudeTestKitVersion` | ロードされているパッケージのバージョン文字列。 |

---

### ドキュメント一覧

| ファイル | 内容 |
|---|---|
| `setup.md` | インストール手順・動作確認・トラブルシューティング |
| `api.md` | 全パブリック関数の API リファレンス |
| `user_manual.md` | 機能カテゴリ別のユーザーマニュアル |
| `example.md` | 実際のテストシナリオの使用例集 |

---

## 使用例・デモ

### 例 1: Deny シナリオの検証

禁止 head（`DeleteFile` 等）が確実に拒否されることを確認します。

```mathematica
denyAdapter = CreateMockAdapter[
  "Provider"   -> CreateMockProvider[{
    "```mathematica\nDeleteFile[\"/etc/passwd\"]\n```"
  }],
  "DenyHeads"  -> {DeleteFile, RunProcess}
];
result = RunClaudeScenario[<|
  "Name"   -> "危険操作 deny テスト",
  "Input"  -> "ファイルを削除して",
  "Adapter" -> denyAdapter
|>];
AssertValidationDenied[result["Trace"]]
(* True *)
```

### 例 2: 秘密漏洩チェック

Trace に API キー等の機密文字列が含まれていないことを検証します。

```mathematica
AssertNoSecretLeak[result["Trace"], {"sk-ant-api03-xxxx", "password123"}]
(* True *)
```

### 例 3: トレースの正規化（ゴールデン比較）

```mathematica
rawTrace  = RunClaudeScenario[<|
  "Name"    -> "正規化テスト",
  "Input"   -> "何かして",
  "Adapter" -> adapter
|>]["Trace"];
normalized = NormalizeClaudeTrace[rawTrace];
normalized[[1, "Type"]]
(* "SessionStart" *)
```

### 例 4: イベント列の検証

```mathematica
AssertEventSequence[
  result["Trace"],
  {"SessionStart", "ProviderRequest", "ValidationResult", "SessionEnd"}
]
(* True *)
```

### 例 5: トランザクション Adapter の使用

```mathematica
txAdapter = CreateMockTransactionAdapter[
  "Provider"      -> CreateMockProvider[{"CommitTransaction[]"}],
  "AllowedHeads"  -> {CommitTransaction},
  "FailAtPhase"   -> "StaticCheck",
  "FailCount"     -> 1
];
```

最初の `StaticCheck` フェーズのみ失敗し、以降は成功するアダプターが作成されます。ロールバック動作のテストに使用できます。

### 例 6: ClaudeOrchestrator のオーケストレーションシナリオ

ClaudeOrchestrator のマルチエージェントフロー全体を Mock で検証します。

```mathematica
(* Planner が 2 タスクを生成し、各 Worker が独立して処理するシナリオ *)
orchestrationResult = RunClaudeOrchestrationScenario[<|
  "Planner" -> CreateMockPlanner[<|
    "Tasks" -> {
      <|"TaskId" -> "t1", "Goal" -> "セル1を分析する",
        "OutputSchema" -> "分析結果の文字列"|>,
      <|"TaskId" -> "t2", "Goal" -> "セル2を要約する",
        "OutputSchema" -> "要約文字列", "DependsOn" -> {"t1"}|>
    }
  |>],
  "WorkerAdapterBuilder" -> Function[{role, task, deps},
    CreateMockWorkerAdapter[role, task, deps,
      "Response"       -> "処理完了",
      "ArtifactPayload" -> <|"Result" -> "分析済み"|>
    ]
  ],
  "Reducer"               -> CreateMockReducer[<|"FinalOutput" -> "統合完了"|>],
  "CommitterAdapterBuilder" -> Function[nb, CreateMockCommitter[nb, <||>]],
  "Input"           -> "ノートブックを分析して要約せよ",
  "TargetNotebook"  -> None,
  "Assertions"      -> {
    AssertNoWorkerNotebookMutation,
    AssertSingleCommitterWrites,
    AssertArtifactsRespectDependencies[#, tasksSpec] &
  }
|>];

orchestrationResult["AllPassed"]
(* True *)
```

### 例 7: Reducer 決定論性の検証

```mathematica
mockReducer = CreateMockReducer[<|"Summary" -> "決定論的な結果"|>];
AssertReducerDeterministic[mockReducer, {artifact1, artifact2}]
(* True *)
```

---

## 免責事項

本ソフトウェアは "as is"（現状有姿）で提供されており、明示・黙示を問わずいかなる保証もありません。
本ソフトウェアの使用または使用不能から生じるいかなる損害についても責任を負いません。
今後の動作保証のための更新が行われるとは限りません。
本ソフトウェアとドキュメントはほぼすべてが生成AIによって生成されたものです。
Windows 11上での実行を想定しており、MacOS, LinuxのMathematicaでの動作検証は一切していません(生成AIの処理で対応可能と想定されます)。

---

## ライセンス

```
MIT License

Copyright (c) 2026 Katsunobu Imai

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.