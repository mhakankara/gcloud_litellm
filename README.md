# LiteLLM Proxy for OpenAI GPT-5 on Google Cloud

This repository provides instructions to deploy a [LiteLLM proxy](https://github.com/BerriAI/litellm) server that allows you to interact with OpenAI GPT-5 using a standardized OpenAI API format, hosted on Google Cloud Run with Cloud SQL PostgreSQL for data persistence.

Supported models:

* OpenAI GPT-5

Requirements:

* Google Cloud Project with billing enabled
* OpenAI API key with GPT-5 access
* Cloud Shell access within your project

**Important**: Replace all placeholder values before running commands:
- `<YOUR_OPENAI_API_KEY>`: Your actual OpenAI API key (e.g., "sk-proj-abc123...")
- `<YOUR_DB_PASSWORD>`: Choose a secure database password (e.g., "MySecurePass123!")
- `<YOUR_MASTER_KEY>`: Set in config.yaml if needed for local development

You can execute everything using the Cloud Shell in your project.

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.png)](https://shell.cloud.google.com/cloudshell/open?shellonly=true&ephemeral=false&cloudshell_git_repo=https://github.com/mhakankara/gcloud_litellm&cloudshell_git_branch=master&cloudshell_tutorial=README.md)

Follow the steps below step by step (copy & paste).

![Screenshot: Cloud Shell](https://github.com/mhakankara/gcloud_litellm/raw/master/img/cloud-shell.png)

Only skip steps if you know what you are doing and are confident.

## Authenticate

Authenticate your Google Cloud Account:

```bash
gcloud auth login
```

## Configuration

<walkthrough-project-setup></walkthrough-project-setup>

Set Google Cloud project ID.
Replace with your current Google Cloud project ID:

```bash
MY_PROJECT_ID="<walkthrough-project-id/>"
```

Set default `gcloud` project:

```bash
gcloud config set project "$MY_PROJECT_ID"
```

Set Google Cloud project number:

```bash
MY_PROJECT_NUMBER="$(gcloud projects list --filter="$MY_PROJECT_ID" --format="value(PROJECT_NUMBER)" --quiet)"
echo "Google Cloud project number: '$MY_PROJECT_NUMBER'"
```

Set Google Cloud region:
(Please note: Region other than `us-central1` can cause problems. Not all services are available in all regions.)

```bash
MY_REGION="us-central1"
```

Set your OpenAI API key:
(Replace with your actual OpenAI API key that has GPT-5 access)

```bash
MY_OPENAI_API_KEY="<YOUR_OPENAI_API_KEY>"
```

Set Artifact Registry repository name for Docker container images:

```bash
MY_ARTIFACT_REPOSITORY="llm-tools"
```

### Enable APIs

Enable Google Cloud APIs:

 > Only necessary if the APIs are not yet activated in the project.

<!-- Cloud Shell copy&paste does not work with bash for loop and comments -->
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

## Create Service Accounts

Service account for LiteLLM proxy (Cloud Run):

```bash
gcloud iam service-accounts create "litellm-proxy" \
    --description="LiteLLM proxy (Cloud Run)" \
    --display-name="LiteLLM proxy" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Create service account for building Docker container images (Cloud Build):

```bash
gcloud iam service-accounts create "docker-build" \
    --description="Build Docker container images (Cloud Build)" \
    --display-name="Docker build" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Grant access to store Docker container images:

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

Grant LiteLLM proxy access to Cloud SQL:

```bash
gcloud projects add-iam-policy-binding "$MY_PROJECT_ID" \
    --member="serviceAccount:litellm-proxy@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudsql.client" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Set service account ID from service account for the creation of Docker container:

```bash
MY_CLOUD_BUILD_ACCOUNT_ID="$(gcloud iam service-accounts describe "docker-build@${MY_PROJECT_ID}.iam.gserviceaccount.com" --format="value(uniqueId)" --quiet)"
echo "Cloud Build account ID: '$MY_CLOUD_BUILD_ACCOUNT_ID'"
```

## Cloud SQL PostgreSQL Database

Create a PostgreSQL instance for LiteLLM data persistence:

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

Set the database password to your chosen password:

```bash
gcloud sql users set-password "postgres" \
    --instance="litellm-db" \
    --password="<YOUR_DB_PASSWORD>" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Create a database for LiteLLM:

```bash
gcloud sql databases create "litellm" \
    --instance="litellm-db" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Get the connection name for later use:

```bash
MY_DB_CONNECTION_NAME="$(gcloud sql instances describe litellm-db --format="value(connectionName)" --project="$MY_PROJECT_ID" --quiet)"
echo "Database connection name: '$MY_DB_CONNECTION_NAME'"
```

## Artifact Registry

Create Artifact Registry repositoriy for Docker container images:

> Only necessary if the repositoriy does not already exist in the project and region.

```bash
gcloud artifacts repositories create "$MY_ARTIFACT_REPOSITORY" \
    --repository-format="docker" \
    --description="Docker contrainer registry for LiteLLM proxy" \
    --location="$MY_REGION" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

## Storage Bucket

Create bucket to store Cloud Build logs:

```bash
gcloud storage buckets create "gs://docker-build-$MY_PROJECT_NUMBER" \
    --location="$MY_REGION" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Grant Cloud Build service account full access to bucket:

```bash
gcloud storage buckets add-iam-policy-binding "gs://docker-build-$MY_PROJECT_NUMBER" \
    --member="serviceAccount:docker-build@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/storage.admin" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

## Docker Container

Build Docker container image for LiteLLM proxy:

```bash
gcloud builds submit \
    --tag="${MY_REGION}-docker.pkg.dev/${MY_PROJECT_ID}/${MY_ARTIFACT_REPOSITORY}/litellm-proxy:latest" \
    --timeout="1h" \
    --region="$MY_REGION" \
    --service-account="projects/${MY_PROJECT_ID}/serviceAccounts/${MY_CLOUD_BUILD_ACCOUNT_ID}" \
    --gcs-source-staging-dir="gs://docker-build-$MY_PROJECT_NUMBER/source" \
    --gcs-log-dir="gs://docker-build-$MY_PROJECT_NUMBER" \
    --quiet
```

## Deploy LiteLLM Proxy

Generate a random string which acts as an OpenAI API key:

```bash
MY_RANDOM=$(openssl rand -hex 21)
echo "API key: 'sk-$MY_RANDOM'"
```

Deploy LiteLLM proxy Docker container image as public Cloud Run service:

```bash
gcloud run deploy "litellm-proxy" \
    --image="${MY_REGION}-docker.pkg.dev/${MY_PROJECT_ID}/${MY_ARTIFACT_REPOSITORY}/litellm-proxy:latest" \
    --memory=1024Mi \
    --cpu=1 \
    --cpu-boost \
    --port="8080" \
    --execution-environment=gen1 \
    --description="LiteLLM Proxy" \
    --region="$MY_REGION" \
    --set-env-vars="LITELLM_MODE=PRODUCTION,LITELLM_LOG=ERROR,OPENAI_API_KEY=${MY_OPENAI_API_KEY},LITELLM_MASTER_KEY=sk-${MY_RANDOM},DATABASE_URL=postgresql://postgres:<YOUR_DB_PASSWORD>@/${MY_PROJECT_ID}:${MY_REGION}:litellm-db/litellm" \
    --add-cloudsql-instances="${MY_DB_CONNECTION_NAME}" \
    --max-instances=1 \
    --allow-unauthenticated \
    --service-account "litellm-proxy@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
    --quiet
```

Done! Now wait three to five minutes and then you can test via the proxy the LLM models:

```bash
MY_LITELLM_PROXY_URL="$(gcloud run services list --filter="litellm-proxy" --format="value(URL)" --quiet)"
echo "API host: '$MY_LITELLM_PROXY_URL'"
echo "API key: 'sk-$MY_RANDOM'"
```

Test OpenAI GPT-5:

```bash
curl --location "${MY_LITELLM_PROXY_URL}/chat/completions" \
    --header "Content-Type: application/json" \
    --header "Authorization: Bearer sk-$MY_RANDOM" \
    --data '{"model": "gpt-5", "messages": [{"role": "user", "content": "what llm are you" }]}'
```

## [Optional] Deploy Lobe Chat

Build Docker container image for [🤯 Lobe Chat](https://github.com/lobehub/lobe-chat) frontend:

> ⏳ Will take approx. 15 minutes

```bash
MY_LOBE_CHAT_VERSION="v1.7.8"
gcloud builds submit "https://github.com/lobehub/lobe-chat.git" \
    --git-source-revision="$MY_LOBE_CHAT_VERSION" \
    --tag="${MY_REGION}-docker.pkg.dev/${MY_PROJECT_ID}/${MY_ARTIFACT_REPOSITORY}/lobe-chat:latest" \
    --timeout="1h" \
    --region="$MY_REGION" \
    --service-account="projects/${MY_PROJECT_ID}/serviceAccounts/${MY_CLOUD_BUILD_ACCOUNT_ID}" \
    --gcs-log-dir="gs://docker-build-$MY_PROJECT_NUMBER" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Create service account for Lobe Chat (Cloud Run):

```bash
gcloud iam service-accounts create "lobe-chat" \
    --description="Lobe Chat (Cloud Run)" \
    --display-name="Lobe Chat" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Generate a random string which acts as an password for Lobe Chat:

```bash
MY_ACCESS_CODE=$(openssl rand -hex 12)
echo "Password: '$MY_ACCESS_CODE'"
```

Deploy Cloud Run service with Lobe Chat frontend:

```bash
cp -f "lobe-chat-envs.yaml" "my-lobe-chat-envs.yaml"
echo >> "my-lobe-chat-envs.yaml"
echo "OPENAI_API_KEY: sk-${MY_RANDOM}" >> "my-lobe-chat-envs.yaml"
echo "OPENAI_PROXY_URL: $MY_LITELLM_PROXY_URL" >> "my-lobe-chat-envs.yaml"
echo "ACCESS_CODE: $MY_ACCESS_CODE" >> "my-lobe-chat-envs.yaml"
gcloud run deploy "lobe-chat" \
    --image="${MY_REGION}-docker.pkg.dev/${MY_PROJECT_ID}/${MY_ARTIFACT_REPOSITORY}/lobe-chat:latest" \
    --memory=512Mi \
    --cpu=1 \
    --cpu-boost \
    --execution-environment=gen1 \
    --description="Lobe Chat" \
    --region="$MY_REGION" \
    --env-vars-file="my-lobe-chat-envs.yaml" \
    --max-instances=1 \
    --allow-unauthenticated \
    --service-account "lobe-chat@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Done! You can now access the Lobe Chat frontend and chat with the LLM models:

```bash
MY_LOBECHAT_URL="$(gcloud run services list --filter="lobe-chat" --format="value(URL)" --quiet)"
echo "URL: '$MY_LOBECHAT_URL'"
echo "Password: '$MY_ACCESS_CODE'"
```

## Clean Up

If you want to delete everything, carry out the following steps.

[Optional] Delete Cloud Run service and service account from Lobe Chat frontend:

```bash
gcloud run services delete "lobe-chat" \
    --region="$MY_REGION" \
    --project="$MY_PROJECT_ID" \
    --quiet

gcloud iam service-accounts delete "lobe-chat@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Delete Cloud Run service and service account from LiteLLM proxy:

```bash
gcloud run services delete "litellm-proxy" \
    --region="$MY_REGION" \
    --project="$MY_PROJECT_ID" \
    --quiet

gcloud iam service-accounts delete "litellm-proxy@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Delete Artifact Registry repositoriy:

```bash
gcloud artifacts repositories delete "$MY_ARTIFACT_REPOSITORY" \
    --location="$MY_REGION" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Delete service account for the creation of Docker container (Cloud Build):

```bash
gcloud iam service-accounts delete "docker-build@${MY_PROJECT_ID}.iam.gserviceaccount.com" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Delete Cloud SQL instance:

```bash
gcloud sql instances delete "litellm-db" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

Delete bucket to store Cloud Build logs

```bash
gcloud storage rm -r "gs://docker-build-$MY_PROJECT_NUMBER" \
    --project="$MY_PROJECT_ID" \
    --quiet
```

## Organization Policies

If your project is a standard Google Cloud project, no adjustments should be necessary and all the steps mentioned should work without errors.

However, if your Google project or organization has been customized and Organization Policies have been rolled out, the following may cause problems. Make sure they are set as mentioned here for your project.

| Constraint                     | Value           |
|--------------------------------|-----------------|
| gcp.resourceLocations          | in:us-locations |
| run.allowedIngress             | is:all          |
| iam.allowedPolicyMemberDomains | allowAll        |

YAML for [Fabric FAST Project Module](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project#organization-policiesd):

```yaml
org_policies:
  "gcp.resourceLocations":
    rules:
    - allow:
        values:
        - in:us-locations
  "run.allowedIngress":
    rules:
    - allow:
        values:
        - is:all
  "iam.allowedPolicyMemberDomains":
    rules:
    - allow:
        all: true
```

## License

All files in this repository are under the [Apache License, Version 2.0](https://github.com/mhakankara/gcloud_litellm/blob/master/LICENSE) unless noted otherwise.