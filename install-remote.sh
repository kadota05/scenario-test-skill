#!/bin/bash
set -e

REPO="kadota05/scenario-test-skill"
BRANCH="main"
TMP_DIR="$(mktemp -d)"
CLAUDE_DIR="$HOME/.claude"

echo "=== Scenario Test Skill v3 Installer ==="
echo ""

# Download
echo "Downloading from github.com/$REPO..."
curl -sL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar xz -C "$TMP_DIR"
SRC="$TMP_DIR/scenario-test-skill-$BRANCH"

# Create directories
mkdir -p "$CLAUDE_DIR/skills/scenario-test-from-sessions-v3"
mkdir -p "$CLAUDE_DIR/agents"

# Install skill
cp "$SRC/skills/scenario-test-from-sessions-v3/SKILL.md" \
   "$CLAUDE_DIR/skills/scenario-test-from-sessions-v3/SKILL.md"
echo "  ✅ skills/scenario-test-from-sessions-v3/SKILL.md"

# Install agents
for agent in branch-context-builder-v3 usage-scenario-discoverer-v3 scenario-reviewer-v3; do
  cp "$SRC/agents/${agent}.md" "$CLAUDE_DIR/agents/${agent}.md"
  echo "  ✅ agents/${agent}.md"
done

# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "=== Installation complete ==="
echo ""
echo "To use:"
echo "  1. Start a new Claude Code session (or run /agents to reload)"
echo "  2. Run: /scenario-test-from-sessions-v3"
