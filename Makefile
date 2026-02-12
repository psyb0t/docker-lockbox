# Docker image configuration
IMAGE_NAME := psyb0t/lockbox
TAG := latest
TEST_TAG := $(TAG)-test

.PHONY: build build-test test clean help

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

# Clean up images
clean:
	docker rmi $(IMAGE_NAME):$(TAG) || true
	docker rmi $(IMAGE_NAME):$(TEST_TAG) || true

# Show available targets
help:
	@echo "Available targets:"
	@echo "  build      - Build the main Docker image"
	@echo "  build-test - Build the test Docker image with -test suffix"
	@echo "  test       - Build test image and run integration tests"
	@echo "  clean      - Remove built images"
