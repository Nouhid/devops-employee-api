# DevOps Employee API — Portfolio Case Study

## Project overview

**Project:** End-to-End DevSecOps and GitOps Delivery Platform  
**Application:** Python 3.12, FastAPI, Uvicorn  
**Repository:** https://github.com/Nouhid/devops-employee-api  
**Environment:** Ubuntu virtual machine, local Kind Kubernetes cluster

This project demonstrates how to build and operate a repeatable software delivery path for a containerized API. The API is intentionally small; the main engineering focus is the platform around it: automated quality gates, security scanning, immutable container publishing, Kubernetes deployment, GitOps reconciliation, and infrastructure monitoring.

> Scope clarification: this is a FastAPI demonstration API with status, health, and version endpoints. It is not a database-backed employee CRUD application.

## Architecture at a glance

The platform is split into five cooperating layers:

1. **Source control:** GitHub hosts application source, tests, CI workflow, Kubernetes manifests, and Argo CD configuration.
2. **Continuous integration and security:** GitHub Actions runs linting, tests and coverage enforcement, secret scanning, filesystem scanning, dependency auditing, and SonarQube Cloud analysis.
3. **Container delivery:** Docker Buildx builds the image; Trivy scans it; successful main-branch runs publish commit-SHA and latest tags to Docker Hub.
4. **Runtime and GitOps:** Argo CD watches the main branch and the `k8s/` directory. It reconciles Kubernetes desired state in a local Kind cluster. Kubernetes Services and NGINX Ingress route requests to FastAPI pods; an HPA is configured for CPU-based scaling.
5. **Observability:** Prometheus collects Kubernetes object and node telemetry from kube-state-metrics and node-exporter. Grafana provides dashboards for exploring that telemetry.

See [the architecture diagram and detailed flow](architecture.md).

## Implemented capabilities

### CI/CD and DevSecOps

- GitHub Actions workflow for pull requests to `main` and pushes to `main`.
- Ruff linting and pytest test execution.
- CI coverage threshold of at least 80%.
- Gitleaks secret detection.
- Trivy filesystem and container-image scans for HIGH and CRITICAL findings, with the configured ignore-unfixed behavior.
- pip-audit against a hash-locked dependency file.
- SonarQube Cloud static analysis and coverage import.
- Docker Buildx image build and Docker Hub publication after the required validation and security jobs succeed.
- Commit-SHA image tags to support traceable releases.

### Kubernetes and GitOps

- Local Kubernetes cluster provisioned with Kind.
- Kubernetes Deployment with two initial replicas.
- ClusterIP/NodePort service exposure and NGINX Ingress routing.
- CPU-based HPA configured for a minimum of two and maximum of five replicas.
- ConfigMap for non-sensitive configuration and a Kubernetes Secret reference for sensitive values.
- Readiness and liveness probes using the API health endpoint.
- CPU and memory requests and limits.
- Argo CD Application tracking `main` and `k8s/`, with automated sync, pruning, and self-healing.

### Container and workload hardening

- Multi-stage Docker build.
- Dedicated non-root application identity (UID/GID 10001).
- Kubernetes `runAsNonRoot` and RuntimeDefault seccomp profile.
- Read-only root filesystem.
- Privilege escalation disabled.
- All Linux capabilities dropped.

### Monitoring

- Prometheus and Grafana deployed through Helm.
- kube-state-metrics and node-exporter enabled for Kubernetes and node telemetry.
- Three-day Prometheus retention in the lab configuration.

The application does not currently expose a Prometheus `/metrics` endpoint. Therefore, this project does not claim application request-rate, latency, or error-rate dashboards. Prometheus persistence is disabled in the lab configuration.

## Release and deployment flow

1. A change is committed and proposed through a pull request.
2. GitHub Actions runs the quality and security checks.
3. On a successful push to `main`, the Docker image is built, scanned, and published with a commit-SHA tag.
4. To promote a release, the Kubernetes Deployment manifest is updated to the selected immutable image tag and committed to `main`.
5. Argo CD detects the manifest change and reconciles the cluster to the desired state.
6. Kubernetes schedules the pods and routes traffic through the configured Service and Ingress.
7. Prometheus and Grafana provide cluster and node-level visibility.

