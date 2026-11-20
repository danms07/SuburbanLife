# Allow firebasedatabase.googleapis.com activation to propagate before instance creation.
resource "time_sleep" "wait_for_rtdb_api" {
  create_duration = "60s"

  depends_on = [
    google_firebase_project.default,
    google_project_service.services["firebasedatabase.googleapis.com"],
  ]
}

resource "google_firebase_database_instance" "default" {
  provider = google-beta

  project         = local.project_id
  region          = var.rtdb_region
  instance_id     = local.rtdb_instance_id
  type            = "DEFAULT_DATABASE"
  desired_state   = "ACTIVE"
  deletion_policy = local.singleton_deletion_policy

  depends_on = [time_sleep.wait_for_rtdb_api]
}

# Firebase Realtime Database rules are not supported by google_firebaserules_release.
# Enable enable_rtdb_rules_provisioner when firebase CLI is authenticated to deploy ../database.rules.json.
resource "terraform_data" "rtdb_rules" {
  count = var.enable_rtdb_rules_provisioner ? 1 : 0

  depends_on = [google_firebase_database_instance.default]

  triggers_replace = [
    google_firebase_database_instance.default.instance_id,
    filesha256("${path.module}/../database.rules.json"),
  ]

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    interpreter = ["bash", "-euo", "pipefail", "-c"]
    command     = "firebase deploy --only database --project \"$PROJECT_ID\" --config firebase.json.template --non-interactive"

    environment = {
      PROJECT_ID = local.project_id
    }
  }
}
