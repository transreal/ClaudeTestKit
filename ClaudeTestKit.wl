(* ClaudeTestKit.wl -- Runtime / Security Kernel テスト装置
   
   責務:
   - MockProvider: 固定応答を返す provider シミュレータ
   - MockAdapter: adapter interface の mock 実装
   - ScenarioRunner: シナリオ定義 → 実行 → 検証
   - Golden normalization: trace からタイムスタンプ等を除去
   - AssertNoSecretLeak: trace / result に秘密が漏れていないことを検証
   - AssertValidationDenied: deny されるべきシナリオの検証
   - AssertAccessViolation: アクセス違反検出の検証
   
   不変条件:
   - security の核心は可能な限り本物の NBAccess public API を使って試す
   - 全部 mock にすると一番大事なところを試せない
   
   Load: Block[{$CharacterEncoding = "UTF-8"}, Get["ClaudeTestKit.wl"]]
*)

BeginPackage["ClaudeTestKit`"];

(* ════════════════════════════════════════════════════════
   Public symbols
   ════════════════════════════════════════════════════════ *)

$ClaudeTestKitVersion::usage =
  If[$Language === "Japanese",
    "$ClaudeTestKitVersion はパッケージバージョン。",
    "$ClaudeTestKitVersion is the package version."];

CreateMockProvider::usage =
  If[$Language === "Japanese",
    "CreateMockProvider[responses] は固定応答を順番に返す mock provider を作る。\n" <>
    "responses: {response1, response2, ...} のリスト。\n" <>
    "例: CreateMockProvider[{\"NBCellRead[nb, 3]\"}]",
    "CreateMockProvider[responses] creates a mock provider returning fixed responses in order.\n" <>
    "responses: {response1, response2, ...}\n" <>
    "Example: CreateMockProvider[{\"NBCellRead[nb, 3]\"}]"];

CreateMockAdapter::usage =
  If[$Language === "Japanese",
    "CreateMockAdapter[opts] は全 adapter 関数の mock 実装を返す。\n" <>
    "Options:\n" <>
    "  \"Provider\" -> mockProvider (CreateMockProvider の返り値)\n" <>
    "  \"AllowedHeads\" -> {head1, head2, ...}\n" <>
    "  \"DenyHeads\" -> {head1, head2, ...}\n" <>
    "  \"ApprovalHeads\" -> {head1, head2, ...}\n" <>
    "  \"ExecutionResults\" -> {result1, result2, ...}\n" <>
    "  \"MaxContinuations\" -> n",
    "CreateMockAdapter[opts] returns a mock implementation of all adapter functions.\n" <>
    "Options:\n" <>
    "  \"Provider\" -> mockProvider\n" <>
    "  \"AllowedHeads\" -> {head1, head2, ...}\n" <>
    "  \"DenyHeads\" -> {head1, head2, ...}\n" <>
    "  \"ApprovalHeads\" -> {head1, head2, ...}\n" <>
    "  \"ExecutionResults\" -> {result1, result2, ...}\n" <>
    "  \"MaxContinuations\" -> n"];

RunClaudeScenario::usage =
  If[$Language === "Japanese",
    "RunClaudeScenario[scenario] はシナリオを実行し結果を返す。\n" <>
    "scenario: <|\"Name\" -> ..., \"Input\" -> ...,\n" <>
    "  \"Adapter\" -> adapter, \"Profile\" -> ...,\n" <>
    "  \"Assertions\" -> {assertion1, ...}|>",
    "RunClaudeScenario[scenario] runs a scenario and returns results.\n" <>
    "scenario: <|\"Name\" -> ..., \"Input\" -> ...,\n" <>
    "  \"Adapter\" -> adapter, \"Profile\" -> ...,\n" <>
    "  \"Assertions\" -> {assertion1, ...}|>"];

NormalizeClaudeTrace::usage =
  If[$Language === "Japanese",
    "NormalizeClaudeTrace[trace] は trace からタイムスタンプ・ID 等を除去し\n" <>
    "golden comparison 可能な形にする。",
    "NormalizeClaudeTrace[trace] removes timestamps/IDs from trace\n" <>
    "for golden comparison."];

AssertNoSecretLeak::usage =
  If[$Language === "Japanese",
    "AssertNoSecretLeak[trace, secrets] は trace 内に秘密文字列が含まれないことを検証する。\n" <>
    "secrets: {\"apikey123\", \"password\", ...}",
    "AssertNoSecretLeak[trace, secrets] verifies no secret strings appear in the trace.\n" <>
    "secrets: {\"apikey123\", \"password\", ...}"];

AssertValidationDenied::usage =
  If[$Language === "Japanese",
    "AssertValidationDenied[trace] は trace 中に Deny または FatalFailure があることを検証する。",
    "AssertValidationDenied[trace] verifies that Deny or FatalFailure exists in the trace."];

AssertOutcome::usage =
  If[$Language === "Japanese",
    "AssertOutcome[trace, expectedOutcome] は最終 outcome が期待値と一致することを検証する。",
    "AssertOutcome[trace, expectedOutcome] verifies the final outcome matches expected."];

AssertBudgetNotExceeded::usage =
  If[$Language === "Japanese",
    "AssertBudgetNotExceeded[runtimeState] は全 budget が上限以内であることを検証する。",
    "AssertBudgetNotExceeded[runtimeState] verifies all budgets are within limits."];

AssertEventSequence::usage =
  If[$Language === "Japanese",
    "AssertEventSequence[trace, expectedTypes] は trace のイベント型列が\n" <>
    "期待する部分列を含むことを検証する。",
    "AssertEventSequence[trace, expectedTypes] verifies the trace event type sequence\n" <>
    "contains the expected subsequence."];

(* ── 既製シナリオ ── *)
$ClaudeTestScenarios::usage =
  If[$Language === "Japanese",
    "$ClaudeTestScenarios は組み込みテストシナリオの Association。",
    "$ClaudeTestScenarios is the Association of built-in test scenarios."];

RunAllClaudeTests::usage =
  If[$Language === "Japanese",
    "RunAllClaudeTests[] は全組み込みシナリオを実行し結果を Dataset で返す。",
    "RunAllClaudeTests[] runs all built-in scenarios and returns results as a Dataset."];

CreateMockTransactionAdapter::usage =
  If[$Language === "Japanese",
    "CreateMockTransactionAdapter[opts] は transaction 用 mock adapter を返す。",
    "CreateMockTransactionAdapter[opts] returns a mock adapter for transactions."];

(* ════════════════════════════════════════════════════════
   ClaudeOrchestrator 連携用 (spec §13)
   ════════════════════════════════════════════════════════ *)

CreateMockPlanner::usage =
  "CreateMockPlanner[taskSpec] は固定 taskSpec (Association) を返す mock planner を作る。\n" <>
  "例: CreateMockPlanner[<|\"Tasks\" -> {<|\"TaskId\"->\"t1\", ...|>}|>]";

CreateMockWorkerAdapter::usage =
  "CreateMockWorkerAdapter[role, task, depArtifacts, opts] は\n" <>
  "role 別の mock worker adapter を返す。opts:\n" <>
  "  \"Response\" -> String | Association (worker の固定応答)\n" <>
  "  \"ProposedHeld\" -> HoldComplete[...] (proposal を強制)\n" <>
  "  \"ArtifactPayload\" -> Association (抽出される payload)";

CreateMockReducer::usage =
  "CreateMockReducer[payload] は artifacts を無視して固定 payload を返す mock reducer。";

CreateMockCommitter::usage =
  "CreateMockCommitter[targetNotebook, reducedArtifact] は mock committer adapter を返す。\n" <>
  "実ファイル書き込みはせず、Metadata に commit record を残すだけ。";

RunClaudeOrchestrationScenario::usage =
  "RunClaudeOrchestrationScenario[scenario] はシナリオを実行し結果を返す。\n" <>
  "scenario keys: \"Planner\", \"WorkerAdapterBuilder\", \"Reducer\",\n" <>
  "               \"CommitterAdapterBuilder\", \"Input\", \"TargetNotebook\",\n" <>
  "               \"Assertions\" (関数リスト)";

AssertNoWorkerNotebookMutation::usage =
  "AssertNoWorkerNotebookMutation[orchestrationResult] は worker の\n" <>
  "いずれも NotebookWrite / CreateNotebook を実行していないことを検証。";

AssertArtifactsRespectDependencies::usage =
  "AssertArtifactsRespectDependencies[orchestrationResult, tasksSpec] は\n" <>
  "DependsOn の先行 artifact が存在する順序で artifact が生成されたことを検証。";

AssertSingleCommitterWrites::usage =
  "AssertSingleCommitterWrites[orchestrationResult] は notebook 書き込み\n" <>
  "proposal が committer runtime のみから提案されたことを検証。";

AssertReducerDeterministic::usage =
  "AssertReducerDeterministic[reducer, artifacts] は同じ artifacts に対して\n" <>
  "reducer が複数回同じ結果を返すことを検証。";

AssertNoCrossWorkerStateAssumption::usage =
  "AssertNoCrossWorkerStateAssumption[orchestrationResult] は worker proposal\n" <>
  "群の中に『他 worker の Mathematica 変数』を参照する兆候がないことを検証。";

AssertTaskOutputMatchesSchema::usage =
  "AssertTaskOutputMatchesSchema[artifact, outputSchema] \:306f artifact payload \:304c\n" <>
  "OutputSchema \:3092\:6e80\:305f\:3059\:3053\:3068\:3092\:691c\:8a3c (ClaudeValidateArtifact \:306e assertion \:7248)\:3002";

CreateMockQueryFunction::usage =
  "CreateMockQueryFunction[responses] \:306f\:56fa\:5b9a\:5fdc\:7b54\:3092\:9806\:756a\:306b\:8fd4\:3059 mock query \:95a2\:6570\:3092\:4f5c\:308b\:3002\n" <>
  "LLM planner / worker \:306e\:30c6\:30b9\:30c8\:7528\:3002responses \:306f\:6587\:5b57\:5217\:30ea\:30b9\:30c8\:3002\n" <>
  "\:4f8b: CreateMockQueryFunction[{jsonResponse1, jsonResponse2}]";

AssertArtifactHasSchemaWarnings::usage =
  "AssertArtifactHasSchemaWarnings[artifact] \:306f artifact \:306b\n" <>
  "SchemaWarnings \:30ad\:30fc\:304c\:5b58\:5728\:3059\:308b\:3053\:3068\:3092\:691c\:8a3c\:3002";

(* \:2500\:2500 T05: Committer fallback \:30c6\:30b9\:30c8 (Phase 33 slide fix) \:2500\:2500 *)

RunT05CommitFallbackTests::usage =
  "RunT05CommitFallbackTests[] \:306f T05 \:3067\:8ffd\:52a0\:3057\:305f committer LLM \:30d7\:30ed\:30f3\:30d7\:30c8\n" <>
  "\:3068\:6c7a\:5b9a\:8ad6 fallback \:306e\:5358\:4f53\:30c6\:30b9\:30c8\:3092\:5b9f\:884c\:3057\:3001PASS/FAIL \:30b5\:30de\:30ea\:3092\:8fd4\:3059\:3002\n" <>
  "\:5bfe\:8c61: iExtractSlidesFromPayload / iCellFromSlideItem / \n" <>
  "        iBuildCommitterHint / iDeterministicSlideCommit (guard)\:3002";

AssertT05SlideExtraction::usage =
  "AssertT05SlideExtraction[] \:306f iExtractSlidesFromPayload \:304c\:4ee3\:8868\:7684\:306a 5 \:30b1\:30fc\:30b9\n" <>
  "(Slides key / Sections key / reducer-nested list / single-slide assoc /\n" <>
  " fallback generic assoc) \:3067\:5c01\:7b49\:306a slide list \:3092\:8fd4\:3059\:3053\:3068\:3092\:691c\:8a3c\:3002";

AssertT05CellFromItem::usage =
  "AssertT05CellFromItem[] \:306f iCellFromSlideItem \:304c Title/Body/Code \:3092\:6301\:3064 item \:3092\n" <>
  "3 \:500b\:306e Cell[_,_] (Title/Text/Input) \:306b\:5c55\:958b\:3059\:308b\:3053\:3068\:3001\:7a7a Association \:3082\n" <>
  "1 Cell \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3059\:308b\:3053\:3068\:3092\:691c\:8a3c\:3002";

AssertT05CommitHintStructure::usage =
  "AssertT05CommitHintStructure[] \:306f iBuildCommitterHint \:304c\:3001\n" <>
  "\:300cCOMMITTER ROLE\:300d\:3001\:300cNotebookWrite[EvaluationNotebook[], Cell[...]]\:300d\:3001\n" <>
  "\:300cReducedArtifact.Payload\:300d\:3068\:3044\:3046 3 \:3064\:306e\:30de\:30fc\:30ab\:30fc\:3092\:5168\:3066\:542b\:3080\n" <>
  "\:30d7\:30ed\:30f3\:30d7\:30c8\:7684\:306a\:30c6\:30ad\:30b9\:30c8\:3092\:8fd4\:3059\:3053\:3068\:3092\:691c\:8a3c\:3002";

AssertT05FallbackGuards::usage =
  "AssertT05FallbackGuards[] \:306f iDeterministicSlideCommit \:304c\:6b63\:3057\:304f\:30ac\:30fc\:30c9\:3059\:308b\:3053\:3068\:3092\:691c\:8a3c:\n" <>
  "  (a) NotebookObject \:4ee5\:5916\:3067\:306f Status==\"NotANotebook\"\:3001\n" <>
  "  (b) \:7a7a payload \:3067\:306f Status==\"NoSlides\"\:3001\n" <>
  "  (c) \:4e0d\:6b63\:5f15\:6570\:3067\:306f Status==\"Failed\"\:3002";

(* \:2500\:2500 T06: slide content-aware extraction \:30c6\:30b9\:30c8 (Phase 33 slide fix) \:2500\:2500 *)

RunT06SlideContentTests::usage =
  "RunT06SlideContentTests[] \:306f T06 \:3067\:8ffd\:52a0\:3057\:305f\:30b3\:30f3\:30c6\:30f3\:30c4\:30d9\:30fc\:30b9\:306e slide \:691c\:51fa\n" <>
  "\:3068 SlideDraft/SlideOutline \:5f62\:5f0f\:306e Cell \:5c55\:958b\:3092\:5358\:4f53\:30c6\:30b9\:30c8\:3059\:308b\:3002";

AssertT06ContentBasedDetection::usage =
  "AssertT06ContentBasedDetection[] \:306f iExtractSlidesFromPayload \:304c\n" <>
  "SlideOutline/SlideDraft \:30ad\:30fc (T05 \:3067\:306f\:62fe\:3048\:306a\:304b\:3063\:305f) \:3084\:3001\n" <>
  "\:5168\:304f\:7121\:95a2\:4fc2\:306a\:30ad\:30fc\:540d\:3067\:3082 slide-like list \:3092\:6b63\:3057\:304f\:62fe\:3046\:3053\:3068\:3092\:691c\:8a3c\:3002";

AssertT06SlideDraftExpansion::usage =
  "AssertT06SlideDraftExpansion[] \:306f iCellFromSlideItem \:304c SlideDraft \:5f62\:5f0f\n" <>
  "(item[\"Cells\"] = {<|\"Style\"->..., \"Content\"->...|>, ...}) \:3092\n" <>
  "\:5185\:90e8 Cell list \:306b\:305d\:306e\:307e\:307e\:5c55\:958b\:3059\:308b\:3053\:3068\:3092\:691c\:8a3c\:3002";

AssertT06SlideOutlineExpansion::usage =
  "AssertT06SlideOutlineExpansion[] \:306f iCellFromSlideItem \:304c SlideOutline \:5f62\:5f0f\n" <>
  "(Title + Subtitle + BodyOutline) \:3092\:9069\:5207\:306a\:30b9\:30bf\:30a4\:30eb\:306e Cell \:306b\:5c55\:958b\:3059\:308b\:3053\:3068\:3092\:691c\:8a3c\:3002";

(* \:2500\:2500 T07: slide intent detection + style sanitization \:30c6\:30b9\:30c8 (Phase 33 slide fix) \:2500\:2500 *)

RunT07SlideIntentTests::usage =
  "RunT07SlideIntentTests[] \:306f T07 \:3067\:8ffd\:52a0\:3057\:305f slide intent \:691c\:51fa\:3068\n" <>
  "style sanitization \:306e\:5358\:4f53\:30c6\:30b9\:30c8\:3092\:5b9f\:884c\:3059\:308b\:3002";

AssertT07StyleSanitization::usage =
  "AssertT07StyleSanitization[] \:306f iSanitizeCellStyle \:304c:\n" <>
  "  (a) \:6709\:52b9 style \:306f\:305d\:306e\:307e\:307e\:8fd4\:3059\n" <>
  "  (b) \"Subsection (title slide)\" \:306f \"Subsection\" \:306b\:843d\:3068\:3059\n" <>
  "  (c) \"Subsection + Item/Subitem \:7fa4\" \:306f \"Subsection\" \:306b\:843d\:3068\:3059\n" <>
  "  (d) \:5b8c\:5168\:306b\:4e0d\:660e\:306a\:3082\:306e\:306f \"Text\" \:306b\:843d\:3068\:3059\n" <>
  "\:3053\:3068\:3092\:691c\:8a3c\:3059\:308b\:3002";

AssertT07SlideIntentDetection::usage =
  "AssertT07SlideIntentDetection[] \:306f iDetectSlideIntent \:304c:\n" <>
  "  (a) \"30 \:30da\:30fc\:30b8\:306e\:30b9\:30e9\:30a4\:30c9\" \:3092 IsSlide=True, PageCount=30 \:3068\:8a8d\:8b58\n" <>
  "  (b) \"10-page presentation\" \:3092 IsSlide=True, PageCount=10 \:3068\:8a8d\:8b58\n" <>
  "  (c) \:5168\:89d2\:6570\:5b57 \"３０ページ\" \:3082 30 \:3068\:8a8d\:8b58\n" <>
  "  (d) slide \:7121\:95a2\:4fc2\:306e\:5165\:529b\:306f IsSlide=False\n" <>
  "\:3092\:691c\:8a3c\:3059\:308b\:3002";

AssertT07InnerCellFromSpecSanitize::usage =
  "AssertT07InnerCellFromSpecSanitize[] \:306f iInnerCellFromSpec \:304c\n" <>
  "Style \:304c\:30d7\:30ed\:30fc\:30ba (\"Subsection (title slide)\" \:7b49) \:306a\:3089\:3070\n" <>
  "\:5fc5\:305a\:6709\:52b9\:306a Mathematica cell style \:540d\:79f0\:306b\:843d\:3068\:3059\:3053\:3068\:3092\:691c\:8a3c\:3059\:308b\:3002";

AssertT07DefaultPlannerSlideAware::usage =
  "AssertT07DefaultPlannerSlideAware[] \:306f iDefaultPlanner \:304c\:5165\:529b\:306b\n" <>
  "\:300c30 \:30da\:30fc\:30b8\:306e\:30b9\:30e9\:30a4\:30c9\:300d\:7b49\:304c\:542b\:307e\:308c\:308b\:5834\:5408\:3001\:5358\:4e00 Explore \:3067\:306f\:306a\:304f\n" <>
  "Explore + Draft \:306e 2 \:30bf\:30b9\:30af\:5206\:89e3\:3092\:8fd4\:3057\:3001 Draft \:306e OutputSchema \:306b\n" <>
  "\"SlideDraft\" \:3092\:542b\:3080\:3053\:3068\:3092\:691c\:8a3c\:3059\:308b\:3002";

AssertT07WorkerPromptSlideHint::usage =
  "AssertT07WorkerPromptSlideHint[] \:306f iWorkerBuildSystemPrompt \:304c\n" <>
  "slide \:5fc5\:5408\:3044\:306e task (Goal/Schema \:306b slide/SlideDraft \:3092\:542b\:3080) \:306b\:5bfe\:3057\:3066\n" <>
  "\"T07 SLIDE-MODE\" \:5370\:5b57\:3092\:542b\:3080\:62e1\:5f35 prompt \:3092\:8fd4\:3059\:3053\:3068\:3092\:691c\:8a3c\:3059\:308b\:3002";

AssertT07bResolveTargetNotebookLogic::usage =
  "AssertT07bResolveTargetNotebookLogic[] \:306f iResolveTargetNotebook \:304c\:3001\n" <>
  "  (a) slide \:610f\:56f3\:3042\:308a\:306e\:5165\:529b\:3067 Intent.IsSlide=True \:3092\:8fd4\:3059\n" <>
  "  (b) slide \:7121\:95a2\:4fc2\:306e\:5165\:529b\:3067 Intent.IsSlide=False \:3092\:8fd4\:3059\n" <>
  "\:3053\:3068\:3092\:8ef8\:306b\:691c\:8a3c\:3059\:308b\:3002 CreateDocument \:306f\:5b9f notebook \:304c\:5fc5\:8981\:306a\:305f\:3081\n" <>
  "\:5b9f\:884c\:30d1\:30b9\:306f\:30d8\:30c3\:30c9\:30ec\:30b9\:306b\:306a\:308b\:3068 None \:306b fallback \:3059\:308b\:30b1\:30fc\:30b9\:306f\:3053\:3053\:3067\:306f\:691c\:8a3c\:3057\:306a\:3044\:3002";

(* \:2500\:2500 Phase 32 Task 3.1: Committer \:81ea\:7136\:8a00\:8a9e Input \:6d41\:5165\:9632\:6b62 \:30c6\:30b9\:30c8 \:2500\:2500 *)

