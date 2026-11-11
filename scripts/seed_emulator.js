/**
 * Automated Firebase Database Seed Script (Emulator & Staging/Remote)
 *
 * Provisions default test data into Firebase Auth, Firestore, and Storage:
 * - Addresses parsed from addresses_import.csv
 * - Administrator account (admin@example.com / AdminPass123!)
 * - Resident accounts (resident@test.com / resident2@test.com)
 * - Roommate candidate account (roommate@test.com / RoommatePass123!)
 * - Security guard account (guard@test.com / GuardPass123!)
 * - App settings (cutoff day, grace period, timezone, rejection reasons)
 * - Neighborhood facilities with operating hours and approval instructions
 * - Sample proof-of-payment PNG receipts, pending payments, and sanctions
 * - Sample community announcement
 *
 * Usage:
 *   node scripts/seed_emulator.js             # Seeds local Firebase Emulators (default)
 *   node scripts/seed_emulator.js --remote    # Seeds linked remote/staging Firebase project
 */

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const args = process.argv.slice(2);
const isRemote = args.includes('--remote') || args.includes('--staging') || args.includes('--prod');

const loadSubmodule = (sub) => {
  try {
    return require(`firebase-admin/${sub}`);
  } catch (e) {
    try {
      return require(`../functions/node_modules/firebase-admin/lib/${sub}`);
    } catch (e2) {
      console.error('Error: firebase-admin module not found.');
      process.exit(1);
    }
  }
};
const { initializeApp, getApp, getApps, cert, applicationDefault } = loadSubmodule('app');
const { getFirestore, FieldValue, Timestamp } = loadSubmodule('firestore');
const { getAuth } = loadSubmodule('auth');
const { getStorage } = loadSubmodule('storage');
const admin = {
  initializeApp,
  app: getApp,
  get apps() {
    return getApps();
  },
  credential: { cert, applicationDefault },
  firestore: Object.assign(() => getFirestore(), { FieldValue, Timestamp }),
  auth: () => getAuth(),
  storage: () => getStorage(),
};

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
let storageBucket = process.env.FIREBASE_STORAGE_BUCKET || `${targetProjectId}.firebasestorage.app`;

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
      storageBucket = process.env.FIREBASE_STORAGE_BUCKET || `${targetProjectId}.firebasestorage.app`;
      console.log(`🌐 [REMOTE MODE] Connecting with serviceAccountKey.json (Project: ${targetProjectId})`);
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: targetProjectId,
        storageBucket,
      });
    } else {
      console.log(`🌐 [REMOTE MODE] Connecting with Application Default Credentials (Project: ${targetProjectId})`);
      admin.initializeApp({
        credential: admin.credential.applicationDefault(),
        projectId: targetProjectId,
        storageBucket,
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
      storageBucket,
    });
  }
}

const auth = admin.auth();
const db = admin.firestore();
const storage = admin.storage();

/**
 * Generates a valid PNG buffer representing a visual receipt
 * with a distinct Suburban Life blue header bar at top, green seal at bottom-right,
 * and horizontal text lines so 90-degree rotations in the full-screen viewer are clearly visible.
 */
