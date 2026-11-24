# DevOps Employee API — Troubleshooting & Revision Playbook

> A chronological, practical record of the troubleshooting work carried out while building `Nouhid/devops-employee-api`. It is organized by the order a DevOps engineer should investigate a failure: establish the symptom, collect evidence, isolate the failing layer, make the smallest safe change, validate it, and record the result.
>
> **Evidence note:** This guide reconstructs the incidents available from the project conversations and recorded terminal outputs. Where an exact original command, error text, or final root cause was not preserved, it is explicitly marked as a diagnostic pattern or a detail not recoverable from the chat history. Do not treat an illustrative command as proof that it was the exact command originally run.

## 1. The troubleshooting workflow used throughout the project

Use this sequence before changing anything:

1. **Define the failure precisely.** Record the command, full error, timestamp, namespace, branch, commit, image tag, and affected resource.
2. **Check the layer above and below.** For example, if a pod is not ready, inspect the pod events and logs, then inspect its Service endpoints and probe configuration.
3. **Read the source of truth.** For GitHub CI, inspect the workflow and job logs. For Kubernetes managed by Argo CD, inspect the Git manifest and the Argo Application revision. For a container, inspect the Dockerfile and image metadata.
4. **Compare desired state with actual state.** Compare Git commit ↔ CI artifact ↔ image tag/digest ↔ Kubernetes manifest ↔ running pod image.
5. **Change one thing at a time.** Prefer a small patch over restarting, deleting, or recreating unrelated resources.
6. **Validate at the same layer that failed.** A successful image build does not prove a pod is ready; a healthy pod does not prove Ingress routing works.
7. **Validate end-to-end once.** Check the actual API path after lower layers are healthy.
8. **Record the resolution.** Include root cause, exact change, proof, and any remaining limitation.

### Fast triage map

| Symptom | First evidence to collect |
|---|---|
| Git push/rebase/merge problem | `git status`, branch, upstream, recent commits, diff |
| CI job failed | Exact failed job and first failing step/log line |
| Docker build fails | Dockerfile line, build context, exact parser/build error |
| Container exits or unhealthy | `docker ps -a`, `docker logs`, inspect health, process/user/port |
| Pod Pending/CrashLoop/ImagePull/NotReady | `kubectl describe pod`, pod logs, events, image and probes |
| Service has no traffic | Service selector ↔ pod labels, EndpointSlices/endpoints, targetPort |
| Ingress does not route | Ingress class/controller, host rule, backend Service, DNS/Host header |
| Argo CD drift or wrong revision | Application repoURL, targetRevision, path, sync revision, Git manifest |
| Sonar quality gate / analysis fails | Sonar job log, scanner parameters, coverage report, dependency install |
| Prometheus target down | Target scrape error, ServiceMonitor/annotations, endpoints, pod/service |
| Grafana panel empty | Datasource health, Prometheus query, time range, target health |

---

## 2. Git and GitHub troubleshooting

### 2.1 Work on the correct branch and preserve a clean working tree

**Why it mattered:** The project used several feature/documentation branches. A local branch could be stale relative to GitHub, and generated test/security reports could appear as untracked files.

**Diagnostic sequence:**

```bash
git status
git branch --show-current
git branch -vv
git fetch origin
git log --oneline --decorate -8
git diff
git diff --cached
```

**How to interpret it:**

- `git status` identifies modified, staged, untracked, or conflicting files.
- `git branch -vv` shows the upstream branch and whether the local branch is ahead/behind.
- `git fetch origin` refreshes remote-tracking refs without changing the working tree.
- Inspect `git diff` before staging or committing. Do not use `git add .` blindly when generated reports or secrets may exist.

**Project lesson:** The local `feat/docker-pipeline` branch was found behind `origin/main` by three commits during the final GitOps review. We did not treat a local branch as authoritative; we compared it with the remote branch.

### 2.2 Feature branch drift and GitOps branch mismatch

**Symptom:** Argo CD showed `Synced` and `Healthy`, but its Application was tracking `feat/docker-pipeline`, while the intended final documentation and release configuration had been merged into `main`.

**Evidence collected:**

- Argo CD source branch: `feat/docker-pipeline`.
- Observed revision began `0b0d3c82...`.
- Feature branch was three commits behind remote `main`.
- The feature-branch deployment used mutable image tag `:v2`.
- The main-branch manifest used an immutable commit-SHA image tag:
  `nouhid28/devops-employee-api:8fa51e990f57f869384631434872b1246f7bbded`.

