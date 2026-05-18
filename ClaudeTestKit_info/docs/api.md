# ClaudeTestKit API リファレンス

## バージョン
### $ClaudeTestKitVersion
型: String
パッケージバージョン。

## Mock 構築 (基礎)
### CreateMockProvider[responses] → MockProvider
固定応答 `{response1, response2, ...}` を順番に返す mock provider を作る。

### CreateMockAdapter[opts] → MockAdapter
全 adapter 関数の mock 実装を返す。
→ Association
Options: "Provider" -> None (CreateMockProvider の返り値), "AllowedHeads" -> {} (許可 head リスト), "DenyHeads" -> {} (拒否 head リスト), "ApprovalHeads" -> {} (承認必要 head), "ExecutionResults" -> {} (実行結果列), "MaxContinuations" -> None (継続上限)

### CreateMockTransactionAdapter[opts] → MockAdapter
transaction 用 mock adapter を返す。

### CreateMockQueryFunction[responses] → Function
固定応答を順番に返す mock query 関数を作る。LLM planner / worker のテスト用。responses は文字列リスト。
例: CreateMockQueryFunction[{jsonResponse1, jsonResponse2}]

## シナリオ実行
### RunClaudeScenario[scenario] → Association
シナリオを実行し結果を返す。scenario keys: "Name", "Input", "Adapter", "Profile", "Assertions"。

### RunAllClaudeTests[] → Dataset
全組み込みシナリオを実行し結果を Dataset で返す。

### $ClaudeTestScenarios
型: Association
組み込みテストシナリオの Association。

## Trace 正規化
### NormalizeClaudeTrace[trace] → Trace
trace からタイムスタンプ・ID 等を除去し golden comparison 可能な形にする。

## 基本 Assertions
### AssertNoSecretLeak[trace, secrets] → Bool
trace 内に秘密文字列 `{"apikey123", "password", ...}` が含まれないことを検証。

### AssertValidationDenied[trace] → Bool
trace 中に Deny または FatalFailure が存在することを検証。

### AssertOutcome[trace, expectedOutcome] → Bool
最終 outcome が期待値と一致することを検証。

### AssertBudgetNotExceeded[runtimeState] → Bool
全 budget が上限以内であることを検証。

### AssertEventSequence[trace, expectedTypes] → Bool
trace のイベント型列が期待する部分列を含むことを検証。

## Orchestrator 連携 Mock (spec §13)
### CreateMockPlanner[taskSpec] → MockPlanner
固定 taskSpec (Association) を返す mock planner。
例: CreateMockPlanner[<|"Tasks" -> {<|"TaskId"->"t1", ...|>}|>]

### CreateMockWorkerAdapter[role, task, depArtifacts, opts] → MockAdapter
role 別の mock worker adapter を返す。
→ Association
Options: "Response" -> Null (String | Association: worker 固定応答), "ProposedHeld" -> Null (HoldComplete[...] で proposal 強制), "ArtifactPayload" -> <||> (抽出される payload Association)

### CreateMockReducer[payload] → MockReducer
artifacts を無視して固定 payload を返す mock reducer。

### CreateMockCommitter[targetNotebook, reducedArtifact] → MockAdapter
mock committer adapter。実ファイル書き込みはせず Metadata に commit record を残すだけ。

### RunClaudeOrchestrationScenario[scenario] → Association
orchestration シナリオを実行し結果を返す。
scenario keys: "Planner", "WorkerAdapterBuilder", "Reducer", "CommitterAdapterBuilder", "Input", "TargetNotebook", "Assertions" (関数リスト)

## Orchestrator 用 Assertions
### AssertNoWorkerNotebookMutation[orchestrationResult] → Bool
いずれの worker も NotebookWrite / CreateNotebook を実行していないことを検証。

### AssertArtifactsRespectDependencies[orchestrationResult, tasksSpec] → Bool
DependsOn の先行 artifact が存在する順序で artifact が生成されたことを検証。

### AssertSingleCommitterWrites[orchestrationResult] → Bool
notebook 書き込み proposal が committer runtime のみから提案されたことを検証。

