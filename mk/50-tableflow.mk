##@ Tableflow (Kafka topic -> Iceberg/Delta in your S3 bucket)
.PHONY: tableflow-up tableflow-status tableflow-enable tableflow-disable tableflow-destroy

TOPIC  ?= $(SNAPSHOT_TOPIC)
FORMAT ?= ICEBERG

tableflow-up: ## Deploy S3 bucket + IAM role + provider integration (non-interactive, handles both phases)
	@./scripts/tableflow.sh up

tableflow-status: ## AWS-side state, trust policy, and topics with Tableflow enabled
	@./scripts/tableflow.sh status

tableflow-enable: ## Enable Tableflow on TOPIC (default c360_snapshot) as FORMAT=ICEBERG|DELTA
	@./scripts/tableflow.sh enable $(TOPIC) $(FORMAT)

tableflow-disable: ## Disable Tableflow on TOPIC
	@./scripts/tableflow.sh disable $(TOPIC)

tableflow-destroy: ## Destroy only the Tableflow AWS infrastructure (asks you to type 'yes')
	@$(MAKE) --no-print-directory -C $(TF_TF) destroy
