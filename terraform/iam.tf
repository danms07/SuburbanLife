locals {
  functions_runtime_roles = toset([
    "roles/datastore.user",
    "roles/firebaseauth.admin",
    "roles/firebasedatabase.admin",
    "roles/firebasemessaging.admin",
    "roles/aiplatform.user",
    "roles/eventarc.eventReceiver",
    "roles/run.invoker",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])
}

# Ensure Eventarc and Cloud Storage Google-managed service agents exist with permissions
# required for Gen 2 Firestore, Storage, and Pub/Sub event triggers.
resource "google_project_service_identity" "eventarc_sa" {
  provider = google-beta

  project = local.project_id
  service = "eventarc.googleapis.com"

  depends_on = [google_project_service.services["eventarc.googleapis.com"]]
}

resource "google_project_iam_member" "eventarc_service_agent" {
  provider = google-beta

  project = local.project_id
  role    = "roles/eventarc.serviceAgent"
  member  = google_project_service_identity.eventarc_sa.member
}

data "google_storage_project_service_account" "gcs_account" {
  provider = google-beta

  project = local.project_id

  depends_on = [
    google_project_service.services["storage.googleapis.com"],
    google_firebase_storage_default_bucket.default,
  ]
}

resource "google_project_iam_member" "gcs_pubsub_publisher" {
  provider = google-beta

  project = local.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

# Dedicated least-privilege runtime service account for Gen 2 Cloud Functions.
resource "google_service_account" "functions_runtime" {
  provider = google-beta

  project         = local.project_id
  account_id      = var.functions_service_account_id
  display_name    = "Suburban Life Cloud Functions Runtime"
  description     = "Least-privilege runtime service account for Suburban Life Gen 2 Cloud Functions."
  deletion_policy = var.deletion_policy

  depends_on = [google_project_service.bootstrap]
}

resource "google_project_iam_member" "functions_runtime_roles" {
  provider = google-beta
  for_each = local.functions_runtime_roles

  project = local.project_id
  role    = each.key
  member  = google_service_account.functions_runtime.member
}

resource "google_storage_bucket_iam_member" "functions_runtime_bucket" {
  provider = google-beta

  bucket = google_firebase_storage_default_bucket.default.bucket[0].bucket_id
  role   = "roles/storage.objectAdmin"
  member = google_service_account.functions_runtime.member
}

# Wait for Compute Engine API initialization before reading the default Compute Engine SA.
resource "time_sleep" "wait_for_compute_default_sa" {
  count           = var.grant_default_compute_sa_permissions ? 1 : 0
  create_duration = "30s"

  depends_on = [google_project_service.services["compute.googleapis.com"]]
}

data "google_compute_default_service_account" "default" {
  count    = var.grant_default_compute_sa_permissions ? 1 : 0
  provider = google-beta

  project = local.project_id

  depends_on = [time_sleep.wait_for_compute_default_sa]
}

resource "google_project_iam_member" "default_compute_sa_roles" {
  provider = google-beta
  for_each = var.grant_default_compute_sa_permissions ? local.functions_runtime_roles : toset([])

  project = local.project_id
  role    = each.key
  member  = data.google_compute_default_service_account.default[0].member
}

resource "google_storage_bucket_iam_member" "default_compute_sa_bucket" {
  count    = var.grant_default_compute_sa_permissions ? 1 : 0
  provider = google-beta

  bucket = google_firebase_storage_default_bucket.default.bucket[0].bucket_id
  role   = "roles/storage.objectAdmin"
  member = data.google_compute_default_service_account.default[0].member
}

# Dedicated least-privilege service account for scripts/build_and_publish_docs.js.
resource "google_service_account" "docs_publisher" {
  count    = var.create_docs_publisher_service_account ? 1 : 0
  provider = google-beta

  project         = local.project_id
  account_id      = var.docs_publisher_service_account_id
  display_name    = "Suburban Life Docs Publisher"
  description     = "Least-privilege service account for scripts/build_and_publish_docs.js (Firestore + default Storage bucket)."
  deletion_policy = var.deletion_policy

  depends_on = [google_project_service.bootstrap]
}

resource "google_project_iam_member" "docs_publisher_firestore" {
  count    = var.create_docs_publisher_service_account ? 1 : 0
  provider = google-beta

  project = local.project_id
  role    = "roles/datastore.user"
  member  = google_service_account.docs_publisher[0].member
}

resource "google_storage_bucket_iam_member" "docs_publisher_bucket" {
  count    = var.create_docs_publisher_service_account ? 1 : 0
  provider = google-beta

  bucket = google_firebase_storage_default_bucket.default.bucket[0].bucket_id
  role   = "roles/storage.objectAdmin"
  member = google_service_account.docs_publisher[0].member
}

# Keyless OIDC Workload Identity Federation for GitHub Actions (no static SA keys created).
resource "google_iam_workload_identity_pool" "github_actions" {
  count    = var.github_repository != null ? 1 : 0
  provider = google-beta

  project                   = local.project_id
  workload_identity_pool_id = var.github_wif_pool_id
  display_name              = "GitHub Actions Pool"
  description               = "Keyless OIDC federation pool for GitHub Actions documentation publishing."
  deletion_policy           = var.deletion_policy

  depends_on = [
    google_project_service.services["iamcredentials.googleapis.com"],
    google_project_service.services["sts.googleapis.com"],
  ]
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  count    = var.github_repository != null ? 1 : 0
  provider = google-beta

  project                            = local.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions[0].workload_identity_pool_id
  workload_identity_pool_provider_id = var.github_wif_provider_id
  display_name                       = "GitHub Actions OIDC"
  description                        = "OIDC provider scoped to ${var.github_repository} branch ${var.github_branch}."
  deletion_policy                    = var.deletion_policy

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.ref == 'refs/heads/${var.github_branch}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "docs_publisher_wif" {
  count    = var.github_repository != null && var.create_docs_publisher_service_account ? 1 : 0
  provider = google-beta

  service_account_id = google_service_account.docs_publisher[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions[0].name}/attribute.repository/${var.github_repository}"
}
