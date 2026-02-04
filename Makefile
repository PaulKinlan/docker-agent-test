.PHONY: help build up down restart shell logs clean create-agent remove-agent update-agent list-agents list-personas agent-logs agent-shell set-api-key get-api-keys remove-api-key clear-api-keys list-providers

help:
	@echo "Container management:"
	@echo "  make build                  - Build the Docker image"
	@echo "  make up                     - Start the container (systemd boot)"
	@echo "  make down                   - Stop and remove the container"
	@echo "  make restart                - Restart the container"
	@echo "  make shell                  - Open a root shell in the container"
	@echo "  make logs                   - View container logs"
	@echo "  make clean                  - Remove image and cleanup"
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
	docker-compose logs -f

clean: down
	docker rmi agent-host:latest || true
	@echo "Note: home directory contents preserved in ./home/"

# --- Agent management ---

create-agent:
ifndef NAME
	$(error NAME is required. Usage: make create-agent NAME=myagent [PERSONA=coder] [API_KEY=PROVIDER=key])
endif
	docker-compose exec agent-host /usr/local/bin/create-agent.sh $(NAME) \
		$(if $(PERSONA),--persona $(PERSONA)) \
		$(if $(API_KEY),--api-key $(API_KEY))

remove-agent:
ifndef NAME
	$(error NAME is required. Usage: make remove-agent NAME=myagent)
endif
	docker-compose exec agent-host /usr/local/bin/remove-agent.sh $(NAME)

update-agent:
ifndef NAME
	$(error NAME is required. Usage: make update-agent NAME=myagent PERSONA=coder)
endif
ifndef PERSONA
	$(error PERSONA is required. Usage: make update-agent NAME=myagent PERSONA=coder)
endif
	docker-compose exec agent-host /usr/local/bin/update-agent.sh $(NAME) --persona $(PERSONA)

list-agents:
	docker-compose exec agent-host /usr/local/bin/list-agents.sh

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
	docker-compose exec agent-host journalctl -u agent@$(NAME).service -f

agent-shell:
ifndef NAME
	$(error NAME is required. Usage: make agent-shell NAME=myagent)
endif
	docker-compose exec --user $(NAME) agent-host /bin/bash

# --- API key management ---

set-api-key:
ifndef NAME
	$(error NAME is required. Usage: make set-api-key NAME=myagent KEY=PROVIDER=value)
endif
ifndef KEY
	$(error KEY is required. Usage: make set-api-key NAME=myagent KEY=ANTHROPIC_API_KEY=sk-xxx)
endif
	docker-compose exec agent-host /usr/local/bin/manage-api-keys.sh set $(NAME) $(KEY)

get-api-keys:
ifndef NAME
	$(error NAME is required. Usage: make get-api-keys NAME=myagent)
endif
	docker-compose exec agent-host /usr/local/bin/manage-api-keys.sh get $(NAME)

remove-api-key:
ifndef NAME
	$(error NAME is required. Usage: make remove-api-key NAME=myagent KEY=PROVIDER)
endif
ifndef KEY
	$(error KEY is required. Usage: make remove-api-key NAME=myagent KEY=OPENAI_API_KEY)
endif
	docker-compose exec agent-host /usr/local/bin/manage-api-keys.sh remove $(NAME) $(KEY)

clear-api-keys:
ifndef NAME
	$(error NAME is required. Usage: make clear-api-keys NAME=myagent)
endif
	docker-compose exec agent-host /usr/local/bin/manage-api-keys.sh clear $(NAME)

list-providers:
	docker-compose exec agent-host /usr/local/bin/manage-api-keys.sh list-providers