**Root cause:** The Argo CD Application source was configured to follow the feature branch rather than the intended stable `main` branch. A green Argo status only meant that Argo had reconciled the branch it was told to follow; it did not prove that it was following the correct branch.

**Resolution:** The Application configuration in Git was corrected to use:

- Repository: `https://github.com/Nouhid/devops-employee-api.git`
- Target revision: `main`
- Manifest path: `k8s`

The corrected Application was applied, and Argo CD observed the main-branch revision. Later it reported revision `5d7b3b0...`, and after the coverage-ignore PR merge it reported `045d91ee822fbce8d9a4c4b7896c19171becc7e4`.

**Reusable diagnosis:**

```bash
kubectl get application employee-api -n argocd -o yaml
kubectl get application employee-api -n argocd \
  -o jsonpath='Repo: {.spec.source.repoURL}{"\n"}Branch: {.spec.source.targetRevision}{"\n"}Path: {.spec.source.path}{"\n"}Sync: {.status.sync.status}{"\n"}Health: {.status.health.status}{"\n"}Revision: {.status.sync.revision}{"\n"}'
```

Compare those values with `argocd/employee-api-application.yaml` on the intended Git branch. Never assume `Synced` means “synced to the branch I intended.”

### 2.3 Undoing a GitOps configuration change safely

**Recorded project history:** A GitOps rollback was made using a Git revert (commit reference recorded as `9e62e3b`), rather than manually editing cluster resources and leaving Git inconsistent.

**Correct principle:** When Argo CD manages a resource, prefer reverting or correcting the manifest in Git. A direct `kubectl edit` may be overwritten by Argo self-healing.

```bash
git log --oneline --decorate
git show <commit>
git revert <commit>
git push
```

Use the actual commit SHA and inspect the resulting diff before pushing. The exact original reverted change and full command transcript were not retained in the conversation history.

### 2.4 Generated reports accidentally appearing in Git

**Symptoms:** The project generated files such as:

- `.coverage`
- `coverage.xml`
- `pip-audit-report.json`
- `trivy-report.json`

These are test/security outputs, not source files. Earlier project cleanup removed generated reports from Git tracking and confirmed ignore rules. Later, a fresh local `coverage.xml` appeared untracked because it was not yet covered by the ignore file on main.

**Resolution for the final coverage report:**

Added to `.gitignore`:

```gitignore
# Generated coverage XML report
coverage.xml
```

Validated with:

```bash
git check-ignore -v coverage.xml
git ls-files | grep -E '(^|/)(coverage\.xml|\.coverage|trivy-report\.json|pip-audit-report\.json)$' \
  || echo "No generated reports tracked"
git status
```

**Observed result:** `coverage.xml` matched `.gitignore:41`; no generated reports were tracked; the main working tree was clean.

**GitHub delivery:** PR #7, `chore: ignore generated coverage report`, was squash-merged. Main became `045d91ee822fbce8d9a4c4b7896c19171becc7e4`.

**Lesson:** Ignore rules prevent new untracked files; they do not automatically remove files already tracked. For an already tracked generated file, remove it from the index (without deleting the local copy if needed), commit the removal, and then verify `git ls-files`.

### 2.5 Safe Git synchronization after merge

The final synchronization sequence used on the Ubuntu VM:

```bash
git fetch origin
git switch main
git pull --ff-only origin main
git status
git log -1 --oneline
```

**Observed result:** Local main fast-forwarded to `045d91e`, matched `origin/main`, and had a clean working tree.

**Why `--ff-only`:** It refuses to create an accidental merge commit when local history has diverged. If it fails, inspect the divergence instead of forcing a pull.

---

## 3. Docker and container troubleshooting

### 3.1 Dockerfile parser failure caused by whitespace after a continuation

**Recorded symptom (19 Nov 2026):**

Docker build failed with parser errors resembling:

```text
unknown instruction: --no-cache-dir
unknown instruction: apt-get
```

The same edit also produced trailing-whitespace warnings from:

```bash
git diff --check
```

**Root cause:** A backslash used for shell line continuation had trailing spaces after it. In a Dockerfile, the continuation backslash must be the final character on the line. If whitespace follows it, Docker does not continue the instruction as intended; the next line can be interpreted as a new Dockerfile instruction.

**Resolution:** The affected multiline `RUN` and `HEALTHCHECK` commands were converted to single-line commands, removing the ambiguous continuation formatting.

**Validation recorded:**

- Rebuilt with `sudo docker build --no-cache -t devops-employee-api:sonar-fix .`.
- Build produced image ID beginning `4362f9766e6f`.
- Test container ran with host port 8001 mapped to container port 8000.
- Container health reported `healthy`.
- `id` inside the container showed `uid=999(appuser)`.
- `/app/main.py` was owned by root and read-only: `-r--r--r-- 1 root root`.
- Test container was removed after validation.

