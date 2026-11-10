## help: Show all available commands
help: Makefile
	@echo
	@echo " Choose a command run:"
	@echo
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@echo

# Cada plataforma tem a sua porta fixa, para todas rodarem juntas:
# Coleção Moda 4000 · jayio 4001 · integramoda 4002 · planta 4003 · pjpark 4004 · paws 4005
# relatorioccb 4006 · reconta 4007 · maestro 4008 · renova 4009 · vitrine 4010 · punhado 4011
# courier 4012
PORT ?= 4012

## dev: Run the app with an IEx shell attached on PORT (default 4012)
.PHONY: dev
dev:
	PORT=$(PORT) iex -S mix phx.server

## server: Run the app on PORT, no shell
.PHONY: server
server:
	PORT=$(PORT) mix phx.server

## setup: Install dependencies, create the database and run migrations
.PHONY: setup
setup:
	mix setup

## test: Run all tests
.PHONY: test
test:
	mix test
