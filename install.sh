#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "=== Scenario Test Skill v3 Installer ==="
echo ""

# Create directories
mkdir -p "$CLAUDE_DIR/skills/scenario-test-from-sessions-v3"
mkdir -p "$CLAUDE_DIR/agents"

# Install skill
cp "$SCRIPT_DIR/skills/scenario-test-from-sessions-v3/SKILL.md" \
   "$CLAUDE_DIR/skills/scenario-test-from-sessions-v3/SKILL.md"
echo "  ✅ skills/scenario-test-from-sessions-v3/SKILL.md"

# Install agents
for agent in branch-context-builder-v3 usage-scenario-discoverer-v3 scenario-reviewer-v3; do
  cp "$SCRIPT_DIR/agents/${agent}.md" "$CLAUDE_DIR/agents/${agent}.md"
  echo "  ✅ agents/${agent}.md"
done

echo ""
echo "=== Installation complete ==="
echo ""
echo "To use:"
echo "  1. Start a new Claude Code session (or run /agents to reload)"
echo "  2. Run: /scenario-test-from-sessions-v3"
echo ""
echo "Requirements:"
echo "  - Claude Code CLI"
echo "  - A git repository with branch history"
echo "  - Claude Code session logs (~/.claude/projects/)"
