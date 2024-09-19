PACKAGE_DIR=package/package
ARTIFACT_NAME=package.zip
ARTIFACT_PATH=package/$(ARTIFACT_NAME)
ifdef AWS_ROLE
	ASSUME_REQUIRED?=assumeRole
endif
ifdef GO_PIPELINE_NAME
	ENV_RM_REQUIRED?=rm_env
else
	USER_SETTINGS=--user $(shell id -u):$(shell id -g)
endif


################
# Entry Points #
################
deps: .env
	docker compose run $(USER_SETTINGS) --rm serverless make _deps

build: .env
	docker compose run $(USER_SETTINGS) --rm virtualenv make _build

deploy: $(ENV_RM_REQUIRED) .env $(ASSUME_REQUIRED)
	docker compose run $(USER_SETTINGS) --rm serverless make _deploy

unitTest: $(ASSUME_REQUIRED) .env
	docker compose run $(USER_SETTINGS) --rm lambda slack_cloudfront_bot.unit_test

smokeTest: .env $(ASSUME_REQUIRED)
	docker compose run $(USER_SETTINGS) --rm serverless make _smokeTest

remove: .env
	docker compose run $(USER_SETTINGS) --rm serverless make _deps _remove

unzip: .env $(ARTIFACT_PATH)
	docker compose run $(USER_SETTINGS) --rm virtualenv make _unzip

styleTest: .env
	docker compose run $(USER_SETTINGS) --rm virtualenv make _unzip
	docker compose run $(USER_SETTINGS) --rm pep8 --ignore 'E501,E128' *.py

run: .env
	docker compose run $(USER_SETTINGS) --rm lambda lambda.invalidate
.PHONY: run

assumeRole: .env
	docker run --rm -e "AWS_ACCOUNT_ID" -e "AWS_ROLE" amaysim/aws:1.1.3 assume-role.sh >> .env

test: .env styleTest unitTest

shell: .env
	docker compose run $(USER_SETTINGS) --rm virtualenv sh

##########
# Others #
##########

# Removes the .env file before each deploy to force regeneration without cleaning the whole environment
rm_env:
	rm -f .env
.PHONY: rm_env

# Create .env based on .env.template if .env does not exist
.env:
	@echo "Create .env with .env.template"
	cp .env.template .env

$(PACKAGE_DIR)/.piprun: requirements.txt
	pip install -r requirements.txt -t $(PACKAGE_DIR)
	@touch "$(PACKAGE_DIR)/.piprun"

_build: $(ARTIFACT_PATH)

$(ARTIFACT_PATH): .env *.py $(PACKAGE_DIR)/.piprun
	cp *.py $(PACKAGE_DIR)
	cd $(PACKAGE_DIR) && zip -rq ../package .

run/lambda.py: $(ARTIFACT_PATH)
	mkdir -p run/
	cd run && unzip -qo -d . ../$(ARTIFACT_PATH)
	@touch run/lambda.py

_unzip: run/lambda.py

run/.lastrun: $(ARTIFACT_PATH)
	cd run && ./lambda.py
	@touch run/.lastrun

_run: run/.lastrun docker compose.yml Makefile

# Install node_modules for serverless plugins
_deps: node_modules.zip

node_modules.zip:
	yarn install --no-bin-links
	zip -rq node_modules.zip node_modules/

_deploy: $(ARTIFACT_PATH) node_modules.zip
	mkdir -p node_modules
	unzip -qo -d . node_modules.zip
	rm -fr .serverless
	sls deploy -v

_remove:
	sls remove -v
	rm -fr .serverless

_clean:
	rm -fr node_modules.zip node_modules .serverless package .requirements venv/ run/ __pycache__/
.PHONY: _deploy _remove _clean
