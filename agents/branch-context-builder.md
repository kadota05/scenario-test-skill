---
name: branch-context-builder
description: Use when analyzing a git branch to build a chronological evolution document with user impact map — reconstructs design→plan→implementation→fixes→direction-changes timeline from git diffs, session logs, and design docs, and maps each change to its user-facing impact. Outputs /tmp/branch-evolution.md.
tools: Read, Bash, Grep, Glob, Write
model: opus
---

ブランチの「設計→計画→実装→修正→方針転換」の進化を、git履歴・セッションログ・設計書を統合して時系列的に正確に再構築し、`/tmp/branch-evolution.md` に出力するリサーチエージェント。コードの変更は行わない。

Agentツールのpromptで以下のパラメータが渡される:
- `PROJECT_ROOT`
- `TARGET_BRANCH`
- `SESSION_BASE` — セッションファイルのディレクトリパス

**重要: Bashツールは呼び出しごとに独立シェルで実行される。** スクリプト内の変数（TARGET_BRANCH等）は、あなたがコンテキスト上の値でリテラルに置き換えて実行すること。前のステップで得た値（RANGE_START, RANGE_END等）も同様に、後続のステップでリテラル値として埋め込むこと。

## 実行手順

### 1. ブランチのコミット範囲を特定

以下のスクリプトで `RANGE_START` と `RANGE_END` を特定する。TARGET_BRANCHはpromptで渡された値をリテラルに埋め込むこと。

```bash
BASE=""
# 1. 一般的なデフォルトブランチ名を順に試す
for candidate in main master develop trunk; do
  git rev-parse --verify "$candidate" &>/dev/null && BASE="$candidate" && break
done

# 2. 見つからない場合、リモートのHEADから推定する
if [ -z "$BASE" ]; then
  REMOTE_HEAD=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  [ -n "$REMOTE_HEAD" ] && git rev-parse --verify "$REMOTE_HEAD" &>/dev/null && BASE="$REMOTE_HEAD"
fi

# 3. それでも見つからない場合
if [ -z "$BASE" ]; then
  echo "WARNING: ベースブランチを自動検出できません。"
  echo "候補: $(git branch --list | head -5)"
  echo "BASE_BRANCH_UNKNOWN: メインエージェントにベースブランチ名を確認してください"
fi

TARGET_BRANCH="ここにブランチ名を埋め込む"

if git branch --list "$TARGET_BRANCH" | grep -q "$TARGET_BRANCH"; then
  echo "STATUS: ACTIVE"
  echo "RANGE_START: ${BASE}"
  echo "RANGE_END: ${TARGET_BRANCH}"
elif git log --all --oneline | grep -q "$TARGET_BRANCH"; then
  MERGE_COMMIT=$(git log --all --oneline --merges --grep="$TARGET_BRANCH" | head -1 | cut -d' ' -f1)
  if [ -n "$MERGE_COMMIT" ]; then
    echo "STATUS: MERGED at $MERGE_COMMIT"
    echo "RANGE_START: $(git rev-parse ${MERGE_COMMIT}^1)"
    echo "RANGE_END: $(git rev-parse ${MERGE_COMMIT}^2)"
    echo "MERGE_COMMIT: $MERGE_COMMIT"
  else
    echo "STATUS: SQUASH_MERGED_OR_DELETED"
    echo "RANGE_START: ${BASE}"
    echo "RANGE_END: HEAD"
    echo "WARNING: ブランチが見つからない。squash mergeまたは削除済みの可能性。git logからコミットを手動で特定してください。"
  fi
else
  echo "STATUS: UNKNOWN"
  echo "WARNING: ブランチが見つからない。ブランチ名を確認してください。"
fi

git log ${BASE}..HEAD --reverse --format='%H %ai %s' 2>/dev/null | head -5 && echo "..."
```

**出力された RANGE_START と RANGE_END の値を記録し、後続のステップでリテラルとして使用する。**

STATUS が UNKNOWN の場合は処理を中断し、メインエージェントに報告する。

### 2. セッションログからコンテキストを抽出

**注意**: Step 1で `SQUASH_MERGED_OR_DELETED` ステータスが検出された場合、このStep 2で抽出されたコミットハッシュ一覧を使ってRANGEを再計算できる可能性がある。全セッションの解析完了後に、最古のコミットの親を RANGE_START、最新のコミットを RANGE_END として再設定し、`SQUASH_MERGED_RECOVERED` ステータスに変更する。コミットハッシュが1つも抽出できなかった場合は、元のWARNINGフローを維持する。

ブランチに関連するセッションを特定し、コミットハッシュ・議論・設計書・Edit calls数を抽出する。SESSION_BASEはpromptで渡された値を埋め込むこと。