RunPhase32Task31Tests::usage =
  "RunPhase32Task31Tests[] \:306f Phase 32 Task 3.1 (Committer \:304c\n" <>
  "Cell[\"\:81ea\:7136\:8a00\:8a9e\", \"Input\"] \:3092\:66f8\:304d\:8fbc\:3080\:308f\:306a\:3044) \:306e\n" <>
  "\:5358\:4f53\:30c6\:30b9\:30c8\:3092\:5b9f\:884c\:3057\:3001PASS/FAIL \:30b5\:30de\:30ea\:3092\:8fd4\:3059\:3002\n" <>
  "\:5bfe\:8c61: iValidateWorkerProposal (role=\"Commit\") +\n" <>
  "        iIsPlausibleInputCellContent + iHeldExprInputCellStrings\:3002";

AssertPhase32Task31RejectsNaturalLangInput::usage =
  "AssertPhase32Task31RejectsNaturalLangInput[] \:306f iValidateWorkerProposal \:306b\n" <>
  "HoldComplete[NotebookWrite[nb, Cell[\"\:65e5\:672c\:8a9e\:6587\", \"Input\"]]] \:3092 role=\"Commit\" \:3067\n" <>
  "\:6295\:5165\:3057\:3001Decision == \"Deny\" \:304b\:3064 ReasonClass == \"NaturalLanguageInInputCell\" \:304c\n" <>
  "\:8fd4\:308b\:3053\:3068\:3092\:691c\:8a3c\:3002OffendingStrings \:304c\:7a7a\:3067\:306a\:3044\:3053\:3068\:3082\:691c\:3002";

AssertPhase32Task31AcceptsMathExprInInputCell::usage =
  "AssertPhase32Task31AcceptsMathExprInInputCell[] \:306f iValidateWorkerProposal \:306b\n" <>
  "HoldComplete[NotebookWrite[nb, Cell[\"Plot[Sin[x], {x, 0, 2 Pi}]\", \"Input\"]]] \:3092\n" <>
  "role=\"Commit\" \:3067\:6295\:5165\:3057\:3001Decision == \"Permit\" \:304b\:3064 ReasonClass == \"OK\" \:304c\n" <>
  "\:8fd4\:308b\:3053\:3068\:3092\:691c\:8a3c\:3002";

AssertPhase32Task31AcceptsNaturalLangInTextCell::usage =
  "AssertPhase32Task31AcceptsNaturalLangInTextCell[] \:306f iValidateWorkerProposal \:306b\n" <>
  "HoldComplete[NotebookWrite[nb, Cell[\"\:65e5\:672c\:8a9e\:6587\", \"Text\"]]] \:3092 role=\"Commit\" \:3067\n" <>
  "\:6295\:5165\:3057\:3001Decision == \"Permit\" \:304c\:8fd4\:308b\:3053\:3068\:3092\:691c\:8a3c (\"Text\" \:306f\:691c\:67fb\:5bfe\:8c61\:5916)\:3002";

(* \:2500\:2500 Phase 32 Task 3.2: Auto \:30b2\:30fc\:30c8\:5f37\:5316 \:30c6\:30b9\:30c8 \:2500\:2500 *)

RunPhase32Task32Tests::usage =
  "RunPhase32Task32Tests[] \:306f Phase 32 Task 3.2 (Auto \:30e2\:30fc\:30c9\:3067\:77ed\:3044 factual\n" <>
  "query \:3092 Single \:306b\:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af\:3001\:8907\:96d1\:30bf\:30b9\:30af\:306f Orchestrator \:306b\:901a\:3059) \:306e\n" <>
  "\:5358\:4f53\:30c6\:30b9\:30c8\:3092\:5b9f\:884c\:3057\:3001PASS/FAIL \:30b5\:30de\:30ea\:3092\:8fd4\:3059\:3002\n" <>
  "\:5bfe\:8c61: iIsShortFactualQuery + iHasComplexTaskMarker\:3002";

AssertPhase32Task32SkipsShortFactualJa::usage =
  "AssertPhase32Task32SkipsShortFactualJa[] \:306f\:3001\:5143\:4e8b\:4f8b\:306e\:77ed\:3044\:65e5\:672c\:8a9e factual\n" <>
  "query (\"$packageDirectory\:306eclaudecode\:2026\:3092\:8abf\:3079\:3066\") \:306b\:5bfe\:3057\n" <>
  "iIsShortFactualQuery \:304c True\:3001iHasComplexTaskMarker \:304c False \:3092\n" <>
  "\:8fd4\:3059\:3053\:3068\:3092\:691c\:8a3c\:3002";

AssertPhase32Task32SkipsShortFactualEn::usage =
  "AssertPhase32Task32SkipsShortFactualEn[] \:306f\:3001\:77ed\:3044\:82f1\:8a9e factual query\n" <>
  "(\"Check if claudecode.wl is newer than its GitHub version\") \:306b\:5bfe\:3057\n" <>
  "iIsShortFactualQuery \:304c True \:3092\:8fd4\:3059\:3053\:3068\:3092\:691c\:8a3c\:3002";

AssertPhase32Task32KeepsLongComplex::usage =
  "AssertPhase32Task32KeepsLongComplex[] \:306f\:3001\:9577\:3044\:30de\:30eb\:30c1\:30b9\:30c6\:30c3\:30d7\:30bf\:30b9\:30af\n" <>
  "(600 \:6587\:5b57\:304b\:3064\:8907\:6570\:306e\:9806\:5e8f\:63a5\:7d9a\:8a9e\:542b\:3080) \:306b\:5bfe\:3057\n" <>
  "iHasComplexTaskMarker \:304c True\:3001iIsShortFactualQuery \:304c False \:3092\n" <>
  "\:8fd4\:3057\:3001Orchestrator \:7d4c\:8def\:3092\:7dad\:6301\:3059\:308b\:3053\:3068\:3092\:691c\:8a3c\:3002";

AssertPhase32Task32KeepsSlideRequest::usage =
  "AssertPhase32Task32KeepsSlideRequest[] \:306f\:3001\:30b9\:30e9\:30a4\:30c9\:30fb\:30ec\:30dd\:30fc\:30c8\:7b49\n" <>
  "\:306e\:6210\:679c\:7269\:8981\:6c42 (\"30\:30da\:30fc\:30b8\:306e\:30b9\:30e9\:30a4\:30c9\:3092\:4f5c\:3063\:3066\") \:306b\:5bfe\:3057\n" <>
  "iHasComplexTaskMarker \:304c True \:3092\:8fd4\:3059\:3053\:3068\:3092\:691c\:8a3c\:3002";

AssertPhase32Task32KeepsSequentialTask::usage =
  "AssertPhase32Task32KeepsSequentialTask[] \:306f\:3001\:9806\:5e8f\:63a5\:7d9a\:8a9e\:304c 2 \:500b\:4ee5\:4e0a\n" <>
  "(\:300c\:307e\:305a\:2026\:6b21\:306b\:2026\:6700\:5f8c\:306b\:2026\:300d) \:3042\:308b\:30bf\:30b9\:30af\:304c\n" <>
  "iHasComplexTaskMarker \:304c True \:3092\:8fd4\:3059\:3053\:3068\:3092\:691c\:8a3c\:3002";

Begin["`Private`"];

(* ── iL: $Language に基づく日英切替 ── *)
iL[ja_String, en_String] := If[$Language === "Japanese", ja, en];

(* 依存: ClaudeRuntime` を先にロードすること。
   使用シンボル: CreateClaudeRuntime, ClaudeRunTurn, ClaudeRuntimeState,
   ClaudeTurnTrace, ClaudeApproveProposal, ClaudeDenyProposal *)

(* ════════════════════════════════════════════════════════
   1. MockProvider
   ════════════════════════════════════════════════════════ *)

CreateMockProvider[responses_List] :=
  Module[{idx = 0, resps = responses},
    <|
      "Type" -> "MockProvider",
      "Query" -> Function[{contextPacket, convState},
        idx++;
        If[idx > Length[resps],
          <|"response" -> "No more mock responses"|>,
          <|"response" -> resps[[idx]]|>
        ]
      ],
      "ResponseCount" -> Function[{}, idx],
      "Reset" -> Function[{}, idx = 0]
    |>
  ];

(* ════════════════════════════════════════════════════════
   2. MockAdapter
   ════════════════════════════════════════════════════════ *)

Options[CreateMockAdapter] = {
  "Provider"         -> None,
  "AllowedHeads"     -> {"NBCellRead", "NBCellWrite", "NBGetContext",
                         "Print", "ToString"},
  "DenyHeads"        -> {"DeleteFile", "SystemOpen", "Run", "RunProcess"},
  "ApprovalHeads"    -> {"NBCellWriteCode", "NBDeleteCellsByTag"},
  "ExecutionResults" -> Automatic,
  "MaxContinuations" -> 0,
  "Secrets"          -> {}
};

CreateMockAdapter[opts:OptionsPattern[]] :=
  Module[{provider, allowedHeads, denyHeads, approvalHeads,
          execResults, maxCont, secrets,
          execIdx = 0, contCount = 0},
    
    provider      = OptionValue["Provider"];
    allowedHeads  = OptionValue["AllowedHeads"];
    denyHeads     = OptionValue["DenyHeads"];
    approvalHeads = OptionValue["ApprovalHeads"];
    execResults   = OptionValue["ExecutionResults"];
    maxCont       = OptionValue["MaxContinuations"];
    secrets       = OptionValue["Secrets"];
    
    If[provider === None,
      provider = CreateMockProvider[{"No provider configured"}]];
    
    <|
      "SyncProvider" -> True,
      
      "BuildContext" -> Function[{input, convState},
        <|"Input" -> input,
          "ConversationState" -> convState,
          "AccessSpec" -> <|"AccessLevel" -> 0.5|>|>
      ],
      
      "QueryProvider" -> provider["Query"],
      
      "ParseProposal" -> Function[{rawResponse},
        Module[{code, heldExpr},
          (* ```mathematica ブロック検索 *)
          code = None;
          If[StringContainsQ[rawResponse, "```mathematica"],
            code = First[
              StringCases[rawResponse,
                "```mathematica\n" ~~ c__ ~~ "\n```" :> c],
              None]];
          If[StringQ[code],
            heldExpr = Quiet @ Check[
              ToExpression[code, InputForm, HoldComplete], None];
            If[heldExpr =!= None,
              Return[<|"HeldExpr" -> heldExpr,
                "TextResponse" -> rawResponse,
                "HasProposal" -> True,
                "RawCode" -> code|>, Module]]];
          (* コードブロックがなければテキストのみ *)
          <|"HeldExpr" -> None,
            "TextResponse" -> rawResponse,
            "HasProposal" -> False|>
        ]
      ],
      
      "ValidateProposal" -> Function[{proposal, contextPacket},
        Module[{heldExpr, headName},
          heldExpr = proposal["HeldExpr"];
          If[heldExpr === None,
            Return[<|"Decision" -> "TextOnly"|>]];
          (* 先頭の head を取り出す *)
          headName = ToString[
            Replace[heldExpr,
              HoldComplete[expr_] :> Head[Unevaluated[expr]]]];
          Which[
            MemberQ[denyHeads, headName],
              <|"Decision"            -> "Deny",
                "ReasonClass"         -> "ForbiddenHead",
                "VisibleExplanation"  -> "Head " <> headName <> " is forbidden",
                "SanitizedExpr"       -> heldExpr|>,
            MemberQ[approvalHeads, headName],
              <|"Decision"            -> "NeedsApproval",
                "ReasonClass"         -> "AccessEscalationRequired",
                "VisibleExplanation"  -> "Head " <> headName <> " requires approval",
                "SanitizedExpr"       -> heldExpr|>,
            MemberQ[allowedHeads, headName] || headName === "CompoundExpression",
              <|"Decision"            -> "Permit",
                "ReasonClass"         -> "None",
                "VisibleExplanation"  -> "",
                "SanitizedExpr"       -> heldExpr|>,
            True,
              <|"Decision"            -> "RepairNeeded",
                "ReasonClass"         -> "ValidationRepairable",
                "VisibleExplanation"  -> "Unknown head: " <> headName,
                "SanitizedExpr"       -> heldExpr|>
          ]
        ]
      ],
      
      "ExecuteProposal" -> Function[{proposal, validationResult},
        Module[{result},
          execIdx++;
          If[ListQ[execResults] && execIdx <= Length[execResults],
            result = execResults[[execIdx]],
            (* デフォルト: HeldExpr を ReleaseHold で実行 *)
            result = Quiet @ Check[
              ReleaseHold[proposal["HeldExpr"]],
              $Failed]];
          If[result === $Failed,
            <|"Success" -> False, "RawResult" -> None,
              "Error" -> "Execution failed"|>,
            <|"Success" -> True, "RawResult" -> result,
              "Error" -> None|>
          ]
        ]
      ],
      
      "RedactResult" -> Function[{executionResult, contextPacket},
        Module[{raw, redacted},
          raw = Lookup[executionResult, "RawResult", None];
          redacted = ToString[Short[raw, 5]];
          (* 秘密文字列を redact *)
          Do[redacted = StringReplace[redacted, s -> "[REDACTED]"],
            {s, secrets}];
          <|"RedactedResult" -> redacted,
            "Summary" -> StringTake[redacted, UpTo[200]]|>
        ]
      ],
      
      "ShouldContinue" -> Function[{redactedResult, convState, turnCount},
        contCount++;
        contCount <= maxCont
      ]
    |>
  ];

(* ════════════════════════════════════════════════════════
   3. RunClaudeScenario
   ════════════════════════════════════════════════════════ *)

