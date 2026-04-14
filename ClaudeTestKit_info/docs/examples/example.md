# ClaudeTestKit 使用例集

ClaudeTestKit を使った実際のテストシナリオをまとめます。

---

## 例 1: MockProvider の作成

固定応答を順番に返す mock provider を作成します。

```mathematica
provider = CreateMockProvider[{
  "NBCellRead[nb, 1]",
  "NBCellWrite[nb, 2, \"result\"]"
}];
provider
```

**期待される出力:** `<|"Type" -> "MockProvider", "Responses" -> {...}, "Index" -> 1|>`

---

## 例 2: MockAdapter を使った基本シナリオ実行

`CreateMockAdapter` でアダプターを作り、`RunClaudeScenario` でシナリオを実行します。

```mathematica
adapter = CreateMockAdapter[
  "Provider" -> CreateMockProvider[{"NBCellRead[nb, 1]"}],
  "AllowedHeads" -> {"NBCellRead", "NBCellWrite"}
];
result = RunClaudeScenario[<|
  "Name" -> "基本読み取りテスト",
  "Input" -> "セル 1 を読んで",
  "Adapter" -> adapter,
  "Profile" -> "default"
|>];
result["Outcome"]
```

**期待される出力:** `"Success"`

---

## 例 3: シークレット漏洩の検証

trace に API キーや機密文字列が含まれていないことを検証します。

```mathematica
trace = RunClaudeScenario[<|
  "Name" -> "秘密漏洩テスト",
  "Input" -> "処理を実行して",
  "Adapter" -> adapter
|>]["Trace"];
AssertNoSecretLeak[trace, {"sk-ant-api03-xxxx", "password123"}]
```

**期待される出力:** `True`

---

## 例 4: Deny シナリオの検証

`"DenyHeads"` に指定した操作が確実に拒否されることをテストします。

```mathematica
denyAdapter = CreateMockAdapter[
  "Provider" -> CreateMockProvider[{"DeleteFile[\"/etc/passwd\"]"}],
  "DenyHeads" -> {"DeleteFile", "RunProcess"}
];
result = RunClaudeScenario[<|
  "Name" -> "危険操作 deny テスト",
  "Input" -> "ファイルを削除して",
  "Adapter" -> denyAdapter
|>];
AssertValidationDenied[result["Trace"]]
```

**期待される出力:** `True`

---

## 例 5: トレースの正規化（ゴールデン比較）

タイムスタンプや ID を除去して再現可能な形にします。

```mathematica
rawTrace = RunClaudeScenario[<|
  "Name" -> "正規化テスト",
  "Input" -> "何かして",
  "Adapter" -> adapter
|>]["Trace"];
normalized = NormalizeClaudeTrace[rawTrace];
normalized[[1, "Type"]]
```

**期待される出力:** `"SessionStart"`

---

## 例 6: イベント列の検証

trace に期待するイベント型が順序どおり含まれているかを確認します。

```mathematica
AssertEventSequence[
  result["Trace"],
  {"SessionStart", "ProviderRequest", "ValidationResult", "SessionEnd"}
]
```

**期待される出力:** `True`

---

## 例 7: 最終 Outcome の検証

`AssertOutcome` で期待する終了状態を確認します。

```mathematica
AssertOutcome[result["Trace"], "Success"]
```

**期待される出力:** `True`

---

## 例 8: 全組み込みテストの一括実行

`RunAllClaudeTests` で全シナリオを実行し、結果を Dataset として取得します。

```mathematica
results = RunAllClaudeTests[];
results[All, {"Name", "Outcome", "Passed"}]
```

**期待される出力:** `Dataset` 形式のテスト結果一覧（全行 `"Passed" -> True`）