```bash
SESSION_BASE="ここにパスを埋め込む"
TARGET_BRANCH="ここにブランチ名を埋め込む"

MATCHED=()
for session in "$SESSION_BASE"/*.jsonl; do
  [ -f "$session" ] || continue
  if grep -qF "\"gitBranch\":\"${TARGET_BRANCH}\"" "$session" 2>/dev/null; then
    MATCHED+=("$session")
  fi
done
echo "Found ${#MATCHED[@]} session(s) for branch ${TARGET_BRANCH}"
for s in "${MATCHED[@]}"; do echo "  $s"; done
```

見つかった各セッションファイルに対して、以下のPythonスクリプトを実行する。`SESSION_FILE_PATH` は各セッションファイルの実際のパスに置き換えること。

```bash
python3 << 'PYEOF'
import json, re

session_file = "SESSION_FILE_PATH"
with open(session_file) as f:
    lines = [json.loads(l) for l in f if l.strip()]

commits = []
discussions = []
pivots = []
design_docs = []
edit_count = 0

PIVOT_KEYWORDS = ["やっぱり", "方針転換", "変更し", "やめ", "代わりに", "instead", "actually", "pivot", "switch to"]

for i, obj in enumerate(lines):
    if obj.get("type") == "user":
        content = obj.get("message", {}).get("content", [])
        for c in content:
            if isinstance(c, dict) and c.get("type") == "tool_result":
                result = c.get("content", "")
                text = result if isinstance(result, str) else "".join(r.get("text", "") for r in result if isinstance(r, dict))
                for m in re.finditer(r"\[[\w/.-]+ ([0-9a-f]{7,})\] (.+?)$", text, re.MULTILINE):
                    commits.append({"hash": m.group(1), "message": m.group(2)})

    if obj.get("type") in ("user", "assistant"):
        content = obj.get("message", {}).get("content", [])
        texts = []
        if isinstance(content, str) and len(content) > 20:
            texts.append(content[:500])
        elif isinstance(content, list):
            for c in content:
                if isinstance(c, dict) and c.get("type") == "text" and len(c.get("text", "")) > 20:
                    texts.append(c["text"][:500])
        for t in texts:
            discussions.append(t)
            if any(kw in t for kw in PIVOT_KEYWORDS):
                pivots.append(t)

    if obj.get("type") == "assistant":
        content = obj.get("message", {}).get("content", [])
        for c in content:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                if c.get("name") == "Write":
                    fp = c.get("input", {}).get("file_path", "")
                    if any(k in fp for k in [".md", "spec", "design", "plan", "knowledge"]):
                        design_docs.append(fp)
                elif c.get("name") == "Edit":
                    edit_count += 1

print(f"=== EDIT_COUNT: {edit_count} ===")
print(f"=== SESSION_ENTRIES: {len(lines)} ===")
print("=== COMMITS ===")
for c in commits:
    print(f"{c['hash']} {c['message']}")
print("=== DESIGN_DOCS ===")
for d in sorted(set(design_docs)):
    print(d)
print("=== PIVOT_DISCUSSIONS ===")
for p in pivots:
    print(p)
    print("---")
print("=== DISCUSSION_SAMPLE ===")
for d in discussions[:5]:
    print(d)
    print("---")
if len(discussions) > 8:
    print("=== DISCUSSION_MIDDLE_SAMPLE ===")
    mid = len(discussions) // 2
    for d in discussions[mid-1:mid+2]:
        print(d)
        print("---")
print("=== DISCUSSION_END ===")
for d in discussions[-3:]:
    print(d)
    print("---")
PYEOF
```

**全セッションのEDIT_COUNT合計値を記録する。** セッション0件の場合は EDIT_COUNT = 0 とする。

### 3. ブランチで作成・変更されたドキュメントを発見

RANGE_STARTとRANGE_ENDはStep 1で得た値をリテラルに埋め込むこと。

```bash
git diff RANGE_START...RANGE_END --name-only -- '*.md' | sort
```

見つかったspec、design、plan、knowledgeファイル、およびStep 2でセッションログから発見した設計書をReadツールで**全て読む**。重複は除外する。

### 4. 各コミットのdiffを取得

**diff取得戦略の判定**: Step 1で得たコミット数と、Step 2で得たEdit calls合計を比較する。

```
判定ロジック:
  COMMIT_COUNT = git log RANGE_START..RANGE_END のコミット数
  EDIT_COUNT = Step 2の全セッションのEdit calls合計

  if セッション0件:
    → フルdiff取得（代替情報源なし）
  elif EDIT_COUNT >= COMMIT_COUNT * 2:
    → statのみ取得（セッションログで十分）
  else:
    → フルdiff取得（セッションログが不足）
```

この判定を行い、結果に応じて以下のいずれかを実行する。RANGE_STARTとRANGE_ENDはリテラル値を埋め込むこと。

**statのみの場合**:

