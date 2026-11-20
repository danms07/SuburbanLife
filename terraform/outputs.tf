output "project_id" {
  description = "Provisioned GCP/Firebase project ID."
  value       = local.project_id
}

output "project_number" {
  description = "Provisioned GCP/Firebase numeric project number."
  value       = local.project_number
}

output "hosting_site_id" {
  description = "Firebase Hosting default site ID."
  value       = google_firebase_hosting_site.default.site_id
}

output "hosting_default_url" {
  description = "Default Firebase Hosting HTTPS URL."
  value       = google_firebase_hosting_site.default.default_url
}

output "web_app_id" {
  description = "Firebase Web App ID."
  value       = google_firebase_web_app.default.app_id
}

output "android_app_id" {
  description = "Firebase Android App ID."
  value       = google_firebase_android_app.default.app_id
}

output "apple_app_id" {
  description = "Firebase Apple/iOS App ID."
  value       = google_firebase_apple_app.default.app_id
}

output "web_app_config" {
  description = "Generated Firebase Web SDK configuration values (use flutterfire configure for multi-platform lib/firebase_options.dart)."
  value = {
    api_key             = data.google_firebase_web_app_config.default.api_key
    auth_domain         = data.google_firebase_web_app_config.default.auth_domain
    database_url        = data.google_firebase_web_app_config.default.database_url
    storage_bucket      = data.google_firebase_web_app_config.default.storage_bucket
    location_id         = data.google_firebase_web_app_config.default.location_id
    messaging_sender_id = data.google_firebase_web_app_config.default.messaging_sender_id
    measurement_id      = data.google_firebase_web_app_config.default.measurement_id
  }
  sensitive = true
}

output "firestore_database_name" {
  description = "Cloud Firestore database name."
  value       = google_firestore_database.default.name
}

output "rtdb_instance_id" {
  description = "Firebase Realtime Database default instance ID."
  value       = google_firebase_database_instance.default.instance_id
}

output "rtdb_database_url" {
  description = "Firebase Realtime Database URL for lib/core/config/app_config.dart (rtdbDatabaseUrl)."
  value       = google_firebase_database_instance.default.database_url
}

output "storage_bucket_id" {
  description = "Default Firebase Cloud Storage bucket name."
  value       = google_firebase_storage_default_bucket.default.bucket[0].bucket_id
}

output "storage_cors_json" {
  description = "Strict non-wildcard Cloud Storage CORS policy JSON ready for gcloud storage buckets update --cors-file."
  value       = jsonencode(local.storage_cors_rules)
}

output "recaptcha_enterprise_site_key" {
  description = "reCAPTCHA Enterprise Web site key for lib/core/config/app_config.dart (AppConfig.recaptchaSiteKey)."
  value       = google_recaptcha_enterprise_key.web.name
}

output "functions_runtime_service_account_email" {
  description = "Dedicated least-privilege runtime service account email for Gen 2 Cloud Functions."
  value       = google_service_account.functions_runtime.email
}

output "docs_publisher_service_account_email" {
  description = "Least-privilege service account email for scripts/build_and_publish_docs.js."
  value       = var.create_docs_publisher_service_account ? google_service_account.docs_publisher[0].email : null
}

output "github_workload_identity_provider" {
  description = "Full Workload Identity Provider resource name for google-github-actions/auth (when github_repository is configured)."
  value       = var.github_repository != null ? google_iam_workload_identity_pool_provider.github_actions[0].name : null
}

output "next_steps" {
  description = "Post-apply CLI steps (run from terraform/ or repo root as noted) to complete client SDK generation, RTDB rules, bucket lifecycle/CORS, Functions deployment, and Web Push VAPID setup."
  value       = <<-EOT
    1. Generate multi-platform Firebase options (run from repo root):
       flutterfire configure --project=${local.project_id}

    2. Update lib/core/config/app_config.dart:
       - recaptchaSiteKey = '${google_recaptcha_enterprise_key.web.name}'
       - rtdbDatabaseUrl  = '${google_firebase_database_instance.default.database_url}'
       - webPushVapidKey  = '<Firebase Console -> Project Settings -> Cloud Messaging -> Web Push certificates>'

    3. Deploy RTDB rules from repo root (unless enable_rtdb_rules_provisioner = true):
       firebase deploy --only database --project ${local.project_id} --config firebase.json.template

    4. Apply Storage lifecycle and strict CORS rules from repo root (unless enable_storage_bucket_config_provisioner = true):
       cors_tmp="$(mktemp)"
       terraform -chdir=terraform output -raw storage_cors_json > "$cors_tmp"
       gcloud storage buckets update gs://${google_firebase_storage_default_bucket.default.bucket[0].bucket_id} --lifecycle-file=./storage_lifecycle.json
       gcloud storage buckets update gs://${google_firebase_storage_default_bucket.default.bucket[0].bucket_id} --cors-file="$cors_tmp"
       rm -f "$cors_tmp"

    5. Deploy Cloud Functions Gen 2 & Hosting from repo root:
       - Set serviceAccount: '${google_service_account.functions_runtime.email}' in setGlobalOptions(...) in functions/index.js (or temporarily set grant_default_compute_sa_permissions = true in terraform.tfvars).
       firebase deploy --only functions,hosting --project ${local.project_id}

    6. Optionally switch app_check_enforcement_mode = "ENFORCED" once Web, Play Integrity (SHA-256), and App Attest (Apple Team ID) clients are rolled out.
  EOT
}
