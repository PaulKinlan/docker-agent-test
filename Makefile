.PHONY: help build up down restart shell logs clean create-agent remove-agent list-agents agent-logs agent-shell

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
	@echo "  make create-agent NAME=foo  - Create a new agent user"
	@echo "  make remove-agent NAME=foo  - Remove an agent user"
	@echo "  make list-agents            - List all agents and their status"
	@echo "  make agent-logs NAME=foo    - Tail logs for an agent"
	@echo "  make agent-shell NAME=foo   - Open a shell as an agent user"

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
	$(error NAME is required. Usage: make create-agent NAME=myagent)
endif
	docker-compose exec agent-host /usr/local/bin/create-agent.sh $(NAME)

remove-agent:
ifndef NAME
	$(error NAME is required. Usage: make remove-agent NAME=myagent)
endif
	docker-compose exec agent-host /usr/local/bin/remove-agent.sh $(NAME)

list-agents:
	docker-compose exec agent-host /usr/local/bin/list-agents.sh

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