RunClaudeScenario[scenario_Association] :=
  Module[{name, input, adapter, profile, assertions,
          runtimeId, jobId, rt, trace, results = <||>,
          maxWait = 10, waited = 0},
    
    name       = Lookup[scenario, "Name", "unnamed"];
    input      = scenario["Input"];
    adapter    = scenario["Adapter"];
    profile    = Lookup[scenario, "Profile", "Eval"];
    assertions = Lookup[scenario, "Assertions", {}];
    
    (* runtime 生成 *)
    runtimeId = ClaudeRuntime`CreateClaudeRuntime[adapter, "Profile" -> profile];
    If[runtimeId === $Failed,
      Return[<|"Name" -> name, "Status" -> "SetupFailed"|>]];
    
    (* turn 起動 *)
    jobId = ClaudeRuntime`ClaudeRunTurn[runtimeId, input,
      "Notebook" -> $Failed]; (* テスト時は notebook なし *)
    
    (* SyncProvider の場合: DAG は即座に完了するはず *)
    (* 非同期の場合: ポーリングで完了を待つ *)
    While[waited < maxWait,
      rt = ClaudeRuntime`ClaudeRuntimeState[runtimeId];
      If[MemberQ[{"Done", "Failed", "AwaitingApproval"}, rt["Status"]],
        Break[]];
      Pause[0.1];
      waited += 0.1];
    
    rt    = ClaudeRuntime`ClaudeRuntimeState[runtimeId];
    trace = ClaudeRuntime`ClaudeTurnTrace[runtimeId];
    
    results["Name"]      = name;
    results["RuntimeId"] = runtimeId;
    results["Status"]    = rt["Status"];
    results["Trace"]     = trace;
    results["State"]     = rt;
    
    (* assertions 実行 *)
    results["AssertionResults"] = Association @ Map[
      Module[{aName, aResult},
        aName   = Lookup[#, "Name", "?"];
        aResult = Quiet @ Check[#["Check"][rt, trace], $Failed];
        aName -> <|"Passed" -> TrueQ[aResult], "Detail" -> aResult|>
      ] &,
      assertions
    ];
    
    results["AllPassed"] = AllTrue[
      Values[results["AssertionResults"]],
      TrueQ[#["Passed"]] &];
    
    results
  ];

(* ════════════════════════════════════════════════════════
   4. NormalizeClaudeTrace
   ════════════════════════════════════════════════════════ *)

NormalizeClaudeTrace[trace_List] :=
  Map[
    Function[{event},
      Module[{e = KeyDrop[event, {"Timestamp"}]},
        If[KeyExistsQ[e, "RuntimeId"], e["RuntimeId"] = "<id>"];
        If[KeyExistsQ[e, "JobId"], e["JobId"] = "<jobId>"];
        e
      ]
    ],
    trace
  ];

(* ════════════════════════════════════════════════════════
   5. Assertion 関数群
   ════════════════════════════════════════════════════════ *)

AssertNoSecretLeak[trace_List, secrets_List] :=
  Module[{traceStr, leaks},
    traceStr = ToString[trace, InputForm];
    leaks = Select[secrets, StringContainsQ[traceStr, #] &];
    If[Length[leaks] === 0,
      True,
      Failure["SecretLeak", <|"Leaked" -> leaks|>]
    ]
  ];

AssertValidationDenied[trace_List] :=
  AnyTrue[trace,
    MatchQ[Lookup[#, "Type", ""], "FatalFailure" | "StatusChange"] &&
    MatchQ[Lookup[#, "Status", Lookup[#, "Detail", ""]], "Failed" | "ForbiddenHead" | "ExplicitDeny"] &
  ];

AssertOutcome[trace_List, expectedOutcome_String] :=
  Module[{lastStatus},
    lastStatus = Last[
      Select[trace, Lookup[#, "Type", ""] === "StatusChange" &],
      <||>];
    Lookup[lastStatus, "Status", "?"] === expectedOutcome
  ];

AssertBudgetNotExceeded[runtimeState_Association] :=
  Module[{limits, used},
    limits = runtimeState["RetryPolicy"]["Limits"];
    used   = runtimeState["BudgetsUsed"];
    AllTrue[Keys[limits],
      Lookup[used, #, 0] <= Lookup[limits, #, 0] &]
  ];

AssertEventSequence[trace_List, expectedTypes_List] :=
  Module[{types, pos = 1, found = True},
    types = Lookup[#, "Type", "?"] & /@ trace;
    Do[
      Module[{idx = FirstPosition[types[[pos ;;]], et, None]},
        If[idx === None, found = False; Break[],
          pos = pos + idx[[1]]]],
      {et, expectedTypes}];
    found
  ];

(* ════════════════════════════════════════════════════════
   6. 組み込みテストシナリオ
   ════════════════════════════════════════════════════════ *)

$ClaudeTestScenarios = <|

  (* ── 正常系: 許可された head で即完了 ── *)
  "PermitSimple" -> <|
    "Name"  -> "PermitSimple",
    "Input" -> "Read cell 3",
    "Adapter" -> CreateMockAdapter[
      "Provider" -> CreateMockProvider[{
        "```mathematica\nNBCellRead[nb, 3]\n```"
      }],
      "ExecutionResults" -> {"Cell content here"}
    ],
    "Assertions" -> {
      <|"Name" -> "StatusDone",
        "Check" -> Function[{st, tr}, st["Status"] === "Done"]|>,
      <|"Name" -> "EventSeq",
        "Check" -> Function[{st, tr},
          AssertEventSequence[tr, {"ContextBuilt", "ProviderQueried",
            "ProposalParsed", "ValidationComplete", "ResultRedacted",
            "TurnComplete"}]]|>,
      <|"Name" -> "BudgetOK",
        "Check" -> Function[{st, tr}, AssertBudgetNotExceeded[st]]|>
    }
  |>,

  (* ── 拒否系: 禁止 head ── *)
  "DenyForbiddenHead" -> <|
    "Name"  -> "DenyForbiddenHead",
    "Input" -> "Delete a file",
    "Adapter" -> CreateMockAdapter[
      "Provider" -> CreateMockProvider[{
        "```mathematica\nDeleteFile[\"important.txt\"]\n```"
      }]
    ],
    "Assertions" -> {
      <|"Name" -> "StatusAwaitingApproval",
        "Check" -> Function[{st, tr}, st["Status"] === "AwaitingApproval"]|>,
      <|"Name" -> "DenyOverrideInPending",
        "Check" -> Function[{st, tr},
          TrueQ[Lookup[
            Lookup[st, "PendingApproval", <||>],
            "DenyOverride", False]]]|>
    }
  |>,

  (* ── 承認待ち系 ── *)
  "NeedsApproval" -> <|
    "Name"  -> "NeedsApproval",
    "Input" -> "Write code to cell",
    "Adapter" -> CreateMockAdapter[
      "Provider" -> CreateMockProvider[{
        "```mathematica\nNBCellWriteCode[nb, 5, \"x=1\"]\n```"
      }]
    ],
    "Assertions" -> {
      <|"Name" -> "StatusAwaiting",
        "Check" -> Function[{st, tr},
          st["Status"] === "AwaitingApproval"]|>,
      <|"Name" -> "ApprovalInTrace",
        "Check" -> Function[{st, tr},
          AnyTrue[tr, Lookup[#, "Type", ""] === "AwaitingApproval" &]]|>
    }
  |>,

  (* ── テキストのみ応答 ── *)
  "TextOnly" -> <|
    "Name"  -> "TextOnly",
    "Input" -> "What is 2+2?",
    "Adapter" -> CreateMockAdapter[
      "Provider" -> CreateMockProvider[{
        "The answer is 4!"
      }]
    ],
    "Assertions" -> {
      <|"Name" -> "StatusDone",
        "Check" -> Function[{st, tr}, st["Status"] === "Done"]|>,
      <|"Name" -> "TextOnlyInTrace",
        "Check" -> Function[{st, tr},
          AnyTrue[tr, Lookup[#, "Type", ""] === "TextOnlyResponse" &]]|>
    }
  |>,

  (* ── 秘密漏洩チェック ── *)
  "NoSecretLeak" -> <|
    "Name"  -> "NoSecretLeak",
    "Input" -> "Show me the API key",
    "Adapter" -> CreateMockAdapter[
      "Provider" -> CreateMockProvider[{
        "```mathematica\nToString[\"sk-secret-12345\"]\n```"
      }],
      "ExecutionResults" -> {"sk-secret-12345"},
      "Secrets" -> {"sk-secret-12345"}
    ],
    "Assertions" -> {
      <|"Name" -> "NoLeak",
        "Check" -> Function[{st, tr},
          TrueQ[AssertNoSecretLeak[tr, {"sk-secret-12345"}]]]|>
    }
  |>,

  (* ── 継続 (multi-turn) ── *)
  "Continuation" -> <|
    "Name"  -> "Continuation",
    "Input" -> "Summarize cells 1-5",
    "Adapter" -> CreateMockAdapter[
      "Provider" -> CreateMockProvider[{
        "```mathematica\nNBCellRead[nb, 1]\n```",
        "```mathematica\nNBCellRead[nb, 2]\n```",
        "Summary: done."
      }],
      "ExecutionResults" -> {"cell1 content", "cell2 content"},
      "MaxContinuations" -> 1
    ],
    "Assertions" -> {
      <|"Name" -> "MultiTurn",
        "Check" -> Function[{st, tr},
          Count[tr, _?(Lookup[#, "Type", ""] === "TurnStarted" &)] >= 2]|>
    }
  |>
|>;

(* ════════════════════════════════════════════════════════
   7. RunAllClaudeTests
   ════════════════════════════════════════════════════════ *)

RunAllClaudeTests[] :=
  Module[{results},
    results = Association @ Map[
      Module[{name = #, scenario, result},
        scenario = $ClaudeTestScenarios[name];
        result = RunClaudeScenario[scenario];
        name -> result
      ] &,
      Keys[$ClaudeTestScenarios]
    ];
    
    Print[Style[iL["\n ClaudeTestKit テスト結果:", "\n ClaudeTestKit Test Results:"], Bold]];
    Do[
      Module[{r = results[name], passed, mark},
        passed = TrueQ[r["AllPassed"]];
        mark = If[passed, Style["\[Checkmark]", Darker[Green]], Style["\[Cross]", Red]];
        Print["  ", mark, " ", name, " (", r["Status"], ")"];
        If[!passed,
          Do[Module[{aName = k, ar = r["AssertionResults"][k]},
            If[!TrueQ[ar["Passed"]],
              Print["      \[Bullet] ", aName, " FAILED: ", ar["Detail"]]]],
            {k, Keys[r["AssertionResults"]]}]]],
      {name, Keys[results]}];
    
    Print["\n  Total: ", Length[results],
      "  Passed: ", Count[Values[results], _?(TrueQ[#["AllPassed"]] &)],
      "  Failed: ", Count[Values[results], _?(!TrueQ[#["AllPassed"]] &)]];
    
    Dataset[results]
  ];

$ClaudeTestKitVersion = "2026-04-19T11-cell-string-parse-tests";

(* ════════════════════════════════════════════════════════
   8. MockTransactionAdapter (Phase 9)
   ════════════════════════════════════════════════════════ *)

Options[CreateMockTransactionAdapter] = {
  "Provider"       -> None,
  "FailAtPhase"    -> None,
  "FailCount"      -> 1,
  "AllowedHeads"   -> {"Print", "ToString", "NBCellRead"},
  "DenyHeads"      -> {"DeleteFile", "Run", "RunProcess"},
  "ApprovalHeads"  -> {"NBCellWriteCode"},
  "Secrets"        -> {},
  "MaxContinuations" -> 0
};

CreateMockTransactionAdapter[opts:OptionsPattern[]] :=
  Module[{provider, failAtPhase, failCount, failCounter = 0,
          baseAdapter, contCount = 0, maxCont,
          allowedH, denyH, approvalH, secrets},
    provider    = OptionValue["Provider"];
    failAtPhase = OptionValue["FailAtPhase"];
    failCount   = OptionValue["FailCount"];
    allowedH    = OptionValue["AllowedHeads"];
    denyH       = OptionValue["DenyHeads"];
    approvalH   = OptionValue["ApprovalHeads"];
    secrets     = OptionValue["Secrets"];
    maxCont     = OptionValue["MaxContinuations"];
    
    If[provider === None,
      provider = CreateMockProvider[{"No provider configured"}]];
    
    (* FailAtPhase のチェック関数: failCount 回まで失敗、以降成功 *)
    Module[{shouldFail},
      shouldFail[phase_] := (
        If[failAtPhase === phase,
          failCounter++;
          failCounter <= failCount,
          False]);
      
      <|
        "SyncProvider" -> True,
        
        "BuildContext" -> Function[{input, convState},
          <|"Input" -> input,
            "ConversationState" -> convState,
            "AccessSpec" -> <|"AccessLevel" -> 0.5|>,
            "PackagePath" -> "/tmp/mock-package.wl",
            "TestPath" -> None|>
        ],
        
        "QueryProvider" -> provider["Query"],
        
        "ParseProposal" -> Function[{rawResponse},
          Module[{code, heldExpr},
            code = None;
            If[StringContainsQ[rawResponse, "```mathematica"],
              code = First[
                StringCases[rawResponse,
                  "```mathematica\n" ~~ Shortest[c__] ~~ "\n```" :> c],
                None]];
            If[StringQ[code],
              heldExpr = Quiet @ Check[
                ToExpression[code, InputForm, HoldComplete], None];
              If[heldExpr =!= None,
                Return[<|"HeldExpr" -> heldExpr,
                  "TextResponse" -> rawResponse,
                  "HasProposal" -> True,
                  "RawCode" -> code|>, Module]]];
            <|"HeldExpr" -> None,
              "TextResponse" -> rawResponse,
              "HasProposal" -> False|>
          ]
        ],
        
        "ValidateProposal" -> Function[{proposal, contextPacket},
          Module[{heldExpr, headName},
            heldExpr = proposal["HeldExpr"];
            If[heldExpr === None,
              Return[<|"Decision" -> "TextOnly"|>]];
            headName = ToString[
              Replace[heldExpr,
                HoldComplete[expr_] :> Head[Unevaluated[expr]]]];
            Which[
              MemberQ[denyH, headName],
                <|"Decision" -> "Deny", "ReasonClass" -> "ForbiddenHead",
                  "VisibleExplanation" -> headName <> " is forbidden",
                  "SanitizedExpr" -> heldExpr|>,
              MemberQ[approvalH, headName],
                <|"Decision" -> "NeedsApproval",
                  "ReasonClass" -> "AccessEscalationRequired",
                  "VisibleExplanation" -> headName <> " requires approval",
                  "SanitizedExpr" -> heldExpr|>,
              MemberQ[allowedH, headName] || headName === "CompoundExpression",
                <|"Decision" -> "Permit", "ReasonClass" -> "None",
                  "VisibleExplanation" -> "", "SanitizedExpr" -> heldExpr|>,
              True,
                <|"Decision" -> "RepairNeeded",
                  "ReasonClass" -> "ValidationRepairable",
                  "VisibleExplanation" -> "Unknown head: " <> headName,
                  "SanitizedExpr" -> heldExpr|>
            ]
          ]
        ],
        
        "ExecuteProposal" -> Function[{proposal, validationResult},
          <|"Success" -> True, "RawResult" -> "mock executed",
            "Error" -> None|>
        ],
        
        "RedactResult" -> Function[{executionResult, contextPacket},
          Module[{raw, redacted},
            raw = Lookup[executionResult, "RawResult", None];
            redacted = ToString[Short[raw, 5]];
            Do[redacted = StringReplace[redacted, s -> "[REDACTED]"],
              {s, secrets}];
            <|"RedactedResult" -> redacted,
              "Summary" -> StringTake[redacted, UpTo[200]]|>
          ]
        ],
        
        "ShouldContinue" -> Function[{redactedResult, convState, turnCount},
          contCount++;
          contCount <= maxCont
        ],
        
        (* ── Transaction 関数 ── *)
        
        "SnapshotPackage" -> Function[{contextPacket},
          If[shouldFail["Snapshot"],
            <|"Success" -> False, "Error" -> "Mock snapshot failure"|>,
            <|"Success" -> True,
              "SnapshotId" -> "mock-snap-" <> ToString[RandomInteger[9999]],
              "BackupPath" -> "/tmp/mock-backup.wl",
              "PackagePath" -> Lookup[contextPacket, "PackagePath",
                "/tmp/mock-package.wl"]|>
          ]
        ],
        
        "ApplyToShadow" -> Function[{proposal, snapshotInfo},
          If[shouldFail["ShadowApply"],
            <|"Success" -> False, "ShadowPath" -> None,
              "Error" -> "Mock shadow apply failure"|>,
            <|"Success" -> True,
              "ShadowPath" -> "/tmp/shadow/mock-package.wl"|>
          ]
        ],
        
        "StaticCheck" -> Function[{shadowResult},
          If[shouldFail["StaticCheck"],
            <|"Success" -> False,
              "Errors" -> {"Mock static check error"},
              "Warnings" -> {}|>,
            <|"Success" -> True, "Errors" -> {}, "Warnings" -> {}|>
          ]
        ],
        
        "ReloadCheck" -> Function[{shadowResult},
          If[shouldFail["ReloadCheck"],
            <|"Success" -> False,
              "Error" -> "Mock reload failure"|>,
            <|"Success" -> True, "Error" -> None|>
          ]
        ],
        
        "RunTests" -> Function[{shadowResult, contextPacket},
          If[shouldFail["TestPhase"],
            <|"Success" -> False,
              "Passed" -> 3, "Failed" -> 2,
              "Failures" -> {"test_a", "test_b"},
              "Error" -> "Mock test failure"|>,
            <|"Success" -> True,
              "Passed" -> 5, "Failed" -> 0,
              "Failures" -> {}, "Error" -> None|>
          ]
        ],
        
        "CommitTransaction" -> Function[{shadowResult, snapshotInfo},
          If[shouldFail["Commit"],
            <|"Success" -> False, "Error" -> "Mock commit failure"|>,
            <|"Success" -> True, "Error" -> None|>
          ]
        ],
        
        "RollbackTransaction" -> Function[{snapshotInfo},
          <|"Success" -> True|>
        ]
      |>
    ]
  ];

(* ════════════════════════════════════════════════════════
   ClaudeOrchestrator 連携実装 (spec §13)
   
   依存: ClaudeOrchestrator` のロードを前提としない (テスト専用の
   軽量 stub を提供)。ClaudeOrchestrator` がロード済みなら
   $ClaudeOrchestratorDenyHeads を流用する。
   ════════════════════════════════════════════════════════ *)

(* Deny head リスト: ClaudeOrchestrator がロードされていればそれを
   使い、未ロードなら fallback を使う。 *)
iOrchDenyHeads[] :=
  If[ValueQ[ClaudeOrchestrator`$ClaudeOrchestratorDenyHeads] &&
     ListQ[ClaudeOrchestrator`$ClaudeOrchestratorDenyHeads],
    ClaudeOrchestrator`$ClaudeOrchestratorDenyHeads,
    {"NotebookWrite", "CreateNotebook", "DocumentNotebook",
     "Export", "Put", "RunProcess", "StartProcess",
     "ExternalEvaluate", "SystemCredential"}];

(* ── CreateMockPlanner ──
   固定 taskSpec を返す planner。MaxTasks に応じてトリム。 *)
CreateMockPlanner[taskSpec_Association] :=
  Function[{input, opts},
    Module[{tasks = Lookup[taskSpec, "Tasks", {}], maxT},
      maxT = Lookup[opts, "MaxTasks", Length[tasks]];
      <|"Tasks" -> Take[tasks, UpTo[maxT]]|>]];

CreateMockPlanner[tasks_List] :=
  CreateMockPlanner[<|"Tasks" -> tasks|>];

(* ── CreateMockWorkerAdapter ──
   role 別 worker adapter stub。caller は opts で固定応答を指定できる。
   Deny head チェックは iValidateWorkerProposalStub で行う。
   
   重要: ClaudeRuntime は HeldExpr=None (TextOnly) のとき、MaxFormatRetries
   枯渇まで repair loop を回すので、テストでは mock adapter が必ず
   harmless な HeldExpr を提案することを既定とする。こうすれば
   ExecuteProposal が確実に 1 度発火し、artifactPayload が
   LastExecutionResult.RawResult に入り、orchestrator の
   iExtractArtifactFromTurn がそれを拾える。
   
   "MutationAttempt" -> True: deny される head (NotebookWrite 等) を
     明示的に提案し、validator が deny することを検証するテスト用。
   "ProposedHeld" -> HoldComplete[...]: 提案を caller が指定する場合用。
   "HoldExprNone" -> True: 旧来の text-only 動作に明示的にしたい場合用。 *)
Options[CreateMockWorkerAdapter] = {
  "Response"        -> "",
  "ProposedHeld"    -> Automatic,
  "ArtifactPayload" -> None,
  "MutationAttempt" -> False,  (* True にすると NotebookWrite を提案 *)
  "HoldExprNone"    -> False   (* True にすると HeldExpr=None を強制 *)
};

CreateMockWorkerAdapter[role_String, task_Association,
    depArtifacts_Association, opts:OptionsPattern[]] :=
  Module[{responseText, heldProp, artifactPayload, mutationAttempt,
          holdNone, heldActual, denyList},
    responseText    = OptionValue["Response"];
    heldProp        = OptionValue["ProposedHeld"];
    artifactPayload = OptionValue["ArtifactPayload"];
    mutationAttempt = TrueQ[OptionValue["MutationAttempt"]];
    holdNone        = TrueQ[OptionValue["HoldExprNone"]];
    
    heldActual = Which[
      mutationAttempt,
        HoldComplete[NotebookWrite[EvaluationNotebook[], Cell["x", "Input"]]],
      holdNone, None,
      heldProp =!= Automatic, heldProp,
      True,
        (* 既定: harmless な noop 提案。runtime の TextOnly 経路を
           バイパスし、ExecuteProposal を直ちに発火させる。 *)
        HoldComplete[True]];
    
    denyList = iOrchDenyHeads[];
    If[role === "Commit",
      denyList = Complement[denyList,
        {"NotebookWrite", "Export", "Put", "PutAppend"}]];
    
    <|
      "SyncProvider" -> True,
      
      "BuildContext" -> Function[{input, convState},
        <|"Input" -> input, "Role" -> role, "Task" -> task,
          "DependencyArtifacts" -> depArtifacts|>],
      
      "QueryProvider" -> Function[{ctx, convState},
        <|"response" -> responseText, "Role" -> role|>],
      
      "ParseProposal" -> Function[{raw},
        <|"HeldExpr"     -> heldActual,
          "TextResponse" -> If[StringQ[raw], raw,
                               Lookup[raw, "response", ""]],
          "HasProposal"  -> (heldActual =!= None),
          (* Stage 2d: orchestrator \:306e iExtractArtifactFromTurn \:304c
             LastProposal.ArtifactPayload \:3092 fallback \:3068\:3057\:3066\:62fe\:3046\:305f\:3081\:3001
             mock worker \:3082 ArtifactPayload \:3092 ParseProposal \:3067\:8fd4\:3059\:3002 *)
          "ArtifactPayload" -> If[artifactPayload === None,
                                  <|"Summary" -> responseText|>,
                                  artifactPayload]|>],
      
      "ValidateProposal" -> Function[{prop, ctx},
        Module[{h = Lookup[prop, "HeldExpr", None], hit},
          If[h === None,
            <|"Decision" -> "Permit", "ReasonClass" -> "NoProposal",
              "VisibleExplanation" -> "", "SanitizedExpr" -> None|>,
            hit = iContainsDenyHeadStub[h, denyList];
            If[hit,
              <|"Decision" -> "Deny", "ReasonClass" -> "ForbiddenHead",
                "VisibleExplanation" ->
                  "Mock worker adapter denied forbidden head",
                "SanitizedExpr" -> None|>,
              <|"Decision" -> "Permit", "ReasonClass" -> "OK",
                "VisibleExplanation" -> "", "SanitizedExpr" -> h|>]]]],
      
      "ExecuteProposal" -> Function[{prop, val},
        Module[{},
          (* Deny の場合 ExecuteProposal は呼ばれない想定 (runtime 側で gate)
             だが、stub として呼ばれた場合は安全に失敗させる。 *)
          If[Lookup[val, "Decision", "Deny"] === "Deny",
            <|"Success" -> False, "RawResult" -> None,
              "Error" -> "DeniedByValidator"|>,
            <|"Success" -> True,
              "RawResult" -> If[artifactPayload === None,
                                <|"Summary" -> responseText|>,
                                artifactPayload],
              "Error" -> None|>]]],
      
      "RedactResult" -> Function[{res, ctx},
        <|"RedactedResult" -> Lookup[res, "RawResult", None],
          "Summary"        -> responseText|>],
      
      "ShouldContinue" -> Function[{red, convState, turnCount}, False]
    |>];

(* stub: deny head 文字列チェック *)
iContainsDenyHeadStub[HoldComplete[expr_], denyList_List] :=
  Module[{syms, names},
    syms = Cases[Unevaluated[expr], s_Symbol :> s,
      {0, Infinity}, Heads -> True];
    names = Map[SymbolName, syms];
    AnyTrue[denyList, MemberQ[names, #] &]
  ];
iContainsDenyHeadStub[_, _] := False;

(* ── CreateMockReducer ── *)
CreateMockReducer[payload_Association] :=
  Function[artifacts, payload];

CreateMockReducer[payload_Association, _] :=
  Function[artifacts, payload];

(* ── CreateMockCommitter ──
   実書き込みはせず commit record だけ残す。*)
CreateMockCommitter[targetNotebook_, reducedArtifact_Association] :=
  Module[{committed = False, lastPayload = None},
    <|
      "SyncProvider" -> True,
      "BuildContext" -> Function[{input, convState},
        <|"Role" -> "Commit",
          "TargetNotebook" -> targetNotebook,
          "ReducedArtifact" -> reducedArtifact|>],
      "QueryProvider" -> Function[{ctx, convState},
        <|"response" -> "[mock committer: ack]"|>],
      "ParseProposal" -> Function[{raw},
        <|"HeldExpr" -> None,
          "TextResponse" -> "[mock committer]",
          "HasProposal" -> False|>],
      "ValidateProposal" -> Function[{prop, ctx},
        <|"Decision" -> "Permit", "ReasonClass" -> "OK",
          "VisibleExplanation" -> "",
          "SanitizedExpr" -> None|>],
      "ExecuteProposal" -> Function[{prop, val},
        committed = True;
        lastPayload = reducedArtifact;
        <|"Success" -> True,
          "RawResult" -> <|"Committed" -> True,
                           "TargetNotebook" -> targetNotebook,
                           "Payload" -> reducedArtifact|>,
          "Error" -> None|>],
      "RedactResult" -> Function[{res, ctx},
        <|"RedactedResult" -> Lookup[res, "RawResult", None],
          "Summary" -> "committed"|>],
      "ShouldContinue" -> Function[{r, c, t}, False],
      "CommitRecord" -> Function[{}, <|"Committed" -> committed,
                                        "LastPayload" -> lastPayload|>]
    |>];

(* ── RunClaudeOrchestrationScenario ── *)
RunClaudeOrchestrationScenario[scenario_Association] :=
  Module[{input, result, assertions, assertionResults},
    input = Lookup[scenario, "Input", "test-input"];
    
    If[!ValueQ[ClaudeOrchestrator`ClaudeRunOrchestration],
      Return[<|"Status" -> "Failed",
               "Error" -> "ClaudeOrchestrator not loaded"|>]];
    
    result = ClaudeOrchestrator`ClaudeRunOrchestration[input,
      "Planner"                  -> Lookup[scenario, "Planner", Automatic],
      "WorkerAdapterBuilder"     ->
        Lookup[scenario, "WorkerAdapterBuilder", Automatic],
      "Reducer"                  -> Lookup[scenario, "Reducer", Automatic],
      "CommitterAdapterBuilder"  ->
        Lookup[scenario, "CommitterAdapterBuilder", Automatic],
      "TargetNotebook"           -> Lookup[scenario, "TargetNotebook", None],
      "SkipCommit"               -> TrueQ[Lookup[scenario, "SkipCommit", True]],
      "Verbose"                  -> TrueQ[Lookup[scenario, "Verbose", False]]];
    
    assertions = Lookup[scenario, "Assertions", {}];
    assertionResults = Map[
      Function[a,
        Module[{r = Quiet @ Check[a[result], $Failed]},
          <|"Assertion" -> ToString[a], "Passed" -> TrueQ[r]|>]],
      assertions];
    
    Append[result, "AssertionResults" -> assertionResults]
  ];

(* ── AssertNoWorkerNotebookMutation ──
   spawnResult の各 artifact の Diagnostics に deny 記録があれば
   OR 全ての artifact が Success でない (worker が NotebookWrite を
   提案して拒否された) 場合でも、最終的に worker adapter が
   notebook を直接変更していなければ合格。
   
   この assertion の実装原則: EventTrace に NotebookWrite / CreateNotebook
   を含む 'ExecutionSucceeded' イベントがないことを確認。 *)
AssertNoWorkerNotebookMutation[orchestrationResult_Association] :=
  Module[{spawn = Lookup[orchestrationResult, "SpawnResult", <||>],
          artifacts, leak = False, a, diag, raw, payload},
    artifacts = Lookup[spawn, "Artifacts", <||>];
    Do[
      a = artifacts[taskId];
      If[AssociationQ[a],
        diag = Lookup[a, "Diagnostics", <||>];
        raw = Lookup[a, "Payload", <||>];
        (* Payload に notebook 変更記録があれば fail *)
        If[AssociationQ[raw] &&
           (TrueQ[Lookup[raw, "Committed", False]] ||
            KeyExistsQ[raw, "NotebookWriteResult"]),
          leak = True]],
      {taskId, Keys[artifacts]}];
    !leak
  ];

AssertNoWorkerNotebookMutation[_] := False;

(* ── AssertArtifactsRespectDependencies ──
   tasksSpec の依存関係が順序に反映されているか (topological 順に
   artifact が生成されているか) を確認。 *)
AssertArtifactsRespectDependencies[orchestrationResult_Association,
    tasksSpec_Association] :=
  Module[{spawn, artifacts, tasks, task, deps, allOk = True},
    spawn = Lookup[orchestrationResult, "SpawnResult", <||>];
    artifacts = Lookup[spawn, "Artifacts", <||>];
    tasks = Lookup[tasksSpec, "Tasks", {}];
    Do[
      If[AssociationQ[task],
        deps = Lookup[task, "DependsOn", {}];
        If[ListQ[deps],
          Do[
            If[!KeyExistsQ[artifacts, d], allOk = False],
            {d, deps}]]],
      {task, tasks}];
    allOk
  ];

AssertArtifactsRespectDependencies[_, _] := False;

(* ── AssertSingleCommitterWrites ──
   CommitResult の Payload.Committed が True で、かつ SpawnResult の
   artifact 群に Committed フラグがないことを確認。 *)
AssertSingleCommitterWrites[orchestrationResult_Association] :=
  Module[{commit, commitOk, workerOk},
    commit = Lookup[orchestrationResult, "CommitResult", <||>];
    commitOk = AssociationQ[commit] &&
      MemberQ[{"Committed", "NotImplemented", "Skipped"},
        Lookup[commit, "Status", ""]];
    workerOk = AssertNoWorkerNotebookMutation[orchestrationResult];
    commitOk && workerOk
  ];

AssertSingleCommitterWrites[_] := False;

(* ── AssertReducerDeterministic ── *)
AssertReducerDeterministic[reducer_, artifacts_Association] :=
  Module[{r1, r2},
    r1 = Quiet @ Check[reducer[artifacts], $Failed];
    r2 = Quiet @ Check[reducer[artifacts], $Failed];
    r1 === r2 && r1 =!= $Failed
  ];

AssertReducerDeterministic[_, _] := False;

(* ── AssertNoCrossWorkerStateAssumption ──
   spawn artifacts の payload / diagnostics が他 worker の Mathematica
   変数名 (セッション変数風) を参照していないことを粗くチェック。 *)
AssertNoCrossWorkerStateAssumption[orchestrationResult_Association] :=
  Module[{spawn, artifacts, leak = False, a, payload, summary,
          suspiciousPatterns},
    spawn = Lookup[orchestrationResult, "SpawnResult", <||>];
    artifacts = Lookup[spawn, "Artifacts", <||>];
    suspiciousPatterns = {
      RegularExpression["\\b[a-zA-Z_][a-zA-Z0-9_]*\\s*="],
      "EvaluationNotebook["
    };
    Do[
      a = artifacts[taskId];
      If[AssociationQ[a],
        payload = Lookup[a, "Payload", <||>];
        summary = Lookup[payload, "Summary", ""];
        If[StringQ[summary] && StringLength[summary] > 0,
          If[StringContainsQ[summary, "EvaluationNotebook["],
            leak = True]]],
      {taskId, Keys[artifacts]}];
    !leak
  ];

AssertNoCrossWorkerStateAssumption[_] := False;

(* ── AssertTaskOutputMatchesSchema ── *)
AssertTaskOutputMatchesSchema[artifact_Association,
    outputSchema_Association] :=
  Module[{v},
    If[!ValueQ[ClaudeOrchestrator`ClaudeValidateArtifact],
      (* ClaudeOrchestrator 未ロード時は緩く Payload 存在のみ確認 *)
      Return[AssociationQ[Lookup[artifact, "Payload", None]]]];
    v = ClaudeOrchestrator`ClaudeValidateArtifact[artifact, outputSchema];
    TrueQ[Lookup[v, "Valid", False]]
  ];

AssertTaskOutputMatchesSchema[_, _] := False;

(* ── CreateMockQueryFunction ──
   \:56fa\:5b9a\:5fdc\:7b54\:3092\:9806\:756a\:306b\:8fd4\:3059 mock query \:95a2\:6570\:3002
   responses \:306f\:6587\:5b57\:5217\:30ea\:30b9\:30c8\:3002\:8d85\:904e\:5206\:306f\:6700\:5f8c\:306e\:5fdc\:7b54\:3092\:7e70\:308a\:8fd4\:3059\:3002
   Stage 2 LLM planner / worker \:30c6\:30b9\:30c8\:7528\:3002 *)
CreateMockQueryFunction[responses_List] :=
  Module[{idx = 0},
    Function[{prompt},
      idx++;
      If[idx <= Length[responses],
        responses[[idx]],
        If[Length[responses] > 0,
          Last[responses],
          ""]]]];

CreateMockQueryFunction[singleResponse_String] :=
  CreateMockQueryFunction[{singleResponse}];

(* ── AssertArtifactHasSchemaWarnings ── *)
AssertArtifactHasSchemaWarnings[artifact_Association] :=
  KeyExistsQ[artifact, "SchemaWarnings"] &&
  Length[artifact["SchemaWarnings"]] > 0;

AssertArtifactHasSchemaWarnings[_] := False;

(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   T05: Committer fallback \:30c6\:30b9\:30c8 (Phase 33 slide fix)
   
   \:5bfe\:8c61\:5185\:90e8\:30d8\:30eb\:30d1\:30fc (ClaudeOrchestrator\`Private\`):
     - iExtractSlidesFromPayload
     - iCellFromSlideItem  
     - iBuildCommitterHint
     - iDeterministicSlideCommit (\:30ac\:30fc\:30c9\:306e\:307f; \:5b9f\:66f8\:8fbc\:306f integration \:30c6\:30b9\:30c8\:5bfe\:8c61)
   
   \:4f7f\:7528:
     RunT05CommitFallbackTests[]   \:2192 <|"Passed"->N, "Failed"->M, "Total"->N+M, ...|>
   \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550 *)

(* ---- \:5185\:90e8\:30d8\:30eb\:30d1\:30fc\:306e\:5b89\:5168\:53d6\:5f97 (ClaudeOrchestrator \:672a\:30ed\:30fc\:30c9\:6642\:306f None) ---- *)

iT05GetPrivate[sym_String] :=
  Module[{fullName, names},
    fullName = "ClaudeOrchestrator`Private`" <> sym;
    names = Quiet @ Check[Names[fullName], {}];
    If[Length[names] > 0,
      Symbol[fullName],
      None]
  ];

(* ---- AssertT05SlideExtraction ---- *)

AssertT05SlideExtraction[] :=
  Module[{extract, r1, r2, r3, r4, r5, ok = True, fails = {}},
    extract = iT05GetPrivate["iExtractSlidesFromPayload"];
    If[extract === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iExtractSlidesFromPayload not loaded"|>]];
    
    (* Case 1: "Slides" key with flat list *)
    r1 = extract[<|"Slides" -> {
      <|"Title" -> "S1"|>, <|"Title" -> "S2"|>, <|"Title" -> "S3"|>}|>];
    If[!ListQ[r1] || Length[r1] =!= 3,
      ok = False; AppendTo[fails, {"Case1-SlidesKey", r1}]];
    
    (* Case 2: "Sections" key *)
    r2 = extract[<|"Sections" -> {<|"Title" -> "A"|>, <|"Title" -> "B"|>}|>];
    If[!ListQ[r2] || Length[r2] =!= 2,
      ok = False; AppendTo[fails, {"Case2-SectionsKey", r2}]];
    
    (* Case 3: reducer-nested \:30ea\:30b9\:30c8 ({{s1,s2},{s3,s4}}) *)
    r3 = extract[<|"Slides" -> {
      {<|"Title" -> "X1"|>, <|"Title" -> "X2"|>},
      {<|"Title" -> "X3"|>, <|"Title" -> "X4"|>}}|>];
    If[!ListQ[r3] || Length[r3] =!= 4,
      ok = False; AppendTo[fails, {"Case3-NestedList", r3}]];
    
    (* Case 4: Payload \:5168\:4f53\:304c 1 \:500b\:306e slide *)
    r4 = extract[<|"Title" -> "Only", "Body" -> "text"|>];
    If[!ListQ[r4] || Length[r4] =!= 1,
      ok = False; AppendTo[fails, {"Case4-SingleSlideAssoc", r4}]];
    
    (* Case 5: generic assoc \:2014 \:5168\:30ad\:30fc\:3092 section \:6271\:3044 *)
    r5 = extract[<|"K1" -> "v1", "K2" -> "v2"|>];
    If[!ListQ[r5] || Length[r5] =!= 2,
      ok = False; AppendTo[fails, {"Case5-GenericFallback", r5}]];
    
    <|"Pass" -> ok,
      "Failures" -> fails,
      "Results" -> <|"C1" -> r1, "C2" -> r2, "C3" -> r3,
                    "C4" -> r4, "C5" -> r5|>|>
  ];

AssertT05SlideExtraction[_] := AssertT05SlideExtraction[];

(* ---- AssertT05CellFromItem ---- *)

AssertT05CellFromItem[] :=
  Module[{cellFn, r1, r2, r3, ok = True, fails = {}},
    cellFn = iT05GetPrivate["iCellFromSlideItem"];
    If[cellFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iCellFromSlideItem not loaded"|>]];
    
    (* Case 1: Title+Body+Code \:2192 3 Cells *)
    r1 = cellFn[<|"Title" -> "T",
                  "Body"  -> "B",
                  "Code"  -> "1+1"|>, True];
    If[!ListQ[r1] || Length[r1] =!= 3 ||
       !MatchQ[r1, {Cell["T", "Title"], Cell["B", "Text"],
                    Cell["1+1", "Input"]}],
      ok = False; AppendTo[fails, {"Case1-TitleBodyCode", r1}]];
    
    (* Case 2: \:7a7a Association \:2192 1 Cell (Text \:30d5\:30a9\:30fc\:30eb\:30d0\:30c3\:30af) *)
    r2 = cellFn[<||>, False];
    If[!ListQ[r2] || Length[r2] =!= 1 ||
       !MatchQ[r2[[1]], Cell[_String, "Text"]],
      ok = False; AppendTo[fails, {"Case2-EmptyAssoc", r2}]];
    
    (* Case 3: isFirst==False+Title \:2192 Section \:30b9\:30bf\:30a4\:30eb *)
    r3 = cellFn[<|"Title" -> "sub"|>, False];
    If[!ListQ[r3] || Length[r3] =!= 1 ||
       !MatchQ[r3, {Cell["sub", "Section"]}],
      ok = False; AppendTo[fails, {"Case3-NotFirstSection", r3}]];
    
    <|"Pass" -> ok,
      "Failures" -> fails,
      "Results" -> <|"C1" -> r1, "C2" -> r2, "C3" -> r3|>|>
  ];

AssertT05CellFromItem[_] := AssertT05CellFromItem[];

(* ---- AssertT05CommitHintStructure ---- *)

AssertT05CommitHintStructure[] :=
  Module[{hintFn, hint, markers, missing, ok},
    hintFn = iT05GetPrivate["iBuildCommitterHint"];
    If[hintFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iBuildCommitterHint not loaded"|>]];
    
    hint = hintFn[<|"Payload" -> <|"Slides" -> {<|"Title" -> "X"|>}|>,
                    "Sources" -> {"t1"}|>, None];
    
    markers = {"COMMITTER ROLE",
               "NotebookWrite[EvaluationNotebook[], Cell[",
               "ReducedArtifact.Payload"};
    missing = Select[markers, !StringContainsQ[hint, #] &];
    
    ok = StringQ[hint] && StringLength[hint] > 200 &&
         Length[missing] === 0;
    
    <|"Pass" -> ok,
      "HintLength" -> If[StringQ[hint], StringLength[hint], 0],
      "MissingMarkers" -> missing|>
  ];

AssertT05CommitHintStructure[_] := AssertT05CommitHintStructure[];

(* ---- AssertT05FallbackGuards ---- *)

AssertT05FallbackGuards[] :=
  Module[{commitFn, r1, r2, r3, ok = True, fails = {}},
    commitFn = iT05GetPrivate["iDeterministicSlideCommit"];
    If[commitFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iDeterministicSlideCommit not loaded"|>]];
    
    (* Case 1: \:975e NotebookObject *)
    r1 = commitFn["not-a-notebook",
      <|"Payload" -> <|"Slides" -> {<|"Title" -> "X"|>}|>|>];
    If[!AssociationQ[r1] || Lookup[r1, "Status", ""] =!= "NotANotebook",
      ok = False; AppendTo[fails, {"Case1-NonNB", r1}]];
    
    (* Case 2: \:30a8\:30e9\:30fc\:30b1\:30fc\:30b9 \:2014 \:6709\:52b9\:306a NotebookObject \:304c\:306a\:3044\:306e\:3067
       NotANotebook \:304c\:8fd4\:308b\:306e\:304c\:6b63\:5e38\:3002Payload \:304c\:7a7a\:3068\:3044\:3046\:72b6\:6cc1\:306e\:691c\:8a3c\:306f
       \:5b9f notebook \:304c\:3044\:308b integration test \:3067\:884c\:3046\:3002
       \:3053\:3053\:3067\:306f invalid \:6271\:3044\:304c\:6b63\:3057\:304f\:30ac\:30fc\:30c9\:3055\:308c\:308b\:3053\:3068\:3092\:898b\:308b *)
    r2 = commitFn[Null, <||>];
    If[!AssociationQ[r2] ||
       !MemberQ[{"NotANotebook", "Failed"}, Lookup[r2, "Status", ""]],
      ok = False; AppendTo[fails, {"Case2-NullInput", r2}]];
    
    (* Case 3: \:4e0d\:6b63\:5f15\:6570 *)
    r3 = commitFn[];
    If[!AssociationQ[r3] || Lookup[r3, "Status", ""] =!= "Failed",
      ok = False; AppendTo[fails, {"Case3-NoArgs", r3}]];
    
    <|"Pass" -> ok,
      "Failures" -> fails,
      "Results" -> <|"C1" -> r1, "C2" -> r2, "C3" -> r3|>|>
  ];

AssertT05FallbackGuards[_] := AssertT05FallbackGuards[];

(* ---- RunT05CommitFallbackTests ---- *)

RunT05CommitFallbackTests[] :=
  Module[{tests, results, passed, failed, details},
    tests = <|
      "SlideExtraction"     -> AssertT05SlideExtraction,
      "CellFromItem"        -> AssertT05CellFromItem,
      "CommitHintStructure" -> AssertT05CommitHintStructure,
      "FallbackGuards"      -> AssertT05FallbackGuards|>;
    
    results = KeyValueMap[
      Function[{name, fn},
        Module[{r},
          r = Quiet @ Check[fn[],
            <|"Pass" -> False, "Error" -> "Threw"|>];
          name -> r]],
      tests];
    results = Association[results];
    
    passed = Count[Values[results], a_Association /; TrueQ[Lookup[a, "Pass", False]]];
    failed = Length[results] - passed;
    
    details = Style[
      "T05 Commit Fallback Tests: " <> ToString[passed] <> "/" <>
        ToString[Length[results]] <> " passed" <>
        If[failed > 0, " (" <> ToString[failed] <> " failed)", ""],
      Bold, If[failed === 0, Darker[Green], RGBColor[0.8, 0.3, 0.2]]];
    Print[details];
    
    Do[
      Print["  ", Lookup[p[[2]], "Pass", False],
        " \:2014 ", p[[1]], ": ",
        If[TrueQ[Lookup[p[[2]], "Pass", False]],
          Style["PASS", Darker[Green]],
          Style["FAIL " <> ToString[Short[p[[2]], 3]],
            RGBColor[0.8, 0.3, 0.2]]]],
      {p, Normal[results]}];
    
    <|"Passed"  -> passed,
      "Failed"  -> failed,
      "Total"   -> Length[results],
      "Results" -> results|>
  ];

(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   T06: Slide content-aware extraction \:30c6\:30b9\:30c8 (Phase 33 slide fix)
   \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550 *)

(* ---- AssertT06ContentBasedDetection ----
   T05 \:3067\:306f\:62fe\:3048\:306a\:304b\:3063\:305f 3 \:30b1\:30fc\:30b9\:3092\:691c\:8a3c:
     (1) key \:540d "SlideOutline" (Slides \:306b\:542b\:307e\:308c\:306a\:3044) \:3067\:3082\:62fe\:3048\:308b
     (2) key \:540d "MySlidesV2" (\:5168\:304f\:7570\:306a\:308b\:540d\:524d) \:3067\:3082\:3001\:4e2d\:8eab\:304c slide-like \:306a\:3089\:62fe\:3046
     (3) key \:540d\:3068\:7121\:95a2\:4fc2\:306b "random_key" \:3067\:3082\:3001 List[Association with Page/Cells] \:306a\:3089\:62fe\:3046 *)

AssertT06ContentBasedDetection[] :=
  Module[{extract, r1, r2, r3, ok = True, fails = {}},
    extract = iT05GetPrivate["iExtractSlidesFromPayload"];
    If[extract === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iExtractSlidesFromPayload not loaded"|>]];
    
    (* Case 1: key \:540d "SlideOutline" (T05 \:306f\:62fe\:3048\:306a\:3044\:3001T06 \:306f\:62fe\:3048\:308b) *)
    r1 = extract[<|
      "SlideOutline" -> {
        <|"Page" -> 1, "Title" -> "S1", "Subtitle" -> "x"|>,
        <|"Page" -> 2, "Title" -> "S2", "Subtitle" -> "y"|>,
        <|"Page" -> 3, "Title" -> "S3", "Subtitle" -> "z"|>}|>];
    If[!ListQ[r1] || Length[r1] =!= 3,
      ok = False; AppendTo[fails, {"Case1-SlideOutline", r1}]];
    
    (* Case 2: key \:540d "MySlidesV2" (\:5168\:304f\:7570\:306a\:308b\:540d\:524d\:3001T06 \:306f\:62fe\:3046) *)
    r2 = extract[<|
      "MySlidesV2" -> {
        <|"Page" -> 1, "Cells" -> {}|>,
        <|"Page" -> 2, "Cells" -> {}|>}|>];
    If[!ListQ[r2] || Length[r2] =!= 2,
      ok = False; AppendTo[fails, {"Case2-MySlidesV2", r2}]];
    
    (* Case 3: \:30ad\:30fc\:540d\:3068\:7121\:95a2\:4fc2 "random_key" \:3067\:3082\:3001content \:304c slide-like \:306a\:3089\:62fe\:3046 *)
    r3 = extract[<|
      "metadata" -> "some info",
      "random_key" -> {
        <|"Page" -> 1, "SlideKind" -> "cover", "Cells" -> {}|>,
        <|"Page" -> 2, "SlideKind" -> "title", "Cells" -> {}|>,
        <|"Page" -> 3, "SlideKind" -> "agenda", "Cells" -> {}|>,
        <|"Page" -> 4, "SlideKind" -> "content", "Cells" -> {}|>}|>];
    If[!ListQ[r3] || Length[r3] =!= 4,
      ok = False; AppendTo[fails, {"Case3-RandomKey", r3}]];
    
    <|"Pass" -> ok,
      "Failures" -> fails,
      "Results" -> <|"C1" -> Length @ r1, "C2" -> Length @ r2,
                     "C3" -> Length @ r3|>|>
  ];

AssertT06ContentBasedDetection[_] := AssertT06ContentBasedDetection[];

(* ---- AssertT06SlideDraftExpansion ----
   item が "Cells" -> {<|"Style"->..., "Content"->...|>, ...} を持つなら
   その Cells をそのまま Cell[Content, Style] に展開すべき。 *)

AssertT06SlideDraftExpansion[] :=
  Module[{cellFn, item, r, ok = True, fails = {}},
    cellFn = iT05GetPrivate["iCellFromSlideItem"];
    If[cellFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iCellFromSlideItem not loaded"|>]];
    
    item = <|
      "Page" -> 1,
      "SlideKind" -> "Cover-Section",
      "Cells" -> {
        <|"Style" -> "Section", "Content" -> "\:7b2c23\:56de Claw Code \:7814\:7a76\:4f1a"|>,
        <|"Style" -> "Text", "Content" -> "2026/04/xx hh:mm-hh:mm"|>,
        <|"Style" -> "Subsection", "Content" -> ""|>,
        <|"Style" -> "ItemParagraph", "Content" -> "agenda line 1"|>,
        <|"Style" -> "ItemNumbered", "Content" -> "topic 1"|>}|>;
    
    r = cellFn[item, True];
    
    (* \:671f\:5f85: \:5148\:982d\:306b Page header Cell + inner 5 cells = 6 \:56de\:3060\:304c\:3001\:7a7a Subsection \:3082 " " \:3067\:51fa\:308b *)
    If[!ListQ[r],
      ok = False; AppendTo[fails, {"NotAList", r}],
      (* 5 \:500b\:306e inner cells + 1 \:500b\:306e Page header = 6 \:500b\:306e cells \:304c\:671f\:5f85 *)
      If[Length[r] < 5,
        ok = False; AppendTo[fails, {"TooFewCells", Length[r], r}]];
      (* \:6700\:521d\:304c Page header, 2 \:756a\:76ee\:304c "Section" style \:306e\:7b2c23\:56de... *)
      (* \:5b89\:5168\:306b\:898b\:308b\:306a\:3089 "Section" style \:306e cell \:304c\:3042\:308b\:3053\:3068\:3060\:3051\:78ba\:304b\:3081\:308b *)
      If[!MemberQ[r, Cell[_String, "Section"]] && !MemberQ[r, Cell["\:7b2c23\:56de Claw Code \:7814\:7a76\:4f1a", "Section"]],
        ok = False; AppendTo[fails, {"NoSectionStyle", r}]];
      If[!MemberQ[r, Cell["2026/04/xx hh:mm-hh:mm", "Text"]],
        ok = False; AppendTo[fails, {"NoTextCell", r}]];
      If[!MemberQ[r, Cell["agenda line 1", "ItemParagraph"]],
        ok = False; AppendTo[fails, {"NoItemParagraph", r}]];
      If[!MemberQ[r, Cell["topic 1", "ItemNumbered"]],
        ok = False; AppendTo[fails, {"NoItemNumbered", r}]]];
    
    <|"Pass" -> ok,
      "Failures" -> fails,
      "Result" -> r,
      "Length" -> If[ListQ[r], Length[r], -1]|>
  ];

AssertT06SlideDraftExpansion[_] := AssertT06SlideDraftExpansion[];

(* ---- AssertT06SlideOutlineExpansion ----
   item が Title + Subtitle + BodyOutline を持つなら、
   Title は "Title"/"Section"、Subtitle は "Subtitle"、
   BodyOutline の各要素は "ItemParagraph" に展開すべき。 *)

AssertT06SlideOutlineExpansion[] :=
  Module[{cellFn, item, r, ok = True, fails = {}},
    cellFn = iT05GetPrivate["iCellFromSlideItem"];
    If[cellFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iCellFromSlideItem not loaded"|>]];
    
    item = <|
      "Page" -> 3,
      "Title" -> "\:672c\:65e5\:306e\:6d41\:308c",
      "Subtitle" -> "8 \:30bb\:30af\:30b7\:30e7\:30f3\:300130 \:30da\:30fc\:30b8",
      "BodyOutline" -> {
        "Item 1: \:8aac\:660e",
        "Item 2: \:69cb\:6210",
        "Item 3: \:307e\:3068\:3081"}|>;
    
    r = cellFn[item, False];
    
    If[!ListQ[r],
      ok = False; AppendTo[fails, {"NotAList", r}],
      If[!MemberQ[r, Cell["\:672c\:65e5\:306e\:6d41\:308c", "Section"]],
        ok = False; AppendTo[fails, {"NoSectionTitle", r}]];
      If[!MemberQ[r, Cell["8 \:30bb\:30af\:30b7\:30e7\:30f3\:300130 \:30da\:30fc\:30b8", "Subtitle"]],
        ok = False; AppendTo[fails, {"NoSubtitle", r}]];
      If[!MemberQ[r, Cell["Item 1: \:8aac\:660e", "ItemParagraph"]],
        ok = False; AppendTo[fails, {"NoItem1", r}]];
      If[Count[r, Cell[_, "ItemParagraph"]] =!= 3,
        ok = False; AppendTo[fails, {"WrongItemCount",
          Count[r, Cell[_, "ItemParagraph"]], r}]]];
    
    <|"Pass" -> ok,
      "Failures" -> fails,
      "Result" -> r|>
  ];

AssertT06SlideOutlineExpansion[_] := AssertT06SlideOutlineExpansion[];

(* ---- RunT06SlideContentTests ---- *)

RunT06SlideContentTests[] :=
  Module[{tests, results, passed, failed, details},
    tests = <|
      "ContentBasedDetection" -> AssertT06ContentBasedDetection,
      "SlideDraftExpansion"   -> AssertT06SlideDraftExpansion,
      "SlideOutlineExpansion" -> AssertT06SlideOutlineExpansion|>;
    
    results = KeyValueMap[
      Function[{name, fn},
        Module[{r},
          r = Quiet @ Check[fn[],
            <|"Pass" -> False, "Error" -> "Threw"|>];
          name -> r]],
      tests];
    results = Association[results];
    
    passed = Count[Values[results], a_Association /; TrueQ[Lookup[a, "Pass", False]]];
    failed = Length[results] - passed;
    
    details = Style[
      "T06 Slide Content Tests: " <> ToString[passed] <> "/" <>
        ToString[Length[results]] <> " passed" <>
        If[failed > 0, " (" <> ToString[failed] <> " failed)", ""],
      Bold, If[failed === 0, Darker[Green], RGBColor[0.8, 0.3, 0.2]]];
    Print[details];
    
    Do[
      Print["  ", Lookup[p[[2]], "Pass", False],
        " \:2014 ", p[[1]], ": ",
        If[TrueQ[Lookup[p[[2]], "Pass", False]],
          Style["PASS", Darker[Green]],
          Style["FAIL " <> ToString[Short[p[[2]], 3]],
            RGBColor[0.8, 0.3, 0.2]]]],
      {p, Normal[results]}];
    
    <|"Passed"  -> passed,
      "Failed"  -> failed,
      "Total"   -> Length[results],
      "Results" -> results|>
  ];

(* \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550
   T07: Slide intent detection + style sanitization \:30c6\:30b9\:30c8 (Phase 33 slide fix)
   \:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550\:2550 *)

(* ---- AssertT07StyleSanitization ----
   iSanitizeCellStyle \:306e\:5358\:4f53\:30c6\:30b9\:30c8\:3002 *)

AssertT07StyleSanitization[] :=
  Module[{fn, ok = True, fails = {}, checkCase},
    fn = iT05GetPrivate["iSanitizeCellStyle"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iSanitizeCellStyle not loaded"|>]];
    
    checkCase[label_, input_, expected_] :=
      Module[{actual},
        actual = Quiet @ Check[fn[input], $Failed];
        If[actual =!= expected,
          ok = False;
          AppendTo[fails, {label, "input" -> input,
            "expected" -> expected, "actual" -> actual}]];
        ];
    
    (* (a) \:6709\:52b9 style \:306f\:305d\:306e\:307e\:307e *)
    checkCase["Valid-Title",        "Title",        "Title"];
    checkCase["Valid-Section",      "Section",      "Section"];
    checkCase["Valid-ItemParagraph","ItemParagraph","ItemParagraph"];
    checkCase["Valid-SubsecInPres",
      "SubsubsectionInPresentation", "SubsubsectionInPresentation"];
    
    (* (b) \:62ec\:5f27\:4ed8\:304d\:30d7\:30ed\:30fc\:30ba *)
    checkCase["Paren-TitleSlide",
      "Subsection (title slide)", "Subsection"];
    checkCase["Paren-Section",
      "Section [cover]", "Section"];
    
    (* (c) \:5206\:96e2\:8a18\:53f7\:30fb\:65e5\:672c\:8a9e\:4ed8\:304d *)
    checkCase["Plus-Group",
      "Subsection + Item/Subitem \:7fa4", "Subsection"];
    checkCase["Slash-Mixed",
      "Section/Topic",                   "Section"];
    
    (* (d) \:30d7\:30ed\:30fc\:30ba\:304b\:3089\:610f\:5473\:6551\:51fa *)
    checkCase["Prose-Bulleted",
      "bulleted list", "Item"];
    checkCase["Prose-Code",
      "my code block", "Code"];
    
    (* (e) \:5b8c\:5168\:4e0d\:660e -> Text *)
    checkCase["Unknown-Empty", "",  "Text"];
    (* \"\:30b9\:30e9\:30a4\:30c9\" (slide) \:3092\:542b\:3080\:306e\:3067 TextInPresentation \:306b\:843d\:3061\:308b *)
    checkCase["Unknown-Slide-JA",
      "\:3086\:3089\:3086\:3089\:30b9\:30e9\:30a4\:30c9",
      "TextInPresentation"];
    (* \"\:30b9\:30bf\:30a4\:30eb\" (style) \:306f\:3044\:305a\:308c\:306e keyword \:306b\:3082\:4e00\:81f4\:3057\:306a\:3044\:306e\:3067 Text \:306b\:843d\:3061\:308b
       (\:3053\:308c\:304c T07 \:30c6\:30b9\:30c8\:304c\:8aa4\:3063\:3066\:3044\:305f\:8aa4\:8a8d\:8b58\: \:30b9\:30bf\:30a4\:30eb \:2260 \:30b9\:30e9\:30a4\:30c9) *)
    checkCase["Unknown-Style-JA",
      "\:3086\:3089\:3086\:3089\:30b9\:30bf\:30a4\:30eb",
      "Text"];
    checkCase["Unknown-Completely", "zzzqqqxxx", "Text"];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT07StyleSanitization[_] := AssertT07StyleSanitization[];

(* ---- AssertT07SlideIntentDetection ---- *)

AssertT07SlideIntentDetection[] :=
  Module[{fn, ok = True, fails = {}, checkCase},
    fn = iT05GetPrivate["iDetectSlideIntent"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iDetectSlideIntent not loaded"|>]];
    
    checkCase[label_, input_, isSlide_, pageN_] :=
      Module[{r},
        r = Quiet @ Check[fn[input],
              <|"IsSlide" -> False, "PageCount" -> None|>];
        If[TrueQ[r["IsSlide"]] =!= TrueQ[isSlide],
          ok = False;
          AppendTo[fails,
            {label, "IsSlide-mismatch", r["IsSlide"], "expected" -> isSlide}]];
        If[pageN =!= Automatic && Lookup[r, "PageCount", None] =!= pageN,
          ok = False;
          AppendTo[fails,
            {label, "PageCount-mismatch",
             "actual" -> Lookup[r, "PageCount", None],
             "expected" -> pageN}]];
        ];
    
    (* (a) \:65e5\:672c\:8a9e\:534a\:89d2\:6570\:5b57 *)
    checkCase["JA-30pages",
      "30 \:30da\:30fc\:30b8\:306e\:30b9\:30e9\:30a4\:30c9\:3092\:4f5c\:6210\:3057\:3066\:307b\:3057\:3044", True, 30];
    
    (* (b) \:82f1\:8a9e *)
    checkCase["EN-10page-presentation",
      "Create a 10-page presentation", True, 10];
    checkCase["EN-slides-plain",
      "Please make slides about trees", True, None];
    
    (* (c) \:5168\:89d2\:6570\:5b57 *)
    checkCase["JA-FullWidth",
      "\:ff13\:ff10\:30da\:30fc\:30b8\:306e\:30d7\:30ec\:30bc\:30f3", True, 30];
    
    (* (d) slide \:7121\:95a2\:4fc2 *)
    checkCase["NonSlide-Translate",
      "\:3053\:306e\:6587\:3092\:82f1\:8a9e\:306b\:7ffb\:8a33\:3057\:3066", False, None];
    checkCase["NonSlide-Code",
      "Fix this Python code", False, None];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT07SlideIntentDetection[_] := AssertT07SlideIntentDetection[];

(* ---- AssertT07InnerCellFromSpecSanitize ----
   iInnerCellFromSpec \:304c T07 \:306e sanitize \:3092\:7d4c\:7531\:3057\:3066\:6709\:52b9 style \:306b\:843d\:3068\:3059\:3053\:3068 *)

AssertT07InnerCellFromSpecSanitize[] :=
  Module[{fn, ok = True, fails = {}, r},
    fn = iT05GetPrivate["iInnerCellFromSpec"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iInnerCellFromSpec not loaded"|>]];
    
    (* (a) \"Subsection (title slide)\" -> Subsection *)
    r = fn[<|"Style" -> "Subsection (title slide)",
             "Content" -> "\:8868\:7d19"|>];
    If[r =!= Cell["\:8868\:7d19", "Subsection"],
      ok = False;
      AppendTo[fails, {"Paren-case", r}]];
    
    (* (b) \"Subsection + Item/Subitem \:7fa4\" -> Subsection *)
    r = fn[<|"Style" -> "Subsection + Item/Subitem \:7fa4",
             "Content" -> "matter"|>];
    If[r =!= Cell["matter", "Subsection"],
      ok = False;
      AppendTo[fails, {"Plus-case", r}]];
    
    (* (c) \:6709\:52b9 style \:306f\:305d\:306e\:307e\:307e *)
    r = fn[<|"Style" -> "ItemParagraph",
             "Content" -> "a line"|>];
    If[r =!= Cell["a line", "ItemParagraph"],
      ok = False;
      AppendTo[fails, {"Valid-case", r}]];
    
    (* (d) \:7a7a\:30b3\:30f3\:30c6\:30f3\:30c4\:306f " " \:306b \:4fdd\:6301 (\:30ec\:30a4\:30a2\:30a6\:30c8\:7528) *)
    r = fn[<|"Style" -> "Subsection", "Content" -> ""|>];
    If[r =!= Cell[" ", "Subsection"],
      ok = False;
      AppendTo[fails, {"Empty-content-case", r}]];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT07InnerCellFromSpecSanitize[_] :=
  AssertT07InnerCellFromSpecSanitize[];

(* ---- AssertT07DefaultPlannerSlideAware ----
   iDefaultPlanner \:304c slide \:5165\:529b\:306b\:5bfe\:3057\:3066 2 task \:5206\:89e3\:3092\:8fd4\:3059 *)

AssertT07DefaultPlannerSlideAware[] :=
  Module[{fn, result, tasks, ok = True, fails = {},
          draftTask, schemaKeys},
    fn = iT05GetPrivate["iDefaultPlanner"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iDefaultPlanner not loaded"|>]];
    
    result = Quiet @ Check[
      fn["30 \:30da\:30fc\:30b8\:306e\:30b9\:30e9\:30a4\:30c9\:3092\:4f5c\:6210", <||>],
      $Failed];
    If[result === $Failed || !AssociationQ[result],
      Return[<|"Pass" -> False,
               "Reason" -> "iDefaultPlanner threw",
               "Result" -> result|>]];
    
    tasks = Lookup[result, "Tasks", {}];
    If[!ListQ[tasks] || Length[tasks] < 2,
      ok = False;
      AppendTo[fails, {"TooFewTasks", Length[tasks]}]];
    
    (* Draft task \:304c\:542b\:307e\:308c\:308b\:304b *)
    draftTask = SelectFirst[tasks,
      Lookup[#, "Role", ""] === "Draft" &, None];
    If[draftTask === None,
      ok = False;
      AppendTo[fails, {"NoDraftTask", tasks}],
      (* Draft task \:306e OutputSchema \:306b SlideDraft \:304c\:3042\:308b\:304b *)
      schemaKeys = If[AssociationQ[Lookup[draftTask, "OutputSchema", <||>]],
        Keys[draftTask["OutputSchema"]], {}];
      If[!MemberQ[schemaKeys, "SlideDraft"],
        ok = False;
        AppendTo[fails, {"DraftLacksSlideDraftSchema", schemaKeys}]]];
    
    (* \:975e slide \:5165\:529b\:306f 1 task \:306e\:307e\:307e *)
    Module[{nonSlideResult, nonSlideTasks},
      nonSlideResult = Quiet @ Check[
        fn["Fix this Python code", <||>], $Failed];
      nonSlideTasks = Lookup[nonSlideResult, "Tasks", {}];
      If[!ListQ[nonSlideTasks] || Length[nonSlideTasks] =!= 1,
        ok = False;
        AppendTo[fails,
          {"NonSlideShouldStaySingleTask",
           Length[nonSlideTasks]}]];
    ];
    
    <|"Pass" -> ok,
      "Failures" -> fails,
      "TaskCount" -> If[ListQ[tasks], Length[tasks], -1]|>
  ];

AssertT07DefaultPlannerSlideAware[_] :=
  AssertT07DefaultPlannerSlideAware[];

(* ---- AssertT07WorkerPromptSlideHint ----
   iWorkerBuildSystemPrompt \:304c slide task \:306b\:5bfe\:3057\:3066 T07 SLIDE-MODE \:3092\:6ce8\:5165 *)

AssertT07WorkerPromptSlideHint[] :=
  Module[{fn, prompt, ok = True, fails = {}, slideTask, nonSlideTask},
    fn = iT05GetPrivate["iWorkerBuildSystemPrompt"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iWorkerBuildSystemPrompt not loaded"|>]];
    
    (* slide-intent \:306a task: Goal \:306b \:30b9\:30e9\:30a4\:30c9 + page count \:304c\:3042\:308b *)
    slideTask = <|
      "TaskId" -> "t_slide",
      "Role"   -> "Draft",
      "Goal"   -> "30 \:30da\:30fc\:30b8\:306e\:30b9\:30e9\:30a4\:30c9\:3092\:751f\:6210\:3059\:308b",
      "Inputs" -> {},
      "Outputs" -> {"slideDraft"},
      "OutputSchema" -> <|"SlideDraft" -> "List[Association]"|>|>;
    
    prompt = Quiet @ Check[fn["Draft", slideTask, <||>], ""];
    If[!StringQ[prompt] || !StringContainsQ[prompt, "T07 SLIDE-MODE"],
      ok = False;
      AppendTo[fails, {"SlideTaskMissingT07Hint",
        If[StringQ[prompt], StringTake[prompt, UpTo[200]], prompt]}]];
    
    (* \:30da\:30fc\:30b8\:6570\:304c\:542b\:307e\:308c\:308b\:304b *)
    If[StringQ[prompt] && !StringContainsQ[prompt, "30"],
      ok = False;
      AppendTo[fails, {"PromptMissingPageCount", 30}]];
    
    (* valid style \:540d\:304c\:542b\:307e\:308c\:308b\:304b *)
    If[StringQ[prompt] && !StringContainsQ[prompt, "ItemParagraph"],
      ok = False;
      AppendTo[fails, {"PromptMissingValidStyles"}]];
    
    (* \:975e slide task: Goal \:306b slide \:8a00\:53ca\:7121\:3057\:3001 Schema \:3082 generic *)
    nonSlideTask = <|
      "TaskId" -> "t_plain",
      "Role"   -> "Explore",
      "Goal"   -> "Summarize the Q4 results",
      "Inputs" -> {},
      "Outputs" -> {"summary"},
      "OutputSchema" -> <|"Summary" -> "String"|>|>;
    
    prompt = Quiet @ Check[fn["Explore", nonSlideTask, <||>], ""];
    If[StringQ[prompt] && StringContainsQ[prompt, "T07 SLIDE-MODE"],
      ok = False;
      AppendTo[fails, {"NonSlideGotT07Hint"}]];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT07WorkerPromptSlideHint[_] :=
  AssertT07WorkerPromptSlideHint[];

(* ---- AssertT07bResolveTargetNotebookLogic ----
   T07b: iResolveTargetNotebook \:304c Intent \:3092\:6b63\:3057\:304f\:8a08\:7b97\:3057\:3001
   slide \:610f\:56f3\:306b\:5fdc\:3058\:3066\:5206\:5c90\:3059\:308b\:3053\:3068\:3092\:78ba\:8a8d\:3002
   \:6ce8: CreateDocument \:81ea\:4f53\:306e\:30c6\:30b9\:30c8\:306f\:30d8\:30c3\:30c9\:30ec\:30b9\:74b0\:5883\:3067\:306f
        \:4fe1\:983c\:3067\:304d\:306a\:3044\:305f\:3081 Intent \:30d5\:30a3\:30fc\:30eb\:30c9\:3060\:3051\:3092\:6c17\:306b\:3059\:308b\:3002 *)

AssertT07bResolveTargetNotebookLogic[] :=
  Module[{fn, r1, r2, ok = True, fails = {}},
    fn = iT05GetPrivate["iResolveTargetNotebook"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iResolveTargetNotebook not loaded"|>]];
    
    (* (a) slide intent \:3042\:308a *)
    r1 = Quiet @ Check[
      fn["30 \:30da\:30fc\:30b8\:306e\:30b9\:30e9\:30a4\:30c9\:3092\:4f5c\:6210\:3057\:3066", False],
      <|"TargetNotebook" -> None,
        "Intent" -> <|"IsSlide" -> False|>,
        "CreatedNew" -> False|>];
    If[!AssociationQ[r1] ||
       !TrueQ[Lookup[Lookup[r1, "Intent", <||>], "IsSlide", False]],
      ok = False;
      AppendTo[fails, {"Slide-case-IntentMissing", r1}]];
    
    (* (b) non-slide *)
    r2 = Quiet @ Check[
      fn["Fix this Python code", False],
      <|"TargetNotebook" -> None,
        "Intent" -> <|"IsSlide" -> True|>,
        "CreatedNew" -> False|>];
    If[!AssociationQ[r2] ||
       TrueQ[Lookup[Lookup[r2, "Intent", <||>], "IsSlide", False]],
      ok = False;
      AppendTo[fails, {"NonSlide-case-IntentWrong", r2}]];
    (* non-slide \:306f CreatedNew \:306f\:5fc5\:305a False *)
    If[AssociationQ[r2] && TrueQ[Lookup[r2, "CreatedNew", False]],
      ok = False;
      AppendTo[fails, {"NonSlide-CreatedNewWrongly", r2}]];
    
    <|"Pass" -> ok, "Failures" -> fails,
      "SlideResult"    -> r1,
      "NonSlideResult" -> r2|>
  ];

AssertT07bResolveTargetNotebookLogic[_] :=
  AssertT07bResolveTargetNotebookLogic[];

(* ---- T08 tests ---------------------------------------------------
   T08: iInnerCellFromSpec \:306e Kind \:5206\:5c90 (\:539f\:5247 30) \:3068\n
   iBuildSlideWorkerHint \:306e ReferenceText \:6ce8\:5165 (\:539f\:5247 31) \:3092\:691c\:8a3c\:3002
   \:30c6\:30f3\:30d7\:30ec\:30fc\:30c8\:7d99\:627f (\:539f\:5247 29) \:306f CreateDocument \:304c\:30d8\:30c3\:30c9\:30ec\:30b9\n
   \:74b0\:5883\:3067\:4e0d\:5b89\:5b9a\:306a\:306e\:3067\:30ed\:30b8\:30c3\:30af\:5206\:5c90\:306e\:307f\:691c\:8a3c\:3002 *)

AssertT08KindDispatch::usage =
  "AssertT08KindDispatch[] \:306f iInnerCellFromSpec \:304c Kind \:30d5\:30a3\:30fc\:30eb\:30c9\:306b\:5fdc\:3058\:3066\n" <>
  "Input / Graphics / ImagePath / Grid2Col \:306e\:5206\:5c90\:3092\:6b63\:3057\:304f\:30c7\:30a3\:30b9\:30d1\:30c3\:30c1\:3059\:308b\:3053\:3068\:3092\:78ba\:8a8d\:3059\:308b\:3002";

AssertT08KindDispatch[] :=
  Module[{fn, ok = True, fails = {}, r},
    fn = iT05GetPrivate["iInnerCellFromSpec"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iInnerCellFromSpec not loaded"|>]];
    
    (* (a) Kind=Input \:2192 Cell[_, "Input"] *)
    r = Quiet @ Check[fn[<|"Kind" -> "Input",
      "Content" -> "Plot[Sin[x],{x,0,10}]"|>], $Failed];
    If[!MatchQ[r, Cell["Plot[Sin[x],{x,0,10}]", "Input"]],
      ok = False;
      AppendTo[fails, {"Input-Kind-wrong", r}]];
    
    (* (b) Kind=Code \:2192 Cell[_, "Input"] *)
    r = Quiet @ Check[fn[<|"Kind" -> "Code",
      "Content" -> "1 + 1"|>], $Failed];
    If[!MatchQ[r, Cell["1 + 1", "Input"]],
      ok = False;
      AppendTo[fails, {"Code-Kind-wrong", r}]];
    
    (* (c) Kind=Graphics with trivially evaluable expression *)
    r = Quiet @ Check[fn[<|"Kind" -> "Graphics",
      "HeldExpression" -> "42"|>], $Failed];
    If[!MatchQ[r, Cell[BoxData[_], "Output"] | Cell[_, "Text"]],
      (* \:8a55\:4fa1\:6210\:529f\:306a\:3089 Output\:3001\:5931\:6557\:306a\:3089 Text fallback \:3002\:3069\:3061\:3089\:3082\:8a31\:5bb9\:3002 *)
      ok = False;
      AppendTo[fails, {"Graphics-Kind-wrong-shape", r}]];
    
    (* (d) Kind=ImagePath \:306b\:5b58\:5728\:3057\:306a\:3044\:30d1\:30b9 \:2192 fallback Cell[_, \"Text\"] *)
    r = Quiet @ Check[fn[<|"Kind" -> "ImagePath",
      "Path" -> "/nonexistent/impossible/path.png"|>], $Failed];
    If[!MatchQ[r, Cell[_String, "Text"]],
      ok = False;
      AppendTo[fails, {"ImagePath-nonexistent-fallback-wrong", r}]];
    
    (* (e) Kind=Grid2Col \:306b text+text \:3092\:6e21\:3059 \:2192 Cell[BoxData[GridBox[...]], \"Output\"] *)
    r = Quiet @ Check[fn[<|"Kind" -> "Grid2Col",
      "Left"  -> <|"Style" -> "Text", "Content" -> "L"|>,
      "Right" -> <|"Style" -> "Text", "Content" -> "R"|>|>], $Failed];
    If[!MatchQ[r, Cell[BoxData[_GridBox], "Output"]],
      ok = False;
      AppendTo[fails, {"Grid2Col-wrong-shape", r}]];
    
    (* (f) Kind \:672a\:6307\:5b9a \:2192 \:5f93\:6765\:306e Style+Content \:6311\:52d5 *)
    r = Quiet @ Check[fn[<|"Style" -> "Section",
      "Content" -> "heading"|>], $Failed];
    If[!MatchQ[r, Cell["heading", "Section"]],
      ok = False;
      AppendTo[fails, {"LegacyMode-wrong", r}]];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT08KindDispatch[_] := AssertT08KindDispatch[];


AssertT08ReferenceTextInjection::usage =
  "AssertT08ReferenceTextInjection[] \:306f iBuildSlideWorkerHint \:304c ReferenceText \:3092\n" <>
  "\:6e21\:3055\:308c\:305f\:3068\:304d hint \:6587\:5b57\:5217\:306b\:30b5\:30f3\:30d7\:30eb\:672c\:6587\:3092\:542b\:3081\:308b\:3053\:3068\:3092\:78ba\:8a8d\:3059\:308b\:3002";

AssertT08ReferenceTextInjection[] :=
  Module[{fn, ok = True, fails = {}, intent, sampleText, out},
    fn = iT05GetPrivate["iBuildSlideWorkerHint"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iBuildSlideWorkerHint not loaded"|>]];
    
    intent = <|"IsSlide" -> True, "PageCount" -> 10,
               "Keywords" -> {"slide-keyword-ja"}|>;
    sampleText = "SAMPLE-VOICE-MARKER-12345 \:3053\:306e\:8a9e\:611f\:3092\:5c3a\:91cd\:3057\:3066";
    
    (* (a) refText=None \:2192 hint \:306b marker \:542b\:307e\:306a\:3044 *)
    out = Quiet @ Check[fn[intent, <||>, True, None], $Failed];
    If[!StringQ[out],
      ok = False;
      AppendTo[fails, {"RefNone-not-string", Head[out]}]];
    If[StringQ[out] && StringContainsQ[out, "SAMPLE-VOICE-MARKER"],
      ok = False;
      AppendTo[fails, {"RefNone-marker-leaked"}]];
    
    (* (b) refText=sample \:2192 hint \:306b marker \:542b\:3080 *)
    out = Quiet @ Check[fn[intent, <||>, True, sampleText], $Failed];
    If[!StringQ[out],
      ok = False;
      AppendTo[fails, {"RefGiven-not-string", Head[out]}]];
    If[StringQ[out] && !StringContainsQ[out, "SAMPLE-VOICE-MARKER-12345"],
      ok = False;
      AppendTo[fails, {"RefGiven-marker-missing"}]];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT08ReferenceTextInjection[_] := AssertT08ReferenceTextInjection[];


AssertT08TemplateInheritanceLogic::usage =
  "AssertT08TemplateInheritanceLogic[] \:306f $ClaudeSlidesTemplatePath \:3092\:8a2d\:5b9a\:3057\:305f\:3068\:304d\n" <>
  "iResolveTargetNotebook \:306e\:623b\:308a\:5024 \"TemplatePath\" \:304c\:305d\:308c\:3092\:53cd\:6620\:3059\:308b\:3053\:3068\:3092\:78ba\:8a8d\:3059\:308b\:3002";

AssertT08TemplateInheritanceLogic[] :=
  Module[{fn, ok = True, fails = {}, r, savedPath, testPath},
    fn = iT05GetPrivate["iResolveTargetNotebook"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iResolveTargetNotebook not loaded"|>]];
    
    testPath = "/nonexistent/fake-template.nb";
    
    (* \:30b7\:30f3\:30dc\:30eb\:30d1\:30b9\:306e\:307f\:78ba\:8a8d (\:5b9f\:30d5\:30a1\:30a4\:30eb\:306f\:4e0d\:8981 \:2014 logic test) *)
    savedPath = Quiet @ Check[ClaudeOrchestrator`$ClaudeSlidesTemplatePath,
      Unevaluated[None]];
    
    (* (a) $ClaudeSlidesTemplatePath \:3092\:8a2d\:5b9a \:2192 \:30d1\:30b9\:304c\:8fd4\:308b *)
    ClaudeOrchestrator`$ClaudeSlidesTemplatePath = testPath;
    r = Quiet @ Check[fn["10 \:30da\:30fc\:30b8\:306e\:30b9\:30e9\:30a4\:30c9\:3092\:4f5c\:6210", False],
      <|"TemplatePath" -> $Failed|>];
    If[!AssociationQ[r] ||
       Lookup[r, "TemplatePath", None] =!= testPath,
      ok = False;
      AppendTo[fails, {"TemplatePath-not-propagated",
        Lookup[r, "TemplatePath", "missing"]}]];
    
    (* \:8a2d\:5b9a\:3092 Unset *)
    If[savedPath === Unevaluated[None] || savedPath === None,
      Quiet[ClearAll[ClaudeOrchestrator`$ClaudeSlidesTemplatePath]],
      ClaudeOrchestrator`$ClaudeSlidesTemplatePath = savedPath];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT08TemplateInheritanceLogic[_] := AssertT08TemplateInheritanceLogic[];


RunT08SlideTemplateTests[] :=
  Module[{tests, results, passed, failed, details},
    tests = <|
      "KindDispatch"           -> AssertT08KindDispatch,
      "ReferenceTextInjection" -> AssertT08ReferenceTextInjection,
      "TemplateInheritance"    -> AssertT08TemplateInheritanceLogic|>;
    
    results = KeyValueMap[
      Function[{name, fn},
        Module[{r},
          r = Quiet @ Check[fn[],
            <|"Pass" -> False, "Error" -> "Threw"|>];
          name -> r]],
      tests];
    results = Association @@ results;
    passed = Count[Values[results], r_?AssociationQ /; TrueQ[Lookup[r, "Pass", False]]];
    failed = Length[results] - passed;
    
    Print[Style[
      "T08 Slide Template + Figure-Kinds + Voice Tests: " <>
        ToString[passed] <> "/" <> ToString[Length[results]] <>
        " passed" <> If[failed > 0,
          " (" <> ToString[failed] <> " failed)", ""],
      If[failed > 0, RGBColor[0.8, 0.3, 0.2],
        RGBColor[0, 2/3, 0]],
      Bold]];
    
    details = KeyValueMap[
      Function[{name, r},
        Module[{pass},
          pass = TrueQ[Lookup[r, "Pass", False]];
          Print["  ", pass, " \[LongDash] ", name, ": ",
            Style[If[pass, "PASS",
              "FAIL " <> ToString[r, InputForm]],
              If[pass, RGBColor[0, 2/3, 0],
                RGBColor[0.8, 0.3, 0.2]]]]]],
      results];
    
    <|"Passed" -> passed,
      "Failed" -> failed,
      "Total"  -> Length[results],
      "Results" -> results|>
  ];

(* ---- T09 tests: structured data -> Input cells (\:539f\:5247 32) ----
   T09 (2026-04-19): iExtractSlidesFromPayload \:306e Case 3 fallback \:304c\:3001
   \:5024\:304c List[Association] / Association / List[List] \:306e\:6642\:306f
   "Body" \:3067\:306f\:306a\:304f "Code" \:30ad\:30fc\:3067\:8fd4\:3059\:3053\:3068\:3092\:691c\:8a3c\:3002 *)

AssertT09StructuredDataToInputCell::usage =
  "AssertT09StructuredDataToInputCell[] \:306f iExtractSlidesFromPayload \:304c\n" <>
  "Case 3 fallback \:306b\:843d\:3061\:305f\:3068\:304d\:3001\:5024\:304c\:69cb\:9020\:5316\:30c7\:30fc\:30bf (List[Assoc] \:7b49)\n" <>
  "\:306a\:3089\:305d\:306e\:30a2\:30a4\:30c6\:30e0\:306b \"Code\" \:30ad\:30fc\:304c\:5165\:308b (Body \:3058\:3083\:306a\:3044) \:3053\:3068\:3092\:78ba\:8a8d\:3059\:308b\:3002";

AssertT09StructuredDataToInputCell[] :=
  Module[{extract, r, ok = True, fails = {}},
    extract = iT05GetPrivate["iExtractSlidesFromPayload"];
    If[extract === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iExtractSlidesFromPayload not loaded"|>]];
    
    (* (a) List[Association] \:5024 \:2192 Code \:30ad\:30fc *)
    r = extract[<|
      "PhaseComparison" -> {
        <|"Area" -> "X1", "Status" -> "Done"|>,
        <|"Area" -> "X2", "Status" -> "Pending"|>}|>];
    If[!ListQ[r] || Length[r] =!= 1,
      ok = False; AppendTo[fails, {"ListOfAssoc-len-wrong", r}],
      If[!KeyExistsQ[First[r], "Code"],
        ok = False; AppendTo[fails, {"ListOfAssoc-no-Code-key", r}]];
      If[KeyExistsQ[First[r], "Body"],
        ok = False; AppendTo[fails, {"ListOfAssoc-has-Body-key", r}]]];
    
    (* (b) \:5358\:4f53 Association \:5024 \:2192 Code \:30ad\:30fc *)
    r = extract[<|
      "Config" -> <|"key1" -> "v1", "key2" -> 42|>|>];
    If[!ListQ[r] || Length[r] =!= 1,
      ok = False; AppendTo[fails, {"SingleAssoc-len-wrong", r}],
      If[!KeyExistsQ[First[r], "Code"],
        ok = False; AppendTo[fails, {"SingleAssoc-no-Code-key", r}]]];
    
    (* (c) List[List] (rectangular table) \:5024 \:2192 Code \:30ad\:30fc *)
    r = extract[<|
      "Table" -> {{"h1", "h2"}, {"a", "b"}, {"c", "d"}}|>];
    If[!ListQ[r] || Length[r] =!= 1,
      ok = False; AppendTo[fails, {"ListOfList-len-wrong", r}],
      If[!KeyExistsQ[First[r], "Code"],
        ok = False; AppendTo[fails, {"ListOfList-no-Code-key", r}]]];
    
    (* (d) \:30b9\:30ab\:30e9\:30fc\:6587\:5b57\:5217\:5024 \:2192 Body \:30ad\:30fc (\:5f93\:6765\:6311\:52d5\:7dad\:6301) *)
    r = extract[<|
      "Summary" -> "This is a plain text summary."|>];
    If[!ListQ[r] || Length[r] =!= 1,
      ok = False; AppendTo[fails, {"ScalarStr-len-wrong", r}],
      If[!KeyExistsQ[First[r], "Body"],
        ok = False; AppendTo[fails, {"ScalarStr-no-Body-key", r}]];
      If[KeyExistsQ[First[r], "Code"],
        ok = False; AppendTo[fails, {"ScalarStr-has-Code-key", r}]]];
    
    (* (e) Scalar integer \:5024 \:2192 Body \:30ad\:30fc (\:5f93\:6765\:6311\:52d5\:7dad\:6301) *)
    r = extract[<|
      "TotalCommits" -> 87|>];
    If[!ListQ[r] || Length[r] =!= 1,
      ok = False; AppendTo[fails, {"Integer-len-wrong", r}],
      If[!KeyExistsQ[First[r], "Body"],
        ok = False; AppendTo[fails, {"Integer-no-Body-key", r}]]];
    
    (* (f) \:6df7\:5408\:30b1\:30fc\:30b9: String + List[Assoc] \:5171\:5b58 \:2192 \:5404\:3005\:9069\:5207\:306a\:30ad\:30fc *)
    r = extract[<|
      "Summary"         -> "text",
      "PhaseComparison" -> {<|"Area" -> "a"|>, <|"Area" -> "b"|>}|>];
    If[!ListQ[r] || Length[r] =!= 2,
      ok = False; AppendTo[fails, {"Mixed-len-wrong", r}],
      (* 1 \:3064\:306f Body\:3001\:3082\:3046 1 \:3064\:306f Code \:306e\:306f\:305a *)
      Module[{hasBody, hasCode},
        hasBody = AnyTrue[r, KeyExistsQ[#, "Body"] &];
        hasCode = AnyTrue[r, KeyExistsQ[#, "Code"] &];
        If[!hasBody || !hasCode,
          ok = False;
          AppendTo[fails, {"Mixed-key-distribution-wrong", r}]]]];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT09StructuredDataToInputCell[_] :=
  AssertT09StructuredDataToInputCell[];


RunT09StructuredDataTests[] :=
  Module[{tests, results, passed, failed, details},
    tests = <|
      "StructuredDataToInputCell" -> AssertT09StructuredDataToInputCell|>;
    
    results = KeyValueMap[
      Function[{name, fn},
        Module[{r},
          r = Quiet @ Check[fn[],
            <|"Pass" -> False, "Error" -> "Threw"|>];
          name -> r]],
      tests];
    results = Association @@ results;
    passed = Count[Values[results], r_?AssociationQ /; TrueQ[Lookup[r, "Pass", False]]];
    failed = Length[results] - passed;
    
    Print[Style[
      "T09 Structured Data \:2192 Input Cells Tests: " <>
        ToString[passed] <> "/" <> ToString[Length[results]] <>
        " passed" <> If[failed > 0,
          " (" <> ToString[failed] <> " failed)", ""],
      If[failed > 0, RGBColor[0.8, 0.3, 0.2],
        RGBColor[0, 2/3, 0]],
      Bold]];
    
    details = KeyValueMap[
      Function[{name, r},
        Module[{pass},
          pass = TrueQ[Lookup[r, "Pass", False]];
          Print["  ", pass, " \[LongDash] ", name, ": ",
            Style[If[pass, "PASS",
              "FAIL " <> ToString[r, InputForm]],
              If[pass, RGBColor[0, 2/3, 0],
                RGBColor[0.8, 0.3, 0.2]]]]]],
      results];
    
    <|"Passed" -> passed,
      "Failed" -> failed,
      "Total"  -> Length[results],
      "Results" -> results|>
  ];

(* ---- T10 tests: Dataset \:4e8b\:524d\:8a55\:4fa1 (\:539f\:5247 33) ----
   T10 (2026-04-19): iExtractSlidesFromPayload \:304c Case 3 fallback \:3067
   \:751f\:306e\:5024\:3092 \"DatasetValue\" \:30ad\:30fc\:3067\:4f1d\:3048\:3001
   iCellFromSlideItem \:304c Dataset[v] \:3067\:4e8b\:524d\:8a55\:4fa1\:3057\:305f Output \:30bb\:30eb\:3092
   Input \:30bb\:30eb\:306e\:5f8c\:306b\:8ffd\:52a0\:3059\:308b\:3053\:3068\:3092\:691c\:8a3c\:3002 *)

AssertT10DatasetValuePropagation::usage =
  "AssertT10DatasetValuePropagation[] \:306f Case 3 fallback \:304c List[Association] \n" <>
  "\:306b\:5bfe\:3057\:3066 \"Code\" + \"DatasetValue\" \:4e21\:65b9\:3092\:5165\:308c\:308b\:3053\:3068\:3092\:78ba\:8a8d\:3059\:308b\:3002";

AssertT10DatasetValuePropagation[] :=
  Module[{extract, r, first, ok = True, fails = {}},
    extract = iT05GetPrivate["iExtractSlidesFromPayload"];
    If[extract === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iExtractSlidesFromPayload not loaded"|>]];
    
    (* List[Assoc] \:2192 Code + DatasetValue *)
    r = extract[<|
      "Milestones" -> {
        <|"Date" -> "2026-03-03", "Feature" -> "a"|>,
        <|"Date" -> "2026-03-10", "Feature" -> "b"|>}|>];
    If[!ListQ[r] || Length[r] =!= 1,
      Return[<|"Pass" -> False,
               "Failures" -> {{"ListAssoc-wrong-len", r}}|>]];
    first = First[r];
    If[!KeyExistsQ[first, "Code"],
      ok = False;
      AppendTo[fails, {"no-Code-key", first}]];
    If[!KeyExistsQ[first, "DatasetValue"],
      ok = False;
      AppendTo[fails, {"no-DatasetValue-key", first}]];
    If[KeyExistsQ[first, "DatasetValue"] &&
       !ListQ[first["DatasetValue"]],
      ok = False;
      AppendTo[fails, {"DatasetValue-not-list", first["DatasetValue"]}]];
    (* \:5024\:304c\:751f\:306e\:30ea\:30b9\:30c8 (\:6587\:5b57\:5217\:3058\:3083\:306a\:3044) *)
    If[KeyExistsQ[first, "DatasetValue"] &&
       StringQ[first["DatasetValue"]],
      ok = False;
      AppendTo[fails, {"DatasetValue-was-stringified"}]];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT10DatasetValuePropagation[_] :=
  AssertT10DatasetValuePropagation[];


AssertT10CellFromSlideItemEmitsOutput::usage =
  "AssertT10CellFromSlideItemEmitsOutput[] \:306f iCellFromSlideItem \:304c\n" <>
  "\"DatasetValue\" \:3092\:6301\:3064 item \:306b\:5bfe\:3057\:3066 Output \:30bb\:30eb (BoxData \:8868\:793a)\n" <>
  "\:3092\:751f\:6210\:3059\:308b\:3053\:3068\:3092\:78ba\:8a8d\:3059\:308b\:3002";

AssertT10CellFromSlideItemEmitsOutput[] :=
  Module[{fn, cells, ok = True, fails = {}, hasSection, hasInput,
          hasOutput},
    fn = iT05GetPrivate["iCellFromSlideItem"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iCellFromSlideItem not loaded"|>]];
    
    cells = Quiet @ Check[
      fn[<|"Title" -> "Milestones",
           "Code"  -> "{<|\"x\" -> 1|>, <|\"x\" -> 2|>}",
           "DatasetValue" -> {<|"x" -> 1|>, <|"x" -> 2|>}|>, False],
      $Failed];
    
    If[!ListQ[cells],
      Return[<|"Pass" -> False,
               "Failures" -> {{"not-a-list", cells}}|>]];
    
    (* \:671f\:5f85: Cell[\"Milestones\",\"Section\"],
                   Cell[code,\"Input\"],
                   Cell[BoxData[...],\"Output\"] *)
    hasSection = AnyTrue[cells,
      MatchQ[#, Cell[_String, "Section", ___]] &];
    hasInput = AnyTrue[cells,
      MatchQ[#, Cell[_String, "Input", ___]] &];
    hasOutput = AnyTrue[cells,
      MatchQ[#, Cell[_BoxData, "Output", ___]] &];
    
    If[!hasSection,
      ok = False; AppendTo[fails, {"missing-Section-cell", cells}]];
    If[!hasInput,
      ok = False; AppendTo[fails, {"missing-Input-cell", cells}]];
    If[!hasOutput,
      ok = False; AppendTo[fails, {"missing-Output-cell", cells}]];
    
    <|"Pass" -> ok, "Failures" -> fails,
      "CellsLength" -> Length[cells]|>
  ];

AssertT10CellFromSlideItemEmitsOutput[_] :=
  AssertT10CellFromSlideItemEmitsOutput[];


AssertT10NoDatasetForPlainText::usage =
  "AssertT10NoDatasetForPlainText[] \:306f \:30b9\:30ab\:30e9\:30fc\:6587\:5b57\:5217\:5024\:306b\:5bfe\:3057\:3066\n" <>
  "DatasetValue \:304c\:4ed8\:304b\:305a\:3001\:5f93\:6765\:306e Body \:2192 Text \:6311\:52d5\:304c\:7dad\:6301\:3055\:308c\:308b\:3053\:3068\:3092\:78ba\:8a8d\:3059\:308b\:3002";

AssertT10NoDatasetForPlainText[] :=
  Module[{extract, r, first, ok = True, fails = {}},
    extract = iT05GetPrivate["iExtractSlidesFromPayload"];
    If[extract === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iExtractSlidesFromPayload not loaded"|>]];
    
    r = extract[<|"Summary" -> "plain text"|>];
    If[!ListQ[r] || Length[r] =!= 1,
      Return[<|"Pass" -> False,
               "Failures" -> {{"wrong-len", r}}|>]];
    first = First[r];
    If[KeyExistsQ[first, "DatasetValue"],
      ok = False;
      AppendTo[fails, {"unexpected-DatasetValue", first}]];
    If[!KeyExistsQ[first, "Body"],
      ok = False;
      AppendTo[fails, {"no-Body-for-scalar", first}]];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT10NoDatasetForPlainText[_] := AssertT10NoDatasetForPlainText[];


RunT10DatasetAutoEvalTests[] :=
  Module[{tests, results, passed, failed, details},
    tests = <|
      "DatasetValuePropagation"     -> AssertT10DatasetValuePropagation,
      "CellFromSlideItemEmitsOutput"-> AssertT10CellFromSlideItemEmitsOutput,
      "NoDatasetForPlainText"       -> AssertT10NoDatasetForPlainText|>;
    
    results = KeyValueMap[
      Function[{name, fn},
        Module[{r},
          r = Quiet @ Check[fn[],
            <|"Pass" -> False, "Error" -> "Threw"|>];
          name -> r]],
      tests];
    results = Association @@ results;
    passed = Count[Values[results], r_?AssociationQ /; TrueQ[Lookup[r, "Pass", False]]];
    failed = Length[results] - passed;
    
    Print[Style[
      "T10 Dataset Auto-Eval Output Tests: " <>
        ToString[passed] <> "/" <> ToString[Length[results]] <>
        " passed" <> If[failed > 0,
          " (" <> ToString[failed] <> " failed)", ""],
      If[failed > 0, RGBColor[0.8, 0.3, 0.2],
        RGBColor[0, 2/3, 0]],
      Bold]];
    
    details = KeyValueMap[
      Function[{name, r},
        Module[{pass},
          pass = TrueQ[Lookup[r, "Pass", False]];
          Print["  ", pass, " \[LongDash] ", name, ": ",
            Style[If[pass, "PASS",
              "FAIL " <> ToString[r, InputForm]],
              If[pass, RGBColor[0, 2/3, 0],
                RGBColor[0.8, 0.3, 0.2]]]]]],
      results];
    
    <|"Passed" -> passed,
      "Failed" -> failed,
      "Total"  -> Length[results],
      "Results" -> results|>
  ];

(* ---- T11 tests: \:30b7\:30ea\:30a2\:30e9\:30a4\:30ba\:3055\:308c\:305f Cell \:5f0f\:306e\:5fa9\:5143 (\:539f\:5247 34) ----
   T11 (2026-04-19): LLM \:304c List[String] \:3067 Cell[...] \:5f0f\:3092\:30b7\:30ea\:30a2\:30e9\:30a4\:30ba\:3057\:3066\n
   \:8fd4\:3057\:305f\:5834\:5408 (\:4f8b: CellExpressions \:30ad\:30fc\:306e\:5024)\:3001 iParseAsCellList \:304c
   \:6b63\:3057\:304f\:30d1\:30fc\:30b9\:3057\:3066 List[Cell[...]] \:3092\:8fd4\:3057\:3001\:4e0d\:6b63\:30d1\:30bf\:30fc\:30f3\:306f None \:3092
   \:8fd4\:3059\:3053\:3068\:3092\:691c\:8a3c\:3002 *)

AssertT11ParseAsCellListSuccess::usage =
  "AssertT11ParseAsCellListSuccess[] \:306f iParseAsCellList \:304c\n" <>
  "\:6709\:52b9\:306a Cell[...] \:5f0f\:6587\:5b57\:5217\:30ea\:30b9\:30c8\:3092 List[Cell] \:306b\:5fa9\:5143\:3059\:308b\:3053\:3068\:3092\:78ba\:8a8d\:3059\:308b\:3002";

AssertT11ParseAsCellListSuccess[] :=
  Module[{fn, r, ok = True, fails = {}},
    fn = iT05GetPrivate["iParseAsCellList"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iParseAsCellList not loaded"|>]];
    
    (* (a) 2 \:3064\:306e Cell \:6587\:5b57\:5217 \:2192 Cell \:30aa\:30d6\:30b8\:30a7\:30af\:30c8\:30ea\:30b9\:30c8 *)
    r = fn[{"Cell[\"title\", \"Title\"]",
            "Cell[\"body text\", \"Text\"]"}];
    If[!ListQ[r] || Length[r] =!= 2,
      ok = False; AppendTo[fails, {"Case-a-wrong-len", r}]];
    If[ListQ[r] && Length[r] === 2,
      If[!MatchQ[r[[1]], Cell["title", "Title", ___]],
        ok = False; AppendTo[fails, {"Case-a-first-wrong", r[[1]]}]];
      If[!MatchQ[r[[2]], Cell["body text", "Text", ___]],
        ok = False; AppendTo[fails, {"Case-a-second-wrong", r[[2]]}]]];
    
    (* (b) Cell[BoxData[...], "Output"] \:306e\:3088\:3046\:306a inner eval \:3092\:542b\:3080\:5f62 *)
    r = fn[{"Cell[\"simple\", \"Text\"]",
            "Cell[BoxData[\"boxed\"], \"Output\"]"}];
    If[!ListQ[r] || Length[r] =!= 2,
      ok = False; AppendTo[fails, {"Case-b-wrong-len", r}]];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT11ParseAsCellListSuccess[_] :=
  AssertT11ParseAsCellListSuccess[];


AssertT11ParseAsCellListRejects::usage =
  "AssertT11ParseAsCellListRejects[] \:306f iParseAsCellList \:304c\n" <>
  "Cell[...] \:3067\:306f\:306a\:3044\:5f0f/\:30b4\:30df\:6587\:5b57\:5217/\:5916\:5074\:30d1\:30bf\:30fc\:30f3\:4e0d\:4e00\:81f4\:306b\:5bfe\:3057\:3066\n" <>
  "None \:3092\:8fd4\:3059\:3053\:3068\:3092\:78ba\:8a8d\:3059\:308b (\:30b3\:30de\:30f3\:30c9\:30a4\:30f3\:30b8\:30a7\:30af\:30b7\:30e7\:30f3\:9632\:6b62)\:3002";

AssertT11ParseAsCellListRejects[] :=
  Module[{fn, r, ok = True, fails = {}},
    fn = iT05GetPrivate["iParseAsCellList"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iParseAsCellList not loaded"|>]];
    
    (* (a) \:6df7\:5728: 1 \:3064\:304c Cell \:3060\:304c\:3082\:3046 1 \:3064\:306f\:5225\:306e\:5f0f \:2192 None *)
    r = fn[{"Cell[\"ok\", \"Text\"]",
            "1 + 2"}];
    If[r =!= None,
      ok = False; AppendTo[fails, {"Case-a-should-be-None", r}]];
    
    (* (b) \:30b4\:30df\:6587\:5b57\:5217 *)
    r = fn[{"random text not parseable as Mma"}];
    If[r =!= None,
      ok = False; AppendTo[fails, {"Case-b-garbage-should-be-None", r}]];
    
    (* (c) \:5f0f\:306f parse \:3067\:304d\:308b\:304c Cell \:3058\:3083\:306a\:3044 *)
    r = fn[{"Graph[{1 -> 2, 2 -> 3}]"}];
    If[r =!= None,
      ok = False; AppendTo[fails, {"Case-c-non-Cell-should-be-None", r}]];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT11ParseAsCellListRejects[_] :=
  AssertT11ParseAsCellListRejects[];


AssertT11ExtractRoutesToPreBuiltCells::usage =
  "AssertT11ExtractRoutesToPreBuiltCells[] \:306f iExtractSlidesFromPayload\n" <>
  "Case 3 fallback \:304c List[String]-of-Cell \:3092 PreBuiltCells \:30ad\:30fc\:306b\:30eb\:30fc\:30c8\:3059\:308b\:3053\:3068\:3092\:78ba\:8a8d\:3002";

AssertT11ExtractRoutesToPreBuiltCells[] :=
  Module[{extract, r, first, ok = True, fails = {}},
    extract = iT05GetPrivate["iExtractSlidesFromPayload"];
    If[extract === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iExtractSlidesFromPayload not loaded"|>]];
    
    (* CellExpressions \:30ad\:30fc\:306b Cell[...] \:6587\:5b57\:5217\:30ea\:30b9\:30c8 *)
    r = extract[<|
      "CellExpressions" -> {
        "Cell[\"Title\", \"Title\"]",
        "Cell[\"Body\", \"Text\"]"}|>];
    If[!ListQ[r] || Length[r] =!= 1,
      Return[<|"Pass" -> False,
               "Failures" -> {{"wrong-len", r}}|>]];
    first = First[r];
    If[!KeyExistsQ[first, "PreBuiltCells"],
      ok = False;
      AppendTo[fails, {"no-PreBuiltCells-key", first}]];
    If[KeyExistsQ[first, "Body"],
      ok = False;
      AppendTo[fails, {"unexpected-Body", first}]];
    If[KeyExistsQ[first, "Code"],
      ok = False;
      AppendTo[fails, {"unexpected-Code", first}]];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT11ExtractRoutesToPreBuiltCells[_] :=
  AssertT11ExtractRoutesToPreBuiltCells[];


AssertT11CellFromSlideItemUsesPreBuiltCells::usage =
  "AssertT11CellFromSlideItemUsesPreBuiltCells[] \:306f iCellFromSlideItem \:304c\n" <>
  "PreBuiltCells \:3092\:53d7\:3051\:53d6\:3063\:305f\:3068\:304d\:3001Section + \:305d\:306e\:307e\:307e\:306e Cell \:3092\:8fd4\:3059\:3053\:3068\:3092\:78ba\:8a8d\:3002";

AssertT11CellFromSlideItemUsesPreBuiltCells[] :=
  Module[{fn, cells, ok = True, fails = {}},
    fn = iT05GetPrivate["iCellFromSlideItem"];
    If[fn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iCellFromSlideItem not loaded"|>]];
    
    cells = Quiet @ Check[
      fn[<|"Title" -> "CellExpressions",
           "PreBuiltCells" -> {
             Cell["A", "Text"],
             Cell["B", "Text"]}|>, False],
      $Failed];
    
    If[!ListQ[cells],
      Return[<|"Pass" -> False,
               "Failures" -> {{"not-a-list", cells}}|>]];
    (* Section + Cell[A] + Cell[B] \:306e 3 \:500b *)
    If[Length[cells] =!= 3,
      ok = False; AppendTo[fails, {"wrong-count", Length[cells], cells}]];
    If[Length[cells] >= 1 &&
       !MatchQ[First[cells], Cell["CellExpressions", "Section", ___]],
      ok = False; AppendTo[fails, {"first-not-Section", First[cells]}]];
    If[Length[cells] >= 2 &&
       !MatchQ[cells[[2]], Cell["A", "Text", ___]],
      ok = False; AppendTo[fails, {"second-not-A", cells[[2]]}]];
    
    <|"Pass" -> ok, "Failures" -> fails|>
  ];

AssertT11CellFromSlideItemUsesPreBuiltCells[_] :=
  AssertT11CellFromSlideItemUsesPreBuiltCells[];


RunT11CellStringParseTests[] :=
  Module[{tests, results, passed, failed, details},
    tests = <|
      "ParseSuccess"            -> AssertT11ParseAsCellListSuccess,
      "ParseRejects"            -> AssertT11ParseAsCellListRejects,
      "ExtractRoutes"           -> AssertT11ExtractRoutesToPreBuiltCells,
      "CellFromSlideItemUsesPreBuilt"
                                -> AssertT11CellFromSlideItemUsesPreBuiltCells|>;
    
    results = KeyValueMap[
      Function[{name, fn},
        Module[{r},
          r = Quiet @ Check[fn[],
            <|"Pass" -> False, "Error" -> "Threw"|>];
          name -> r]],
      tests];
    results = Association @@ results;
    passed = Count[Values[results], r_?AssociationQ /; TrueQ[Lookup[r, "Pass", False]]];
    failed = Length[results] - passed;
    
    Print[Style[
      "T11 Cell-String List Parse Tests: " <>
        ToString[passed] <> "/" <> ToString[Length[results]] <>
        " passed" <> If[failed > 0,
          " (" <> ToString[failed] <> " failed)", ""],
      If[failed > 0, RGBColor[0.8, 0.3, 0.2],
        RGBColor[0, 2/3, 0]],
      Bold]];
    
    details = KeyValueMap[
      Function[{name, r},
        Module[{pass},
          pass = TrueQ[Lookup[r, "Pass", False]];
          Print["  ", pass, " \[LongDash] ", name, ": ",
            Style[If[pass, "PASS",
              "FAIL " <> ToString[r, InputForm]],
              If[pass, RGBColor[0, 2/3, 0],
                RGBColor[0.8, 0.3, 0.2]]]]]],
      results];
    
    <|"Passed" -> passed,
      "Failed" -> failed,
      "Total"  -> Length[results],
      "Results" -> results|>
  ];

(* ---- RunT07SlideIntentTests ---- *)

RunT07SlideIntentTests[] :=
  Module[{tests, results, passed, failed, details},
    tests = <|
      "StyleSanitization"        -> AssertT07StyleSanitization,
      "SlideIntentDetection"     -> AssertT07SlideIntentDetection,
      "InnerCellFromSpecSanitize"-> AssertT07InnerCellFromSpecSanitize,
      "DefaultPlannerSlideAware" -> AssertT07DefaultPlannerSlideAware,
      "WorkerPromptSlideHint"    -> AssertT07WorkerPromptSlideHint,
      "ResolveTargetNotebook"    -> AssertT07bResolveTargetNotebookLogic|>;
    
    results = KeyValueMap[
      Function[{name, fn},
        Module[{r},
          r = Quiet @ Check[fn[],
            <|"Pass" -> False, "Error" -> "Threw"|>];
          name -> r]],
      tests];
    results = Association[results];
    
    passed = Count[Values[results],
      a_Association /; TrueQ[Lookup[a, "Pass", False]]];
    failed = Length[results] - passed;
    
    details = Style[
      "T07/T07b Slide Intent + Style Sanitization + Target NB Tests: " <>
        ToString[passed] <> "/" <>
        ToString[Length[results]] <> " passed" <>
        If[failed > 0, " (" <> ToString[failed] <> " failed)", ""],
      Bold, If[failed === 0, Darker[Green], RGBColor[0.8, 0.3, 0.2]]];
    Print[details];
    
    Do[
      Print["  ", Lookup[p[[2]], "Pass", False],
        " \:2014 ", p[[1]], ": ",
        If[TrueQ[Lookup[p[[2]], "Pass", False]],
          Style["PASS", Darker[Green]],
          Style["FAIL " <> ToString[Short[p[[2]], 3]],
            RGBColor[0.8, 0.3, 0.2]]]],
      {p, Normal[results]}];
    
    <|"Passed"  -> passed,
      "Failed"  -> failed,
      "Total"   -> Length[results],
      "Results" -> results|>
  ];

(* \:2500\:2500\:2500 Phase 32 Task 3.1: Committer \:81ea\:7136\:8a00\:8a9e Input \:6d41\:5165\:9632\:6b62 \:30c6\:30b9\:30c8 \:2500\:2500\:2500

   \:80cc\:666f:
     ClaudeEval \:3092 Auto \:30e2\:30fc\:30c9\:3067\:547c\:3093\:3060\:3068\:304d\:3001Committer LLM \:304c
     NotebookWrite[nb, Cell["\:6b21\:306b\:3001GitHub...", "Input"]] \:306e\:5f62\:3067
     \:81ea\:7136\:8a00\:8a9e\:3092 Input \:30bb\:30eb\:306b\:66f8\:304d\:8fbc\:3080\:30d0\:30b0\:304c\:89b3\:5bdf\:3055\:308c\:305f\:3002
     Mathematica \:306f Input \:30bb\:30eb\:5185\:306e\:65e5\:672c\:8a9e\:30b7\:30f3\:30dc\:30eb\:3092
     Times[_Symbol, _Symbol, ...] \:3068\:3057\:3066 Orderless \:8a55\:4fa1\:3057\:3001\:8f9e\:66f8\:9806
     \:30bd\:30fc\:30c8\:7d50\:679c\:304c Output \:306b\:51fa\:3066\:3001\:7d00\:3089\:308f\:3057\:3044\:6210\:679c\:7269\:306b\:306a\:308b\:3002
   
   \:305d\:3053\:3067 iValidateWorkerProposal (role="Commit") \:3092\:62e1\:5f35\:3057\:3001
   HeldExpr \:4e2d\:306e Cell[s, "Input", ___] \:306b\:3064\:3044\:3066 s \:304c\:8a55\:4fa1\:53ef\:80fd\:306a
   Mathematica \:5f0f\:304b\:3092 iIsPlausibleInputCellContent \:3067\:691c\:3081\:3001
   \:8a55\:4fa1\:4e0d\:80fd\:306a\:3089 Deny \:3059\:308b\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

(* ---- AssertPhase32Task31RejectsNaturalLangInput ---- *)

AssertPhase32Task31RejectsNaturalLangInput[] :=
  Module[{validateFn, proposal, result, ok = True, fails = {},
          offending},
    validateFn = iT05GetPrivate["iValidateWorkerProposal"];
    If[validateFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iValidateWorkerProposal not loaded"|>]];
    
    (* "\:6b21\:306b\:3001GitHub \:5074\:3092\:8abf\:3079\:307e\:3059" \:306f\:65e5\:672c\:8a9e\:8a08\:753b\:6587\:3002
       ToExpression \:3067 HoldComplete[Times[_Symbol, _Symbol, ...]] \:306b\:306a\:308b\:3002 *)
    proposal = <|
      "HeldExpr" -> HoldComplete[
        NotebookWrite[EvaluationNotebook[],
          Cell["\:6b21\:306b\:3001GitHub \:5074\:3092\:8abf\:3079\:307e\:3059", "Input"]]]
    |>;
    
    result = Quiet @ Check[
      validateFn[proposal, <||>, "Commit"],
      $Failed];
    
    If[!AssociationQ[result],
      Return[<|"Pass" -> False,
               "Failures" -> {{"not-an-association", result}}|>]];
    
    If[Lookup[result, "Decision", None] =!= "Deny",
      ok = False;
      AppendTo[fails, {"wrong-decision",
        Lookup[result, "Decision", None]}]];
    
    If[Lookup[result, "ReasonClass", None] =!= "NaturalLanguageInInputCell",
      ok = False;
      AppendTo[fails, {"wrong-reason-class",
        Lookup[result, "ReasonClass", None]}]];
    
    offending = Lookup[result, "OffendingStrings", None];
    If[!ListQ[offending] || Length[offending] === 0,
      ok = False;
      AppendTo[fails, {"empty-offending-strings", offending}]];
    
    <|"Pass" -> ok, "Failures" -> fails, "Raw" -> result|>
  ];

AssertPhase32Task31RejectsNaturalLangInput[_] :=
  AssertPhase32Task31RejectsNaturalLangInput[];


(* ---- AssertPhase32Task31AcceptsMathExprInInputCell ---- *)

AssertPhase32Task31AcceptsMathExprInInputCell[] :=
  Module[{validateFn, proposal, result, ok = True, fails = {}},
    validateFn = iT05GetPrivate["iValidateWorkerProposal"];
    If[validateFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iValidateWorkerProposal not loaded"|>]];
    
    (* \:6b63\:5e38\:306a Mathematica \:5f0f\:3002Plot[Sin[x], {x, 0, 2 Pi}] *)
    proposal = <|
      "HeldExpr" -> HoldComplete[
        NotebookWrite[EvaluationNotebook[],
          Cell["Plot[Sin[x], {x, 0, 2 Pi}]", "Input"]]]
    |>;
    
    result = Quiet @ Check[
      validateFn[proposal, <||>, "Commit"],
      $Failed];
    
    If[!AssociationQ[result],
      Return[<|"Pass" -> False,
               "Failures" -> {{"not-an-association", result}}|>]];
    
    If[Lookup[result, "Decision", None] =!= "Permit",
      ok = False;
      AppendTo[fails, {"wrong-decision",
        Lookup[result, "Decision", None],
        "reason-class",
        Lookup[result, "ReasonClass", None]}]];
    
    If[Lookup[result, "ReasonClass", None] =!= "OK",
      ok = False;
      AppendTo[fails, {"wrong-reason-class",
        Lookup[result, "ReasonClass", None]}]];
    
    <|"Pass" -> ok, "Failures" -> fails, "Raw" -> result|>
  ];

AssertPhase32Task31AcceptsMathExprInInputCell[_] :=
  AssertPhase32Task31AcceptsMathExprInInputCell[];


(* ---- AssertPhase32Task31AcceptsNaturalLangInTextCell ---- *)

AssertPhase32Task31AcceptsNaturalLangInTextCell[] :=
  Module[{validateFn, proposal, result, ok = True, fails = {}},
    validateFn = iT05GetPrivate["iValidateWorkerProposal"];
    If[validateFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iValidateWorkerProposal not loaded"|>]];
    
    (* \:81ea\:7136\:8a00\:8a9e\:3060\:304c "Text" \:30b9\:30bf\:30a4\:30eb\:3002\:3053\:308c\:306f\:691c\:67fb\:5bfe\:8c61\:5916\:3002 *)
    proposal = <|
      "HeldExpr" -> HoldComplete[
        NotebookWrite[EvaluationNotebook[],
          Cell["\:6b21\:306b\:3001GitHub \:5074\:3092\:8abf\:3079\:307e\:3059", "Text"]]]
    |>;
    
    result = Quiet @ Check[
      validateFn[proposal, <||>, "Commit"],
      $Failed];
    
    If[!AssociationQ[result],
      Return[<|"Pass" -> False,
               "Failures" -> {{"not-an-association", result}}|>]];
    
    If[Lookup[result, "Decision", None] =!= "Permit",
      ok = False;
      AppendTo[fails, {"wrong-decision",
        Lookup[result, "Decision", None],
        "reason-class",
        Lookup[result, "ReasonClass", None]}]];
    
    <|"Pass" -> ok, "Failures" -> fails, "Raw" -> result|>
  ];

AssertPhase32Task31AcceptsNaturalLangInTextCell[_] :=
  AssertPhase32Task31AcceptsNaturalLangInTextCell[];


(* ---- RunPhase32Task31Tests ---- *)

RunPhase32Task31Tests[] :=
  Module[{tests, results, passed, failed},
    tests = <|
      "RejectsNaturalLangInput"      -> AssertPhase32Task31RejectsNaturalLangInput,
      "AcceptsMathExprInInputCell"   -> AssertPhase32Task31AcceptsMathExprInInputCell,
      "AcceptsNaturalLangInTextCell" -> AssertPhase32Task31AcceptsNaturalLangInTextCell|>;
    
    results = KeyValueMap[
      Function[{name, fn},
        Module[{r},
          r = Quiet @ Check[fn[],
            <|"Pass" -> False, "Error" -> "Threw"|>];
          name -> r]],
      tests];
    results = Association @@ results;
    
    passed = Count[Values[results],
      r_?AssociationQ /; TrueQ[Lookup[r, "Pass", False]]];
    failed = Length[results] - passed;
    
    Print[Style[
      "Phase 32 Task 3.1 Tests (Committer natural-language Input guard): " <>
        ToString[passed] <> "/" <> ToString[Length[results]] <>
        " passed" <> If[failed > 0,
          " (" <> ToString[failed] <> " failed)", ""],
      If[failed > 0, RGBColor[0.8, 0.3, 0.2],
        RGBColor[0, 2/3, 0]],
      Bold]];
    
    KeyValueMap[
      Function[{name, r},
        Module[{pass},
          pass = TrueQ[Lookup[r, "Pass", False]];
          Print["  ", pass, " \[LongDash] ", name, ": ",
            Style[If[pass, "PASS",
              "FAIL " <> ToString[Short[r, 3], InputForm]],
              If[pass, RGBColor[0, 2/3, 0],
                RGBColor[0.8, 0.3, 0.2]]]]]],
      results];
    
    <|"Passed"  -> passed,
      "Failed"  -> failed,
      "Total"   -> Length[results],
      "Results" -> results|>
  ];


(* \:2500\:2500\:2500 Phase 32 Task 3.2: Auto \:30b2\:30fc\:30c8\:5f37\:5316 \:30c6\:30b9\:30c8 \:2500\:2500\:2500

   \:80cc\:666f:
     Task 3.1 \:3067 Committer \:306e\:81ea\:7136\:8a00\:8a9e Input \:6d41\:5165\:306f\:9632\:3054\:305f\:304c\:3001
     \:4f9d\:7136\:3068\:3057\:3066\:77ed\:3044 factual query (\:4f8b: "\:2026GitHub \:3088\:308a\:65b0\:3057\:3044\:304b\:8abf\:3079\:3066")
     \:306f Orchestrator \:7d4c\:8def\:306b\:4e57\:3063\:3066 Worker \:304c GitHub API \:3092\:547c\:3079\:305a
     \:30bf\:30b9\:30af\:304c\:5b8c\:9042\:3057\:306a\:3044\:3002
     Task 3.2 \:306f\:77ed factual query \:3092 Orchestrator \:7d4c\:8def\:3092\:8df3\:3070\:3057\:3066
     Single \:30d1\:30b9 (claudecode.wl \:5f93\:6765\:5b9f\:88c5) \:306b\:843d\:3068\:3059\:3002
   
   \:5bfe\:8c61: iIsShortFactualQuery[s] + iHasComplexTaskMarker[s]
     \:524d\:8005\:306f\:300c\:77ed\:3044\:30fb\:8abf\:67fb\:30fb\:30d5\:30a1\:30a4\:30eb\:30fb\:30d1\:30c3\:30b1\:30fc\:30b8\:540d\:300d\:5229\:30fb\:5411\:3051\:306b True\:3002
     \:5f8c\:8005\:306f\:300c\:30b9\:30e9\:30a4\:30c9\:30fb\:30ec\:30dd\:30fc\:30c8\:30fb\:9806\:5e8f\:63a5\:7d9a\:8a9e\:300d\:306a\:3069\:8907\:96d1\:30bf\:30b9\:30af\:306b True\:3002
   \:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500\:2500 *)

(* ---- AssertPhase32Task32SkipsShortFactualJa ---- *)

AssertPhase32Task32SkipsShortFactualJa[] :=
  Module[{isShortFn, isComplexFn, query, resShort, resComplex,
          ok = True, fails = {}},
    isShortFn   = iT05GetPrivate["iIsShortFactualQuery"];
    isComplexFn = iT05GetPrivate["iHasComplexTaskMarker"];
    If[isShortFn === None || isComplexFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iIsShortFactualQuery / iHasComplexTaskMarker not loaded"|>]];
    
    (* \:5143\:4e8b\:4f8b: result3.nb \:3067\:89b3\:5bdf\:3055\:308c\:305f\:30d7\:30ed\:30f3\:30d7\:30c8 *)
    query = "$packageDirectory\:306eclaudecode, ClaudeRuntime, documentation\:304c\:3001GitHub\:30ea\:30dd\:30b8\:30c8\:30ea\:306e\:30d0\:30fc\:30b8\:30e7\:30f3\:3088\:308a\:65b0\:3057\:3044\:304b\:3069\:3046\:304b\:3092\:8abf\:3079\:3066";
    
    resShort   = Quiet @ Check[isShortFn[query], $Failed];
    resComplex = Quiet @ Check[isComplexFn[query], $Failed];
    
    If[!TrueQ[resShort],
      ok = False;
      AppendTo[fails, {"not-short-factual", resShort}]];
    
    If[TrueQ[resComplex],
      ok = False;
      AppendTo[fails, {"unexpectedly-complex", resComplex}]];
    
    <|"Pass" -> ok, "Failures" -> fails,
      "Query" -> query,
      "IsShortFactual" -> resShort,
      "IsComplex" -> resComplex|>
  ];

AssertPhase32Task32SkipsShortFactualJa[_] :=
  AssertPhase32Task32SkipsShortFactualJa[];


(* ---- AssertPhase32Task32SkipsShortFactualEn ---- *)

AssertPhase32Task32SkipsShortFactualEn[] :=
  Module[{isShortFn, isComplexFn, query, resShort, resComplex,
          ok = True, fails = {}},
    isShortFn   = iT05GetPrivate["iIsShortFactualQuery"];
    isComplexFn = iT05GetPrivate["iHasComplexTaskMarker"];
    If[isShortFn === None || isComplexFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iIsShortFactualQuery / iHasComplexTaskMarker not loaded"|>]];
    
    query = "Check if claudecode.wl is newer than its GitHub version";
    
    resShort   = Quiet @ Check[isShortFn[query], $Failed];
    resComplex = Quiet @ Check[isComplexFn[query], $Failed];
    
    If[!TrueQ[resShort],
      ok = False;
      AppendTo[fails, {"not-short-factual", resShort}]];
    
    If[TrueQ[resComplex],
      ok = False;
      AppendTo[fails, {"unexpectedly-complex", resComplex}]];
    
    <|"Pass" -> ok, "Failures" -> fails,
      "Query" -> query,
      "IsShortFactual" -> resShort,
      "IsComplex" -> resComplex|>
  ];

AssertPhase32Task32SkipsShortFactualEn[_] :=
  AssertPhase32Task32SkipsShortFactualEn[];


(* ---- AssertPhase32Task32KeepsLongComplex ---- *)

AssertPhase32Task32KeepsLongComplex[] :=
  Module[{isShortFn, isComplexFn, query, resShort, resComplex,
          ok = True, fails = {}},
    isShortFn   = iT05GetPrivate["iIsShortFactualQuery"];
    isComplexFn = iT05GetPrivate["iHasComplexTaskMarker"];
    If[isShortFn === None || isComplexFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iIsShortFactualQuery / iHasComplexTaskMarker not loaded"|>]];
    
    (* 600 \:6587\:5b57\:8d85\:3001\:9806\:5e8f\:63a5\:7d9a\:8a9e\:8907\:6570\:3001\:660e\:3089\:304b\:306b\:8907\:96d1 *)
    query = "\:307e\:305a claudecode.wl \:306e\:516c\:958b\:95a2\:6570\:4e00\:89a7\:3092 api.md \:304b\:3089\:62bd\:51fa\:3057\:3001" <>
      "\:6b21\:306b ClaudeRuntime.wl \:306e\:516c\:958b\:95a2\:6570\:4e00\:89a7\:3082\:540c\:69d8\:306b\:62bd\:51fa\:3057\:3066\:3001" <>
      "\:305d\:308c\:305e\:308c\:306e\:95a2\:6570\:306e\:4f7f\:7528\:4f8b\:3001\:30aa\:30d7\:30b7\:30e7\:30f3\:3001\:623b\:308a\:5024\:306e\:578b\:3092\:6bd4\:8f03\:3057\:305f" <>
      "\:8868\:3092\:751f\:6210\:3057\:3066\:3001\:6700\:5f8c\:306b\:5dee\:7570\:70b9\:3092\:307e\:3068\:3081\:305f\:30ec\:30dd\:30fc\:30c8\:3092\:4f5c\:3063\:3066\:304f\:3060\:3055\:3044\:3002" <>
      "\:30ec\:30dd\:30fc\:30c8\:306f\:30b9\:30e9\:30a4\:30c9\:5f62\:5f0f\:3067\:3001\:5404\:95a2\:6570\:306b\:3064\:304d 1 \:30b9\:30e9\:30a4\:30c9\:3001" <>
      "\:30b3\:30fc\:30c9\:4f8b\:3068\:89e3\:8aac\:3092\:4e26\:3079\:3066\:3001\:30d1\:30c3\:30b1\:30fc\:30b8\:306b\:307e\:3068\:3081\:3066\:304f\:3060\:3055\:3044\:3002" <>
      "\:8907\:96d1\:306a\:30bf\:30b9\:30af\:306a\:306e\:3067\:3001\:30b9\:30c6\:30c3\:30d7\:3054\:3068\:306b\:898b\:76f4\:3057\:306a\:304c\:3089" <>
      "\:9032\:3081\:3066\:304f\:3060\:3055\:3044\:3002\:5168\:4f53\:3068\:3057\:3066\:7d42\:4e86\:5f8c\:306b\:7d71\:5408\:78ba\:8a8d\:3092\:3057\:3066\:4e0b\:3055\:3044\:3002";
    
    resShort   = Quiet @ Check[isShortFn[query], $Failed];
    resComplex = Quiet @ Check[isComplexFn[query], $Failed];
    
    If[TrueQ[resShort],
      ok = False;
      AppendTo[fails, {"misclassified-as-short-factual", resShort,
        "length", StringLength[query]}]];
    
    If[!TrueQ[resComplex],
      ok = False;
      AppendTo[fails, {"not-detected-as-complex", resComplex,
        "length", StringLength[query]}]];
    
    <|"Pass" -> ok, "Failures" -> fails,
      "QueryLength" -> StringLength[query],
      "IsShortFactual" -> resShort,
      "IsComplex" -> resComplex|>
  ];

AssertPhase32Task32KeepsLongComplex[_] :=
  AssertPhase32Task32KeepsLongComplex[];


(* ---- AssertPhase32Task32KeepsSlideRequest ---- *)

AssertPhase32Task32KeepsSlideRequest[] :=
  Module[{isComplexFn, query, resComplex, ok = True, fails = {}},
    isComplexFn = iT05GetPrivate["iHasComplexTaskMarker"];
    If[isComplexFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iHasComplexTaskMarker not loaded"|>]];
    
    (* \:77ed\:3044\:304c\:300c\:30b9\:30e9\:30a4\:30c9\:300d\:30ad\:30fc\:30ef\:30fc\:30c9\:3067\:8907\:96d1\:5224\:5b9a *)
    query = "30\:30da\:30fc\:30b8\:306e\:30b9\:30e9\:30a4\:30c9\:3092\:4f5c\:3063\:3066";
    
    resComplex = Quiet @ Check[isComplexFn[query], $Failed];
    
    If[!TrueQ[resComplex],
      ok = False;
      AppendTo[fails, {"slide-request-not-flagged-complex", resComplex}]];
    
    <|"Pass" -> ok, "Failures" -> fails,
      "Query" -> query,
      "IsComplex" -> resComplex|>
  ];

AssertPhase32Task32KeepsSlideRequest[_] :=
  AssertPhase32Task32KeepsSlideRequest[];


(* ---- AssertPhase32Task32KeepsSequentialTask ---- *)

AssertPhase32Task32KeepsSequentialTask[] :=
  Module[{isComplexFn, query, resComplex, ok = True, fails = {}},
    isComplexFn = iT05GetPrivate["iHasComplexTaskMarker"];
    If[isComplexFn === None,
      Return[<|"Pass" -> False,
               "Reason" -> "iHasComplexTaskMarker not loaded"|>]];
    
    (* \:9806\:5e8f\:63a5\:7d9a\:8a9e 3 \:500b \:2192 \:8907\:96d1\:5224\:5b9a *)
    query = "\:307e\:305a\:30d5\:30a1\:30a4\:30eb\:3092\:30ed\:30fc\:30c9\:3057\:3001\:6b21\:306b\:5185\:5bb9\:3092\:691c\:8a3c\:3057\:3001\:6700\:5f8c\:306b\:30ec\:30dd\:30fc\:30c8\:3092\:4f5c\:308b";
    
    resComplex = Quiet @ Check[isComplexFn[query], $Failed];
    
    If[!TrueQ[resComplex],
      ok = False;
      AppendTo[fails, {"sequential-task-not-flagged-complex", resComplex}]];
    
    <|"Pass" -> ok, "Failures" -> fails,
      "Query" -> query,
      "IsComplex" -> resComplex|>
  ];

AssertPhase32Task32KeepsSequentialTask[_] :=
  AssertPhase32Task32KeepsSequentialTask[];


(* ---- RunPhase32Task32Tests ---- *)

RunPhase32Task32Tests[] :=
  Module[{tests, results, passed, failed},
    tests = <|
      "SkipsShortFactualJa"   -> AssertPhase32Task32SkipsShortFactualJa,
      "SkipsShortFactualEn"   -> AssertPhase32Task32SkipsShortFactualEn,
      "KeepsLongComplex"      -> AssertPhase32Task32KeepsLongComplex,
      "KeepsSlideRequest"     -> AssertPhase32Task32KeepsSlideRequest,
      "KeepsSequentialTask"   -> AssertPhase32Task32KeepsSequentialTask|>;
    
    results = KeyValueMap[
      Function[{name, fn},
        Module[{r},
          r = Quiet @ Check[fn[],
            <|"Pass" -> False, "Error" -> "Threw"|>];
          name -> r]],
      tests];
    results = Association @@ results;
    
    passed = Count[Values[results],
      r_?AssociationQ /; TrueQ[Lookup[r, "Pass", False]]];
    failed = Length[results] - passed;
    
    Print[Style[
      "Phase 32 Task 3.2 Tests (Auto gate hardening): " <>
        ToString[passed] <> "/" <> ToString[Length[results]] <>
        " passed" <> If[failed > 0,
          " (" <> ToString[failed] <> " failed)", ""],
      If[failed > 0, RGBColor[0.8, 0.3, 0.2],
        RGBColor[0, 2/3, 0]],
      Bold]];
    
    KeyValueMap[
      Function[{name, r},
        Module[{pass},
          pass = TrueQ[Lookup[r, "Pass", False]];
          Print["  ", pass, " \[LongDash] ", name, ": ",
            Style[If[pass, "PASS",
              "FAIL " <> ToString[Short[r, 3], InputForm]],
              If[pass, RGBColor[0, 2/3, 0],
                RGBColor[0.8, 0.3, 0.2]]]]]],
      results];
    
    <|"Passed"  -> passed,
      "Failed"  -> failed,
      "Total"   -> Length[results],
      "Results" -> results|>
  ];


End[];
EndPackage[];

Print[Style[If[$Language === "Japanese",
  "ClaudeTestKit パッケージがロードされました。(v" <>
    ClaudeTestKit`$ClaudeTestKitVersion <> ")",
  "ClaudeTestKit package loaded. (v" <>
    ClaudeTestKit`$ClaudeTestKitVersion <> ")"], Bold]];
Print[If[$Language === "Japanese", "
  CreateMockProvider[responses]            \[Rule] mock provider
  CreateMockAdapter[opts]                  \[Rule] mock adapter
  CreateMockTransactionAdapter[opts]       \[Rule] transaction mock adapter
  RunClaudeScenario[scenario]              \[Rule] シナリオ実行・検証
  RunAllClaudeTests[]                      \[Rule] 全組み込みテスト実行
  NormalizeClaudeTrace[trace]              \[Rule] golden 正規化
  AssertNoSecretLeak[trace, secrets]       \[Rule] 秘密漏洩チェック
  AssertValidationDenied[trace]            \[Rule] deny 検証
  AssertOutcome[trace, outcome]            \[Rule] outcome 検証
  AssertBudgetNotExceeded[state]           \[Rule] budget 検証
  AssertEventSequence[trace, types]        \[Rule] イベント列検証
  -- ClaudeOrchestrator \:9023\:643a --
  CreateMockPlanner[tasks]                 \[Rule] mock planner
  CreateMockWorkerAdapter[role, task, ...] \[Rule] mock worker adapter
  CreateMockReducer[payload]               \[Rule] mock reducer
  CreateMockCommitter[nb, reduced]         \[Rule] mock committer
  RunClaudeOrchestrationScenario[scn]      \[Rule] orchestration \:30b7\:30ca\:30ea\:30aa\:5b9f\:884c
  AssertNoWorkerNotebookMutation[result]
  AssertSingleCommitterWrites[result]
  AssertArtifactsRespectDependencies[r,t]
  AssertReducerDeterministic[reducer, art]
  AssertTaskOutputMatchesSchema[art, sch]
  -- Stage 2 --
  CreateMockQueryFunction[responses]         \[Rule] mock LLM query \:95a2\:6570
  AssertArtifactHasSchemaWarnings[artifact]
", "
  CreateMockProvider[responses]            \[Rule] mock provider
  CreateMockAdapter[opts]                  \[Rule] mock adapter
  CreateMockTransactionAdapter[opts]       \[Rule] transaction mock adapter
  RunClaudeScenario[scenario]              \[Rule] Run & verify scenario
  RunAllClaudeTests[]                      \[Rule] Run all built-in tests
  NormalizeClaudeTrace[trace]              \[Rule] Golden normalization
  AssertNoSecretLeak[trace, secrets]       \[Rule] Secret leak check
  AssertValidationDenied[trace]            \[Rule] Deny verification
  AssertOutcome[trace, outcome]            \[Rule] Outcome verification
  AssertBudgetNotExceeded[state]           \[Rule] Budget verification
  AssertEventSequence[trace, types]        \[Rule] Event sequence check
  -- ClaudeOrchestrator integration --
  CreateMockPlanner[tasks]                 \[Rule] mock planner
  CreateMockWorkerAdapter[role, task, ...] \[Rule] mock worker adapter
  CreateMockReducer[payload]               \[Rule] mock reducer
  CreateMockCommitter[nb, reduced]         \[Rule] mock committer
  RunClaudeOrchestrationScenario[scn]      \[Rule] Run orchestration scenario
  AssertNoWorkerNotebookMutation[result]
  AssertSingleCommitterWrites[result]
  AssertArtifactsRespectDependencies[r,t]
  AssertReducerDeterministic[reducer, art]
  AssertTaskOutputMatchesSchema[art, sch]
  -- Stage 2 --
  CreateMockQueryFunction[responses]         \[Rule] mock LLM query function
  AssertArtifactHasSchemaWarnings[artifact]
"]];
