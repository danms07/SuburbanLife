let admin;

function getAdmin() {
  if (admin) return admin;
  const loadSubmodule = (sub) => {
    try {
      return require(`firebase-admin/${sub}`);
    } catch (e) {
      try {
        return require(`../functions/node_modules/firebase-admin/lib/${sub}`);
      } catch (e2) {
        throw new Error('firebase-admin module not found. Run "npm install" inside functions/ or scripts/ directory.');
      }
    }
  };
  const { initializeApp, getApp, getApps, cert, applicationDefault } = loadSubmodule('app');
  const { getFirestore, FieldValue, Timestamp } = loadSubmodule('firestore');
  const { getAuth } = loadSubmodule('auth');
  admin = {
    initializeApp,
    app: getApp,
    get apps() {
      return getApps();
    },
    credential: {
      cert,
      applicationDefault,
    },
    firestore: Object.assign(() => getFirestore(), {
      FieldValue,
      Timestamp,
    }),
    auth: () => getAuth(),
  };
  return admin;
}

const path = require('path');
const fs = require('fs');

const SUPPORTED_ROLES = ['admin', 'resident', 'guard', 'roommate'];

function parseCliArgs(argv) {
  const args = argv.slice(2);
  const showHelp = args.includes('--help') || args.includes('-h');
  const isEmulator =
    args.includes('--emulator') ||
    args.includes('-e') ||
    Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST);
  const withResident =
    args.includes('--with-resident') ||
    args.includes('--keep-resident') ||
    args.includes('--dual');

  const cleanArgs = args.filter((a) => !a.startsWith('--') && !a.startsWith('-'));

  const passwordArg =
    (args.find((a) => a.startsWith('--password=')) || '').replace('--password=', '') ||
    (args.find((a) => a.startsWith('-p=')) || '').replace('-p=', '') ||
    'Password123!';
  const nameArg = (args.find((a) => a.startsWith('--name=')) || '').replace('--name=', '');

  return {
    identifier: cleanArgs[0] || '',
    role: cleanArgs[1] || '',
    isEmulator,
    withResident,
    passwordArg,
    nameArg,
    showHelp,
  };
}

