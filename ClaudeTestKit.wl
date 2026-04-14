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

$ClaudeTestKitVersion = "2026-04-11T6";

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
"]];