**Important implementation detail:** image publishing and deployment promotion are separate steps. The current workflow publishes images; it does not automatically rewrite the Kubernetes manifest with a newly published image tag. The manifest change is the GitOps promotion trigger.

## Security and reliability decisions

| Decision | Reason |
|---|---|
| Hash-pinned Python dependencies | Make dependency installation reproducible and verifiable |
| CI quality and security gates | Prevent publishing when required validation jobs fail |
| Immutable commit-SHA image tags | Tie a deployed image to a specific source revision |
| Non-root container execution | Reduce privileges available to the application process |
| Read-only filesystem and dropped capabilities | Reduce the container's writable surface and Linux privileges |
| Readiness/liveness probes | Give Kubernetes signals for traffic readiness and process health |
| Resource requests and limits | Declare workload resource expectations and boundaries |
| GitOps reconciliation | Keep the desired Kubernetes state in version control |
| Secrets kept outside Git | Avoid committing sensitive values into the repository |

## Demonstrated outcomes

The following outcomes were observed during the project implementation:

- The latest recorded post-merge GitHub Actions run completed all six jobs successfully: application build/test, Gitleaks, Trivy filesystem scan, pip-audit, SonarQube Cloud analysis, and Docker build/scan/push.
- Argo CD reported the application as **Synced** and **Healthy**, tracking the repository's `main` branch and `k8s/` path.
- The Kubernetes Deployment reported two of two replicas ready; both application pods were running with zero restarts at the time of the reported check.
- Live requests to `/`, `/health`, and `/version` returned HTTP 200.
- The repository's generated coverage report was added to `.gitignore`; the main branch was confirmed clean after synchronization.

These are implementation-time observations, not a claim of production availability or a formal load/performance test.

## Current scope and future improvements

The current project is a local learning and portfolio environment. It is not presented as a production deployment.

Potential next iterations:

- Add application-level Prometheus instrumentation and request metrics.
- Add alert rules and an alert-routing workflow.
- Introduce persistent monitoring storage and backup/retention planning.
- Integrate an automated, reviewed image-promotion mechanism while preserving immutable tags.
- Move the runtime to a managed Kubernetes platform and adopt production-grade secret management.
- Add deployment/load testing and documented recovery exercises.

AWS, Terraform, a database, and a managed production cluster are not part of the current implementation.

## Resume-ready project description

**DevSecOps & GitOps Platform for a Containerized FastAPI Service**

- Built a GitHub Actions CI/CD pipeline integrating Ruff, pytest coverage enforcement, Gitleaks, Trivy, pip-audit, and SonarQube Cloud.
- Containerized a Python FastAPI service using a multi-stage Docker build and published scanned, commit-tagged images to Docker Hub.
- Deployed the service to a local Kind Kubernetes cluster using hardened manifests, readiness/liveness probes, resource controls, Service, Ingress, and HPA configuration.
- Implemented GitOps delivery with Argo CD auto-sync, pruning, and self-healing, using Git-managed Kubernetes manifests and immutable image tags.
- Deployed Prometheus and Grafana with kube-state-metrics and node-exporter for Kubernetes and node-level observability.

## Short portfolio introduction

I built an end-to-end DevSecOps and GitOps platform around a small FastAPI service. The project demonstrates automated testing and security gates, Docker image delivery, Kubernetes deployment, Argo CD reconciliation, and Prometheus/Grafana monitoring. The emphasis is on reproducible delivery, container hardening, infrastructure visibility, and clear documentation of what is implemented versus what remains a future improvement.

## Project links

- **Source code:** https://github.com/Nouhid/devops-employee-api
- **Architecture:** https://github.com/Nouhid/devops-employee-api/blob/main/docs/architecture.md
- **CI/CD runs:** https://github.com/Nouhid/devops-employee-api/actions
- **Container image:** https://hub.docker.com/r/nouhid28/devops-employee-api
- **SonarQube Cloud:** https://sonarcloud.io/project/overview?id=Nouhid_devops-employee-api
