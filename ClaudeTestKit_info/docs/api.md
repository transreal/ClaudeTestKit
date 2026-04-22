# ClaudeTestKit API Reference
パッケージ: ClaudeTestKit
バージョン変数: `$ClaudeTestKitVersion`
GitHub: https://github.com/transreal/ClaudeTestKit
依存: ClaudeRuntime, ClaudeOrchestrator, NBAccess

## 変数

### $ClaudeTestKitVersion
型: String
パッケージバージョン文字列。

### $ClaudeTestScenarios
型: Association
組み込みテストシナリオのAssociation。`RunAllClaudeTests[]`が参照する。

## Mock生成

### CreateMockProvider[responses]
固定応答リストを順番に返すmock providerを生成する。
→ Association (provider object)
`responses`: 文字列リスト `{resp1, resp2, ...}`
例: `CreateMockProvider[{"NBCellRead[nb, 3]", "Done"}]`

### CreateMockAdapter[opts]
全adapter関数のmock実装を返す。
→ Association (adapter object)
Options: "Provider" -> None (CreateMockProviderの返り値), "AllowedHeads" -> {} (許可するHead一覧), "DenyHeads" -> {} (拒否するHead一覧), "ApprovalHeads" -> {} (承認が必要なHead一覧), "ExecutionResults" -> {} (実行結果リスト), "MaxContinuations" -> Infinity (最大継続回数)

### CreateMockTransactionAdapter[opts]
トランザクション用mock adapterを返す。
→ Association (adapter object)
`opts`: CreateMockAdapterと同様のオプションを受け付ける。

### CreateMockPlanner[taskSpec]
固定taskSpec(Association)を返すmock plannerを生成する。
→ Association (planner function)
例: `CreateMockPlanner[<|"Tasks" -> {<|"TaskId" -> "t1", "Goal" -> "...", "OutputSchema" -> {}|>}|>]`

### CreateMockWorkerAdapter[role, task, depArtifacts, opts]
role別のmock worker adapterを返す。
→ Association (worker adapter)
Options: "Response" -> "" (workerの固定応答 String|Association), "ProposedHeld" -> None (強制するHoldComplete[...] proposal), "ArtifactPayload" -> <||> (抽出されるpayload)

### CreateMockReducer[payload]
artifactsを無視して固定payloadを返すmock reducerを生成する。
→ Function

### CreateMockCommitter[targetNotebook, reducedArtifact]
実ファイル書き込みをせずMetadataにcommit recordを残すmock committer adapterを返す。
→ Association (committer adapter)

### CreateMockQueryFunction[responses]
固定応答を順番に返すmock query関数を生成する。LLM planner/workerのテスト用。
→ Function
`responses`: 文字列リスト(JSON応答)
例: `CreateMockQueryFunction[{jsonResp1, jsonResp2}]`

## シナリオ実行

### RunClaudeScenario[scenario]
シナリオを実行し結果を返す。
→ Association (実行結果)
`scenario`: `<|"Name" -> String, "Input" -> String, "Adapter" -> adapter, "Profile" -> String, "Assertions" -> {fn1, ...}|>`

### RunClaudeOrchestrationScenario[scenario]
ClaudeOrchestratorシナリオを実行し結果を返す。
→ Association (実行結果)
`scenario` keys: "Planner", "WorkerAdapterBuilder", "Reducer", "CommitterAdapterBuilder", "Input", "TargetNotebook", "Assertions" (関数リスト)

### RunAllClaudeTests[]
全組み込みシナリオを実行し結果をDatasetで返す。
→ Dataset

## Trace/結果アサーション

### NormalizeClaudeTrace[trace]
traceからタイムスタンプ・ID等を除去しgolden comparison可能な形にする。
→ List

### AssertNoSecretLeak[trace, secrets]
trace内に秘密文字列が含まれないことを検証する。
→ True | Failure
`secrets`: `{"apikey123", "password", ...}`

### AssertValidationDenied[trace]
trace中にDenyまたはFatalFailureが存在することを検証する。
→ True | Failure

### AssertOutcome[trace, expectedOutcome]
最終outcomeが期待値と一致することを検証する。
→ True | Failure

### AssertBudgetNotExceeded[runtimeState]
全budgetが上限以内であることを検証する。
→ True | Failure

### AssertEventSequence[trace, expectedTypes]
traceのイベント型列が期待する部分列を含むことを検証する。
→ True | Failure

