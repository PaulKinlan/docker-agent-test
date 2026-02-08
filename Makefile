.PHONY: help build up down restart shell logs clean reset soft-reset create-agent remove-agent update-agent list-agents list-personas agent-logs agent-shell mail set-api-key get-api-keys remove-api-key clear-api-keys list-providers snapshot-init snapshot snapshot-log snapshot-diff snapshot-status tui install-tui

help:
	@echo "Container management:"
	@echo "  make build                  - Build the Docker image"
	@echo "  make up                     - Start the container (systemd boot)"
	@echo "  make down                   - Stop and remove the container"
	@echo "  make restart                - Restart the container"
	@echo "  make shell                  - Open a root shell in the container"
	@echo "  make logs                   - View container logs"
	@echo "  make clean                  - Remove image and cleanup"
	@echo "  make reset                  - Full reset: stop container, remove image, wipe all data"
	@echo "  make soft-reset             - Remove all agents, clear logs and mail (container stays running)"
	@echo ""
	@echo "Agent management (container must be running):"
	@echo "  make create-agent NAME=foo              - Create agent with base persona"
	@echo "  make create-agent NAME=foo PERSONA=coder - Create agent with specialist persona"
	@echo "  make create-agent NAME=foo API_KEY=ANTHROPIC_API_KEY=sk-xxx - Create with API key"
	@echo "  make update-agent NAME=foo PERSONA=coder - Update agent's persona"
	@echo "  make remove-agent NAME=foo              - Remove an agent user"
	@echo "  make list-agents                        - List all agents and their status"
	@echo "  make list-personas                      - List available personas"
	@echo "  make agent-logs NAME=foo                - Tail logs for an agent"
	@echo "  make agent-shell NAME=foo               - Open a shell as an agent user"
	@echo "  make mail TO=alice MSG=\"Hello\"           - Send mail to an agent (from root)"
	@echo "  make mail TO=alice FROM=bob MSG=\"Hi\"     - Send mail as a specific user"
	@echo ""
	@echo "Snapshots (run on host, container not required):"
	@echo "  make snapshot-init                      - Initialize the snapshot repository"
	@echo "  make snapshot                           - Take a snapshot of agent state"
	@echo "  make snapshot MSG=\"my note\"              - Take a snapshot with a custom message"
	@echo "  make snapshot-log                       - Show snapshot history"
	@echo "  make snapshot-diff                      - Show changes since last snapshot"
	@echo "  make snapshot-status                    - Summarize changes since last snapshot"
	@echo ""
	@echo "Interactive TUI:"
	@echo "  make install-tui                        - Install TUI dependencies (first time)"
	@echo "  make tui                                - Open the interactive TUI"
	@echo ""
	@echo "API key management (container must be running):"
	@echo "  make set-api-key NAME=foo KEY=ANTHROPIC_API_KEY=sk-xxx - Set API key for agent"
	@echo "  make get-api-keys NAME=foo              - Show API keys for agent (masked)"
	@echo "  make remove-api-key NAME=foo KEY=OPENAI_API_KEY - Remove API key from agent"
	@echo "  make clear-api-keys NAME=foo            - Remove all API keys from agent"
	@echo "  make list-providers                     - List known API key provider names"

build:
	docker-compose build

up:
	docker-compose up -d

down:
	docker-compose down

restart: down up

shell:
	docker-compose exec agent-host /bin/bash

logs:
	docker-compose logs -f --timestamps

clean: down
	docker rmi agent-host:latest || true
	@echo "Note: home directory contents preserved in ./home/"

soft-reset: ## Remove all agents, clear logs and mail (container stays running)
	docker-compose exec -T agent-host /usr/local/bin/soft-reset.sh --yes

reset: down ## Full reset: stop container, remove image, wipe home/log/mail
	docker rmi agent-host:latest || true
	sudo find ./home -mindepth 1 ! -name '.gitkeep' -delete
	sudo find ./log -mindepth 1 ! -name '.gitkeep' -delete
	sudo find ./mail -mindepth 1 ! -name '.gitkeep' -delete
	@echo "Reset complete. All agent data, logs, and mail removed."

# --- Agent management ---

create-agent:
ifndef NAME
	$(error NAME is required. Usage: make create-agent NAME=myagent [PERSONA=coder] [API_KEY=PROVIDER=key])
