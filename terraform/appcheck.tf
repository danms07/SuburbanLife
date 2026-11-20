locals {
  recaptcha_allowed_domains = distinct(concat(
    [
      "${local.hosting_site_id}.web.app",
      "${local.hosting_site_id}.firebaseapp.com",
    ],
    var.custom_domains,
    var.recaptcha_extra_allowed_domains,
  ))

  app_check_protected_services = toset([
    "firestore.googleapis.com",
    "firebasestorage.googleapis.com",
    "firebasedatabase.googleapis.com",
    "identitytoolkit.googleapis.com",
  ])
}

resource "google_recaptcha_enterprise_key" "web" {
  provider = google-beta

  project         = local.project_id
  display_name    = var.recaptcha_display_name
  deletion_policy = var.deletion_policy

  web_settings {
    integration_type  = "SCORE"
    allow_all_domains = false
    allowed_domains   = local.recaptcha_allowed_domains
  }

  depends_on = [
    google_firebase_project.default,
    google_project_service.services["recaptchaenterprise.googleapis.com"],
  ]
}

# Wait briefly so App Check backend indexes newly registered Web/Android/Apple Firebase apps.
resource "time_sleep" "wait_for_app_check_apps" {
  create_duration = "30s"

  depends_on = [
    google_project_service.services["firebaseappcheck.googleapis.com"],
    google_project_service.services["recaptchaenterprise.googleapis.com"],
    google_project_service.services["playintegrity.googleapis.com"],
    google_firebase_web_app.default,
    google_firebase_android_app.default,
    google_firebase_apple_app.default,
  ]
}

resource "google_firebase_app_check_recaptcha_enterprise_config" "web" {
  provider = google-beta

  project         = local.project_id
  app_id          = google_firebase_web_app.default.app_id
  site_key        = google_recaptcha_enterprise_key.web.name
  token_ttl       = var.app_check_token_ttl
  deletion_policy = var.deletion_policy

  depends_on = [time_sleep.wait_for_app_check_apps]
}

resource "google_firebase_app_check_play_integrity_config" "android" {
  count    = length(local.normalized_android_sha256) > 0 ? 1 : 0
  provider = google-beta

  project         = local.project_id
  app_id          = google_firebase_android_app.default.app_id
  token_ttl       = var.app_check_token_ttl
  deletion_policy = var.deletion_policy

  depends_on = [time_sleep.wait_for_app_check_apps]

  lifecycle {
    precondition {
      condition     = length(google_firebase_android_app.default.sha256_hashes) > 0
      error_message = "At least one Android SHA-256 fingerprint is required for Play Integrity App Check."
    }
  }
}

resource "google_firebase_app_check_app_attest_config" "apple" {
  count    = var.ios_team_id != null && trimspace(var.ios_team_id) != "" ? 1 : 0
  provider = google-beta

  project         = local.project_id
  app_id          = google_firebase_apple_app.default.app_id
  token_ttl       = var.app_check_token_ttl
  deletion_policy = var.deletion_policy

  depends_on = [time_sleep.wait_for_app_check_apps]

  lifecycle {
    precondition {
      condition     = try(google_firebase_apple_app.default.team_id, "") != ""
      error_message = "ios_team_id must be configured on google_firebase_apple_app.default for Apple App Attest App Check."
    }
  }
}

# Configure App Check enforcement mode (defaults to UNENFORCED for safe initial rollout).
resource "google_firebase_app_check_service_config" "services" {
  provider = google-beta
  for_each = local.app_check_protected_services

  project          = local.project_id
  service_id       = each.key
  enforcement_mode = var.app_check_enforcement_mode
  deletion_policy  = var.deletion_policy

  depends_on = [
    google_project_service.services["firebaseappcheck.googleapis.com"],
    google_firebase_app_check_recaptcha_enterprise_config.web,
    google_firestore_database.default,
    google_firebase_database_instance.default,
    google_firebase_storage_default_bucket.default,
    google_identity_platform_config.default,
  ]
}
