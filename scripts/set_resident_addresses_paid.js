#!/usr/bin/env node

/**
 * Suburban Life - Batch Payment Status Maintenance Script
 * 
 * Purpose:
 *   Iterates across all addresses in the 'addresses' collection that are linked
 *   to an active resident, and updates their paymentStatus to 'paid'.
 * 
 * Features:
 *   - Local Emulator support (--emulator / -e)
 *   - Safe Dry-Run preview mode (--dry-run / -d)
 *   - Force re-write flag (--force / -f) to update even already 'paid' records
 *   - Firestore batch write chunking (400 items/batch to respect Firestore limits)
 *   - Bidirectional resident detection (addresses.residentUid and users.addressRef)
 *   - System address protection (safeguards admin_office)
 *   - Detailed summary reporting
 */

let admin;
try {
  admin = require('firebase-admin');
} catch (e) {
  try {
    admin = require('../functions/node_modules/firebase-admin');
  } catch (e2) {
    console.error('Error: firebase-admin module not found. Run "npm install" inside scripts/ or functions/.');
    process.exit(1);
  }
}

const path = require('path');
const fs = require('fs');

/**
 * Extracts a clean document ID from a Firestore DocumentReference or string path.
 * 
 * @param {object|string} addressRef 
 * @returns {string|null}
 */
function extractAddressId(addressRef) {
  if (!addressRef) return null;
  if (typeof addressRef === 'string') {
    return addressRef.startsWith('addresses/') ? addressRef.replace('addresses/', '') : addressRef;
  }
  if (typeof addressRef === 'object' && addressRef.id) {
    return addressRef.id;
  }
  return null;
}

/**
 * Builds an in-memory lookup map of addressId -> residentUserInfo from users collection.
 * 
 * @param {Array<object>} userDocs 
 * @returns {Map<string, object>}
 */
function buildResidentUsersMap(userDocs) {
  const residentMap = new Map();
  for (const doc of userDocs) {
    const data = typeof doc.data === 'function' ? doc.data() : doc;
    const uid = doc.id || data.uid;
    const role = (data.role || '').toLowerCase();

    // Map resident or roommate accounts referencing an address
    if (role === 'resident' || role === 'roommate') {
      const addressId = extractAddressId(data.addressRef);
      if (addressId && addressId !== 'admin_office') {
        // Primary residents take precedence over roommates in mapping
        if (!residentMap.has(addressId) || role === 'resident') {
          residentMap.set(addressId, {
            uid: uid,
            name: data.name || '',
            email: data.email || '',
            role: role,
          });
        }
      }
    }
  }
  return residentMap;
}

/**
 * Determines whether an address document is linked to a resident.
 * 
 * @param {object} addressData 
 * @param {string} addressId 
 * @param {Map<string, object>} residentUsersMap 
 * @returns {{ isLinked: boolean, residentUid: string|null, reason: string }}
 */
function isLinkedToResident(addressData, addressId, residentUsersMap = new Map()) {
  if (!addressData) {
    return { isLinked: false, residentUid: null, reason: 'Empty address document' };
  }

  // System administrative office is excluded
  if (
    addressId === 'admin_office' ||
    addressData.streetName === 'Admin office' ||
    addressData.streetName === 'Oficina de administración'
  ) {
    return { isLinked: false, residentUid: null, reason: 'Administrative office address' };
  }

  // 1. Direct link via residentUid on the address document
  if (
    addressData.residentUid &&
    typeof addressData.residentUid === 'string' &&
    addressData.residentUid.trim().length > 0
  ) {
    return {
      isLinked: true,
      residentUid: addressData.residentUid.trim(),
      reason: 'Linked via address.residentUid',
    };
  }

  // 2. Reverse link via resident user document in users collection
  if (residentUsersMap && residentUsersMap.has(addressId)) {
    const userInfo = residentUsersMap.get(addressId);
    return {
      isLinked: true,
      residentUid: userInfo.uid,
      reason: `Linked via resident user (${userInfo.email || userInfo.name || userInfo.uid})`,
    };
  }

  return { isLinked: false, residentUid: null, reason: 'Unclaimed / No resident associated' };
}