endif
	docker-compose exec -T agent-host /usr/local/bin/create-agent.sh $(NAME) \
		$(if $(PERSONA),--persona $(PERSONA)) \
		$(if $(API_KEY),--api-key $(API_KEY))

remove-agent:
ifndef NAME
	$(error NAME is required. Usage: make remove-agent NAME=myagent)
endif
	docker-compose exec -T agent-host /usr/local/bin/remove-agent.sh $(NAME)

update-agent:
ifndef NAME
	$(error NAME is required. Usage: make update-agent NAME=myagent PERSONA=coder)
endif
ifndef PERSONA
	$(error PERSONA is required. Usage: make update-agent NAME=myagent PERSONA=coder)
endif
	docker-compose exec -T agent-host /usr/local/bin/update-agent.sh $(NAME) --persona $(PERSONA)

list-agents:
	docker-compose exec -T agent-host /usr/local/bin/list-agents.sh

list-personas:
	@echo "Available personas (in config/personas/):"
	@echo ""
	@echo "  base       - Default persona applied to all agents"
	@for f in config/personas/*.md; do \
		name=$$(basename "$$f" .md); \
		if [ "$$name" != "base" ]; then \
			echo "  $$name"; \
		fi; \
	done
	@echo ""
	@echo "Usage: make create-agent NAME=myagent PERSONA=<name>"

agent-logs:
ifndef NAME
	$(error NAME is required. Usage: make agent-logs NAME=myagent)
endif
	docker-compose exec -T agent-host journalctl -u agent@$(NAME).service -f

agent-shell:
ifndef NAME
	$(error NAME is required. Usage: make agent-shell NAME=myagent)
endif
	docker-compose exec --user $(NAME) agent-host /bin/bash

mail: ## Send mail to an agent
ifndef TO
	$(error TO is required. Usage: make mail TO=alice MSG="Hello" [FROM=bob] [SUBJECT="Hi"])
endif
ifndef MSG
	$(error MSG is required. Usage: make mail TO=alice MSG="Hello" [FROM=bob] [SUBJECT="Hi"])
endif
	docker-compose exec -T agent-host /usr/local/bin/send-mail.sh "$(TO)" $(if $(FROM),--from "$(FROM)") $(if $(SUBJECT),--subject "$(SUBJECT)") -- "$(MSG)"

# --- API key management ---

set-api-key:
ifndef NAME
	$(error NAME is required. Usage: make set-api-key NAME=myagent KEY=PROVIDER=value)
endif
ifndef KEY
	$(error KEY is required. Usage: make set-api-key NAME=myagent KEY=ANTHROPIC_API_KEY=sk-xxx)
endif
	docker-compose exec -T agent-host /usr/local/bin/manage-api-keys.sh set $(NAME) $(KEY)

get-api-keys:
ifndef NAME
	$(error NAME is required. Usage: make get-api-keys NAME=myagent)
endif
	docker-compose exec -T agent-host /usr/local/bin/manage-api-keys.sh get $(NAME)

remove-api-key:
ifndef NAME
	$(error NAME is required. Usage: make remove-api-key NAME=myagent KEY=PROVIDER)
endif
ifndef KEY
	$(error KEY is required. Usage: make remove-api-key NAME=myagent KEY=OPENAI_API_KEY)
endif
	docker-compose exec -T agent-host /usr/local/bin/manage-api-keys.sh remove $(NAME) $(KEY)

clear-api-keys:
ifndef NAME
	$(error NAME is required. Usage: make clear-api-keys NAME=myagent)
endif
	docker-compose exec -T agent-host /usr/local/bin/manage-api-keys.sh clear $(NAME)

list-providers:
	docker-compose exec -T agent-host /usr/local/bin/manage-api-keys.sh list-providers

# --- Agent snapshots (host-side) ---

snapshot-init:
	@./scripts/snapshot-agents.sh init

snapshot:
	@./scripts/snapshot-agents.sh create "$(if $(MSG),$(MSG),)"

snapshot-log:
	@./scripts/snapshot-agents.sh log

snapshot-diff:
	@./scripts/snapshot-agents.sh diff

snapshot-status:
	@./scripts/snapshot-agents.sh status

# --- Interactive TUI ---

install-tui: ## Install TUI dependencies
	@cd tui && npm install

tui: ## Open the interactive TUI
	@node cli.mjs
