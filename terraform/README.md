# SuburbanLife — Terraform Infrastructure Setup

This directory provisions a complete Google Cloud & Firebase backend for **SuburbanLife** using the `hashicorp/google-beta` (`>= 8.0.0, < 9.0.0`) and `hashicorp/time` (`>= 0.12.0, < 1.0.0`) providers.

## What Is Provisioned

| File | Scope |
| :--- | :--- |
| [`versions.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/versions.tf) | Terraform `>= 1.6.0` and pinned provider constraints |
| [`providers.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/providers.tf) | Dual `google-beta` providers (`user_project_override = true` default + `no_user_project_override` for project/API bootstrap) |
| [`variables.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/variables.tf) | Validated inputs for new/existing projects, regions, signing hashes, App Check, IAM, and GitHub WIF |
| [`project.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/project.tf) | GCP project creation (`create_project = true`) or lookup (`false`), normalization helpers, and `check` assertions |
| [`apis.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/apis.tf) | Bootstrap APIs, Firebase project enablement, and all product APIs (Firestore, RTDB, Storage, Auth, App Check, FCM, Crashlytics, Gen 2 Cloud Functions, Cloud Scheduler, Vertex AI) |
| [`apps.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/apps.tf) | Web, Android (`com.example.suburban_life`), and Apple (`com.example.suburbanLife`) Firebase apps, Hosting site, and Web SDK config |
| [`auth.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/auth.tf) | Identity Platform Email/Password configuration + strict authorized domain allow-list |
| [`firestore.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/firestore.tf) | `(default)` `FIRESTORE_NATIVE` DB (PITR + delete protection), all composite indexes & single-field overrides from [`firestore.indexes.json`](file:///Users/menddaniel/gitProjects/SuburbanLife/firestore.indexes.json), native TTL policies (`access_logs.expireAt`, `qr_codes.expireAt`, `booking_attachments.expireAt`), and [`firestore.rules`](file:///Users/menddaniel/gitProjects/SuburbanLife/firestore.rules) release |
| [`database.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/database.tf) | Default Firebase Realtime Database (`us-central1`) + opt-in local CLI rules deployer for [`database.rules.json`](file:///Users/menddaniel/gitProjects/SuburbanLife/database.rules.json) |
| [`storage.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/storage.tf) | Default Cloud Storage bucket, [`storage.rules`](file:///Users/menddaniel/gitProjects/SuburbanLife/storage.rules) release, and opt-in `gcloud` lifecycle ([`storage_lifecycle.json`](file:///Users/menddaniel/gitProjects/SuburbanLife/storage_lifecycle.json)) + non-wildcard Web CORS deployer |
| [`appcheck.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/appcheck.tf) | Strict-domain reCAPTCHA Enterprise Web key + config, conditional Play Integrity / App Attest configs, and service enforcement across Firestore, Storage, RTDB, and Identity Toolkit |
| [`iam.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/iam.tf) | Eventarc & GCS service agents, least-privilege `functions_runtime` SA + bucket-scoped Storage IAM, optional default Compute SA compatibility binding, `docs_publisher` SA, and optional GitHub OIDC WIF pool/provider |
| [`outputs.tf`](file:///Users/menddaniel/gitProjects/SuburbanLife/terraform/outputs.tf) | App IDs, RTDB URL, reCAPTCHA Enterprise site key, strict Storage CORS JSON, SA emails, WIF provider name, and `next_steps` CLI guide |

## Prerequisites

1. **Terraform** `>= 1.6.0`
2. **Google Cloud CLI (`gcloud`)** authenticated with Application Default Credentials:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```
3. **Blaze Billing Account**: Cloud Functions Gen 2, Cloud Build, Artifact Registry, Eventarc, Cloud Scheduler, Identity Platform, and Vertex AI require an active Cloud Billing account (`billing_account` in `terraform.tfvars`).
4. **IAM Permissions for the Operator**:
   - Creating a new project: Billing Account User (`roles/billing.user`), Project Creator (`roles/resourcemanager.projectCreator`) on the org/folder (or project creation rights on a standalone account).
   - Adopting an existing project: Owner (`roles/owner`) or Editor + Security Admin / Firebase Admin so Terraform can enable APIs and manage IAM bindings.
5. **Optional CLIs**:
   - `firebase` (`firebase-tools`) if setting `enable_rtdb_rules_provisioner = true` or deploying Functions/Hosting.
   - `flutterfire` (`dart pub global activate flutterfire_cli`) for post-apply [`lib/firebase_options.dart`](file:///Users/menddaniel/gitProjects/SuburbanLife/lib/firebase_options.dart) generation.

> [!NOTE]
> The repository's [`firebase_options.dart`](file:///Users/menddaniel/gitProjects/SuburbanLife/lib/firebase_options.dart), [`app_config.dart`](file:///Users/menddaniel/gitProjects/SuburbanLife/lib/core/config/app_config.dart), and root [`storage_cors.json`](file:///Users/menddaniel/gitProjects/SuburbanLife/storage_cors.json) remain untouched by Terraform. Strict per-environment CORS is rendered dynamically via `outputs.storage_cors_json` / `enable_storage_bucket_config_provisioner`, and `flutterfire configure` updates client files cleanly post-apply.

## Quick Start (New Project)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars (set project_id, billing_account, optional signing hashes/Team ID)

terraform init
terraform plan
terraform apply
```

Review post-apply commands at any time with:

```bash
terraform output -raw next_steps
```

## Optional Local CLI Provisioners

Terraform native Google/Firebase providers do not manage **RTDB security rules** or update the **default Firebase bucket's lifecycle/CORS** natively when using `google_firebase_storage_default_bucket` without importing the underlying `google_storage_bucket`. Two opt-in flags cover these cleanly without forcing CLI dependencies during normal `plan`/`apply`:

- `enable_rtdb_rules_provisioner = true` — runs `firebase deploy --only database --project "$PROJECT_ID" --config firebase.json.template --non-interactive` after RTDB creation. Requires `firebase login`.
- `enable_storage_bucket_config_provisioner = true` — runs `gcloud storage buckets update` to apply [`storage_lifecycle.json`](file:///Users/menddaniel/gitProjects/SuburbanLife/storage_lifecycle.json) and strict non-wildcard Hosting CORS origins from `storage_cors_rules`. Requires `gcloud` auth.

Leave both `false` (default) to run those commands manually using `terraform output -raw next_steps`.

## Adopting an Existing Project

To bring an existing SuburbanLife Firebase/GCP project under Terraform management, set `create_project = false` and `project_id = "<existing-id>"` in `terraform.tfvars`, then import existing singletons before running `terraform apply`:

```bash
cd terraform
terraform init

# Core Firebase project & Auth
terraform import google_firebase_project.default "projects/<project_id>"
terraform import google_identity_platform_config.default "projects/<project_id>/config"

# Apps & Hosting site
terraform import google_firebase_web_app.default "projects/<project_id>/webApps/<web_app_id>"
terraform import google_firebase_android_app.default "projects/<project_id>/androidApps/<android_app_id>"
terraform import google_firebase_apple_app.default "projects/<project_id>/iosApps/<apple_app_id>"
terraform import google_firebase_hosting_site.default "projects/<project_id>/sites/<site_id>"

# Databases & Storage
terraform import google_firestore_database.default "projects/<project_id>/databases/(default)"
terraform import google_firebase_database_instance.default "projects/<project_id>/locations/<rtdb_region>/instances/<instance_id>"
terraform import google_firebase_storage_default_bucket.default "projects/<project_id>/defaultBucket"

# Rules releases
terraform import google_firebaserules_release.firestore "projects/<project_id>/releases/cloud.firestore"
terraform import google_firebaserules_release.storage "projects/<project_id>/releases/firebase.storage/<bucket_id>"
```

Then run `terraform plan` to review any missing composite indexes, TTL policies, App Check configs, or IAM bindings.

## Post-Apply Manual / App Steps

1. **Client Firebase Config**: Run `flutterfire configure --project=<project_id>` from the repository root to regenerate [`lib/firebase_options.dart`](file:///Users/menddaniel/gitProjects/SuburbanLife/lib/firebase_options.dart), `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist`.
2. **Runtime Constants**: Update [`lib/core/config/app_config.dart`](file:///Users/menddaniel/gitProjects/SuburbanLife/lib/core/config/app_config.dart):
   - `recaptchaSiteKey` -> `terraform output -raw recaptcha_enterprise_site_key`
   - `rtdbDatabaseUrl` -> `terraform output -raw rtdb_database_url`
   - `webPushVapidKey` -> Firebase Console **Project Settings -> Cloud Messaging -> Web Push certificates** (no public GCP/Terraform API exists to generate VAPID key pairs automatically).
3. **Cloud Functions Gen 2 Runtime SA**:
   - Recommended (least privilege): pass `serviceAccount: '<functions_runtime_service_account_email>'` in `setGlobalOptions(...)` inside [`functions/index.js`](file:///Users/menddaniel/gitProjects/SuburbanLife/functions/index.js) before deploying Functions.
   - Compatibility fallback: set `grant_default_compute_sa_permissions = true` in `terraform.tfvars` if deploying Functions under the default Compute Engine service account.
4. **Google Analytics & Crashlytics**: Enable Google Analytics linkage in the Firebase Console if desired, and trigger an initial mobile build/run for Crashlytics onboarding (`firebasecrashlytics.googleapis.com` is pre-enabled).
5. **Docs Publishing Automation (Keyless OIDC vs Secret JSON)**:
   - Terraform creates no static service account private keys (`google_service_account_key` is intentionally omitted).
   - Setting `github_repository = "owner/repo"` provisions a Workload Identity Pool & OIDC Provider scoped to `github_branch` (`main`) bound to `suburban-life-docs-publisher`. Note that [`docs_pipeline.yml`](file:///Users/menddaniel/gitProjects/SuburbanLife/.github/workflows/docs_pipeline.yml) and [`scripts/build_and_publish_docs.js`](file:///Users/menddaniel/gitProjects/SuburbanLife/scripts/build_and_publish_docs.js) currently expect a `FIREBASE_SERVICE_ACCOUNT` JSON credential and would need a small update to use `google-github-actions/auth` + `applicationDefault()` if switching from secret JSON to keyless WIF.
6. **App Check Enforcement Rollout**: Keep `app_check_enforcement_mode = "UNENFORCED"` until Web, Android (`android_sha256_hashes` + Play Integrity), and iOS (`ios_team_id` + App Attest) builds are live and verified in Firebase App Check metrics, then set `app_check_enforcement_mode = "ENFORCED"` and re-apply.
