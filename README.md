# SkyWatch — Distributed Weather Pipeline

A microservices weather tracking system built on K3s, RabbitMQ, ArgoCD, and Prometheus.

```
Browser → [Frontend Pod] → RabbitMQ → [Worker Pod] → Open-Meteo API
                              ↑
                         (K3s cluster on 2 AWS EC2 t3.micro nodes)
```

## Architecture

| Component | Node | Purpose |
|-----------|------|---------|
| K3s Server | Node 1 (Master) | Kubernetes control plane |
| ArgoCD | Node 1 (Master) | GitOps continuous deployment |
| Prometheus | Node 1 (Master) | Metrics collection |
| Frontend | Node 2 (Worker) | Flask web UI — accepts city names |
| Worker | Node 2 (Worker) | RabbitMQ consumer — fetches weather |
| RabbitMQ | Node 2 (Worker) | Message broker |
| Grafana | Node 2 (Worker) | Observability dashboard |

## Prerequisites

```bash
# Local tools required
terraform --version   # >= 1.6
ansible --version     # >= 2.14
helm version          # >= 3.12
kubectl version       # >= 1.28
```

AWS credentials configured (`aws configure` or env vars).

---

## Week 1 — Infrastructure (Terraform + Ansible)

### 1. Configure Terraform variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   key_name             = "your-aws-keypair-name"
#   ssh_private_key_path = "~/.ssh/your-key.pem"
#   allowed_ssh_cidr     = "$(curl -s ifconfig.me)/32"
```

### 2. Provision EC2 instances

```bash
terraform init
terraform plan
terraform apply
```

Terraform outputs the public IPs and writes `ansible/inventory.ini` automatically.

```
Outputs:
  master_public_ip = "1.2.3.4"
  worker_public_ip = "5.6.7.8"
  app_url          = "http://5.6.7.8:30080"
  argocd_url       = "http://1.2.3.4:30081"
  grafana_url      = "http://5.6.7.8:30030"
```

### 3. Install K3s with Ansible

```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml
```

The playbook:
1. Waits for SSH on both nodes
2. Installs K3s **server** on the master
3. Reads the node token from `/var/lib/rancher/k3s/server/node-token`
4. Joins the worker with `k3s agent --server https://MASTER_IP:6443 --token TOKEN`
5. Writes a `kubeconfig` file to the project root

### 4. Verify cluster

```bash
export KUBECONFIG=./kubeconfig
kubectl get nodes
# NAME              STATUS   ROLES                  AGE
# skywatch-master   Ready    control-plane,master   2m
# skywatch-worker   Ready    <none>                 1m
```

> **How the worker joins the master:** K3s uses a shared secret token stored at
> `/var/lib/rancher/k3s/server/node-token`. Ansible reads this file from the
> master via `slurp`, then passes it as `--token` to the agent installer on
> the worker. The worker connects back over port **6443** (K3s API) using the
> master's private IP (reachable within the same VPC/subnet).

### 5. Teardown (cost guardrail — run at end of every session)

```bash
cd terraform
terraform destroy
```

---

## Week 2 — CI / Containerisation (Docker + GitHub Actions)

### 1. Push to GitHub

```bash
git init
git remote add origin https://github.com/YOUR_USERNAME/skywatch.git
git add .
git commit -m "feat: initial project scaffold"
git push -u origin main
```

GitHub Actions (`.github/workflows/ci.yml`) triggers automatically and:

1. **Lints** `app.py` and `worker.py` with `flake8`
2. **Builds** both Docker images with Buildx (layer caching via GitHub Actions cache)
3. **Pushes** to GHCR as `ghcr.io/YOUR_USERNAME/skywatch-{frontend,worker}:SHA`
4. **Updates** `helm/skywatch/values.yaml` with the new image tag and commits back

No secrets to configure — the workflow uses `GITHUB_TOKEN` (automatically provided by Actions) for GHCR push.

### 2. Verify images

```bash
docker pull ghcr.io/YOUR_USERNAME/skywatch-frontend:latest
docker pull ghcr.io/YOUR_USERNAME/skywatch-worker:latest
```

### 3. Local testing with Docker Compose (optional)

```bash
# Quick local test before deploying to K3s
docker compose up
# Open http://localhost:5000
```

---

## Week 3 — GitOps (Helm + ArgoCD)

### 1. Prepare Helm chart

Edit `helm/skywatch/values.yaml` — replace `GITHUB_USERNAME` with your username:

```bash
sed -i 's/GITHUB_USERNAME/your-github-username/g' helm/skywatch/values.yaml
```

Fetch the RabbitMQ sub-chart:

```bash
cd helm/skywatch
helm dependency update
cd ../..
```

### 2. Install ArgoCD

```bash
export KUBECONFIG=./kubeconfig
bash argocd/setup.sh
```

The script installs ArgoCD, patches its service to NodePort 30081, and prints the admin password.

### 3. Connect ArgoCD to your repo

Edit `argocd/application.yaml` — replace `GITHUB_USERNAME`:

```bash
sed -i 's/GITHUB_USERNAME/your-github-username/g' argocd/application.yaml
kubectl apply -f argocd/application.yaml
```

ArgoCD will now:
- Watch the `helm/skywatch/` directory in your repo
- Deploy the chart automatically whenever `values.yaml` changes
- Show sync status at `http://MASTER_IP:30081`

### 4. Verify deployment

```bash
kubectl get all -n skywatch
# NAME                                    READY   STATUS    RESTARTS
# pod/skywatch-frontend-xxx               1/1     Running   0
# pod/skywatch-worker-xxx                 1/1     Running   0
# pod/skywatch-rabbitmq-0                 1/1     Running   0
```

Access the app: `http://WORKER_IP:30080`

### 5. GitOps demo — rolling update

Push any code change → CI builds → updates `values.yaml` tag → ArgoCD detects change → rolling update with zero downtime.

```bash
# Watch pods rolling
kubectl rollout status deployment/skywatch-frontend -n skywatch
kubectl rollout status deployment/skywatch-worker -n skywatch
```

---

## Week 4 — Observability (Prometheus + Grafana)

### 1. Install kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f monitoring/prometheus-values.yaml
```

### 2. Import the Grafana dashboard

```bash
# Get Grafana NodePort address
WORKER_IP=$(kubectl get node skywatch-worker -o jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}')
echo "Grafana: http://${WORKER_IP}:30030  (admin / skywatch-grafana)"
```

1. Open Grafana → **Dashboards → Import**
2. Upload `monitoring/grafana-dashboard.json`
3. Select the **Prometheus** data source

The dashboard shows:
- **CPU & Memory** per node (from `node_exporter`)
- **Queue depth** of `weather_requests` (from RabbitMQ Prometheus plugin)
- **Message rate** (publish vs consume)
- **Pod readiness** for frontend, worker, and RabbitMQ

### 3. Demo — rolling update with live metrics

```bash
# Terminal 1: generate traffic
while true; do curl -s -X POST http://${WORKER_IP}:30080 -d "city=London" > /dev/null; sleep 2; done

# Terminal 2: trigger a rolling update (bump replicas or image tag)
kubectl scale deployment skywatch-worker -n skywatch --replicas=3

# Watch queue depth spike then drain in Grafana
```

---

## Project Structure

```
project/
├── app/
│   ├── frontend/          # Flask web UI
│   │   ├── app.py
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── templates/index.html
│   └── worker/            # RabbitMQ consumer + Open-Meteo client
│       ├── worker.py
│       ├── Dockerfile
│       └── requirements.txt
├── terraform/             # Week 1 — AWS infrastructure
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── inventory.tpl      # Generates ansible/inventory.ini
├── ansible/               # Week 1 — K3s installation
│   ├── playbook.yml
│   └── roles/
│       ├── k3s_master/
│       └── k3s_worker/
├── helm/skywatch/         # Week 3 — Kubernetes packaging
│   ├── Chart.yaml         # Declares RabbitMQ as sub-chart dependency
│   ├── values.yaml        # Updated by CI with image tags
│   └── templates/
├── .github/workflows/     # Week 2 — CI pipeline
│   └── ci.yml
├── argocd/                # Week 3 — GitOps
│   ├── application.yaml
│   └── setup.sh
└── monitoring/            # Week 4 — Observability
    ├── prometheus-values.yaml
    └── grafana-dashboard.json
```

## Cost Guardrails

| Rule | Detail |
|------|--------|
| Instance type | `t3.micro` only (free tier eligible) |
| Storage | 15 GB EBS per node = 30 GB total |
| No managed services | K3s on EC2, not EKS; NodePort, not ELB |
| Destroy after each session | `terraform destroy` — two t3.micro instances running 24/7 = ~1,488 hours/month, exceeding the 750-hour free tier |
| No Elastic IPs | Use dynamic public IPs (change on restart, but cost $0) |