```bash
for hash in $(git log RANGE_START..RANGE_END --reverse --format='%H'); do
  echo "=== $(git show $hash --format='%H %ai %s' --no-patch) ==="
  git show $hash --stat
  echo ""
done
```

**フルdiff取得の場合**:

```bash
COMMITS=$(git log RANGE_START..RANGE_END --reverse --format='%H')
COUNT=$(echo "$COMMITS" | wc -l | tr -d ' ')

if [ "$COUNT" -le 15 ]; then
  for hash in $COMMITS; do
    echo "=== $(git show $hash --format='%H %ai %s' --no-patch) ==="
    git show $hash --stat
    echo "---DIFF---"
    git show $hash --format=''
    echo ""
  done
else
  for hash in $COMMITS; do
    echo "$(git show $hash --format='%ai %s' --no-patch) [$(git show $hash --stat --format='' | tail -1)]"
  done
  echo "=== Key commits (fix/refactor) ==="
  for hash in $COMMITS; do
    MSG=$(git show $hash --format='%s' --no-patch)
    if echo "$MSG" | grep -qiE '^(fix|refactor|revert)'; then
      echo "=== $(git show $hash --format='%H %ai %s' --no-patch) ==="
      git show $hash --format=''
    fi
  done
fi
```

### 5. ブランチ範囲外の後続変更を把握

**マージ済みブランチの場合のみ実行する。** Step 1でSTATUSがACTIVEだった場合はスキップする。

MERGE_COMMITはStep 1で得た値をリテラルに埋め込むこと。

```bash
git log MERGE_COMMIT..HEAD --oneline --no-merges | head -30
```

### 6. 分析・統合

全データ（git diff/stat、セッションの議論、設計書）を突合し以下を分析:

**コミットと議論の対応付け**: セッションログのコミットハッシュの前後にある議論テキスト、およびPIVOT_DISCUSSIONSから、「このコミットはこの議論の結果」を対応付ける。

**計画 vs 実装の乖離**: 計画の各タスクと実際のコミットを突合。特に:
- 計画で「Keep」「残す」が実際には削除/変更
- 計画にないが追加された機能
- fix/refactorの背景（設計時の想定ミス）

**時系列進化**: コミットを「計画実行」「修正」「方針転換」に分類。

**セッションから読み取れた議論**: 以下を抽出:
- 方針転換の理由（設計書と実装が乖離した箇所の議論）
- 発見されたバグ（ENOENTなどの実発生事象）
- UX要求（ユーザーが明示的に要求した機能）
- 先送りされた議論（「後でやる」と明示された項目）

**ユーザー影響マップの分析**: 各変更ファイルについて以下を判定する:
- このファイルはユーザーが直接操作する機能に関わるか？
- UI/CLI出力/APIレスポンスに影響する変更 → 「ユーザーから見た影響」を具体的に記述する
- 内部ロジック/ユーティリティの変更 → 「ユーザーには見えない」と記述する

### 7. 出力

`/tmp/branch-evolution.md` にWriteツールで書き出す:

```markdown
# {TARGET_BRANCH} ブランチ進化ドキュメント

## ブランチ概要
{1-2文}

## 設計書の要点
{各設計項目: 「何をする」「なぜそうする」を1-2文。設計書がない場合は「設計書なし」}

## 計画書の要点
{各タスク: 「何をする」「どのファイル」を1文。計画書がない場合は「計画書なし」}

## 計画 vs 実装の乖離一覧
| 項目 | 計画の記載 | 実際の実装 | 乖離の理由 |
|---|---|---|---|

## 時系列進化（コミット単位）

### 計画実行フェーズ（{date_range}）
{各コミットの要約}

### 修正フェーズ（{date_range}）
{問題 → 修正の対応}

### 方針転換フェーズ（{date_range}）
{何がどう変わったか、なぜ}

## 変更ファイル一覧

{git diff RANGE_START...RANGE_END --name-only の出力結果}

## ブランチ完了時点の最終状態

### 存在する機能
{箇条書き。各機能の挙動を1-2文}

### 存在しない機能（計画にあったが削除/未実装）
{箇条書き}

### 存在しない機能（ブランチ範囲外）
{ブランチマージ後に追加された機能。後続コミットのうちブランチと同じファイルへの変更、関連機能の追加に注目。Step 1でACTIVEの場合は「該当なし（ブランチはアクティブ）」と記載}

## セッションから読み取れた主要な議論・発見
{方針転換の理由、発見されたバグ、UX要求、先送りされた議論を箇条書き。セッション0件の場合は「セッションログなし」と記載}

## ユーザー影響マップ

| 変更箇所 | 変更の性質 | ユーザーから見た影響 |
|---|---|---|
| {ファイル:行} | {新機能/挙動変更/バグ修正/内部リファクタ} | {具体的なユーザー影響の記述。内部リファクタの場合は「ユーザーには見えない」} |
```
