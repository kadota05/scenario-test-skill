# Scenario Test from Sessions v3

Claude Codeのセッション履歴・設計書・git履歴を分析し、シナリオベーステスト仕様書を自動生成するスキル。

## 普通のテストとの違い

普通のテストは「機能が正しく動くか」を見る。このスキルは「実際の使われ方の中でも壊れないか」を見る。

生成されるシナリオは2種類に分類される:

- **実利用シナリオ (US)** — ユーザーが普通に使っていて遭遇する状況。絶対に通ってほしいテスト。
- **実装境界シナリオ (IB)** — コードの境界条件を突いて気づきを与えるもの。対応するかは開発者次第。

## セットアップ

ワンコマンドでインストール:

```bash
curl -sL https://raw.githubusercontent.com/kadota05/scenario-test-skill/main/install-remote.sh | bash
```

または、リポジトリをcloneしてインストール:

```bash
git clone https://github.com/kadota05/scenario-test-skill.git
cd scenario-test-skill
./install.sh
```

## 使い方

1. Claude Codeで対象プロジェクトを開く
2. 新しいセッションを開始する（または `/agents` でリロード）
3. 以下を実行:

```
/scenario-test-from-sessions-v3
```

ブランチを選択すると、自動的に以下が実行される:

1. **Branch Context** — git履歴・セッションログ・設計書を統合分析
2. **Usage Scenario Discovery** — 利用シーン・利用文脈を発見
3. **Scenario Generation** — 実利用/実装境界の2カテゴリでシナリオを生成
4. **Review** — 分類の妥当性・品質を自動レビュー
5. **Output** — `docs/test-scenarios/` に仕様書を出力

## 前提条件

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- gitリポジトリ（ブランチ履歴があること）
- Claude Codeセッションログ（`~/.claude/projects/` 配下）

## ファイル構成

```
~/.claude/
├── skills/
│   └── scenario-test-from-sessions-v3/
│       └── SKILL.md                          # メインスキル
└── agents/
    ├── branch-context-builder-v3.md          # git履歴・セッション分析
    ├── usage-scenario-discoverer-v3.md       # 利用シーン発見
    └── scenario-reviewer-v3.md               # レビュー（チェックA-I）
```

## アップデート

```bash
cd scenario-test-skill
git pull
./install.sh
```

## License

MIT