**Reusable workflow:**

```bash
git diff --check
nl -ba Dockerfile
sudo docker build --no-cache -t devops-employee-api:debug .
sudo docker run -d --name employee-api-debug -p 8001:8000 devops-employee-api:debug
sudo docker ps -a
sudo docker logs employee-api-debug
sudo docker inspect --format='{{json .State.Health}}' employee-api-debug
sudo docker exec employee-api-debug id
sudo docker exec employee-api-debug ls -l /app/main.py
sudo docker rm -f employee-api-debug
```

Use a unique debug container name and remove it when finished. The above is a reusable diagnostic sequence; the historical container name may have differed.

### 3.2 Non-root and read-only application files

**Reason for the work:** Sonar/security review required a hardened runtime. The Dockerfile was updated to run the application as a non-root user and make the application source read-only.

**Evidence:** The test image ran as `appuser` (UID 999 in that specific Docker test), and `/app/main.py` was root-owned/read-only. The Kubernetes workload later used UID/GID 10001.

**Important distinction:** The Docker test's UID 999 and the Kubernetes manifest's UID/GID 10001 are observations from different runtime configurations; do not conflate them.

**Troubleshooting principle:** If a hardened container fails to start, inspect the application logs and identify whether it is trying to write to a read-only path or access a file as the wrong user. Do not remove the security controls as the first response. Redirect writable runtime data to an explicitly writable volume or temporary path, or correct ownership at image-build time.

### 3.3 Docker service, socket, port, and name issues from the wider lab

Earlier Docker practice in the user's Ubuntu lab also encountered operational issues:

- Docker service unit missing / Docker or containerd dependency mismatch.
- Permission denied when accessing `/var/run/docker.sock`.
- Host port already allocated.
- Container name already in use.
- Nginx test container and a test image/container workflow.

These are recorded as earlier lab incidents, but the exact commands and full resolution transcript are not preserved as part of the Employee API project. Use this safe diagnostic order:

```bash
sudo systemctl status docker --no-pager
sudo systemctl status containerd --no-pager
sudo journalctl -u docker -n 100 --no-pager
docker version
ls -l /var/run/docker.sock
id
docker ps -a
sudo ss -lntp
```

Interpretation:

- Daemon unavailable → inspect service state and journal before reinstalling.
- Socket permission denied → distinguish a stopped daemon from a user/group permission issue. Do not blindly chmod the socket.
- Port already allocated → identify the process/container listening on that host port before choosing another port.
- Name conflict → inspect the existing container; remove it only if it is safe to do so.

### 3.4 Container port mapping and health verification

The API listens on container port 8000. In the recorded Docker debug run, host port 8001 was mapped to container port 8000. In Kubernetes, Service port 8000 targets the container.

Always distinguish:

- Host port: where a client connects on the VM.
- Container port: where Uvicorn listens inside the container.
- Kubernetes Service port: the stable in-cluster service port.
- `targetPort`: the container port selected by the Service.

A running container is not proof that the application is healthy. Inspect logs, health state, and a real HTTP request.

---

## 4. Python dependencies, SonarQube Cloud, and CI dependency installation

### 4.1 Reproducible dependency installation and Sonar-related hardening

**Context:** Sonar/security review led to changes in dependency installation. The pipeline used `requirements.lock`; dependency installation was hardened to require hashes and binary distributions.

**Recorded fix:**

```yaml
- name: Install Dependencies
  run: |
    python -m pip install \
      --require-hashes \
      --only-binary=:all: \
      -r requirements.lock
```

**Why these options matter:**

- `--require-hashes` requires each locked package artifact to match a recorded hash.
- `--only-binary=:all:` avoids building packages from source during this installation step.
- `requirements.lock` makes the CI dependency set explicit and repeatable.

