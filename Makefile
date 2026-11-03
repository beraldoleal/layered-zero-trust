.PHONY: default
default: help

.PHONY: help
##@ Pattern tasks

# No need to add a comment here as help is described in common/
help:
	@make -f common/Makefile MAKEFILE_LIST="Makefile common/Makefile" help

%:
	make -f common/Makefile $*

.PHONY: install
install: operator-deploy post-install ## installs the pattern and loads the secrets
	@echo "Installed"

.PHONY: post-install
post-install: ## Post-install tasks
	make vault-init
	make vault-config-jwt
	make load-secrets
	@echo "Done"

.PHONY: vault-init
vault-init: ## Initialize and unseal Vault (must run before vault-config-jwt and load-secrets)
	common/scripts/vault-utils.sh vault_init $(NAME)

.PHONY: test
test:
	@make -f common/Makefile PATTERN_OPTS="-f values-global.yaml -f values-hub.yaml" test
