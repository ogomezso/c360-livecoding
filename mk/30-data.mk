##@ Data
.PHONY: data

CUSTOMERS    ?= 200
TRANSACTIONS ?= 1000
INTERACTIONS ?= 800

data: ## Produce synthetic Spanish banking data to the source topics (CUSTOMERS= TRANSACTIONS= INTERACTIONS=)
	@ASSUME_YES=1 ./scripts/generate-data.sh $(CUSTOMERS) $(TRANSACTIONS) $(INTERACTIONS)
