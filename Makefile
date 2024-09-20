PACKAGE_DIR=package/package
ARTIFACT_NAME=package.zip
ARTIFACT_PATH=package/$(ARTIFACT_NAME)
ifdef AWS_ROLE
	ASSUME_REQUIRED?=assumeRole
endif
ifdef GO_PIPELINE_NAME
	ENV_RM_REQUIRED?=rm_env
endif


################
# Entry Points #
################
deps: .env
	docker compose run --rm serverless make _deps

build: .env _pullPythonLambda
	docker compose run --rm virtualenv make _build

deploy: $(ENV_RM_REQUIRED) .env $(ASSUME_REQUIRED)
	docker compose run --rm serverless make _deploy

unitTest: $(ASSUME_REQUIRED) .env _pullPythonLambda
	docker compose up --wait --detach lambda-test
	docker compose run --rm virtualenv curl -f -s "http://lambda-test:8080/2015-03-31/functions/function/invocations" -d '{}' -v
	if [[ "$$?" -eq "0" ]]; then echo "Pass" && docker compose down; else echo "Fail" && docker compose down && false; fi

smokeTest: .env $(ASSUME_REQUIRED)
	docker compose run --rm serverless make _smokeTest

remove: .env
	docker compose run --rm serverless make _deps _remove

unzip: .env $(ARTIFACT_PATH) _pullPythonLambda
	docker compose run --rm virtualenv make _unzip

styleTest: .env _pullPythonLambda
	docker compose run --rm virtualenv make _unzip
	docker compose run --rm pep8 --ignore 'E501,E128' *.py

run: .env
	docker compose run --rm lambda lambda.invalidate
.PHONY: run

assumeRole: .env
	docker run --rm -e "AWS_ACCOUNT_ID" -e "AWS_ROLE" amaysim/aws:1.1.3 assume-role.sh >> .env

test: .env styleTest unitTest

shell: .env _pullPythonLambda
	docker compose run  --rm virtualenv sh

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
	docker rmi -f serverless-slack-cloudfront-bot-virtualenv:latest
.PHONY: _deploy _remove _clean

_dockerLoginPublicECR:
	aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
.PHONY: _dockerLoginPublicECR

_pullPythonLambda: _dockerLoginPublicECR
	docker pull public.ecr.aws/lambda/python:3.11
.PHONY: _pullPythonLambda