## Orchestrationアサーション

### AssertNoWorkerNotebookMutation[orchestrationResult]
workerのいずれもNotebookWrite/CreateNotebookを実行していないことを検証する。
→ True | Failure

### AssertArtifactsRespectDependencies[orchestrationResult, tasksSpec]
DependsOnの先行artifactが存在する順序でartifactが生成されたことを検証する。
→ True | Failure

### AssertSingleCommitterWrites[orchestrationResult]
notebook書き込みproposalがcommitter runtimeのみから提案されたことを検証する。
→ True | Failure

### AssertReducerDeterministic[reducer, artifacts]
同じartifactsに対してreducerが複数回同じ結果を返すことを検証する。
→ True | Failure

### AssertNoCrossWorkerStateAssumption[orchestrationResult]
worker proposal群の中に他workerのMathematica変数を参照する兆候がないことを検証する。
→ True | Failure

### AssertTaskOutputMatchesSchema[artifact, outputSchema]
artifact payloadがOutputSchemaを満たすことを検証する(ClaudeValidateArtifactのassertion版)。
→ True | Failure

### AssertArtifactHasSchemaWarnings[artifact]
artifactにSchemaWarningsキーが存在することを検証する。
→ True | Failure

## T05: Committer Fallback テスト

### RunT05CommitFallbackTests[]
T05で追加したcommitter LLMプロンプトと決定論fallbackの単体テストを実行しPASS/FAILサマリを返す。
→ Association
対象内部関数: `iExtractSlidesFromPayload`, `iCellFromSlideItem`, `iBuildCommitterHint`, `iDeterministicSlideCommit`

### AssertT05SlideExtraction[]
`iExtractSlidesFromPayload`が5代表ケース(Slides key / Sections key / reducer-nested list / single-slide assoc / fallback generic assoc)で封等なslide listを返すことを検証する。
→ True | Failure

### AssertT05CellFromItem[]
`iCellFromSlideItem`がTitle/Body/Codeを持つitemを3個のCell[_,_](Title/Text/Input)に展開すること、空AssociationでもCell 1個にフォールバックすることを検証する。
→ True | Failure

### AssertT05CommitHintStructure[]
`iBuildCommitterHint`が"COMMITTER ROLE"・"NotebookWrite[EvaluationNotebook[], Cell[...]]"・"ReducedArtifact.Payload"の3マーカーを全て含むプロンプト的テキストを返すことを検証する。
→ True | Failure

### AssertT05FallbackGuards[]
`iDeterministicSlideCommit`が(a)NotebookObject以外でStatus=="NotANotebook"、(b)空payloadでStatus=="NoSlides"、(c)不正引数でStatus=="Failed"を返すことを検証する。
→ True | Failure

## T06: Slide Content-Aware Extraction テスト

### RunT06SlideContentTests[]
T06で追加したコンテンツベースのslide検出とSlideDraft/SlideOutline形式のCell展開を単体テストする。
→ Association

### AssertT06ContentBasedDetection[]
`iExtractSlidesFromPayload`がSlideOutline/SlideDraftキー(T05では拾えなかった)や無関係なキー名でもslide-like listを正しく拾うことを検証する。
→ True | Failure

### AssertT06SlideDraftExpansion[]
`iCellFromSlideItem`がSlideDraft形式(item["Cells"] = {<|"Style"->..., "Content"->...|>, ...})を内部Cell listにそのまま展開することを検証する。
→ True | Failure

### AssertT06SlideOutlineExpansion[]
`iCellFromSlideItem`がSlideOutline形式(Title + Subtitle + BodyOutline)を適切なスタイルのCellに展開することを検証する。
→ True | Failure

## T07: Slide Intent Detection + Style Sanitization テスト

### RunT07SlideIntentTests[]
T07で追加したslide intent検出とstyle sanitizationの単体テストを実行する。
→ Association

### AssertT07StyleSanitization[]
`iSanitizeCellStyle`が(a)有効styleはそのまま返す、(b)"Subsection (title slide)"→"Subsection"、(c)"Subsection + Item/Subitem 群"→"Subsection"、(d)完全不明→"Text"に落とすことを検証する。
→ True | Failure

### AssertT07SlideIntentDetection[]
`iDetectSlideIntent`が(a)"30ページのスライド"をIsSlide=True・PageCount=30、(b)"10-page presentation"をIsSlide=True・PageCount=10、(c)全角数字"３０ページ"を30と認識、(d)slide無関係入力はIsSlide=Falseを返すことを検証する。
→ True | Failure