function generateSampleReceiptPng(width = 360, height = 520) {
  const crcTable = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    crcTable[n] = c;
  }

  function crc32(buf) {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) {
      c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    }
    return (c ^ 0xffffffff) >>> 0;
  }

  function makeChunk(type, data) {
    const lenBuf = Buffer.alloc(4);
    lenBuf.writeUInt32BE(data.length, 0);
    const typeBuf = Buffer.from(type, 'ascii');
    const crcBuf = Buffer.alloc(4);
    const combined = Buffer.concat([typeBuf, data]);
    crcBuf.writeUInt32BE(crc32(combined), 0);
    return Buffer.concat([lenBuf, typeBuf, data, crcBuf]);
  }

  const rawData = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    const rowStart = y * (width * 4 + 1);
    rawData[rowStart] = 0; // filter type 0
    for (let x = 0; x < width; x++) {
      const px = rowStart + 1 + x * 4;
      let r = 248, g = 249, b = 252;

      // Outer border
      if (x < 8 || x >= width - 8 || y < 8 || y >= height - 8) {
        r = 40; g = 100; b = 190;
      }
      // Top Suburban Life blue header banner (distinct top orientation marker)
      else if (y >= 8 && y < 95) {
        r = 40; g = 100; b = 190;
        if (x >= 28 && x <= 75 && y >= 28 && y <= 75) {
          r = 255; g = 255; b = 255;
        }
        if (y >= 85) {
          r = 245; g = 158; b = 11;
        }
      }
      // Green amount highlight box in upper-middle
      else if (x >= 32 && x < width - 32 && y >= 125 && y < 185) {
        r = 220; g = 247; b = 230;
        if (y < 130 || y >= 180 || x < 37 || x >= width - 37) {
          r = 37; g = 211; b = 102;
        }
      }
      // Simulated receipt text rows
      else if (
        x >= 36 &&
        x < width - 60 &&
        ((y >= 220 && y < 234) ||
          (y >= 255 && y < 269) ||
          (y >= 290 && y < 304) ||
          (y >= 325 && y < 339) ||
          (y >= 360 && y < 374))
      ) {
        r = 115; g = 120; b = 135;
      }
      // Distinct green approval stamp circle in bottom-right corner
      else {
        const dx = x - (width - 85);
        const dy = y - (height - 85);
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < 42 && dist > 30) {
          r = 37; g = 211; b = 102;
        } else if (dist <= 22) {
          r = 200; g = 245; b = 215;
        }
      }

      rawData[px] = r;
      rawData[px + 1] = g;
      rawData[px + 2] = b;
      rawData[px + 3] = 255;
    }
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const idat = zlib.deflateSync(rawData);
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

  return Buffer.concat([
    signature,
    makeChunk('IHDR', ihdr),
    makeChunk('IDAT', idat),
    makeChunk('IEND', Buffer.alloc(0)),
  ]);
}

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

  // Set custom claims (both boolean flag for Firestore/Storage rules and role string)
  if (role) {
    await auth.setCustomUserClaims(userRecord.uid, {
      [role]: true,
      role: role,
    });
  } else {
    await auth.setCustomUserClaims(userRecord.uid, {});
  }
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
      restrictionType: 'cooldown',
      cooldownUnit: 'days',
      cooldownValue: 7,
      quotaPeriod: 'unrestricted',
      quotaLimit: 0,
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
      restrictionType: 'cooldown',
      cooldownUnit: 'hours',
      cooldownValue: 4,
      quotaPeriod: 'unrestricted',
      quotaLimit: 0,
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
      restrictionType: 'quota',
      cooldownUnit: 'unrestricted',
      cooldownValue: 0,
      quotaPeriod: 'monthly',
      quotaLimit: 2,
      anticipationUnit: 'unrestricted',
      anticipationValue: 0,
      openingTime: '09:00',
      closingTime: '21:00',
      presetApprovalMessage: 'Remember to leave the grill clean after use. / Recuerde dejar el asador limpio después de su uso.',
    },
    {
      id: 'paddle_court',
      name: 'Paddle Court / Cancha de Pádel',
      isUnique: true,
      quantity: 1,
      restrictionType: 'quota',
      cooldownUnit: 'unrestricted',
      cooldownValue: 0,
      quotaPeriod: 'daily',
      quotaLimit: 1,
      anticipationUnit: 'unrestricted',
      anticipationValue: 0,
      openingTime: '07:00',
      closingTime: '22:00',
      presetApprovalMessage: 'Court lights turn off automatically at 22:00. / Las luces de la cancha se apagan automáticamente a las 22:00.',
    },
    {
      id: 'bicycle',
      name: 'Community Bicycles / Bicicletas',
      isUnique: false,
      quantity: 4,
      restrictionType: 'unrestricted',
      cooldownUnit: 'unrestricted',
      cooldownValue: 0,
      quotaPeriod: 'unrestricted',
      quotaLimit: 0,
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

function buildStorageUrl(filePath, token) {
  const encodedPath = encodeURIComponent(filePath);
  if (isRemote) {
    return `https://firebasestorage.googleapis.com/v0/b/${storageBucket}/o/${encodedPath}?alt=media&token=${token}`;
  }
  return `http://127.0.0.1:9199/v0/b/${storageBucket}/o/${encodedPath}?alt=media&token=${token}`;
}

async function seedUsersAndSamplePayments() {
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
    paymentStatus: 'pending',
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

  // 5. Upload generated sample proof-of-payment PNGs & seed pending payment requests
  console.log('🧾 Generating & uploading sample proof of payment receipts...');
  const pngBuffer = generateSampleReceiptPng(360, 520);
  const filePath = `payments/${residentUser.uid}/sample_receipt_october.png`;
  const bucket = storage.bucket(storageBucket);
  await bucket.file(filePath).save(pngBuffer, {
    contentType: 'image/png',
    metadata: {
      metadata: {
        uploaderUid: residentUser.uid,
        firebaseStorageDownloadTokens: 'sample-receipt-token-001',
      },
    },
  });
  const receiptUrl = buildStorageUrl(filePath, 'sample-receipt-token-001');

  const currentPeriod = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  await db.collection('payments').doc('sample_pending_payment_1').set({
    id: 'sample_pending_payment_1',
    addressRef: residentAddressRef,
    residentUid: residentUser.uid,
    uploaderUid: residentUser.uid,
    amount: 1500.0,
    concept: 'monthly quota',
    folio: 'BBVA-849201',
    periods: [currentPeriod],
    period: currentPeriod,
    status: 'pending',
    receiptUrl: receiptUrl,
    paymentDate: Date.now(),
    timestamp: Date.now(),
  });

  // 6. Second Resident User & second pending payment (landscape-oriented receipt to test rotation)
  const secondAddressRef = db.collection('addresses').doc('2nd_Avenue_105');
  const secondResident = await createOrUpdateUser('resident2@test.com', 'TestPass123!', 'Maria Lopez', 'resident');

  await secondAddressRef.set({
    streetName: '2nd Avenue',
    number: 105,
    residentUid: secondResident.uid,
    deliveryDate: admin.firestore.Timestamp.fromDate(deliveryDate),
    paymentStatus: 'pending',
  }, { merge: true });

  await db.collection('users').doc(secondResident.uid).set({
    uid: secondResident.uid,
    name: 'Maria Lopez',
    email: 'resident2@test.com',
    role: 'resident',
    addressRef: secondAddressRef,
    createdAt: Date.now(),
  }, { merge: true });

  const pngBuffer2 = generateSampleReceiptPng(520, 360);
  const filePath2 = `payments/${secondResident.uid}/sample_receipt_november_landscape.png`;
  await bucket.file(filePath2).save(pngBuffer2, {
    contentType: 'image/png',
    metadata: {
      metadata: {
        uploaderUid: secondResident.uid,
        firebaseStorageDownloadTokens: 'sample-receipt-token-002',
      },
    },
  });
  const receiptUrl2 = buildStorageUrl(filePath2, 'sample-receipt-token-002');

  const nextMonthDate = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const nextPeriod = `${nextMonthDate.getFullYear()}-${String(nextMonthDate.getMonth() + 1).padStart(2, '0')}`;

  await db.collection('payments').doc('sample_pending_payment_2').set({
    id: 'sample_pending_payment_2',
    addressRef: secondAddressRef,
    residentUid: secondResident.uid,
    uploaderUid: secondResident.uid,
    amount: 3000.0,
    concept: 'monthly quota',
    folio: 'SANTANDER-391044',
    periods: [currentPeriod, nextPeriod],
    period: currentPeriod,
    status: 'pending',
    receiptUrl: receiptUrl2,
    paymentDate: Date.now() - 3600 * 1000,
    timestamp: Date.now(),
  });

  // 7. Seed Sanctions (1 active sanction on 1st Avenue #99, and 1 sanction under payment review on 2nd Avenue #105)
  console.log('⚖️ Seeding sample sanctions and sanction payment...');
  const evidencePath1 = 'sanctions/1st_Avenue_99/sample_sanction_evidence_1.png';
  await bucket.file(evidencePath1).save(pngBuffer, {
    contentType: 'image/png',
    metadata: {
      metadata: {
        uploaderUid: adminUser.uid,
        firebaseStorageDownloadTokens: 'sample-sanction-token-001',
      },
    },
  });
  const evidenceUrl1 = buildStorageUrl(evidencePath1, 'sample-sanction-token-001');

  await db.collection('sanctions').doc('sample_sanction_1').set({
    id: 'sample_sanction_1',
    addressRef: residentAddressRef,
    residentUid: residentUser.uid,
    authorizedUids: [residentUser.uid],
    reason: 'Excessive noise after 11:00 PM / Ruido excesivo después de las 11:00 PM',
    amount: 800.0,
    evidenceUrl: evidenceUrl1,
    status: 'active',
    createdAt: Date.now() - 86400 * 1000,
    createdBy: adminUser.uid,
  });

  const evidencePath2 = 'sanctions/2nd_Avenue_105/sample_sanction_evidence_2.png';
  await bucket.file(evidencePath2).save(pngBuffer2, {
    contentType: 'image/png',
    metadata: {
      metadata: {
        uploaderUid: adminUser.uid,
        firebaseStorageDownloadTokens: 'sample-sanction-token-002',
      },
    },
  });
  const evidenceUrl2 = buildStorageUrl(evidencePath2, 'sample-sanction-token-002');

  await db.collection('sanctions').doc('sample_sanction_2').set({
    id: 'sample_sanction_2',
    addressRef: secondAddressRef,
    residentUid: secondResident.uid,
    authorizedUids: [secondResident.uid],
    reason: 'Unauthorized parking in visitor spot / Estacionamiento indebido en cajón de visitas',
    amount: 500.0,
    evidenceUrl: evidenceUrl2,
    status: 'pending_review',
    createdAt: Date.now() - 172800 * 1000,
    createdBy: adminUser.uid,
  });

  await db.collection('payments').doc('sample_pending_payment_3').set({
    id: 'sample_pending_payment_3',
    addressRef: secondAddressRef,
    residentUid: secondResident.uid,
    uploaderUid: secondResident.uid,
    amount: 500.0,
    concept: 'sanction',
    sanctionId: 'sample_sanction_2',
    folio: 'BBVA-772109',
    periods: [],
    status: 'pending',
    receiptUrl: receiptUrl,
    paymentDate: Date.now() - 1800 * 1000,
    timestamp: Date.now(),
  });

  console.log('✅ Sample payments & sanctions seeded.');

  // 8. Seed sample pending ownership claim (landscape-oriented deed image to test rotation)
  console.log('🏠 Seeding sample pending resident ownership claim...');
  const applicantUser = await createOrUpdateUser('applicant@test.com', 'TestPass123!', 'Elena Vargas', null);
  const claimedAddressRef = db.collection('addresses').doc('1st_Avenue_101');

  await claimedAddressRef.set({
    streetName: '1st Avenue',
    number: 101,
    residentUid: null,
    paymentStatus: 'paid',
    hasActiveSanctions: false,
    activeSanctionsCount: 0,
  }, { merge: true });

  await db.collection('users').doc(applicantUser.uid).set({
    uid: applicantUser.uid,
    name: 'Elena Vargas',
    email: 'applicant@test.com',
    role: 'resident',
    addressRef: null,
    familyMembers: [],
    createdAt: Date.now(),
  }, { merge: true });

  const ownershipProofPath = `ownership_proofs/${applicantUser.uid}/sample_ownership_proof_landscape.png`;
  await bucket.file(ownershipProofPath).save(pngBuffer2, {
    contentType: 'image/png',
    metadata: {
      metadata: {
        uploaderUid: applicantUser.uid,
        firebaseStorageDownloadTokens: 'sample-ownership-token-001',
      },
    },
  });
  const ownershipProofUrl = buildStorageUrl(ownershipProofPath, 'sample-ownership-token-001');

  await db.collection('ownership_claims').doc('sample_ownership_claim_1').set({
    id: 'sample_ownership_claim_1',
    userUid: applicantUser.uid,
    addressRef: claimedAddressRef,
    proofUrl: ownershipProofUrl,
    status: 'pending',
    deliveryDate: admin.firestore.Timestamp.fromDate(deliveryDate),
    timestamp: admin.firestore.Timestamp.now(),
  });
  console.log('   - Applicant: applicant@test.com / TestPass123! (Pending claim on 1st Avenue #101)');

  return { adminUser, residentUser, secondResident, roommateUser, guardUser, applicantUser };
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
    const { adminUser } = await seedUsersAndSamplePayments();
    await seedAnnouncements(adminUser.uid);
    console.log(`🎉 ${modeLabel} seeding completed successfully!`);
    process.exit(0);
  } catch (error) {
    console.error('❌ Seeding failed:', error);
    process.exit(1);
  }
}

main();