The Sonar-related fix was committed on `feat/docker-pipeline` in commit `0b0d3c8`. A later CI run (#33) reported all six pipeline jobs successful.

### 4.2 Coverage report generation and Sonar import

The test stage generated both terminal coverage and an XML report:

```bash
python -m pytest -v \
  --cov=main \
  --cov-report=term-missing \
  --cov-report=xml:coverage.xml \
  --cov-fail-under=80
```

**Important details:**

- `coverage.xml` is a generated artifact used by downstream analysis.
- The 80% threshold is enforced by pytest-cov in CI.
- The report must exist at the path configured for Sonar analysis.
- Do not confuse a coverage report being generated with Sonar successfully importing it; inspect the Sonar job logs for report discovery/import messages.

A whitespace issue in a previous multiline shell command was corrected by removing trailing spaces after continuation backslashes. `git diff --check` is a useful early check before waiting for CI.

### 4.3 How to diagnose a future Sonar job failure

The exact historical Sonar scanner failure text is not present in the available transcript, so do not invent one. Use this sequence:

1. Open the failing SonarQube Cloud job, not just the overall workflow.
2. Identify whether the failure is dependency installation, scanner startup, authentication, project binding, coverage import, or quality gate.
3. Confirm the scanner is using the intended project key and branch.
4. Confirm `coverage.xml` was generated in the same workspace and at the configured path.
5. Confirm dependency installation uses the lock file and required hashes.
6. Fix the failing stage only, push the change, and rerun the pipeline.

Useful repository-side checks:

```bash
grep -nE 'sonar|coverage|pytest|requirements.lock|require-hashes' .github/workflows/ci.yml
grep -nE 'sonar|coverage' sonar-project.properties 2>/dev/null || true
git diff --check
```

Never paste a Sonar token into a workflow file or commit it. Use the repository's configured GitHub Actions secret.

---

## 5. GitHub Actions and DevSecOps pipeline troubleshooting

### 5.1 Identify the failed job before changing code

The project pipeline had six principal jobs:

1. Build and Test Application
2. Gitleaks Secret Detection
3. Trivy Vulnerability Scanner
4. Python Dependency Vulnerability Audit
5. SonarQube Cloud Analysis
6. Docker Build, Scan and Push

A workflow can show an overall failure even when five jobs succeeded. Open the failed job and then the first failed step. Avoid changing unrelated Docker, Kubernetes, or Python code based only on the overall red workflow indicator.

### 5.2 Trivy Kubernetes security findings

**Recorded finding:** An earlier Trivy Kubernetes configuration scan reported HIGH findings including `KSV-0014` and `KSV-0118` against the Deployment.

**Resolution direction reflected in the hardened workload:** The Kubernetes Deployment was updated with explicit container security settings, including:

- non-root execution (UID/GID 10001),
- RuntimeDefault seccomp profile,
- privilege escalation disabled,
- read-only root filesystem,
- all Linux capabilities dropped,
- resource requests and limits,
- readiness and liveness probes.

The later security commit `88714c9` was reported clean locally, and the subsequent CI pipeline passed its Trivy job.

**Reusable diagnosis:**

```bash
trivy config --severity HIGH,CRITICAL k8s/
```

Read the exact check ID and the affected manifest path. Fix the underlying Kubernetes security context rather than suppressing the finding without justification. If an exception is truly needed, scope it narrowly and document why.

### 5.3 Gitleaks and secrets

Gitleaks was part of the required pipeline. The project used a Kubernetes Secret reference for sensitive application configuration; actual secret values were not committed in the repository.

**Correct troubleshooting sequence if Gitleaks fails:**

- Identify the exact file, line, and detected token type from the job log.
- Determine whether the string is a real credential or a test/example value.
- If real, revoke/rotate it; deleting it from the latest commit alone does not make an exposed credential safe.
- Remove the secret from the repository history if necessary, using a coordinated history rewrite.
- For a legitimate false positive, use the narrowest supported allowlist mechanism with a comment.
- Re-run Gitleaks and verify no secret value is printed into logs.

Do not store actual credentials in `k8s/secret.yaml`, README examples, or shell history.

### 5.4 pip-audit

pip-audit scans the resolved Python dependencies for known advisories. If it fails:

- Read the package name, installed version, advisory ID, and fixed version.
- Check whether the package is direct or transitive in the lock file.
- Update the dependency input and regenerate the lock file with hashes.
- Re-run the exact locked install and audit locally/CI.
- Do not arbitrarily remove a dependency without checking whether the application or test suite needs it.

The project's later CI runs reported pip-audit success.

### 5.5 Docker publishing should happen only after gates pass

The Docker job built the image, ran Trivy image scanning, authenticated to Docker Hub, and pushed commit-SHA and `latest` tags on main. The job depended on the validation/security stages.

**Troubleshooting principle:** If Docker publishing did not happen, first inspect upstream job conclusions and the Docker job's dependency graph. A skipped Docker job may be the correct safety behavior after a failed test/security gate.

**Observed successful runs:**

- Run #33: all six jobs passed after the dependency/security fixes.
- Run #39 (after PR #7): all six jobs passed, including Docker build, image scan, login, and push.
- Documentation PR #8 also completed its six checks successfully before merge.

---

## 6. Kubernetes and Kind troubleshooting

### 6.1 Establish cluster, context, namespace, and resource state

Before editing manifests, verify that kubectl is talking to the intended cluster and namespace:

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get namespaces
kubectl get all -n employee-api
kubectl get events -n employee-api --sort-by=.lastTimestamp
```

This project ran on a local Kind cluster named `practice3`, with namespace `employee-api`. A command against the wrong context or namespace can make a healthy resource appear missing.

### 6.2 Kubernetes configuration file permission issue

**Recorded earlier lab symptom:** `kubectl config set-context --current --namespace=js_nouhid` failed with:

```text
/etc/kubernetes/practice3.conf.lock: permission denied
```

**Meaning:** kubectl was attempting to write/lock a configuration file under `/etc/kubernetes`, a location the current user could not modify.

**Correct troubleshooting approach:**

```bash
echo "$KUBECONFIG"
kubectl config view --minify
ls -l /etc/kubernetes/practice3.conf
ls -l ~/.kube/config
```

Use a user-owned kubeconfig under `~/.kube/config` for ordinary user operations, or deliberately manage permissions through the cluster's intended administrative process. Do not repeatedly run config mutations against a root-owned file or make it world-writable. The exact final remediation transcript for this earlier lab issue was not retained.

### 6.3 Manifest editing permission issue

**Recorded earlier Kubernetes practice symptom:** writing to `/opt/k8s-labs/welcome-app/welcome-app.yaml` failed with permission denied; the user also reported not being in sudoers.

**Lesson:** Separate file ownership/OS permission problems from Kubernetes API permission problems.

```bash
ls -ld /opt/k8s-labs /opt/k8s-labs/welcome-app
ls -l /opt/k8s-labs/welcome-app/welcome-app.yaml
whoami
id
```

Use a user-owned working copy, edit it, review the diff, then copy/apply it through an authorized path. Do not attempt to bypass sudo policy.

### 6.4 Pod is Running but not Ready

**Observed during the final Argo branch correction:** After Argo switched to the main-branch manifests at revision `5d7b3b0...`, the new pod `employee-api-5b4b565d4d-vtxg7` showed `Running` but `0/1` Ready, while the two older pods were `1/1`. The Deployment still showed two available replicas and one updated replica; Argo health was `Progressing`.

**Diagnostic commands requested at the time:**

```bash
kubectl describe pod employee-api-5b4b565d4d-vtxg7 -n employee-api
kubectl logs employee-api-5b4b565d4d-vtxg7 -n employee-api --tail=80
```

**Important evidence limitation:** The exact readiness failure cause and its direct fix were not captured in the retained chat record. Later, the rollout was observed complete with two ready pods and no restarts. Do not state a specific probe failure or claim a particular root cause for that transient pod without the original Events/logs.

**Correct general reasoning:**

- `Running` means the container process started; it does not mean the readiness probe passed.
- `describe pod` reveals Events, probe failures, image pull status, and scheduling details.
- `logs` reveal application startup/runtime errors.
- Inspect the probe path/port and container listening address only after reading that evidence.

### 6.5 ImagePullBackOff / wrong image diagnosis

The project used both a mutable development tag (`:v2`) and a commit-SHA tag. The final main manifest pinned the immutable SHA tag.

If a pod cannot pull an image:

```bash
kubectl describe pod <pod> -n employee-api
kubectl get deployment employee-api -n employee-api \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Inspect Events for `ErrImagePull`, `ImagePullBackOff`, authentication errors, missing tag, or registry/network errors. Confirm the exact image tag exists in Docker Hub and that the Deployment references it. Do not diagnose an image pull issue from pod status alone.

**Project image identity evidence:** The final observed Deployment used:
`nouhid28/devops-employee-api:8fa51e990f57f869384631434872b1246f7bbded`.
The two pods had the same image digest:
`sha256:5dbd0a04fe500cc2e8e8e4bfd0122a82453cbeba008484caa8c65ae82a36656d`.

### 6.6 Service selector mismatch and no endpoints

An earlier Kubernetes practice exercise deliberately changed a Service selector from `app: welcome-app` to `app: wrong-app` to reproduce a service-routing bug. The correct diagnosis is to compare Service selector labels with Pod labels and inspect endpoints:

```bash
kubectl get service <service-name> -n <namespace> -o yaml
kubectl get pods -n <namespace> --show-labels
kubectl get endpoints <service-name> -n <namespace>
```

If the selector matches no pods, the Service has no endpoints and cannot forward traffic. Fix the selector or the pod labels so they match. This was a deliberate debugging exercise in the earlier `welcome-app` practice namespace, not a claim that the final Employee API Service had this defect.

### 6.7 Port-forward fails because the local port is occupied

**Recorded earlier Kubernetes practice symptom:** port-forwarding to local port 8080 failed because something was already listening. `ss` showed a listener even though `lsof` did not provide a useful result.

**Diagnostic sequence:**

```bash
ss -lntp | grep ':8080'
sudo fuser -v 8080/tcp
```

Choose another unused local port rather than killing an unknown process. For the final Employee API validation, the service was forwarded to local port 8081 and the endpoints were tested successfully.

```bash
kubectl port-forward -n employee-api service/employee-api 8081:8000
```

In another terminal:

```bash
curl -i http://localhost:8081/health
curl -i http://localhost:8081/version
curl -i http://localhost:8081/
```

Observed final responses: all three returned HTTP 200.

### 6.8 NodePort reachability and Kind networking

**Earlier lab observation:** NodePort access through the host/LAN address `192.168.1.41` failed, while direct curls to Kind node container addresses `172.22.0.5:32540` and `172.22.0.3:32540` returned the test application's HTML.

**Lesson:** A NodePort exposed inside the Kind node network is not automatically reachable through the host's LAN interface. Kind nodes are containers with their own network; host port mappings and firewall/network routing determine host reachability.

**Diagnostic sequence:**

```bash
kubectl get service -A
kubectl get nodes -o wide
docker ps
sudo ss -lntp
```

Check the Service's NodePort, Kind node networking, Docker port mappings, and host firewall. Do not assume the Kubernetes Service is broken just because the host LAN address cannot reach the Kind node port.

### 6.9 Secret injection and configuration

The Employee API Deployment referenced a Kubernetes Secret named `employee-api-secret`. Secret values were kept outside Git. A previous lab workflow created a namespace-scoped Secret and then applied the Deployment.

**Safe checks:**

```bash
kubectl get secret employee-api-secret -n employee-api
kubectl describe deployment employee-api -n employee-api
kubectl describe pod <pod> -n employee-api
```

Avoid printing secret values into terminal recordings, chat, CI logs, or documentation. A Secret object existing does not prove the pod consumed the intended key; inspect the Deployment's `secretKeyRef` names and pod events.

### 6.10 HPA and metrics

The Employee API HPA was configured for a minimum of two and maximum of five replicas, targeting 50% average CPU utilization. A previously observed value was around 2% current CPU against a 50% target, with two replicas.

**Troubleshooting sequence:**

```bash
kubectl get hpa -n employee-api
kubectl describe hpa employee-api-hpa -n employee-api
kubectl top pods -n employee-api
kubectl top nodes
```

If metrics show `<unknown>`, investigate the Metrics API / metrics-server and its events before changing the HPA target. An HPA being configured is not proof that scale-out was load-tested; this project did not claim a demonstrated load test.

---

## 7. Argo CD GitOps troubleshooting

### 7.1 Understand the three independent Argo states

Do not treat these as synonyms:

- **Sync status:** whether live resources match the desired manifests at the observed Git revision.
- **Health status:** whether Argo considers the resources healthy.
- **Source revision:** which Git revision Argo actually observed.

A green `Synced` status against the wrong branch is still a source-of-truth error.

### 7.2 Verify Application source and observed revision

```bash
kubectl get application employee-api -n argocd \
  -o jsonpath='Repository: {.spec.source.repoURL}{"\n"}Branch: {.spec.source.targetRevision}{"\n"}Path: {.spec.source.path}{"\n"}Sync: {.status.sync.status}{"\n"}Health: {.status.health.status}{"\n"}Revision: {.status.sync.revision}{"\n"}'
```

Compare repo, branch, path, and revision with the Application YAML committed to main.

### 7.3 Self-healing verification

**Recorded test (20 Nov 2026):** A ConfigMap value `API_TITLE` was manually patched to `MANUAL-CHANGE-TEST`. Argo CD remained `Synced` / `Healthy`, and the value reverted to the Git-defined value `DevOps Employee Management API`.

**What this demonstrated:** Argo CD self-healing was active and restored the live resource to the declared Git state after manual drift.

**Operational lesson:** Do not use direct cluster edits as the normal change workflow for Argo-managed resources. Make the desired change in Git and allow Argo to reconcile it.

### 7.4 Auto-sync, prune, and self-heal

The Application configuration used automated sync with pruning and self-healing. The project also configured an HPA-related ignore difference so the HPA-managed replica count would not be treated as unwanted drift.

When investigating unexpected sync behavior, inspect the Application YAML and Argo status before manually syncing or deleting resources. Check whether a resource is intentionally ignored, whether pruning is enabled, and whether the source branch is correct.

---

## 8. Prometheus and Grafana troubleshooting

### 8.1 Prometheus target health

**Observed result:** The Prometheus Targets page/API showed 12 active scrape targets, all with `Health: up`. The targets included Kubernetes API/server, nodes, kubelet/cAdvisor, service endpoints, node exporters, and Prometheus itself.

**How to investigate a future down target:**

1. Identify the exact target and scrape error in Prometheus Targets.
2. Determine whether the target is a pod, Service, node, or Kubernetes control-plane endpoint.
3. Check the backing pod and Service.
4. Check labels, annotations, ServiceMonitor/target discovery configuration, and endpoint port.
5. Resolve the network or scrape-path error; then confirm the target changes to `up`.

Useful commands:

```bash
kubectl get pods -n monitoring -o wide
kubectl get services -n monitoring
kubectl get endpoints -n monitoring
helm list -n monitoring
```

### 8.2 Grafana cannot find or query Prometheus

The user previously asked where to add the Prometheus server URL in Grafana. The important distinction is between:

- a Prometheus server that is running,
- a Grafana data source configured to point to it,
- a data source connection test that succeeds,
- dashboards that query metrics actually being scraped.

For a Helm-installed Prometheus/Grafana stack in the same cluster, use the Prometheus Kubernetes Service DNS name and port shown by `kubectl get services -n monitoring`; do not guess the Service name or URL. In Grafana, configure the Prometheus data source, save/test it, and confirm the connection test succeeds.

The exact final data-source URL entered in the original session is not present in the retained history.

### 8.3 Understand the monitoring scope

The deployed monitoring stack included Prometheus, Grafana, kube-state-metrics, and node-exporter. The project documentation correctly states:

- monitoring covers Kubernetes object and node-level telemetry;
- the FastAPI application does not currently expose a Prometheus `/metrics` endpoint;
- application request rate, latency, and error-rate dashboards are therefore not claimed;
- Prometheus persistence is disabled and retention is three days in this lab.

This distinction matters in interviews: a cluster dashboard is not the same as application-level observability.

---

## 9. Ingress and application connectivity

### 9.1 Trace the request path in order

For this project, the request path is:

`Client → NGINX Ingress → Kubernetes Service → ready API Pod → Uvicorn :8000`

If a request fails, test from the nearest layer outward:

1. Pod readiness and logs.
2. Service endpoints.
3. In-cluster Service connectivity.
4. Ingress controller and Ingress rule.
5. Host header / DNS resolution from the client.

### 9.2 Host-based Ingress testing

The project used host `employee-api.local`. A successful test used an explicit Host header:

```bash
curl -i -H "Host: employee-api.local" http://localhost/health
curl -i -H "Host: employee-api.local" http://localhost/version
```

The Host header is important because NGINX Ingress routes by host rule. A request to localhost without the expected host may match no rule even when the Ingress controller is running.

The Ingress path was successfully tested during the project.

---

## 10. Final end-to-end verification — recorded final state

This section records the final known state after the documentation and repository-hygiene work. It is a result summary, not a request to repeat the checks.

### Git and GitHub

- Repository: `Nouhid/devops-employee-api`.
- Main branch after PR #7: `045d91ee822fbce8d9a4c4b7896c19171becc7e4`.
- PR #7 added the generated `coverage.xml` ignore rule and was merged.
- The local Ubuntu checkout was synchronized to main and reported clean.
- PR #8 added the portfolio case study and README navigation; it was merged as `93e280582c529078c464cae0ab801b6c8aa295cf`.
- Six CI checks on the documentation PR completed successfully.

### CI/CD

A post-PR #7 run (#39, run ID `45344371762`) completed all six jobs successfully:

- Build and Test Application
- Gitleaks Secret Detection
- Trivy Vulnerability Scanner
- Python Dependency Vulnerability Audit
- SonarQube Cloud Analysis
- Docker Build, Scan and Push

### Argo CD and Kubernetes

Final reported Argo Application:

- Repository: `https://github.com/Nouhid/devops-employee-api.git`
- Branch: `main`
- Path: `k8s`
- Sync: `Synced`
- Health: `Healthy`
- Observed revision: `045d91ee822fbce8d9a4c4b7896c19171becc7e4`

Final reported Deployment:

- Namespace: `employee-api`
- Replicas: 2/2 ready
- Pods: both `Running`, 1/1 ready, zero restarts at the time of observation
- Image: `nouhid28/devops-employee-api:8fa51e990f57f869384631434872b1246f7bbded`
- Service: NodePort `8000:30080/TCP`

The Deployment image tag remained pinned to a previously built immutable SHA image. Argo's observed Git revision being newer does not imply the image tag must be identical to the Git commit SHA; the manifest explicitly defines the selected image version.

### API

The following requests returned HTTP 200:

- `GET /health` → `{"status":"healthy"}`
- `GET /version` → `{"application":"devops-employee-api","version":"1.0.0"}`
- `GET /` → running/welcome response

### Monitoring

- Prometheus: 12 targets reported up.
- Grafana dashboards were available.
- Scope remains cluster/node telemetry, not application request metrics.

---

## 11. Interview revision: explain a troubleshooting incident clearly

Use this five-part answer format:

1. **Situation:** What failed? Quote the exact symptom.
2. **Investigation:** Which evidence did you collect first and why?
3. **Root cause:** What specifically caused the failure?
4. **Resolution:** What smallest change fixed it?
5. **Validation:** What command or observed behavior proved it was fixed?

### Example: Argo CD followed the wrong branch

- **Situation:** Argo showed Synced/Healthy, but the Application followed a feature branch instead of main.
- **Investigation:** Compared the Argo Application source, target revision, observed revision, and the two branches' manifests.
- **Root cause:** The Application's target revision was set to `feat/docker-pipeline`.
- **Resolution:** Updated the Application definition to track `main` and the `k8s` directory.
- **Validation:** Argo reported main's revision, Synced/Healthy, and the Deployment had two ready replicas.

### Example: Dockerfile parser failure

- **Situation:** Docker interpreted a line such as `--no-cache-dir` as an unknown Dockerfile instruction.
- **Investigation:** Read the parser error and inspected Dockerfile line continuations; `git diff --check` exposed trailing whitespace.
- **Root cause:** Spaces followed the continuation backslash.
- **Resolution:** Rewrote the affected multiline instructions as single-line commands.
- **Validation:** The image built, the container became healthy, and the process ran as the configured non-root user.

### Example: Generated coverage report in Git status

- **Situation:** `coverage.xml` appeared as an untracked local file after test execution.
- **Investigation:** Checked ignore rules with `git check-ignore -v` and tracked files with `git ls-files`.
- **Root cause:** The generated XML report did not yet have an ignore rule on main.
- **Resolution:** Added `coverage.xml` to `.gitignore` through PR #7.
- **Validation:** Git identified the ignore rule, no generated reports were tracked, and the working tree was clean.

---

## 12. What not to claim

To keep the project credible in interviews and on a resume:

- Do not describe this as a production or managed Kubernetes deployment; it ran on local Kind.
- Do not claim the API is database-backed or implements full employee CRUD.
- Do not claim application-level Prometheus metrics; no `/metrics` endpoint was implemented.
- Do not claim HPA scale-out was load-tested; the HPA was configured and metrics were available.
- Do not claim AWS or Terraform were implemented; they were intentionally outside this project.
- Do not invent a root cause for the transient pod readiness event where the original pod Events/log output was not preserved.
- Do not claim the CI workflow automatically rewrites the Kubernetes image tag. The pipeline publishes the image; release promotion is done by updating the manifest in Git and letting Argo CD reconcile it.

## 13. Core commands to memorize

```bash
# Git state and history
git status
git branch -vv
git fetch origin
git log --oneline --decorate -8
git diff --check

# Docker build and runtime
sudo docker build --no-cache -t app:debug .
sudo docker ps -a
sudo docker logs <container>
sudo docker inspect <container>
sudo docker exec <container> id

# Kubernetes state and evidence
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -n employee-api -o wide
kubectl describe pod <pod> -n employee-api
kubectl logs <pod> -n employee-api --tail=100
kubectl get deployment,service,endpoints -n employee-api
kubectl get events -n employee-api --sort-by=.lastTimestamp
kubectl rollout status deployment/employee-api -n employee-api

# Argo CD GitOps source and health
kubectl get application employee-api -n argocd -o yaml

# HPA and monitoring
kubectl get hpa -n employee-api
kubectl top pods -n employee-api
kubectl get pods,services,endpoints -n monitoring

# API and Ingress
curl -i http://localhost:8081/health
curl -i http://localhost:8081/version
curl -i -H "Host: employee-api.local" http://localhost/health
```

**Final habit:** Diagnose from evidence, fix the narrowest cause, validate the exact failed layer, then verify the end-to-end path once. Avoid repeated health checks when no new change has occurred.