### AssertReducerDeterministic[reducer, artifacts] → Bool
同じ artifacts に対して reducer が複数回同じ結果を返すことを検証。

### AssertNoCrossWorkerStateAssumption[orchestrationResult] → Bool
worker proposal 群に「他 worker の Mathematica 変数」を参照する兆候がないことを検証。

### AssertTaskOutputMatchesSchema[artifact, outputSchema] → Bool
artifact payload が OutputSchema を満たすことを検証 (ClaudeValidateArtifact の assertion 版)。

### AssertArtifactHasSchemaWarnings[artifact] → Bool
artifact に SchemaWarnings キーが存在することを検証。

## T05: Committer fallback テスト (Phase 33)
### RunT05CommitFallbackTests[] → Association
T05 で追加した committer LLM プロンプトと決定論 fallback の単体テストを実行し PASS/FAIL サマリを返す。対象: iExtractSlidesFromPayload / iCellFromSlideItem / iBuildCommitterHint / iDeterministicSlideCommit (guard)。

### AssertT05SlideExtraction[] → Bool
iExtractSlidesFromPayload が代表的な 5 ケース (Slides key / Sections key / reducer-nested list / single-slide assoc / fallback generic assoc) で封等な slide list を返すことを検証。

### AssertT05CellFromItem[] → Bool
iCellFromSlideItem が Title/Body/Code を持つ item を 3 個の Cell[_,_] (Title/Text/Input) に展開し、空 Association も 1 Cell にフォールバックすることを検証。

### AssertT05CommitHintStructure[] → Bool
iBuildCommitterHint が「COMMITTER ROLE」「NotebookWrite[EvaluationNotebook[], Cell[...]]」「ReducedArtifact.Payload」の 3 マーカーを全て含むプロンプトを返すことを検証。

### AssertT05FallbackGuards[] → Bool
iDeterministicSlideCommit のガード検証:
(a) NotebookObject 以外で Status=="NotANotebook"
(b) 空 payload で Status=="NoSlides"
(c) 不正引数で Status=="Failed"

## T06: slide content-aware extraction テスト (Phase 33)
### RunT06SlideContentTests[] → Association
T06 で追加したコンテンツベースの slide 検出と SlideDraft/SlideOutline 形式の Cell 展開を単体テストする。

### AssertT06ContentBasedDetection[] → Bool
iExtractSlidesFromPayload が SlideOutline/SlideDraft キー (T05 では拾えなかった) や全く無関係なキー名でも slide-like list を正しく拾うことを検証。

### AssertT06SlideDraftExpansion[] → Bool
iCellFromSlideItem が SlideDraft 形式 (item["Cells"] = {<|"Style"->..., "Content"->...|>, ...}) を内部 Cell list にそのまま展開することを検証。

### AssertT06SlideOutlineExpansion[] → Bool
iCellFromSlideItem が SlideOutline 形式 (Title + Subtitle + BodyOutline) を適切なスタイルの Cell に展開することを検証。

## T07: slide intent + style sanitization テスト (Phase 33)
### RunT07SlideIntentTests[] → Association
T07 で追加した slide intent 検出と style sanitization の単体テストを実行する。

### AssertT07StyleSanitization[] → Bool
iSanitizeCellStyle の検証:
(a) 有効 style はそのまま返す
(b) "Subsection (title slide)" → "Subsection"
(c) "Subsection + Item/Subitem 群" → "Subsection"
(d) 完全に不明なものは "Text" に落とす

### AssertT07SlideIntentDetection[] → Bool
iDetectSlideIntent の検証:
(a) "30 ページのスライド" → IsSlide=True, PageCount=30
(b) "10-page presentation" → IsSlide=True, PageCount=10
(c) 全角数字 "３０ページ" も 30
(d) slide 無関係入力は IsSlide=False

### AssertT07InnerCellFromSpecSanitize[] → Bool
iInnerCellFromSpec が Style がプローズ ("Subsection (title slide)" 等) なら必ず有効な Mathematica cell style 名称に落とすことを検証。

