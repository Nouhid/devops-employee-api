# DevOps Employee API — End-to-End DevSecOps & GitOps Platform

[![DevSecOps CI Pipeline](https://github.com/Nouhid/devops-employee-api/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Nouhid/devops-employee-api/actions/workflows/ci.yml)
[![Docker Image](https://img.shields.io/docker/v/nouhid28/devops-employee-api?label=Docker%20Hub)](https://hub.docker.com/r/nouhid28/devops-employee-api)

A hands-on DevOps portfolio project that takes a small Python API through automated testing, containerization, security analysis, image publishing, Kubernetes deployment, GitOps reconciliation, and monitoring.

The application is intentionally small so the engineering work is centered on the delivery platform and operational practices.

> Scope: this repository contains a FastAPI demonstration service with health and version endpoints. It is not a database-backed employee CRUD system.

## Technology stack

| Area | Technology |
|---|---|
| Application | Python 3.12, FastAPI, Uvicorn |
| Code quality and tests | Ruff, pytest, pytest-cov |
| CI/CD | GitHub Actions |
| Containerization | Multi-stage Docker build |
| Registry | Docker Hub |
| Security | Gitleaks, Trivy, pip-audit, SonarQube Cloud |
| Orchestration | Kubernetes on a local Kind cluster |
| GitOps | Argo CD |
| Traffic and scaling | NGINX Ingress, Kubernetes Service, HPA |
| Monitoring | Prometheus, Grafana, kube-state-metrics, node-exporter |

## Platform architecture

The platform is organized into source control, CI and security validation, image delivery, Kubernetes/GitOps deployment, and monitoring layers.

See [docs/architecture.md](docs/architecture.md) for the architecture diagram, request path, delivery sequence, security controls, and implementation boundaries.

## CI/CD and DevSecOps pipeline

The GitHub Actions workflow runs on pull requests targeting main and on pushes to main.

| Stage | Tool | Purpose |
|---|---|---|
| Lint | Ruff | Enforce Python code quality |
| Test | pytest + pytest-cov | Run automated tests; CI enforces at least 80% coverage |
| Secret detection | Gitleaks | Detect accidentally committed credentials |
| Filesystem scan | Trivy | Scan repository dependencies and configuration for HIGH/CRITICAL findings |
| Dependency audit | pip-audit | Audit hash-locked Python dependencies for known vulnerabilities |
| Code analysis | SonarQube Cloud | Analyze maintainability, reliability, security, and coverage |
| Image build | Docker Buildx | Build the application image |
| Image scan | Trivy | Scan the built image before publishing |
| Image publish | Docker Hub | Publish commit-SHA and latest tags on pushes to main |

The Docker publishing job depends on the validation and security jobs, so a failed required stage prevents image publishing.

## Kubernetes and GitOps

The Kubernetes resources are stored in the k8s directory:

- Deployment: two initial replicas, readiness/liveness probes, resource requests and limits.
- Service: NodePort on port 30080 for the local Kind lab.
- Ingress: NGINX Ingress rule for employee-api.local.
- HPA: CPU-based autoscaling from two to five replicas, targeting 50% average CPU utilization.
- ConfigMap: non-sensitive application configuration.
- Secret reference: the Deployment expects employee-api-secret in the namespace; secret values are not stored in Git.

The Argo CD Application is defined in argocd/employee-api-application.yaml. It tracks the main branch and k8s directory, with automated sync, pruning, and self-healing enabled.

Release promotion uses immutable image tags: the Deployment manifest's image reference is updated to the selected commit-SHA tag in Git, and Argo CD reconciles the desired state from main. This keeps each release reviewable and version-controlled.

## Monitoring

Prometheus and Grafana are deployed in the monitoring namespace. The supplied Helm values enable kube-state-metrics and node-exporter and configure a three-day Prometheus retention window.

The current monitoring setup focuses on Kubernetes object and node-level telemetry. The FastAPI service does not currently expose a Prometheus /metrics endpoint, so application-level request metrics are not claimed.

Persistence is disabled in the supplied lab values; monitoring history is disposable when the lab is recreated.

## Application API

| Method | Endpoint | Purpose |
|---|---|---|
| GET | / | Application welcome/status response |
| GET | /health | Health check used by Kubernetes probes |
| GET | /version | Return the configured application version |
| GET | /docs | Interactive OpenAPI documentation |

## Run locally

Create and activate a virtual environment:

```bash
python3.12 -m venv .venv
source .venv/bin/activate
```

Install hash-locked dependencies:

```bash
python -m pip install --require-hashes -r requirements.lock
```

Start the API:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

Open http://localhost:8000/docs to explore the API.

Run quality checks:

```bash
ruff check main.py tests/
pytest -v --cov=main --cov-report=term-missing --cov-fail-under=80
```

## Build and run the container

```bash
docker build -t devops-employee-api:local .
docker run --rm -p 8000:8000 devops-employee-api:local
```

The runtime image uses a dedicated non-root user (UID 10001), and the application file is read-only. The Kubernetes Deployment additionally enforces a non-root security context, a read-only root filesystem, disabled privilege escalation, dropped Linux capabilities, and the RuntimeDefault seccomp profile.

## Repository layout

```text
.
├── .github/workflows/ci.yml       # CI and DevSecOps pipeline
├── argocd/                        # Argo CD Application
├── docs/architecture.md           # Architecture and delivery flow
├── k8s/                           # Kubernetes manifests
├── tests/                         # Automated API tests
├── Dockerfile                     # Multi-stage container build
├── compose.yaml                   # Local Compose configuration
├── main.py                        # FastAPI application
├── requirements.lock              # Hash-pinned dependency lock
├── requirements-dev.txt           # Development dependency inputs
├── prometheus-values.yaml         # Prometheus Helm values
└── grafana-values.yaml            # Grafana Helm values
```

## Engineering decisions and current boundaries

- The API is deliberately small so the project demonstrates platform engineering rather than business-domain complexity.
- Kubernetes runs in a local Kind lab, not a managed production cluster.
- The supplied monitoring configuration is lab-oriented and does not provide persistent metrics storage.
- Application-level Prometheus instrumentation, alert routing, and production-grade secret management are future extensions, not implemented features.
- The repository should not contain real credentials. Configure GitHub Actions secrets and Kubernetes Secrets outside version control.
- AWS and Terraform are outside this project's current scope.

## Project links

- [Source repository](https://github.com/Nouhid/devops-employee-api)
- [GitHub Actions](https://github.com/Nouhid/devops-employee-api/actions)
- [Docker Hub image](https://hub.docker.com/r/nouhid28/devops-employee-api)
- [SonarQube Cloud project](https://sonarcloud.io/project/overview?id=Nouhid_devops-employee-api)

---
Built as a practical DevOps learning and portfolio project.
