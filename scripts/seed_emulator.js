/**
 * Automated Firebase Database Seed Script (Emulator & Staging/Remote)
 * 
 * Provisions default test data into Firebase Auth and Firestore:
 * - Addresses parsed from addresses_import.csv
 * - Administrator account (admin@example.com / AdminPass123!)
 * - Resident account (resident@test.com / TestPass123!) linked to 1st Avenue #99
 * - Roommate candidate account (roommate@test.com / RoommatePass123!)
 * - Security guard account (guard@test.com / GuardPass123!)
 * - App settings (cutoff day, grace period, timezone, rejection reasons)
 * - Neighborhood facilities with operating hours and approval instructions
 * - Sample community announcement
 * 
 * Usage:
 *   node scripts/seed_emulator.js             # Seeds local Firebase Emulators (default)
 *   node scripts/seed_emulator.js --remote    # Seeds linked remote/staging Firebase project
 */

const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const isRemote = args.includes('--remote') || args.includes('--staging') || args.includes('--prod');

let admin;
try {
  admin = require('firebase-admin');
} catch (e) {
  try {
    admin = require('../functions/node_modules/firebase-admin');
  } catch (e2) {
    console.error('Error: firebase-admin module not found.');
    process.exit(1);
  }
}

// Resolve project ID from GCLOUD_PROJECT env or .firebaserc default
function resolveProjectId() {
  if (process.env.GCLOUD_PROJECT) {
    return process.env.GCLOUD_PROJECT;
  }
  try {
    const rcPath = path.join(__dirname, '../.firebaserc');
    if (fs.existsSync(rcPath)) {
      const rc = JSON.parse(fs.readFileSync(rcPath, 'utf8'));
      if (rc.projects && rc.projects.default) {
        return rc.projects.default;
      }
    }
  } catch (_) {}
  return 'demo-suburban';
}

let targetProjectId = resolveProjectId();

if (isRemote) {
  // Ensure emulator host variables do not intercept remote calls
  delete process.env.FIRESTORE_EMULATOR_HOST;
  delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
  delete process.env.FIREBASE_STORAGE_EMULATOR_HOST;

  const serviceAccountPath = path.resolve(__dirname, 'serviceAccountKey.json');
  if (!admin.apps.length) {
    if (fs.existsSync(serviceAccountPath)) {
      const serviceAccount = require(serviceAccountPath);
      targetProjectId = serviceAccount.project_id || targetProjectId;
      console.log(`🌐 [REMOTE MODE] Connecting with serviceAccountKey.json (Project: ${targetProjectId})`);
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: targetProjectId,
      });
    } else {
      console.log(`🌐 [REMOTE MODE] Connecting with Application Default Credentials (Project: ${targetProjectId})`);
      admin.initializeApp({
        credential: admin.credential.applicationDefault(),
        projectId: targetProjectId,
      });
    }
  }
} else {
  process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
  process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
  process.env.FIREBASE_STORAGE_EMULATOR_HOST = process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:9199';

  // Initialize Firebase Admin without credentials in emulator mode
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: targetProjectId,
    });
  }
}

const auth = admin.auth();
const db = admin.firestore();

async function createOrUpdateUser(email, password, displayName, role) {
  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(email);
    await auth.updateUser(userRecord.uid, {
      password: password,
      displayName: displayName,
    });
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      userRecord = await auth.createUser({
        email: email,
        password: password,
        displayName: displayName,
      });
    } else {
      throw e;
    }
  }

  // Set custom claims (both boolean flag for Firestore rules/client and role string)
  await auth.setCustomUserClaims(userRecord.uid, {
    [role]: true,
    role: role,
  });
  return userRecord;
}

