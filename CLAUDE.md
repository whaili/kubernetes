# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

### Building Kubernetes

**Basic build (Linux binaries):**
```bash
make
```

**Build specific components:**
```bash
make WHAT=cmd/kubectl
make WHAT=cmd/kubelet
```

**Build with debug symbols (for debugging with tools like delve):**
```bash
make DBG=1
```

**Cross-compile for all platforms:**
```bash
make cross
```

**Quick release (in Docker container):**
```bash
make quick-release
```

**Using containerized build environment:**
```bash
build/run.sh make                    # Build Linux binaries
build/run.sh make cross              # Build all platforms
build/run.sh make kubectl KUBE_BUILD_PLATFORMS=darwin/amd64  # Build specific binary/platform
```

Build artifacts are output to `_output/` directory.

### Testing

**Run unit tests:**
```bash
make test
# Or for specific packages:
make test WHAT=./pkg/kubelet
make test WHAT=./pkg/scheduler GOFLAGS=-v
```

**Run integration tests:**
```bash
make test-integration
# Or with containerized build:
build/run.sh make test-integration
```

**Run CLI tests:**
```bash
make test-cmd
build/run.sh make test-cmd
```

**Run specific test:**
Use the standard Go test syntax with the test script:
```bash
hack/make-rules/test.sh ./pkg/scheduler -run TestSpecificTest
```

**Run tests with coverage:**
```bash
KUBE_COVER=y make test
```

**Run tests without race detector:**
```bash
KUBE_RACE="" make test
```

Note: Unit tests exclude e2e, e2e_node, e2e_kubeadm, and integration tests by default.

### Verification and Updates

**Run all verification checks (required before submitting PRs):**
```bash
make verify
# or
hack/verify-all.sh
```

**Run quick verification (skips slow checks):**
```bash
make quick-verify
```

**Update generated code and vendored dependencies:**
```bash
make update
# or
hack/update-all.sh
```

**Update vendored dependencies:**
```bash
hack/update-vendor.sh
```

### Cleaning

**Clean build artifacts:**
```bash
make clean
# or with containerized build:
build/make-clean.sh
```

### Ginkgo (E2E test framework)

**Build ginkgo:**
```bash
make ginkgo
```

### Repository Structure

- **`cmd/`**: Main entry points for Kubernetes binaries (kube-apiserver, kube-controller-manager, kube-scheduler, kubelet, kubectl, kube-proxy, kubeadm, etc.)
- **`pkg/`**: Core implementation packages
  - `pkg/api/`: API-related utilities
  - `pkg/apis/`: Internal API types and validation
  - `pkg/controller/`: Controller implementations (deployment, replicaset, daemonset, job, cronjob, etc.)
  - `pkg/kubelet/`: Kubelet implementation
  - `pkg/scheduler/`: Scheduler implementation
  - `pkg/proxy/`: kube-proxy implementation
  - `pkg/kubectl/`: kubectl command implementation
  - `pkg/registry/`: API object storage/registry logic
- **`staging/src/k8s.io/`**: Staged external repositories that are published independently (client-go, api, apimachinery, apiserver, kubectl, etc.)
- **`vendor/`**: Vendored dependencies
- **`hack/`**: Build, test, and development scripts
- **`test/`**: Test code
  - `test/e2e/`: End-to-end tests
  - `test/e2e_node/`: Node e2e tests
  - `test/integration/`: Integration tests
- **`api/`**: OpenAPI specs and API discovery
- **`build/`**: Build configuration and Docker-based build scripts
- **`cluster/`**: Cluster deployment scripts

### Go Workspace and Modules

Kubernetes uses a Go workspace (`go.work`) with multiple modules. The main module is at the root, and staged repositories under `staging/src/k8s.io/` are separate modules that are published independently but developed in-tree.

When importing packages from staged repos (e.g., `k8s.io/client-go`), the Go workspace automatically resolves them to `staging/src/k8s.io/client-go/`.

### Staging Repositories

Code in `staging/src/k8s.io/` is authoritative and periodically published to separate repositories. These include:
- `k8s.io/api` - API types
- `k8s.io/apimachinery` - API machinery (meta, runtime, etc.)
- `k8s.io/client-go` - Client libraries
- `k8s.io/apiserver` - API server library
- `k8s.io/kubectl` - kubectl implementation
- And many others (see staging/README.md)

### Key Concepts

**Controllers**: Follow the controller pattern - watch resources, compare desired vs actual state, take action. Most controllers are in `pkg/controller/` and registered in `cmd/kube-controller-manager/`.

**API Server**: The central component exposing the Kubernetes API. Implementation is in `pkg/kubeapiserver/` and `staging/src/k8s.io/apiserver/`.

**Kubelet**: The node agent that manages containers. Implementation is in `pkg/kubelet/` with many subsystems (pod management, container runtime interface, volume plugins, etc.).

**Scheduler**: Assigns pods to nodes. Implementation is in `pkg/scheduler/` with a plugin architecture for scheduling algorithms.

**kubectl**: The CLI client. Command implementations are in `pkg/kubectl/` and `staging/src/k8s.io/kubectl/`.

## Development Environment

**Go version:** 1.24.7 (see `.go-version`)

**Build environment:** Can build locally with Go or use containerized build with Docker (recommended for consistency).

## Important Scripts

- `hack/make-rules/build.sh`: Build binaries
- `hack/make-rules/test.sh`: Run unit tests
- `hack/make-rules/test-integration.sh`: Run integration tests
- `hack/make-rules/verify.sh`: Run verification checks
- `hack/make-rules/update.sh`: Update generated code
- `build/run.sh`: Run commands in build container
- `build/shell.sh`: Drop into bash shell in build container

## Testing Notes

- Tests use Ginkgo/Gomega for e2e tests and standard Go testing for unit tests
- Integration tests typically require etcd and start a local API server
- Cache mutation detector is enabled by default (`KUBE_CACHE_MUTATION_DETECTOR=true`)
- Default test timeout is 180s per package
- Race detector is enabled by default for tests

## Submitting Changes

Before submitting a PR:
1. Run `make verify` to ensure all checks pass
2. If verification fails, run `make update` to fix generated code
3. Ensure tests pass with `make test`
4. Sign the Contributor License Agreement (CLA)

All scripts must be run from the Kubernetes root directory.

## Code Architecture
The detailed project understanding documents are organized into five parts under the `docs/claude/` directory:  
- 01-overview.md – Project Overview (directories, responsibilities, build/run methods, external dependencies, newcomer reading order)  
- 02-entrypoint.md – Program Entry & Startup Flow (entry functions, CLI commands, initialization and startup sequence)  
- 03-callchains.md – Core Call Chains (function call tree, key logic explanations, main sequence diagram)  
- 04-modules.md – Module Dependencies & Data Flow (module relationships, data structures, request/response processing, APIs)  
- 05-architecture.md – System Architecture (overall structure, startup flow, key call chains, module dependencies, external systems, configuration)  
When answering any questions related to source code structure, module relationships, or execution flow, **always refer to these five documents first**, and include file paths and function names for clarity.

## Reply Guidelines
- Always reference **file path + function name** when explaining code.
- Use **Mermaid diagrams** for flows, call chains, and module dependencies.
- If context is missing, ask explicitly which files to `/add`.
- Never hallucinate non-existing functions or files.
- Always reply in **Chinese**

## Excluded Paths
- vendor/
- build/
- dist/
- .git/
- third_party/


## Glossary


## Run Instructions