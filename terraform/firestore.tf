locals {
  firestore_indexes_raw = jsondecode(file("${path.module}/../firestore.indexes.json"))

  firestore_indexes = {
    for idx in lookup(local.firestore_indexes_raw, "indexes", []) :
    join(":", [
      idx.collectionGroup,
      lookup(idx, "queryScope", "COLLECTION"),
      join(",", [
        for f in idx.fields :
        "${f.fieldPath}=${coalesce(lookup(f, "order", null), lookup(f, "arrayConfig", null), "NONE")}"
      ])
    ]) => idx
  }

  firestore_field_overrides = {
    for fo in lookup(local.firestore_indexes_raw, "fieldOverrides", []) :
    "${fo.collectionGroup}.${fo.fieldPath}" => fo
  }

  # Collections using `expireAt` native Firestore TTL retention policies.
  firestore_ttl_fields = toset([
    "access_logs.expireAt",
    "qr_codes.expireAt",
    "booking_attachments.expireAt",
  ])
}

resource "google_firestore_database" "default" {
  provider = google-beta

  project                           = local.project_id
  name                              = "(default)"
  location_id                       = var.firestore_location
  type                              = "FIRESTORE_NATIVE"
  concurrency_mode                  = "OPTIMISTIC"
  app_engine_integration_mode       = "DISABLED"
  point_in_time_recovery_enablement = var.firestore_point_in_time_recovery_enabled ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"
  delete_protection_state           = var.firestore_delete_protection_enabled ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  deletion_policy                   = var.deletion_policy

  depends_on = [
    google_firebase_project.default,
    google_project_service.services["firestore.googleapis.com"],
  ]
}

resource "google_firestore_index" "indexes" {
  provider = google-beta
  for_each = local.firestore_indexes

  project         = local.project_id
  database        = google_firestore_database.default.name
  collection      = each.value.collectionGroup
  query_scope     = lookup(each.value, "queryScope", "COLLECTION")
  deletion_policy = var.deletion_policy

  dynamic "fields" {
    for_each = each.value.fields
    content {
      field_path   = fields.value.fieldPath
      order        = lookup(fields.value, "order", null)
      array_config = lookup(fields.value, "arrayConfig", null)
    }
  }
}

# Disable built-in single-field indexes per firestore.indexes.json fieldOverrides
# and enable native Firestore TTL policies on expireAt fields.
resource "google_firestore_field" "overrides" {
  provider = google-beta
  for_each = local.firestore_field_overrides

  project         = local.project_id
  database        = google_firestore_database.default.name
  collection      = each.value.collectionGroup
  field           = each.value.fieldPath
  deletion_policy = var.deletion_policy

  index_config {
    dynamic "indexes" {
      for_each = lookup(each.value, "indexes", [])
      content {
        query_scope  = lookup(indexes.value, "queryScope", "COLLECTION")
        order        = lookup(indexes.value, "order", null)
        array_config = lookup(indexes.value, "arrayConfig", null)
      }
    }
  }

  dynamic "ttl_config" {
    for_each = contains(local.firestore_ttl_fields, each.key) ? [1] : []
    content {}
  }

  depends_on = [google_firestore_index.indexes]
}

resource "google_firebaserules_ruleset" "firestore" {
  provider = google-beta

  project = local.project_id
  # Rulesets are immutable (ForceNew); DELETE allows create_before_destroy cleanup without PREVENT errors.
  deletion_policy = "DELETE"

  source {
    files {
      name    = "firestore.rules"
      content = file("${path.module}/../firestore.rules")
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_firestore_database.default,
    google_project_service.services["firebaserules.googleapis.com"],
  ]
}

resource "google_firebaserules_release" "firestore" {
  provider = google-beta

  project      = local.project_id
  name         = "cloud.firestore"
  ruleset_name = "projects/${local.project_id}/rulesets/${google_firebaserules_ruleset.firestore.name}"
  # ABANDON keeps the active release intact in GCP during ForceNew replacement before DCL patches it in-place.
  deletion_policy = "ABANDON"

  lifecycle {
    replace_triggered_by = [
      google_firebaserules_ruleset.firestore,
    ]
  }
}
