# ClaudeTestKit API リファレンス

パッケージ: `ClaudeTestKit`
リポジトリ: https://github.com/transreal/ClaudeTestKit
ロード方法: `Block[{$CharacterEncoding = "UTF-8"}, Get["ClaudeTestKit.wl"]]`

## 変数

### $ClaudeTestKitVersion
型: String
パッケージバージョン文字列。

### $ClaudeTestScenarios
型: Association
組み込みテストシナリオの Association。`RunAllClaudeTests[]` が内部で参照する。

## Mock 生成

### CreateMockProvider[responses] → Association
固定応答を順番に返す mock provider を作る。
responses: `{"応答1", "応答2", ...}` の文字列リスト。呼び出しごとに順に消費される。
例: `CreateMockProvider[{"NBCellRead[nb, 3]", "Done"}]`

### CreateMockAdapter[opts] → Association
全 adapter 関数の mock 実装を返す。
→ Association (adapter interface を満たす)
Options: "Provider" -> None (CreateMockProvider の返り値), "AllowedHeads" -> {} (許可 head リスト), "DenyHeads" -> {} (拒否 head リスト), "ApprovalHeads" -> {} (承認要求 head リスト), "ExecutionResults" -> {} (実行結果リスト、順に消費), "MaxContinuations" -> Infinity (継続上限)

### CreateMockTransactionAdapter[opts] → Association
transaction 用 mock adapter を返す。オプション構造は `CreateMockAdapter` に準じる。

### CreateMockPlanner[taskSpec] → Function
固定 taskSpec (Association) を返す mock planner を作る。
taskSpec 例: `<|"Tasks" -> {<|"TaskId" -> "t1", "Goal" -> "...", "OutputSchema" -> "..."|>}|>`
例: `CreateMockPlanner[<|"Tasks" -> {<|"TaskId"->"t1", "Goal"->"analyze"|>}|>]`

### CreateMockWorkerAdapter[role, task, depArtifacts, opts] → Association
role 別の mock worker adapter を返す。
Options: "Response" -> "" (worker の固定応答、String または Association), "ProposedHeld" -> None (proposal を強制する HoldComplete[...]), "ArtifactPayload" -> <||> (抽出される payload Association)

### CreateMockReducer[payload] → Function
artifacts 引数を無視して固定 payload を返す mock reducer。

### CreateMockCommitter[targetNotebook, reducedArtifact] → Association
mock committer adapter を返す。実ファイル書き込みはせず、Metadata に commit record を残すだけ。

### CreateMockQueryFunction[responses] → Function
固定応答を順番に返す mock query 関数を作る。LLM planner / worker のテスト用。
responses: 文字列リスト (JSON 文字列を想定)。
例: `CreateMockQueryFunction[{jsonResp1, jsonResp2}]`

## シナリオ実行

### RunClaudeScenario[scenario] → Association
シナリオを実行し結果を返す。
scenario: `<|"Name" -> "テスト名", "Input" -> "入力文字列", "Adapter" -> adapter, "Profile" -> profile, "Assertions" -> {assertFn1, ...}|>`
戻り値 Association のキー: "Name", "Passed", "Trace", "Result", "Errors"

### RunAllClaudeTests[] → Dataset
全組み込みシナリオ (`$ClaudeTestScenarios`) を実行し結果を Dataset で返す。

### RunClaudeOrchestrationScenario[scenario] → Association
オーケストレーションシナリオを実行し結果を返す。
scenario keys: "Planner" (planner 関数), "WorkerAdapterBuilder" (role→adapter 関数), "Reducer" (reducer 関数), "CommitterAdapterBuilder" (→adapter 関数), "Input" (文字列), "TargetNotebook" (NotebookObject または None), "Assertions" ({assertFn1, ...})

## Trace 処理

### NormalizeClaudeTrace[trace] → List
trace からタイムスタンプ・セッション ID 等の可変要素を除去し、golden comparison 可能な形にする。

## Assert 関数

### AssertNoSecretLeak[trace, secrets] → True | Failure
trace 内に秘密文字列が含まれないことを検証する。
secrets: `{"apikey123", "password", ...}`

### AssertValidationDenied[trace] → True | Failure
trace 中に Deny または FatalFailure イベントが存在することを検証する。

### AssertOutcome[trace, expectedOutcome] → True | Failure
最終 outcome が expectedOutcome と一致することを検証する。

### AssertBudgetNotExceeded[runtimeState] → True | Failure
runtimeState 内の全 budget が上限以内であることを検証する。

### AssertEventSequence[trace, expectedTypes] → True | Failure
trace のイベント型列が expectedTypes を部分列として含むことを検証する。
例: `AssertEventSequence[trace, {"ToolCall", "ToolResult", "Done"}]`

### AssertNoWorkerNotebookMutation[orchestrationResult] → True | Failure
worker のいずれも NotebookWrite / CreateNotebook を実行していないことを検証する。

### AssertArtifactsRespectDependencies[orchestrationResult, tasksSpec] → True | Failure
DependsOn の先行 artifact が後続より先に生成されていることを検証する。