/**
 * Evaluates whether an address document requires a database update to 'paid'.
 * 
 * @param {object} addressData 
 * @param {string} addressId 
 * @param {Map<string, object>} residentUsersMap 
 * @param {{ force?: boolean }} options 
 * @returns {object}
 */
function evaluateAddressUpdate(addressData, addressId, residentUsersMap = new Map(), options = {}) {
  const { force = false } = options;
  const linkInfo = isLinkedToResident(addressData, addressId, residentUsersMap);

  const street = addressData?.streetName || 'Unknown Street';
  const number = addressData?.number !== undefined ? addressData.number : '?';
  const displayLabel = `${street} #${number} [${addressId}]`;

  if (!linkInfo.isLinked) {
    return {
      addressId,
      displayLabel,
      isLinked: false,
      needsUpdate: false,
      residentUid: null,
      currentStatus: addressData?.paymentStatus || 'unassigned',
      reason: linkInfo.reason,
    };
  }

  const currentStatus = addressData?.paymentStatus || 'unassigned';
  const isAlreadyPaid = typeof currentStatus === 'string' && currentStatus.toLowerCase() === 'paid';

  if (isAlreadyPaid && !force) {
    return {
      addressId,
      displayLabel,
      isLinked: true,
      needsUpdate: false,
      residentUid: linkInfo.residentUid,
      currentStatus,
      reason: "Already 'paid' (skipped)",
    };
  }

  return {
    addressId,
    displayLabel,
    isLinked: true,
    needsUpdate: true,
    residentUid: linkInfo.residentUid,
    currentStatus,
    reason: isAlreadyPaid ? "Forced refresh to 'paid'" : `Status update: '${currentStatus}' -> 'paid'`,
  };
}

/**
 * Constructs the Firestore update payload for an address.
 * 
 * @param {object} addressData 
 * @param {string} residentUid 
 * @param {any} serverTimestampValue 
 * @returns {object}
 */
function buildUpdatePayload(addressData, residentUid, serverTimestampValue) {
  const payload = {
    paymentStatus: 'paid',
    isWithinGracePeriod: true,
  };

  if (serverTimestampValue !== undefined) {
    payload.updatedAt = serverTimestampValue;
  }

  // Populate residentUid if it was missing on the address document
  const currentResidentUid = addressData?.residentUid;
  if ((!currentResidentUid || String(currentResidentUid).trim() === '') && residentUid) {
    payload.residentUid = residentUid;
  }

  return payload;
}

/**
 * Parses CLI command line arguments.
 * 
 * @param {Array<string>} argv 
 * @returns {object}
 */
function parseCliArgs(argv = process.argv.slice(2)) {
  const isEmulator = argv.includes('--emulator') || argv.includes('-e') || Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  const isDryRun = argv.includes('--dry-run') || argv.includes('-d');
  const isForce = argv.includes('--force') || argv.includes('-f');
  const isHelp = argv.includes('--help') || argv.includes('-h');
  const isQuiet = argv.includes('--quiet') || argv.includes('-q');
  const projectArg = (argv.find(a => a.startsWith('--project=')) || '').replace('--project=', '');
  const projectId = projectArg || process.env.GCLOUD_PROJECT || 'suburban-life-a67ab';

  return {
    isEmulator,
    isDryRun,
    isForce,
    isHelp,
    isQuiet,
    projectId,
  };
}

/**
 * Displays the CLI help guide.
 */
function printHelp() {
  console.log(`
===============================================================
       Suburban Life - Set Resident Addresses to Paid        
===============================================================

Usage:
  node scripts/set_resident_addresses_paid.js [options]

Description:
  Iterates across all addresses in the Firestore 'addresses' collection
  that are linked to a resident and updates their paymentStatus to 'paid'.

Options:
  --emulator, -e    Connect to local Firestore Emulator (127.0.0.1:8080).
                    Does not require serviceAccountKey.json.
  --dry-run, -d     Preview all matching addresses and status transitions
                    without making actual database modifications.
  --force, -f       Update all linked addresses, even if they are
                    already marked with paymentStatus: 'paid'.
  --project=<id>    Specify Google Cloud Project ID (default: suburban-life-a67ab).
  --quiet, -q       Suppress individual address item logs and display
                    only summary statistics.
  --help, -h        Show this help documentation.

Examples:
  # 1. Preview changes against local Firebase Emulator (recommended first step):
  node scripts/set_resident_addresses_paid.js --emulator --dry-run

  # 2. Apply updates in local Firebase Emulator:
  node scripts/set_resident_addresses_paid.js --emulator

  # 3. Preview changes in Production before executing writes:
  node scripts/set_resident_addresses_paid.js --dry-run

  # 4. Apply updates in Production:
  node scripts/set_resident_addresses_paid.js

  # 5. Force update all linked addresses in Production:
  node scripts/set_resident_addresses_paid.js --force
===============================================================
`);
}