function printHelp() {
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
  --emulator, -e     Connect to local Firebase Emulators (Auth :9099, Firestore :8080)
                     No serviceAccountKey.json required in emulator mode!
  --with-resident    Also keep/grant the 'resident' claim when setting 'admin' role
  --password=<pwd>   Password to auto-create user in emulator if not exists (default: Password123!)
  --name=<name>      Display name when auto-creating user

Examples:
  # In Firebase Emulator (Creates user if not exists & assigns admin claims + office address):
  node scripts/set_role.js admin@example.com admin --emulator --password=AdminPass123!

  # In Production (Promotes existing resident to admin while keeping their house & resident view switch):
  node scripts/set_role.js user@suburban.com admin
===============================================================
`);
}

function extractAddressId(addressRef) {
  if (!addressRef) return null;
  if (typeof addressRef === 'string') {
    const trimmed = addressRef.trim();
    if (!trimmed) return null;
    const parts = trimmed.split('/');
    return parts[parts.length - 1] || null;
  }
  if (typeof addressRef === 'object') {
    if (typeof addressRef.id === 'string' && addressRef.id.trim()) {
      return addressRef.id.trim();
    }
    if (typeof addressRef.path === 'string' && addressRef.path.trim()) {
      const parts = addressRef.path.trim().split('/');
      return parts[parts.length - 1] || null;
    }
  }
  return null;
}

function isAdminOfficeAddress(addressId, addressData) {
  if (addressId === 'admin_office') return true;
  const street = (addressData?.streetName || '').toString().trim().toLowerCase();
  return street === 'admin office' || street === 'oficina de administración';
}

function buildRoleClaims(existingClaims, role, hasResidentialAddress, withResident = false) {
  const claims = { ...(existingClaims || {}) };

  delete claims.admin;
  delete claims.resident;
  delete claims.guard;
  delete claims.roommate;

  claims[role] = true;

  if (role === 'admin' && (hasResidentialAddress || withResident)) {
    claims.resident = true;
  }

  return claims;
}

function resolveUserAddressUpdate(role, currentAddressRef, currentAddressData, ownedResidentialRefs, adminOfficeRef) {
  const currentAddressId = extractAddressId(currentAddressRef);
  const currentIsAdminOffice = isAdminOfficeAddress(currentAddressId, currentAddressData);
  const currentIsResidential = Boolean(currentAddressRef && !currentIsAdminOffice);
  const primaryOwnedRef = Array.isArray(ownedResidentialRefs) && ownedResidentialRefs.length > 0
    ? ownedResidentialRefs[0]
    : null;

  if (role === 'admin') {
    if (currentIsResidential) {
      return { shouldUpdate: false, addressRef: currentAddressRef, source: 'existing_residential' };
    }
    if (primaryOwnedRef) {
      return { shouldUpdate: true, addressRef: primaryOwnedRef, source: 'owned_residential' };
    }
    return { shouldUpdate: true, addressRef: adminOfficeRef, source: 'admin_office' };
  }

  if (role === 'resident') {
    if (currentIsResidential) {
      return { shouldUpdate: false, addressRef: currentAddressRef, source: 'existing_residential' };
    }
    if (primaryOwnedRef) {
      return { shouldUpdate: true, addressRef: primaryOwnedRef, source: 'owned_residential' };
    }
    if (currentIsAdminOffice) {
      return { shouldUpdate: true, addressRef: null, source: 'cleared_admin_office' };
    }
    return { shouldUpdate: false, addressRef: null, source: 'unchanged' };
  }

  if (role === 'guard' || role === 'roommate') {
    if (currentIsAdminOffice) {
      return { shouldUpdate: true, addressRef: null, source: 'cleared_admin_office' };
    }
    return { shouldUpdate: false, addressRef: currentAddressRef || null, source: 'unchanged' };
  }

  return { shouldUpdate: false, addressRef: currentAddressRef || null, source: 'unchanged' };
}

function initializeFirebaseAdmin(isEmulator, identifier, role) {
  const fbAdmin = getAdmin();
  if (fbAdmin.apps.length > 0) return fbAdmin;

  if (isEmulator) {
    process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
    process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
    const projectId = process.env.GCLOUD_PROJECT || 'suburban-life-a67ab';

    console.log(`[EMULATOR MODE] Connecting to Auth: ${process.env.FIREBASE_AUTH_EMULATOR_HOST}, Firestore: ${process.env.FIRESTORE_EMULATOR_HOST}`);

    fbAdmin.initializeApp({
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
    fbAdmin.initializeApp({
      credential: fbAdmin.credential.cert(serviceAccount),
    });
  }
  return fbAdmin;
}

async function run(argv = process.argv) {
  const parsed = parseCliArgs(argv);
  const { identifier, role, isEmulator, withResident, passwordArg, nameArg, showHelp } = parsed;

  if (showHelp || !identifier || !role) {
    printHelp();
    process.exit(showHelp ? 0 : 1);
  }

  if (!SUPPORTED_ROLES.includes(role)) {
    console.error(`Error: "${role}" is not a supported role.`);
    console.error('Supported Roles: admin, resident, guard, roommate');
    process.exit(1);
  }

  const fbAdmin = initializeFirebaseAdmin(isEmulator, identifier, role);

  try {
    let uid = identifier;
    let userRecord = null;

    if (identifier.includes('@')) {
      try {
        userRecord = await fbAdmin.auth().getUserByEmail(identifier);
        uid = userRecord.uid;
      } catch (err) {
        if (err.code === 'auth/user-not-found' && isEmulator) {
          console.log(`User "${identifier}" not found in Emulator Auth. Creating new user...`);
          userRecord = await fbAdmin.auth().createUser({
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
      userRecord = await fbAdmin.auth().getUser(uid);
    }

    let db = null;
    let existingUserData = null;
    let currentAddressRef = null;
    let currentAddressData = null;
    let ownedResidentialRefs = [];
    let hasResidentialAddress = false;

    // 1. Inspect Firestore residential state before assigning claims
    try {
      db = fbAdmin.firestore();
      const userSnap = await db.collection('users').doc(uid).get();
      if (userSnap.exists) {
        existingUserData = userSnap.data();
        currentAddressRef = existingUserData.addressRef || null;
      }

      if (currentAddressRef) {
        const currentAddrId = extractAddressId(currentAddressRef);
        if (currentAddrId) {
          const currentAddrSnap = await db.collection('addresses').doc(currentAddrId).get();
          if (currentAddrSnap.exists) {
            currentAddressData = currentAddrSnap.data();
          }
        }
      }

      const ownedSnap = await db.collection('addresses').where('residentUid', '==', uid).get();
      ownedResidentialRefs = ownedSnap.docs
        .filter((doc) => !isAdminOfficeAddress(doc.id, doc.data()))
        .map((doc) => doc.ref);

      const currentAddressId = extractAddressId(currentAddressRef);
      const currentIsResidential = Boolean(
        currentAddressRef && !isAdminOfficeAddress(currentAddressId, currentAddressData)
      );
      hasResidentialAddress = currentIsResidential || ownedResidentialRefs.length > 0;
    } catch (fsReadErr) {
      console.warn('Note: Firestore pre-check skipped or failed:', fsReadErr.message);
    }

    // 2. Update Custom Claims in Firebase Auth
    const existingClaims = (userRecord && userRecord.customClaims) ? userRecord.customClaims : {};
    const claims = buildRoleClaims(existingClaims, role, hasResidentialAddress, withResident);

    await fbAdmin.auth().setCustomUserClaims(uid, claims);
    console.log(`✓ Custom Claims updated in Auth for: ${uid} (${userRecord.email || identifier})`);
    console.log('  Claims:', JSON.stringify(claims));

    // 3. Synchronize Firestore Document (if Firestore is available)
    if (db) {
      try {
        let adminOfficeRef = null;
        if (role === 'admin' && !hasResidentialAddress) {
          adminOfficeRef = db.collection('addresses').doc('admin_office');
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
        }

        const addressDecision = resolveUserAddressUpdate(
          role,
          currentAddressRef,
          currentAddressData,
          ownedResidentialRefs,
          adminOfficeRef
        );

        const userDocUpdate = {
          uid: uid,
          email: userRecord.email || existingUserData?.email || identifier,
          name: userRecord.displayName || existingUserData?.name || nameArg || (userRecord.email || identifier).split('@')[0],
          role: role,
          updatedAt: Date.now(),
        };

        if (addressDecision.shouldUpdate) {
          userDocUpdate.addressRef = addressDecision.addressRef;
        }

        await db.collection('users').doc(uid).set(userDocUpdate, { merge: true });
        console.log(`✓ Firestore document updated in users/${uid} (address source: ${addressDecision.source})`);
      } catch (fsErr) {
        console.warn('Note: Firestore synchronization skipped or failed:', fsErr.message);
      }
    }

    console.log(`\nSUCCESS: User ${userRecord.email || identifier} is now configured as [${role.toUpperCase()}].`);
    console.log('Note: If the user is currently signed in, ask them to restart the app or sign out and back in to refresh their ID token.\n');
    if (require.main === module) {
      process.exit(0);
    }
  } catch (error) {
    console.error('Execution error:', error.message || error);
    if (require.main === module) {
      process.exit(1);
    }
    throw error;
  }
}

if (require.main === module) {
  run();
}

module.exports = {
  SUPPORTED_ROLES,
  parseCliArgs,
  extractAddressId,
  isAdminOfficeAddress,
  buildRoleClaims,
  resolveUserAddressUpdate,
  run,
};
