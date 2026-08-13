let admin;
try {
  admin = require('firebase-admin');
} catch (e) {
  try {
    admin = require('../functions/node_modules/firebase-admin');
  } catch (e2) {
    console.error('Error: firebase-admin module not found. Run "npm install" inside functions/ or root directory.');
    process.exit(1);
  }
}

const path = require('path');
const fs = require('fs');

// Parse CLI flags
const args = process.argv.slice(2);
const isEmulator = args.includes('--emulator') || args.includes('-e') || Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST);
const cleanArgs = args.filter(a => !a.startsWith('--') && !a.startsWith('-'));

// Extract optional parameters
const passwordArg = (args.find(a => a.startsWith('--password=')) || '').replace('--password=', '') ||
                    (args.find(a => a.startsWith('-p=')) || '').replace('-p=', '') || 'Password123!';
const nameArg = (args.find(a => a.startsWith('--name=')) || '').replace('--name=', '');

const identifier = cleanArgs[0];
const role = cleanArgs[1];
const supportedRoles = ['admin', 'resident', 'guard', 'roommate'];

if (!identifier || !role) {
  console.log(`
===============================================================
       Suburban Life - Set User Role & Claims Utility          
===============================================================

Usage:
  node scripts/set_role.js <uid_or_email> <role> [options]

Arguments:
  <uid_or_email>   Target User UID or Email address (e.g. admin@example.com)
  <role>           Role to assign: admin, resident, guard, roommate

Options:
  --emulator, -e   Connect to local Firebase Emulators (Auth :9099, Firestore :8080)
                   No serviceAccountKey.json required in emulator mode!
  --password=<pwd> Password to auto-create user in emulator if not exists (default: Password123!)
  --name=<name>    Display name when auto-creating user

Examples:
  # In Firebase Emulator (Creates user if not exists & assigns admin claims + office address):
  node scripts/set_role.js admin@example.com admin --emulator --password=AdminPass123!

  # In Production:
  node scripts/set_role.js user@suburban.com resident
===============================================================
`);
  process.exit(1);
}

if (!supportedRoles.includes(role)) {
  console.error(`Error: "${role}" is not a supported role.`);
  console.error('Supported Roles: admin, resident, guard, roommate');
  process.exit(1);
}

// Initialize Firebase Admin
if (isEmulator) {
  process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
  process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
  const projectId = process.env.GCLOUD_PROJECT || 'privadacatania-3a7b8';
  
  console.log(`[EMULATOR MODE] Connecting to Auth: ${process.env.FIREBASE_AUTH_EMULATOR_HOST}, Firestore: ${process.env.FIRESTORE_EMULATOR_HOST}`);
  
  admin.initializeApp({
    projectId: projectId,
  });
} else {
  const serviceAccountPath = path.resolve(__dirname, 'serviceAccountKey.json');
  if (!fs.existsSync(serviceAccountPath)) {
    console.error(`[PRODUCTION ERROR] serviceAccountKey.json not found at ${serviceAccountPath}`);
    console.error('To run against local Firebase Emulators without serviceAccountKey, add the "--emulator" flag:');
    console.error(`  node scripts/set_role.js ${identifier} ${role} --emulator`);
    process.exit(1);
  }

  const serviceAccount = require(serviceAccountPath);
  console.log('[PRODUCTION MODE] Connecting to Firebase Production with serviceAccountKey.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

async function run() {
  try {
    let uid = identifier;
    let userRecord = null;

    if (identifier.includes('@')) {
      try {
        userRecord = await admin.auth().getUserByEmail(identifier);
        uid = userRecord.uid;
      } catch (err) {
        if (err.code === 'auth/user-not-found' && isEmulator) {
          console.log(`User "${identifier}" not found in Emulator Auth. Creating new user...`);
          userRecord = await admin.auth().createUser({
            email: identifier,
            password: passwordArg,
            displayName: nameArg || identifier.split('@')[0],
          });
          uid = userRecord.uid;
          console.log(`✓ Created Emulator user: ${identifier} (UID: ${uid}) with password: "${passwordArg}"`);
        } else {
          throw err;
        }
      }
    } else {
      userRecord = await admin.auth().getUser(uid);
    }

    // 1. Update Custom Claims in Firebase Auth
    const existingClaims = (userRecord && userRecord.customClaims) ? userRecord.customClaims : {};
    const claims = { ...existingClaims };
    
    // Clear other primary role flags to prevent ambiguity
    delete claims.admin;
    delete claims.resident;
    delete claims.guard;
    delete claims.roommate;
    claims[role] = true;

    await admin.auth().setCustomUserClaims(uid, claims);
    console.log(`✓ Custom Claims updated in Auth for: ${uid} (${userRecord.email || identifier})`);
    console.log('  Claims:', JSON.stringify(claims));

    // 2. Synchronize Firestore Document (if Firestore is available)
    try {
      const db = admin.firestore();
      let addressRef = null;

      if (role === 'admin') {
        // Ensure "admin_office" address exists in Firestore
        const adminOfficeRef = db.collection('addresses').doc('admin_office');
        const adminOfficeSnap = await adminOfficeRef.get();
        if (!adminOfficeSnap.exists) {
          await adminOfficeRef.set({
            id: 'admin_office',
            streetName: 'Admin office',
            number: 0,
            paymentStatus: 'paid',
            createdAt: Date.now(),
          });
          console.log('✓ Created fixed "Admin office" address in Firestore');
        }
        addressRef = adminOfficeRef;
      }

      const userDocUpdate = {
        uid: uid,
        email: userRecord.email || identifier,
        name: userRecord.displayName || nameArg || (userRecord.email || identifier).split('@')[0],
        role: role,
        updatedAt: Date.now(),
      };
      if (addressRef) {
        userDocUpdate.addressRef = addressRef;
      }

      await db.collection('users').doc(uid).set(userDocUpdate, { merge: true });
      console.log(`✓ Firestore document updated in users/${uid}`);
    } catch (fsErr) {
      console.warn('Note: Firestore synchronization skipped or failed:', fsErr.message);
    }

    console.log(`\nSUCCESS: User ${userRecord.email || identifier} is now configured as [${role.toUpperCase()}].\n`);
    process.exit(0);
  } catch (error) {
    console.error('Execution error:', error.message || error);
    process.exit(1);
  }
}

run();
