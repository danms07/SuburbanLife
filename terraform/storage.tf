locals {
  storage_cors_origins = distinct(concat(
    [
      "https://${local.hosting_site_id}.web.app",
      "https://${local.hosting_site_id}.firebaseapp.com",
    ],
    [for d in var.custom_domains : "https://${d}"],
    var.extra_cors_origins,
  ))

  # Strict origin allow-list for Web GET/HEAD Transparency and media fetches (no wildcard origin).
  storage_cors_rules = [
    {
      origin = local.storage_cors_origins
      method = ["GET", "HEAD"]
      responseHeader = [
        "Content-Type",
        "Content-Length",
        "Content-Disposition",
        "Content-Range",
      ]
      maxAgeSeconds = 3600
    }
  ]
}

# Create after Firestore (default) so the project's default GCP resource location is settled consistently.
resource "google_firebase_storage_default_bucket" "default" {
  provider = google-beta

  project         = local.project_id
  location        = var.storage_location
  deletion_policy = var.deletion_policy

  depends_on = [
    google_firebase_project.default,
    google_firestore_database.default,
    google_project_service.services["firebasestorage.googleapis.com"],
    google_project_service.services["storage.googleapis.com"],
    google_project_service.services["storage-api.googleapis.com"],
  ]
}

resource "google_firebaserules_ruleset" "storage" {
  provider = google-beta

  project = local.project_id
  # Rulesets are immutable (ForceNew); DELETE allows create_before_destroy cleanup without PREVENT errors.
  deletion_policy = "DELETE"

  source {
    files {
      name    = "storage.rules"
      content = file("${path.module}/../storage.rules")
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_firebase_storage_default_bucket.default,
    google_project_service.services["firebaserules.googleapis.com"],
  ]
}

resource "google_firebaserules_release" "storage" {
  provider = google-beta

  project      = local.project_id
  name         = "firebase.storage/${google_firebase_storage_default_bucket.default.bucket[0].bucket_id}"
  ruleset_name = "projects/${local.project_id}/rulesets/${google_firebaserules_ruleset.storage.name}"
  # ABANDON keeps the active release intact in GCP during ForceNew replacement before DCL patches it in-place.
  deletion_policy = "ABANDON"

  lifecycle {
    replace_triggered_by = [
      google_firebaserules_ruleset.storage,
    ]
  }
}

# Opt-in provisioner applying ../storage_lifecycle.json (62d visitor media, 125d booking attachments)
# and strict Web CORS origins using gcloud CLI.
resource "terraform_data" "storage_bucket_config" {
  count = var.enable_storage_bucket_config_provisioner ? 1 : 0

  depends_on = [google_firebase_storage_default_bucket.default]

  triggers_replace = [
    google_firebase_storage_default_bucket.default.bucket[0].bucket_id,
    filesha256("${path.module}/../storage_lifecycle.json"),
    jsonencode(local.storage_cors_rules),
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-euo", "pipefail", "-c"]
    command     = <<-EOT
      cors_tmp="$(mktemp)"
      trap 'rm -f "$cors_tmp"' EXIT
      printf '%s' "$CORS_JSON" > "$cors_tmp"
      gcloud storage buckets update "gs://$BUCKET_ID" --lifecycle-file="$LIFECYCLE_FILE" --quiet
      gcloud storage buckets update "gs://$BUCKET_ID" --cors-file="$cors_tmp" --quiet
    EOT

    environment = {
      BUCKET_ID     = google_firebase_storage_default_bucket.default.bucket[0].bucket_id
      LIFECYCLE_FILE = abspath("${path.module}/../storage_lifecycle.json")
      CORS_JSON     = jsonencode(local.storage_cors_rules)
    }
  }
}
