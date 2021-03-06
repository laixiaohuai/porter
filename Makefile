
# Image URL to use all building/pushing image targets
IMG_MANAGER ?= kubespheredev/porter:v0.3-dev
IMG_AGENT ?= kubespheredev/porter-agent:v0.3-dev
NAMESPACE ?= porter-system

CRD_OPTIONS ?= "crd:trivialVersions=true"

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: manager

# Run tests
test: fmt vet
	go test -v  ./api/... ./controllers/... ./pkg/...  -coverprofile cover.out

# Build manager binary
manager: fmt vet
	go build -o bin/manager github.com/kubesphere/porter/cmd/manager

# Install CRDs into a cluster
install: manifests
	kubectl apply -f config/crd/bases

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests
	kubectl apply -f config/crd/bases
	kustomize build config/default | kubectl apply -f -

# Generate code
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./api/...

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./api/..." paths="./controllers/..." output:crd:artifacts:config=config/crd/bases
# Run go fmt against code
fmt:
	go fmt ./pkg/... ./cmd/...   ./api/... ./controllers/...

# Run go vet against code
vet:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go vet ./pkg/... ./cmd/...  ./controllers/...


controller-gen:
ifeq (, $(shell which controller-gen))
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.2.0
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

clean-up:
	./hack/cleanup.sh

release:
	export DOCKER_CLI_EXPERIMENTAL=enabled
	GOOS=linux GOARCH=amd64 go build -o bin/manager-linux-amd64 github.com/kubesphere/porter/cmd/manager
	GOOS=linux GOARCH=amd64 go build -o bin/agent-linux-amd64 github.com/kubesphere/porter/cmd/agent
	GOOS=linux GOARCH=arm64 go build -o bin/manager-linux-arm64 github.com/kubesphere/porter/cmd/manager
	GOOS=linux GOARCH=arm64 go build -o bin/agent-linux-arm64 github.com/kubesphere/porter/cmd/agent
	docker buildx build --platform linux/amd64,linux/arm64 -t ${IMG_AGENT} -f ./cmd/agent/Dockerfile .  --push
	docker buildx build --platform linux/amd64,linux/arm64 -t ${IMG_MANAGER} -f ./cmd/manager/Dockerfile .  --push

ifeq ($(uname), Darwin)
	sed -i '' -e 's@image: .*@image: '"${IMG_AGENT}"'@' ./config/release/agent_image_patch.yaml
	sed -i '' -e 's@image: .*@image: '"${IMG_MANAGER}"'@' ./config/release/manager_image_patch.yaml	
else
	sed -i -e 's@image: .*@image: '"${IMG_AGENT}"'@' ./config/release/agent_image_patch.yaml
	sed -i -e 's@image: .*@image: '"${IMG_MANAGER}"'@' ./config/release/manager_image_patch.yaml
endif
	kustomize build config/release -o deploy/porter.yaml
	@echo "Done, the yaml is in deploy folder named 'porter.yaml'"

install-travis:
	chmod +x ./hack/*.sh
	./hack/install_tools.sh