### AssertT07DefaultPlannerSlideAware[] → Bool
iDefaultPlanner が入力に「30 ページのスライド」等が含まれる場合、単一 Explore ではなく Explore + Draft の 2 タスク分解を返し、Draft の OutputSchema に "SlideDraft" を含むことを検証。

### AssertT07WorkerPromptSlideHint[] → Bool
iWorkerBuildSystemPrompt が slide 必合いの task (Goal/Schema に slide/SlideDraft を含む) に対して "T07 SLIDE-MODE" 印字を含む拡張 prompt を返すことを検証。

### AssertT07bResolveTargetNotebookLogic[] → Bool
iResolveTargetNotebook の検証:
(a) slide 意図あり入力で Intent.IsSlide=True を返す
(b) slide 無関係入力で Intent.IsSlide=False を返す
(CreateDocument は実 notebook が必要なため、ヘッドレス時に None fallback するケースはここでは検証しない)

## Phase 32 Task 3.1: Committer 自然言語 Input 流入防止 テスト
### RunPhase32Task31Tests[] → Association
Phase 32 Task 3.1 (Committer が Cell["自然言語", "Input"] を書き込まない) の単体テストを実行し PASS/FAIL サマリを返す。対象: iValidateWorkerProposal (role="Commit") + iIsPlausibleInputCellContent + iHeldExprInputCellStrings。

### AssertPhase32Task31RejectsNaturalLangInput[] → Bool
HoldComplete[NotebookWrite[nb, Cell["日本語文", "Input"]]] を role="Commit" で投入し、Decision == "Deny" かつ ReasonClass == "NaturalLanguageInInputCell"、OffendingStrings が空でないことを検証。

### AssertPhase32Task31AcceptsMathExprInInputCell[] → Bool
HoldComplete[NotebookWrite[nb, Cell["Plot[Sin[x], {x, 0, 2 Pi}]", "Input"]]] を role="Commit" で投入し、Decision == "Permit" かつ ReasonClass == "OK" を検証。

### AssertPhase32Task31AcceptsNaturalLangInTextCell[] → Bool
HoldComplete[NotebookWrite[nb, Cell["日本語文", "Text"]]] を role="Commit" で投入し、Decision == "Permit" を検証 ("Text" は検査対象外)。

## Phase 32 Task 3.2: Auto ゲート強化 テスト
### RunPhase32Task32Tests[] → Association
Phase 32 Task 3.2 (Auto モードで短い factual query を Single にフォールバック、複雑タスクは Orchestrator に通す) の単体テストを実行し PASS/FAIL サマリを返す。対象: iIsShortFactualQuery + iHasComplexTaskMarker。

### AssertPhase32Task32SkipsShortFactualJa[] → Bool
短い日本語 factual query ("$packageDirectoryのclaudecode…を調べて") に対し iIsShortFactualQuery=True、iHasComplexTaskMarker=False を返すことを検証。

### AssertPhase32Task32SkipsShortFactualEn[] → Bool
短い英語 factual query ("Check if claudecode.wl is newer than its GitHub version") に対し iIsShortFactualQuery=True を返すことを検証。

### AssertPhase32Task32KeepsLongComplex[] → Bool
長いマルチステップタスク (600 文字かつ複数の順序接続語含む) に対し iHasComplexTaskMarker=True、iIsShortFactualQuery=False を返し Orchestrator 経路を維持することを検証。

### AssertPhase32Task32KeepsSlideRequest[] → Bool
スライド・レポート等の成果物要求 ("30ページのスライドを作って") に対し iHasComplexTaskMarker=True を返すことを検証。

### AssertPhase32Task32KeepsSequentialTask[] → Bool
順序接続語が 2 個以上 (「まず…次に…最後に…」) あるタスクが iHasComplexTaskMarker=True を返すことを検証。

## 関連パッケージ
- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime)
- [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator)
- [NBAccess](https://github.com/transreal/NBAccess)
- [claudecode](https://github.com/transreal/claudecode)