/**
 * Initializes Firebase Admin SDK based on environment configuration.
 * 
 * @param {{ isEmulator: boolean, projectId: string }} config 
 * @returns {object} Firestore database instance
 */
function initializeFirebase(config) {
  const { isEmulator, projectId } = config;

  if (isEmulator) {
    process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
    process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';

    if (!admin.apps.length) {
      admin.initializeApp({ projectId: projectId });
    }
    console.log(`[EMULATOR MODE] Connected to Firestore Emulator: ${process.env.FIRESTORE_EMULATOR_HOST} (Project: ${projectId})`);
  } else {
    const serviceAccountPath = path.resolve(__dirname, 'serviceAccountKey.json');
    if (!admin.apps.length) {
      if (fs.existsSync(serviceAccountPath)) {
        const serviceAccount = require(serviceAccountPath);
        console.log('[PRODUCTION MODE] Connected with serviceAccountKey.json');
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
          projectId: projectId,
        });
      } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
        console.log('[PRODUCTION MODE] Connected with GOOGLE_APPLICATION_CREDENTIALS');
        admin.initializeApp({
          credential: admin.credential.applicationDefault(),
          projectId: projectId,
        });
      } else {
        console.error(`\n[CREDENTIAL ERROR] serviceAccountKey.json not found at: ${serviceAccountPath}`);
        console.error('To run against local Firebase Emulators without credentials, provide the "--emulator" flag:');
        console.error('  node scripts/set_resident_addresses_paid.js --emulator\n');
        process.exit(1);
      }
    }
  }

  return admin.firestore();
}

/**
 * Executes batched Firestore updates with chunking to stay well within limits.
 * 
 * @param {object} db 
 * @param {Array<{ ref: object, data: object }>} updatesToApply 
 * @returns {Promise<number>}
 */
async function applyBatchUpdates(db, updatesToApply) {
  const BATCH_SIZE = 400; // Limit is 500 in Firestore
  let committed = 0;

  for (let i = 0; i < updatesToApply.length; i += BATCH_SIZE) {
    const chunk = updatesToApply.slice(i, i + BATCH_SIZE);
    const batch = db.batch();

    for (const item of chunk) {
      batch.update(item.ref, item.data);
    }

    await batch.commit();
    committed += chunk.length;
    console.log(`  ✓ Committed batch: ${committed} of ${updatesToApply.length} addresses updated.`);
  }

  return committed;
}

/**
 * Main execution routine.
 */
