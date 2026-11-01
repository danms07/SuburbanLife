#!/bin/bash
set -e

echo "==============================================================="
echo "       Suburban Life - Automated Pre-Rollout Test Suite      "
echo "==============================================================="

# 1. Check for firebase CLI
if ! command -v firebase &> /dev/null; then
    echo "❌ Error: Firebase CLI (firebase) is not installed or not in PATH."
    exit 1
fi

# 2. Check for flutter CLI
if ! command -v flutter &> /dev/null; then
    echo "❌ Error: Flutter CLI (flutter) is not installed or not in PATH."
    exit 1
fi

echo "🚀 Starting Firebase Emulators & Running Automated Test Suite..."
echo ""

# Execute emulator lifecycle with automated seeding, Cloud Functions & Security Rules verification, CLI script tests, and full Flutter suite
firebase emulators:exec --project=demo-suburban \
  "node scripts/seed_emulator.js && FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=demo-suburban npm --prefix functions test && npm --prefix scripts test && flutter test"

echo ""
echo "==============================================================="
echo "🎉 All Pre-Rollout Automated Tests Passed Successfully!"
echo "==============================================================="