### AssertT07InnerCellFromSpecSanitize[]
`iInnerCellFromSpec`がStyleがプローズ("Subsection (title slide)"等)のとき必ず有効なMathematica cell style名に落とすことを検証する。
→ True | Failure

### AssertT07DefaultPlannerSlideAware[]
`iDefaultPlanner`が入力に"30ページのスライド"等を含む場合、単一ExploreではなくExplore+Draftの2タスク分解を返し、DraftのOutputSchemaに"SlideDraft"を含むことを検証する。
→ True | Failure

### AssertT07WorkerPromptSlideHint[]
`iWorkerBuildSystemPrompt`がslide必合いのtask(Goal/Schemaにslide/SlideDraftを含む)に対して"T07 SLIDE-MODE"印字を含む拡張promptを返すことを検証する。
→ True | Failure

### AssertT07bResolveTargetNotebookLogic[]
`iResolveTargetNotebook`が(a)slide意図ありの入力でIntent.IsSlide=True、(b)slide無関係の入力でIntent.IsSlide=Falseを返すことを検証する。ヘッドレス環境ではCreateDocumentがNoneにfallbackするケースはここでは検証しない。
→ True | Failure

## Phase 32 Task 3.1: Committer 自然言語 Input 流入防止テスト

### RunPhase32Task31Tests[]
Phase 32 Task 3.1(CommitterがCell["自然言語","Input"]を書き込まない)の単体テストを実行しPASS/FAILサマリを返す。
→ Association
対象内部関数: `iValidateWorkerProposal`(role="Commit"), `iIsPlausibleInputCellContent`, `iHeldExprInputCellStrings`

### AssertPhase32Task31RejectsNaturalLangInput[]
`iValidateWorkerProposal`にHoldComplete[NotebookWrite[nb, Cell["日本語文","Input"]]]をrole="Commit"で投入し、Decision=="Deny"かつReasonClass=="NaturalLanguageInInputCell"、OffendingStringsが非空なことを検証する。
→ True | Failure

### AssertPhase32Task31AcceptsMathExprInInputCell[]
`iValidateWorkerProposal`にHoldComplete[NotebookWrite[nb, Cell["Plot[Sin[x], {x, 0, 2 Pi}]","Input"]]]をrole="Commit"で投入し、Decision=="Permit"かつReasonClass=="OK"を検証する。
→ True | Failure

### AssertPhase32Task31AcceptsNaturalLangInTextCell[]
`iValidateWorkerProposal`にHoldComplete[NotebookWrite[nb, Cell["日本語文","Text"]]]をrole="Commit"で投入し、Decision=="Permit"を検証する("Text"は検査対象外)。
→ True | Failure

## Phase 32 Task 3.2: Auto ゲート強化テスト

### RunPhase32Task32Tests[]
Phase 32 Task 3.2(AutoモードでShort factual queryをSingleにfallback、複雑タスクはOrchestratorに通す)の単体テストを実行しPASS/FAILサマリを返す。
→ Association
対象内部関数: `iIsShortFactualQuery`, `iHasComplexTaskMarker`

### AssertPhase32Task32SkipsShortFactualJa[]
短い日本語factual query("$packageDirectoryのclaudecode…を調べて")に対し`iIsShortFactualQuery`=True、`iHasComplexTaskMarker`=Falseを検証する。
→ True | Failure

### AssertPhase32Task32SkipsShortFactualEn[]
短い英語factual query("Check if claudecode.wl is newer than its GitHub version")に対し`iIsShortFactualQuery`=Trueを検証する。
→ True | Failure

### AssertPhase32Task32KeepsLongComplex[]
600文字かつ複数の順序接続語を含む長いマルチステップタスクに対し`iHasComplexTaskMarker`=True、`iIsShortFactualQuery`=FalseでOrchestratorルートを維持することを検証する。
→ True | Failure

### AssertPhase32Task32KeepsSlideRequest[]
成果物要求("30ページのスライドを作って")に対し`iHasComplexTaskMarker`=Trueを検証する。
→ True | Failure

### AssertPhase32Task32KeepsSequentialTask[]
順序接続語が2個以上("まず…次に…最後に…")あるタスクに対し`iHasComplexTaskMarker`=Trueを検証する。
→ True | Failure