async function run(customArgs) {
  const args = customArgs || parseCliArgs();

  if (args.isHelp) {
    printHelp();
    return { success: true, exitCode: 0 };
  }

  console.log(`
===============================================================
       Suburban Life - Set Resident Addresses to Paid        
===============================================================
Mode:     ${args.isEmulator ? 'EMULATOR' : 'PRODUCTION'}
Dry Run:  ${args.isDryRun ? 'YES (No database writes)' : 'NO (Live database updates)'}
Force:    ${args.isForce ? 'YES (Overwriting already paid records)' : 'NO (Skipping already paid records)'}
===============================================================
`);

  const startTime = Date.now();
  const db = initializeFirebase(args);

  // Step 1: Scan users to index resident account address links
  console.log('\n🔍 Step 1: Scanning resident user accounts in "users" collection...');
  let residentUsersMap = new Map();
  try {
    const usersSnap = await db.collection('users').get();
    residentUsersMap = buildResidentUsersMap(usersSnap.docs);
    console.log(`   Found ${usersSnap.size} total users (${residentUsersMap.size} resident address links indexed).`);
  } catch (err) {
    console.warn(`   ⚠️ Could not query "users" collection (${err.message}). Falling back to address document fields only.`);
  }

  // Step 2: Query all addresses
  console.log('\n🏘️  Step 2: Scanning all addresses in "addresses" collection...');
  const addressesSnap = await db.collection('addresses').get();
  console.log(`   Retrieved ${addressesSnap.size} address documents.`);

  // Step 3: Evaluate each address
  console.log('\n📊 Step 3: Evaluating payment status of residential addresses...');
  const updatesToApply = [];
  let unlinkedCount = 0;
  let alreadyPaidCount = 0;
  let needsUpdateCount = 0;

  const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();

  for (const doc of addressesSnap.docs) {
    const addressData = doc.data();
    const evaluation = evaluateAddressUpdate(addressData, doc.id, residentUsersMap, { force: args.isForce });

    if (!evaluation.isLinked) {
      unlinkedCount++;
      if (!args.isQuiet) {
        console.log(`   [SKIP - UNCLAIMED] ${evaluation.displayLabel} -> ${evaluation.reason}`);
      }
      continue;
    }

    if (!evaluation.needsUpdate) {
      alreadyPaidCount++;
      if (!args.isQuiet) {
        console.log(`   [SKIP - ALREADY PAID] ${evaluation.displayLabel} (Resident: ${evaluation.residentUid})`);
      }
      continue;
    }

    needsUpdateCount++;
    const payload = buildUpdatePayload(addressData, evaluation.residentUid, serverTimestamp);
    updatesToApply.push({
      ref: doc.ref,
      data: payload,
      displayLabel: evaluation.displayLabel,
      residentUid: evaluation.residentUid,
      currentStatus: evaluation.currentStatus,
    });

    if (!args.isQuiet) {
      const tag = args.isDryRun ? '[DRY RUN - WOULD UPDATE]' : '[QUEUED UPDATE]';
      console.log(`   ${tag} ${evaluation.displayLabel} | Resident: ${evaluation.residentUid} | Status: '${evaluation.currentStatus}' -> 'paid'`);
    }
  }

  // Step 4: Execute database writes (if not dry-run and updates exist)
  let committedCount = 0;
  if (args.isDryRun) {
    console.log(`\n🔒 Dry-run mode enabled: skipped ${updatesToApply.length} pending database write(s).`);
  } else if (updatesToApply.length > 0) {
    console.log(`\n💾 Step 4: Committing ${updatesToApply.length} address update(s) to Firestore...`);
    committedCount = await applyBatchUpdates(db, updatesToApply);
  } else {
    console.log('\n✨ No addresses required payment status updates.');
  }

  const durationSec = ((Date.now() - startTime) / 1000).toFixed(2);

  // Summary Report
  console.log(`
===============================================================
                       SUMMARY REPORT                          
===============================================================
Total Addresses Scanned:          ${addressesSnap.size}
Unclaimed / Excluded:             ${unlinkedCount}
Linked to Residents:              ${alreadyPaidCount + needsUpdateCount}
  - Already Marked as 'paid':     ${alreadyPaidCount}
  - Payment Status Updated:       ${args.isDryRun ? `${needsUpdateCount} (simulated)` : committedCount}
Execution Time:                   ${durationSec}s
Status:                           SUCCESS
===============================================================
`);

  return {
    success: true,
    totalScanned: addressesSnap.size,
    unlinkedCount,
    linkedCount: alreadyPaidCount + needsUpdateCount,
    alreadyPaidCount,
    updatedCount: args.isDryRun ? needsUpdateCount : committedCount,
    isDryRun: args.isDryRun,
  };
}

if (require.main === module) {
  run().catch((error) => {
    console.error('\n❌ Execution failed:', error.message || error);
    process.exit(1);
  });
}

module.exports = {
  extractAddressId,
  buildResidentUsersMap,
  isLinkedToResident,
  evaluateAddressUpdate,
  buildUpdatePayload,
  parseCliArgs,
  printHelp,
  run,
};
