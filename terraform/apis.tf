locals {
  bootstrap_apis = toset([
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "firebase.googleapis.com",
    "iam.googleapis.com",
  ])

  base_product_apis = [
    # Core databases, rules, and storage
    "firestore.googleapis.com",
    "firebasedatabase.googleapis.com",
    "firebaserules.googleapis.com",
    "firebasestorage.googleapis.com",
    "storage.googleapis.com",
    "storage-api.googleapis.com",

    # Authentication and API key provisioning
    "identitytoolkit.googleapis.com",
    "securetoken.googleapis.com",
    "apikeys.googleapis.com",

    # Hosting and App Check
    "firebasehosting.googleapis.com",
    "firebaseappcheck.googleapis.com",
    "recaptchaenterprise.googleapis.com",
    "playintegrity.googleapis.com",

    # Messaging, installations, and Crashlytics
    "fcm.googleapis.com",
    "fcmregistrations.googleapis.com",
    "firebasecloudmessaging.googleapis.com",
    "firebaseinstallations.googleapis.com",
    "firebasecrashlytics.googleapis.com",

    # Cloud Functions Gen 2, triggers, scheduler, and Vertex AI Gemini translations
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "eventarcpublishing.googleapis.com",
    "pubsub.googleapis.com",
    "cloudscheduler.googleapis.com",
    "aiplatform.googleapis.com",

    # Observability
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]

  conditional_apis = concat(
    var.grant_default_compute_sa_permissions ? ["compute.googleapis.com"] : [],
    var.github_repository != null ? ["sts.googleapis.com", "iamcredentials.googleapis.com"] : [],
  )

  product_apis = toset(concat(local.base_product_apis, local.conditional_apis))
}

# Bootstrap APIs are enabled without user_project_override before Quota/ServiceUsage checks exist.
resource "google_project_service" "bootstrap" {
  provider = google-beta.no_user_project_override
  for_each = local.bootstrap_apis

  project                    = local.project_id
  service                    = each.key
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Attach Firebase to the target GCP project.
resource "google_firebase_project" "default" {
  provider = google-beta

  project         = local.project_id
  deletion_policy = local.singleton_deletion_policy

  depends_on = [google_project_service.bootstrap]
}

# Enable all Firebase, Cloud Functions Gen 2, Vertex AI, App Check, and IAM APIs.
resource "google_project_service" "services" {
  provider = google-beta.no_user_project_override
  for_each = local.product_apis

  project                    = local.project_id
  service                    = each.key
  disable_on_destroy         = false
  disable_dependent_services = false

  depends_on = [
    google_project_service.bootstrap,
    google_firebase_project.default,
  ]
}
