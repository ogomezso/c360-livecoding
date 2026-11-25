##@ Data
.PHONY: data demo-changes

CUSTOMERS    ?= 200
TRANSACTIONS ?= 1000
INTERACTIONS ?= 800

data: ## Produce synthetic Spanish banking data to the source topics (CUSTOMERS= TRANSACTIONS= INTERACTIONS=)
	@ASSUME_YES=1 ./scripts/generate-data.sh $(CUSTOMERS) $(TRANSACTIONS) $(INTERACTIONS)

# Not part of the build: run it DURING the demo to make something happen (see README, Phase 8).
# CHANGES picks how many customers; DRY_RUN=1 only shows who would be picked; IDS=<id>,<id> chooses them yourself.
CHANGES ?= 3

demo-changes: ## Add NEW data live: mobile logins + a purchase for CHANGES customers (default 3); DRY_RUN=1 previews, IDS=<id>,<id> picks them
	@./scripts/demo-changes.sh --customers $(CHANGES) $(if $(IDS),--ids $(IDS),) $(if $(DRY_RUN),--dry-run,)
