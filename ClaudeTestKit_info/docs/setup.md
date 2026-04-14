# ClaudeTestKit — インストール手順書

macOS/Linux ではパス区切りやシェルコマンドを適宜読み替えてください。

---

## 動作要件

| 項目 | 最低バージョン |
|------|--------------|
| Mathematica / Wolfram Engine | 13.0 以降 |
| ClaudeRuntime | 最新版 |
| NBAccess | 最新版 |

外部ツール・API キーは ClaudeTestKit 単体の使用には不要です。
ClaudeRuntime のセキュリティカーネルをテストする場合は、ClaudeRuntime 側の設定（API キー等）を先に完了させてください。

---

## インストール手順

### 1. $packageDirectory の確認

Mathematica のノートブックで以下を実行し、パッケージディレクトリのパスを確認します。

```mathematica
$packageDirectory
```

`$packageDirectory` が未定義の場合は、ClaudeRuntime または claudecode パッケージをインストールしてください。

### 2. ファイルの配置

[ClaudeTestKit リポジトリ](https://github.com/transreal/ClaudeTestKit) から `ClaudeTestKit.wl` をダウンロードし、
`$packageDirectory` に直接配置します。

```
C:\Users\<ユーザー名>\<packageDirectory>\
    ClaudeTestKit.wl   ← ここに配置
```

サブディレクトリには置かないでください。

### 3. 依存パッケージの確認

ClaudeTestKit は以下のパッケージに依存します。同じく `$packageDirectory` に配置されていることを確認してください。

- [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime)
- [NBAccess](https://github.com/transreal/NBAccess)

### 4. $Path への追加

claudecode を使用している場合、`$Path` は自動的に設定されます。手動で設定する場合は以下を実行します。

```mathematica
If[!MemberQ[$Path, $packageDirectory],
  AppendTo[$Path, $packageDirectory]
]
```

**注意**: `$packageDirectory` そのものを `$Path` に追加してください。サブディレクトリを追加するのは誤りです。

### 5. パッケージの読み込み

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeTestKit`", "ClaudeTestKit.wl"]
]
```

---

## 動作確認

### バージョン確認

```mathematica
$ClaudeTestKitVersion
```

バージョン文字列が返れば読み込み成功です。

### 組み込みテストの実行

```mathematica
results = RunAllClaudeTests[]
```

`Dataset` 形式で全テストシナリオの結果が返ります。全行が `True` または `"Pass"` であれば正常です。

### MockProvider の簡易テスト

```mathematica
provider = CreateMockProvider[{"NBCellRead[nb, 1]", "Done"}];
adapter  = CreateMockAdapter[
  "Provider"         -> provider,
  "AllowedHeads"     -> {NBCellRead},
  "ExecutionResults" -> {"cell content"}
];
```

エラーなく実行できれば、基本的な mock 機能が正常に動作しています。

### シナリオ実行のサンプル

```mathematica
scenario = <|
  "Name"       -> "ReadCellTest",
  "Input"      -> "セル 1 の内容を読んで",
  "Adapter"    -> adapter,
  "Profile"    -> <|"MaxContinuations" -> 3|>,
  "Assertions" -> {AssertNoSecretLeak[#Trace, {}]&}
|>;
RunClaudeScenario[scenario]
```

---

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| `Needs::nocont` エラー | `$packageDirectory` が `$Path` に含まれているか確認 |
| 文字化け | `Block[{$CharacterEncoding = "UTF-8"}, ...]` で読み込む |
| `ClaudeRuntime` 関連エラー | ClaudeRuntime が正しく読み込まれているか確認 |
| `NBAccess` 関連エラー | NBAccess が正しく読み込まれているか確認 |