async function seedAddresses() {
  console.log('📦 Seeding physical addresses from CSV...');
  const csvPath = path.join(__dirname, '../addresses_import.csv');
  if (!fs.existsSync(csvPath)) {
    console.warn('⚠️ addresses_import.csv not found, skipping CSV import.');
    return;
  }

  const csvContent = fs.readFileSync(csvPath, 'utf8');
  const lines = csvContent.split('\n');
  let addressCount = 0;

  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    const match = line.match(/(".*?"|[^",\s]+)(?=\s*,|\s*$)/g);
    if (!match || match.length < 3) continue;

    const streetName = match[0].replace(/"/g, '').trim();
    const initialNum = parseInt(match[1], 10);
    const finalNum = parseInt(match[2], 10);
    const exclusionsStr = match[3] ? match[3].replace(/"/g, '') : '';
    const exclusions = exclusionsStr ? exclusionsStr.split(',').map(n => parseInt(n.trim(), 10)) : [];

    const batch = db.batch();
    for (let num = initialNum; num <= finalNum; num++) {
      if (exclusions.includes(num)) continue;
      const docId = `${streetName.replace(/\s+/g, '_')}_${num}`;
      const docRef = db.collection('addresses').doc(docId);
      batch.set(docRef, {
        streetName: streetName,
        number: num,
        paymentStatus: 'paid',
        hasActiveSanctions: false,
        activeSanctionsCount: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      addressCount++;
    }
    await batch.commit();
  }

  // Ensure Admin Office address exists
  await db.collection('addresses').doc('admin_office').set({
    streetName: 'Admin office',
    number: 0,
    paymentStatus: 'paid',
    hasActiveSanctions: false,
    activeSanctionsCount: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  console.log(`✅ Seeded ${addressCount + 1} addresses.`);
}

async function seedAppSettings() {
  console.log('⚙️ Seeding app settings...');
  await db.collection('config').doc('app_settings').set({
    paymentCutoffDay: 1,
    gracePeriodDays: 5,
    timeZone: 'America/Mexico_City',
    paymentRejectionReasons: [
      'Illegible receipt / Comprobante ilegible',
      'Amount does not match / El monto no coincide',
      'Invalid reference or folio / Folio o referencia inválida',
    ],
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log('✅ App settings seeded.');
}

async function seedFacilities() {
  console.log('🏢 Seeding community facilities...');
  const facilities = [
    {
      id: 'multipurpose_room',
      name: 'Multipurpose Room / Salón',
      isUnique: true,
      quantity: 1,
      cooldownUnit: 'days',
      cooldownValue: 7,
      anticipationUnit: 'hours',
      anticipationValue: 24,
      openingTime: '08:00',
      closingTime: '22:00',
      presetApprovalMessage: 'Please pick up the keys at the guardhouse 15 minutes before your event. / Favor de recoger las llaves en caseta 15 minutos antes de su evento.',
    },
    {
      id: 'bbq_grill_1',
      name: 'BBQ Grill 1 / Asador 1',
      isUnique: true,
      quantity: 1,
      cooldownUnit: 'days',
      cooldownValue: 3,
      anticipationUnit: 'unrestricted',
      anticipationValue: 0,
      openingTime: '09:00',
      closingTime: '21:00',
      presetApprovalMessage: 'Remember to leave the grill clean after use. / Recuerde dejar el asador limpio después de su uso.',
    },
    {
      id: 'bbq_grill_2',
      name: 'BBQ Grill 2 / Asador 2',
      isUnique: true,
      quantity: 1,
      cooldownUnit: 'days',
      cooldownValue: 3,
      anticipationUnit: 'unrestricted',
      anticipationValue: 0,
      openingTime: '09:00',
      closingTime: '21:00',
      presetApprovalMessage: 'Remember to leave the grill clean after use. / Recuerde dejar el asador limpio después de su uso.',
    },
    {
      id: 'bicycle',
      name: 'Community Bicycles / Bicicletas',
      isUnique: false,
      quantity: 4,
      cooldownUnit: 'unrestricted',
      cooldownValue: 0,
      anticipationUnit: 'unrestricted',
      anticipationValue: 0,
      openingTime: '06:00',
      closingTime: '20:00',
      presetApprovalMessage: 'Request helmets and locks at the guardhouse. / Solicite cascos y candados en caseta.',
    },
  ];

  const batch = db.batch();
  for (const f of facilities) {
    batch.set(db.collection('facilities').doc(f.id), f, { merge: true });
  }
  await batch.commit();
  console.log(`✅ Seeded ${facilities.length} facilities.`);
}

async function seedUsers() {
  console.log('👥 Seeding default users...');

  // 1. Admin User
  const adminOfficeRef = db.collection('addresses').doc('admin_office');
  const adminUser = await createOrUpdateUser('admin@example.com', 'AdminPass123!', 'System Administrator', 'admin');
  await db.collection('users').doc(adminUser.uid).set({
    uid: adminUser.uid,
    name: 'System Administrator',
    email: 'admin@example.com',
    role: 'admin',
    addressRef: adminOfficeRef,
    createdAt: Date.now(),
  }, { merge: true });

  // 2. Primary Resident User linked to 1st Avenue #99
  const residentAddressRef = db.collection('addresses').doc('1st_Avenue_99');
  const residentUser = await createOrUpdateUser('resident@test.com', 'TestPass123!', 'Carlos Gomez', 'resident');
  
  // Set delivery date to 3 months ago so payment status engine has a historical timeline
  const now = new Date();
  const deliveryDate = new Date(now.getFullYear(), now.getMonth() - 3, 1);

  await residentAddressRef.set({
    streetName: '1st Avenue',
    number: 99,
    residentUid: residentUser.uid,
    deliveryDate: admin.firestore.Timestamp.fromDate(deliveryDate),
    paymentStatus: 'paid',
    hasActiveSanctions: false,
    activeSanctionsCount: 0,
  }, { merge: true });

  await db.collection('users').doc(residentUser.uid).set({
    uid: residentUser.uid,
    name: 'Carlos Gomez',
    email: 'resident@test.com',
    role: 'resident',
    addressRef: residentAddressRef,
    familyMembers: [],
    createdAt: Date.now(),
  }, { merge: true });

  // 3. Roommate Candidate User (unlinked initially)
  const roommateUser = await createOrUpdateUser('roommate@test.com', 'RoommatePass123!', 'Ana Gomez', 'roommate');
  await db.collection('users').doc(roommateUser.uid).set({
    uid: roommateUser.uid,
    name: 'Ana Gomez',
    email: 'roommate@test.com',
    role: 'roommate',
    addressRef: null,
    createdAt: Date.now(),
  }, { merge: true });

  // 4. Security Guard User
  const guardUser = await createOrUpdateUser('guard@test.com', 'GuardPass123!', 'Roberto Vigilante', 'guard');
  await db.collection('users').doc(guardUser.uid).set({
    uid: guardUser.uid,
    name: 'Roberto Vigilante',
    email: 'guard@test.com',
    role: 'guard',
    addressRef: null,
    createdAt: Date.now(),
  }, { merge: true });

  console.log('✅ Users seeded:');
  console.log(`   - Admin:    admin@example.com / AdminPass123! (UID: ${adminUser.uid})`);
  console.log(`   - Resident: resident@test.com / TestPass123! (UID: ${residentUser.uid})`);
  console.log(`   - Roommate: roommate@test.com / RoommatePass123! (UID: ${roommateUser.uid})`);
  console.log(`   - Guard:    guard@test.com / GuardPass123! (UID: ${guardUser.uid})`);

  return { adminUser, residentUser, roommateUser, guardUser };
}

async function seedAnnouncements(adminUid) {
  console.log('📢 Seeding sample announcements...');
  await db.collection('announcements').doc('welcome_announcement').set({
    title: 'Welcome to Suburban Life! / ¡Bienvenidos a Suburban Life!',
    content: 'The community portal is now active. You can book facilities, upload payment receipts, and generate visitor QR codes.',
    translatedTitles: {
      en: 'Welcome to Suburban Life!',
      es: '¡Bienvenidos a Suburban Life!',
    },
    translatedContents: {
      en: 'The community portal is now active. You can book facilities, upload payment receipts, and generate visitor QR codes.',
      es: 'El portal comunitario ya está activo. Puedes reservar amenidades, subir comprobantes de pago y generar códigos QR para visitantes.',
    },
    creatorUid: adminUid,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    targetAudience: 'all',
    readBy: [],
  }, { merge: true });
  console.log('✅ Sample announcements seeded.');
}

async function main() {
  const modeLabel = isRemote ? 'Remote/Staging' : 'Emulator';
  console.log(`🚀 Starting Firebase ${modeLabel} Database Seeding (Project: ${targetProjectId})...`);
  try {
    await seedAddresses();
    await seedAppSettings();
    await seedFacilities();
    const { adminUser } = await seedUsers();
    await seedAnnouncements(adminUser.uid);
    console.log(`🎉 ${modeLabel} seeding completed successfully!`);
    process.exit(0);
  } catch (error) {
    console.error('❌ Seeding failed:', error);
    process.exit(1);
  }
}

main();
