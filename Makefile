# Docker image configuration
IMAGE_NAME := psyb0t/lockbox
TAG := latest
TEST_TAG := $(TAG)-test

# Lint tools run from pinned images, so the host needs only Docker and Make.
SHELLCHECK_IMAGE ?= koalaman/shellcheck:v0.11.0
PYTHON_IMAGE ?= python:3.12-slim
FLAKE8_VERSION ?= 7.3.0
SHELL_SOURCES := entrypoint.sh create_installer.sh test.sh
# black's line length, so flake8 and the formatter agree.
FLAKE8_MAX_LINE ?= 88

# GitHub Pages build image, pinned by digest.
JEKYLL_IMAGE ?= ghcr.io/actions/jekyll-build-pages:v1.0.13@sha256:6791ebfd912185ed59bfb5fb102664fa872496b79f87ff8b9cfba292a7345041
DOCS_SITE ?= .testing/docs-site

.PHONY: all build build-test test lint lint-shell lint-python docs clean help

# Default target
all: build

# Build the main image
build:
	docker build -t $(IMAGE_NAME):$(TAG) .

# Build the test image with -test suffix
build-test:
	docker build -t $(IMAGE_NAME):$(TEST_TAG) .

# Run integration tests
test: build-test
	./test.sh

# Run every linter
lint: lint-shell lint-python

# shellcheck on the shell scripts
lint-shell:
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt $(SHELLCHECK_IMAGE) $(SHELL_SOURCES)

# flake8 on lockbox-wrapper
lint-python:
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt $(PYTHON_IMAGE) sh -ec '\
		pip install --quiet --disable-pip-version-check --root-user-action=ignore flake8==$(FLAKE8_VERSION); \
		flake8 --max-line-length=$(FLAKE8_MAX_LINE) lockbox-wrapper'

# Build docs/ with the image GitHub Pages uses into a gitignored directory
docs:
	@mkdir -p "$(DOCS_SITE)"
	docker run --rm \
		--user "$$(id -u):$$(id -g)" \
		-e HOME=/tmp \
		-e GITHUB_WORKSPACE=/work \
		-e GITHUB_REPOSITORY=psyb0t/docker-lockbox \
		-e INPUT_SOURCE=docs \
		-e INPUT_DESTINATION="$(DOCS_SITE)" \
		-e INPUT_VERBOSE=false \
		-v "$(CURDIR):/work" \
		$(JEKYLL_IMAGE)

# Clean up images
clean:
	docker rmi $(IMAGE_NAME):$(TAG) || true
	docker rmi $(IMAGE_NAME):$(TEST_TAG) || true

# Show available targets
help:
	@echo "Available targets:"
	@echo "  build       - Build the main Docker image"
	@echo "  build-test  - Build the test Docker image with -test suffix"
	@echo "  test        - Build test image and run integration tests"
	@echo "  lint        - Run shellcheck and flake8 in containers"
	@echo "  lint-shell  - Run shellcheck on the shell scripts"
	@echo "  lint-python - Run flake8 on lockbox-wrapper"
	@echo "  docs        - Build the documentation site into $(DOCS_SITE)"
	@echo "  clean       - Remove built images"
