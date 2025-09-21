# LiteLLM Proxy for OpenAI GPT-5 on Google Cloud (Cloud Run + Cloud SQL Postgres)

This repository provides step-by-step instructions to deploy a [LiteLLM proxy](https://github.com/BerriAI/litellm) that exposes an **OpenAI-compatible** `/chat/completions` API for **GPT-5 only**, running on **Cloud Run** with **Cloud SQL for PostgreSQL** for persistence.

Supported models:

* OpenAI **GPT-5** (only)

Requirements:

* Google Cloud Project with **billing enabled**
* **OpenAI API key** with GPT-5 access
* **Cloud Shell** access within your project

**Important**: Replace placeholder values before running commands:
- `<YOUR_OPENAI_API_KEY>` – your OpenAI key (e.g., `sk-proj-...`)
- `<YOUR_DB_PASSWORD>` – a strong password for the `postgres` user
- `<DEV_ONLY_MASTER_KEY>` – optional fallback in `config.yaml` for *local/dev* only

You can execute everything using **Cloud Shell**.

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.png)](https://shell.cloud.google.com/cloudshell/open?shellonly=true&ephemeral=false&cloudshell_git_repo=https://github.com/mhakankara/gcloud_litellm&cloudshell_git_branch=master&cloudshell_tutorial=README.md)

---

## Authenticate

Authenticate your Google Cloud Account:

```bash
gcloud auth login
```

---

## Configuration

<walkthrough-project-setup></walkthrough-project-setup>

Set Google Cloud project ID (replace with your project):

```bash
MY_PROJECT_ID="<walkthrough-project-id/>"
```

Set default `gcloud` project:

```bash
gcloud config set project "$MY_PROJECT_ID"
```

Get Google Cloud **project number**:

```bash
MY_PROJECT_NUMBER="$(gcloud projects list --filter="$MY_PROJECT_ID" --format="value(PROJECT_NUMBER)" --quiet)"
echo "Google Cloud project number: '$MY_PROJECT_NUMBER'"
```

Set Google Cloud **region** (recommended: `us-central1`):

```bash
MY_REGION="us-central1"
```

Set your **OpenAI API key** (GPT-5 access):

```bash
MY_OPENAI_API_KEY="<YOUR_OPENAI_API_KEY>"
```

Set **Artifact Registry** repository name for Docker images:

```bash
MY_ARTIFACT_REPOSITORY="llm-tools"
```

### Enable APIs

```bash
gcloud services enable \
  iam.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  containeranalysis.googleapis.com \
  containerscanning.googleapis.com \
  sqladmin.googleapis.com \
  --project="$MY_PROJECT_ID" \
  --quiet
```

---

## Create Service Accounts

Service account for LiteLLM proxy (Cloud Run):

```bash
gcloud iam service-accounts create "litellm-proxy" \
  --description="LiteLLM proxy (Cloud Run)" \
  --display-name="LiteLLM proxy" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

Grant **Cloud SQL Client**:

```bash
gcloud projects add-iam-policy-binding "$MY_PROJECT_ID" \
  --member="serviceAccount:litellm-proxy@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

Create service account for building Docker images (Cloud Build):

```bash
gcloud iam service-accounts create "docker-build" \
  --description="Build Docker container images (Cloud Build)" \
  --display-name="Docker build" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

Grant Artifact Registry + Logs Writer to the build SA:

```bash
gcloud projects add-iam-policy-binding "$MY_PROJECT_ID" \
  --member="serviceAccount:docker-build@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer" \
  --project="$MY_PROJECT_ID" \
  --quiet

gcloud projects add-iam-policy-binding "$MY_PROJECT_ID" \
  --member="serviceAccount:docker-build@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

---

## Cloud SQL PostgreSQL Database

Create a PostgreSQL instance:

```bash
gcloud sql instances create "litellm-db" \
  --database-version="POSTGRES_15" \
  --tier="db-f1-micro" \
  --region="$MY_REGION" \
  --storage-type="SSD" \
  --storage-size="10GB" \
  --storage-auto-increase \
  --backup-start-time="03:00" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

Set the password for `postgres` user:

```bash
MY_DB_PASSWORD="REPLACE_ME_WITH_STRONG_PASSWORD"
```

```bash
gcloud sql users set-password "postgres" \
  --instance="litellm-db" \
  --password="$MY_DB_PASSWORD" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

Create a database:

```bash
gcloud sql databases create "litellm" \
  --instance="litellm-db" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

Get the connection name:

```bash
MY_DB_CONNECTION_NAME="$(gcloud sql instances describe litellm-db --format="value(connectionName)" --project="$MY_PROJECT_ID" --quiet)"
echo "Database connection name: '$MY_DB_CONNECTION_NAME'"
```

---

## Artifact Registry

```bash
gcloud artifacts repositories create "$MY_ARTIFACT_REPOSITORY" \
  --repository-format="docker" \
  --description="Docker container registry for LiteLLM proxy" \
  --location="$MY_REGION" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

---

## Storage Bucket

```bash
gcloud storage buckets create "gs://docker-build-$MY_PROJECT_NUMBER" \
  --location="$MY_REGION" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

```bash
gcloud storage buckets add-iam-policy-binding "gs://docker-build-$MY_PROJECT_NUMBER" \
  --member="serviceAccount:docker-build@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.admin" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

---

## Docker Container

```bash
gcloud builds submit \
  --tag="${MY_REGION}-docker.pkg.dev/${MY_PROJECT_ID}/${MY_ARTIFACT_REPOSITORY}/litellm-proxy:latest" \
  --timeout="1h" \
  --region="$MY_REGION" \
  --service-account="projects/${MY_PROJECT_ID}/serviceAccounts/docker-build@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
  --gcs-source-staging-dir="gs://docker-build-$MY_PROJECT_NUMBER/source" \
  --gcs-log-dir="gs://docker-build-$MY_PROJECT_NUMBER" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

---

## Deploy LiteLLM Proxy

Generate a master key:

```bash
MY_RANDOM=$(openssl rand -hex 21)
MY_SALT=$(openssl rand -hex 32)
echo "MASTER: sk-$MY_RANDOM"
echo "SALT  : sk-$MY_SALT"
```

Set DB password

```bash
# Build a Prisma-friendly Cloud SQL socket DSN.
# Prisma needs a host:port; the real connection uses the Unix socket in ?host=/cloudsql/...
DB_SOCKET="postgresql://postgres:${MY_DB_PASSWORD}@localhost:5432/litellm?host=/cloudsql/${MY_PROJECT_ID}:${MY_REGION}:litellm-db"
```

Generate an Admin UI password (or set your own)
```bash
UI_USERNAME="admin"
UI_PASSWORD="$(openssl rand -base64 18)"
echo "UI username: $UI_USERNAME"
echo "UI password: $UI_PASSWORD"
```

```bash
gcloud run deploy "litellm-proxy" \
  --image="${MY_REGION}-docker.pkg.dev/${MY_PROJECT_ID}/${MY_ARTIFACT_REPOSITORY}/litellm-proxy:latest" \
  --region="$MY_REGION" \
  --memory="2Gi" \
  --cpu="2" \
  --cpu-boost \
  --execution-environment="gen1" \
  --port="8080" \
  --add-cloudsql-instances="${MY_PROJECT_ID}:${MY_REGION}:litellm-db" \
  --service-account="litellm-proxy@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
  --allow-unauthenticated \
  --set-env-vars="LITELLM_MODE=PRODUCTION,LITELLM_LOG=ERROR,OPENAI_API_KEY=${MY_OPENAI_API_KEY},LITELLM_MASTER_KEY=sk-${MY_RANDOM},LITELLM_SALT_KEY=sk-${MY_SALT},STORE_MODEL_IN_DB=True,USE_PRISMA_MIGRATE=True,DATABASE_URL=${DB_SOCKET},UI_USERNAME=${UI_USERNAME},UI_PASSWORD=${UI_PASSWORD}" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

---

## Test GPT-5

```bash
MY_LITELLM_PROXY_URL="$(gcloud run services list --filter="litellm-proxy" --format="value(URL)" --quiet)"
echo "API host: '$MY_LITELLM_PROXY_URL'"
echo "Admin key:  'sk-$MY_RANDOM'"
```

```bash
curl --location "${MY_LITELLM_PROXY_URL}/chat/completions" \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer sk-$MY_RANDOM" \
  --data '{"model": "gpt-5", "messages": [{"role": "user", "content": "what llm are you"}]}'
```

---

## Clean Up

```bash
gcloud run services delete "litellm-proxy" \
  --region="$MY_REGION" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

```bash
gcloud iam service-accounts delete "litellm-proxy@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

```bash
gcloud artifacts repositories delete "$MY_ARTIFACT_REPOSITORY" \
  --location="$MY_REGION" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

```bash
gcloud iam service-accounts delete "docker-build@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

```bash
gcloud sql instances delete "litellm-db" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

```bash
gcloud storage rm -r "gs://docker-build-$MY_PROJECT_NUMBER" \
  --project="$MY_PROJECT_ID" \
  --quiet
```

---