### AssertSingleCommitterWrites[orchestrationResult] → True | Failure
notebook 書き込み proposal が committer runtime のみから提案されたことを検証する。

### AssertReducerDeterministic[reducer, artifacts] → True | Failure
同じ artifacts に対して reducer を複数回呼び出し、結果が一致することを検証する。

### AssertNoCrossWorkerStateAssumption[orchestrationResult] → True | Failure
worker proposal 群に他 worker の Mathematica 変数を参照する兆候がないことを検証する。

### AssertTaskOutputMatchesSchema[artifact, outputSchema] → True | Failure
artifact payload が outputSchema を満たすことを検証する (ClaudeValidateArtifact の assertion 版)。

### AssertArtifactHasSchemaWarnings[artifact] → True | Failure
artifact に SchemaWarnings キーが存在することを検証する。

## T05: Committer fallback テスト

### RunT05CommitFallbackTests[] → Association
committer LLM プロンプトと決定論的 fallback の単体テストを実行し、PASS/FAIL サマリを返す。
対象内部関数: iExtractSlidesFromPayload / iCellFromSlideItem / iBuildCommitterHint / iDeterministicSlideCommit (guard)。

### AssertT05SlideExtraction[] → True | Failure
iExtractSlidesFromPayload が代表的な 5 ケース (Slides key / Sections key / reducer-nested list / single-slide assoc / fallback generic assoc) で封等な slide list を返すことを検証する。

### AssertT05CellFromItem[] → True | Failure
iCellFromSlideItem が Title/Body/Code を持つ item を 3 個の `Cell[_,_]` (Title/Text/Input) に展開すること、空 Association も 1 Cell にフォールバックすることを検証する。

### AssertT05CommitHintStructure[] → True | Failure
iBuildCommitterHint が "COMMITTER ROLE"・"NotebookWrite[EvaluationNotebook[], Cell[...]]"・"ReducedArtifact.Payload" の 3 マーカーを全て含むプロンプト的テキストを返すことを検証する。

### AssertT05FallbackGuards[] → True | Failure
iDeterministicSlideCommit が正しくガードすることを検証する: (a) NotebookObject 以外では Status=="NotANotebook"、(b) 空 payload では Status=="NoSlides"、(c) 不正引数では Status=="Failed"。

## T06: slide content-aware extraction テスト

### RunT06SlideContentTests[] → Association
コンテンツベースの slide 検出と SlideDraft/SlideOutline 形式の Cell 展開の単体テストを実行する。

### AssertT06ContentBasedDetection[] → True | Failure
iExtractSlidesFromPayload が SlideOutline/SlideDraft キー (T05 では拾えなかった) や全く無関係なキー名でも slide-like list を正しく拾うことを検証する。

### AssertT06SlideDraftExpansion[] → True | Failure
iCellFromSlideItem が SlideDraft 形式 (`item["Cells"] = {<|"Style"->..., "Content"->...|>, ...}`) を内部 Cell list にそのまま展開することを検証する。

### AssertT06SlideOutlineExpansion[] → True | Failure
iCellFromSlideItem が SlideOutline 形式 (Title + Subtitle + BodyOutline) を適切なスタイルの Cell に展開することを検証する。

## T07: slide intent detection + style sanitization テスト

### RunT07SlideIntentTests[] → Association
slide intent 検出と style sanitization の単体テストを実行する。

### AssertT07StyleSanitization[] → True | Failure
iSanitizeCellStyle が (a) 有効 style はそのまま返す、(b) "Subsection (title slide)" → "Subsection"、(c) "Subsection + Item/Subitem 群" → "Subsection"、(d) 完全に不明なものは "Text" に落とすことを検証する。

### AssertT07SlideIntentDetection[] → True | Failure
iDetectSlideIntent が (a) "30 ページのスライド" → IsSlide=True, PageCount=30、(b) "10-page presentation" → IsSlide=True, PageCount=10、(c) 全角数字 "３０ページ" → 30、(d) slide 無関係の入力 → IsSlide=False を検証する。

### AssertT07InnerCellFromSpecSanitize[] → True | Failure
iInnerCellFromSpec が Style がプロースな文字列 ("Subsection (title slide)" 等) ならば必ず有効な Mathematica cell style 名称に落とすことを検証する。

### AssertT07DefaultPlannerSlideAware[] → True | Failure
iDefaultPlanner が入力に "30 ページのスライド" 等を含む場合、単一 Explore でなく Explore + Draft の 2 タスク分解を返し、Draft の OutputSchema に "SlideDraft" を含むことを検証する。

### AssertT07WorkerPromptSlideHint[] → True | Failure
iWorkerBuildSystemPrompt が slide 必合いの task (Goal/Schema に slide/SlideDraft を含む) に対して "T07 SLIDE-MODE" 印字を含む拡張 prompt を返すことを検証する。

### AssertT07bResolveTargetNotebookLogic[] → True | Failure
iResolveTargetNotebook が (a) slide 意図ありの入力で Intent.IsSlide=True を返す、(b) slide 無関係の入力で Intent.IsSlide=False を返すことを軸に検証する。CreateDocument は実 notebook が必要なため、ヘッドレスでは None に fallback するケースはここでは検証しない。