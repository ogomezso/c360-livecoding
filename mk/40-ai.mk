##@ AI assistants (Confluent MCP wiring)
# One MCP server definition, one adapter per tool: scripts/ai-mcp-config.sh.
# Adding an assistant = a case in that script + one target here + add it to ai-all.
.PHONY: ai-claude ai-copilot ai-bob ai-all ai-status ai-kill-mcp context

ai-claude: ## Claude Code (CLI + VS Code extension) -> ./.mcp.json
	@./scripts/ai-mcp-config.sh claude

ai-copilot: ## GitHub Copilot in VS Code -> ./.vscode/mcp.json
	@./scripts/ai-mcp-config.sh copilot

ai-bob: ## IBM Bob -> ~/.bob/settings/mcp.json (merged; existing servers kept, .bak written)
	@./scripts/ai-mcp-config.sh bob

ai-all: ## Wire every assistant above
	@./scripts/ai-mcp-config.sh all

context: ## Pin every assistant to this demo's environment/cluster (CLAUDE.md, copilot-instructions, .bob/rules)
	@./scripts/context.sh all

ai-status: ## Show which assistants have the MCP server configured AND an up-to-date environment context
	@./scripts/ai-mcp-config.sh status
	@./scripts/context.sh status

ai-kill-mcp: ## Kill stray mcp-confluent processes (they slow down the VS Code extension)
	@if pgrep -f '[m]cp-confluent' >/dev/null; then pgrep -fl '[m]cp-confluent'; pkill -f '[m]cp-confluent' && echo '  ✓ killed'; else echo '  ✓ none running'; fi
