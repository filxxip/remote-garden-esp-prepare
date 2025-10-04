IMAGE_NAME ?= esp-wrapper
REGISTRY ?= ghcr.io
REGISTRY_USER ?= filxxip
IMAGE_TAG ?= latest
FULL_IMAGE_NAME = $(REGISTRY)/$(REGISTRY_USER)/$(IMAGE_NAME):$(IMAGE_TAG)

ifneq (,$(wildcard .env))
    include .env
    export
endif

.PHONY: help build push deploy run clean

help:
	@echo "Docker Image Build & Deploy"
	@echo ""
	@echo "Available targets:"
	@echo "  build        - Build Docker image locally"
	@echo "  push         - Push image to registry"
	@echo "  deploy       - Build and push image (build + push)"
	@echo "  run          - Run container locally"
	@echo "  clean        - Remove local image"
	@echo ""
	@echo "Configuration:"
	@echo "  IMAGE_NAME:   $(IMAGE_NAME)"
	@echo "  REGISTRY:     $(REGISTRY)"
	@echo "  REGISTRY_USER: $(REGISTRY_USER)"
	@echo "  IMAGE_TAG:    $(IMAGE_TAG)"
	@echo "  Full name:    $(FULL_IMAGE_NAME)"
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  make push"
	@echo "  make deploy"
	@echo "  make deploy IMAGE_TAG=v1.0.0"
	@echo "  make run PORT=/dev/ttyUSB0 TOKEN=mytoken"

build:
	@echo "Building Docker image..."
	@echo "Image: $(FULL_IMAGE_NAME)"
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .
	docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(FULL_IMAGE_NAME)
	@echo "Build complete: $(FULL_IMAGE_NAME)"

push: 
	@echo "Pushing image to registry..."
	@echo "Image: $(FULL_IMAGE_NAME)"
	docker push $(FULL_IMAGE_NAME)
	@echo "Push complete: $(FULL_IMAGE_NAME)"

deploy: build push
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Deployment complete!"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "Image pushed to: $(FULL_IMAGE_NAME)"
	@echo ""
	@echo "To use this image, update your .env:"
	@echo "  DOCKER_IMAGE_URL=$(FULL_IMAGE_NAME)"
	@echo ""
	@echo "Pull and run:"
	@echo "  docker pull $(FULL_IMAGE_NAME)"
	@echo "  docker run --rm -it $(FULL_IMAGE_NAME)"

run:
	@echo "Running container locally..."
	@bash -c '\
		PORT_ARG=""; \
		TOKEN_ARG=""; \
		if [ -n "$(PORT)" ]; then \
			PORT_ARG="--device=$(PORT):$(PORT) -e PORT=$(PORT)"; \
		fi; \
		if [ -n "$(TOKEN)" ]; then \
			TOKEN_ARG="-e TOKEN=$(TOKEN)"; \
		fi; \
		docker run --rm -it \
			--privileged \
			-v docker-storage:/var/lib/docker \
			$$PORT_ARG \
			$$TOKEN_ARG \
			$(IMAGE_NAME):$(IMAGE_TAG); \
	'

clean:
	@echo "Removing local Docker image..."
	docker rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	docker rmi $(FULL_IMAGE_NAME) 2>/dev/null || true
	@echo "Cleanup complete"
