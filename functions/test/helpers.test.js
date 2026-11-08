const test = require('node:test');
const assert = require('node:assert/strict');
const { _test } = require('../index.js');
const { DEFAULT_APP_NAME, BRAND_COLORS: EXPECTED_BRAND_COLORS } = require('../brand_config.js');
const { generateSecurePassword, replacePlaceholders, getNowInTimezone, validateDeliveryDate } = _test;

test('generateSecurePassword generates passwords meeting complexity rules', (t) => {
  // Test default length 12
  const pwd12 = generateSecurePassword();
  assert.equal(pwd12.length, 12);
  assert.match(pwd12, /[A-Z]/, 'Must contain uppercase');
  assert.match(pwd12, /[a-z]/, 'Must contain lowercase');
  assert.match(pwd12, /[0-9]/, 'Must contain digit');
  assert.match(pwd12, /[!@#$%&*+]/, 'Must contain symbol');

  // Test minimum length enforcement (passing 4 should enforce at least 8)
  const pwdMin = generateSecurePassword(4);
  assert.ok(pwdMin.length >= 8, 'Length must be at least 8');

  // Test custom length 20
  const pwd20 = generateSecurePassword(20);
  assert.equal(pwd20.length, 20);

  // Test multiple generations produce distinct outputs
  const set = new Set();
  for (let i = 0; i < 50; i++) {
    const p = generateSecurePassword();
    assert.match(p, /[A-Z]/);
    assert.match(p, /[a-z]/);
    assert.match(p, /[0-9]/);
    assert.match(p, /[!@#$%&*+]/);
    set.add(p);
  }
  assert.equal(set.size, 50, 'All generated passwords should be unique');
});

test('replacePlaceholders replaces placeholder tags case-insensitively', (t) => {
  const template = 'Hello %Name%, your email is %EMAIL%, password is %Password%, address is %ADDRESS%, role is %Role%, app is %appName%.';
  const data = {
    name: 'Jane Doe',
    email: 'jane@example.com',
    password: 'SecretPass123!',
    address: 'Oak St #10',
    role: 'Resident',
    appName: DEFAULT_APP_NAME,
  };

  const result = replacePlaceholders(template, data);

  assert.equal(
    result,
    `Hello Jane Doe, your email is jane@example.com, password is SecretPass123!, address is Oak St #10, role is Resident, app is ${DEFAULT_APP_NAME}.`
  );
});

test('replacePlaceholders handles missing data with safe defaults', (t) => {
  const template = 'Name: %name%, Address: %address%, Role: %role%, App: %appName%';
  const result = replacePlaceholders(template, {});

  assert.equal(result, `Name: , Address: N/A, Role: Residente, App: ${DEFAULT_APP_NAME}`);
});

test('replacePlaceholders returns empty string on null or empty template', (t) => {
  assert.equal(replacePlaceholders(null, {}), '');
  assert.equal(replacePlaceholders('', {}), '');
});

test('callableOptions configures App Check enforcement properly', (t) => {
  const { callableOptions, isEmulator } = _test;
  assert.ok(typeof isEmulator === 'boolean', 'isEmulator should be a boolean');
  assert.ok(typeof callableOptions === 'object', 'callableOptions should be an object');
  if (isEmulator) {
    assert.equal(callableOptions.enforceAppCheck, false);
  } else {
    assert.equal(callableOptions.enforceAppCheck, true);
    assert.equal(callableOptions.consumeAppCheckToken, true);
  }
});

test('isPasswordCompliant enforces Firebase Auth password complexity rules', (t) => {
  const { isPasswordCompliant } = _test;
  
  // Valid passwords (>=8 chars, upper, lower, digit, symbol)
  assert.equal(isPasswordCompliant('SecretPass123!'), true);
  assert.equal(isPasswordCompliant('Admin#2026!'), true);
  assert.equal(isPasswordCompliant('Ab1@efgh'), true);
  assert.equal(isPasswordCompliant('P@ssword1'), true);

  // Invalid: missing special character
  assert.equal(isPasswordCompliant('SecretPass123'), false);
  // Invalid: missing uppercase
  assert.equal(isPasswordCompliant('secretpass123!'), false);
  // Invalid: missing lowercase
  assert.equal(isPasswordCompliant('SECRETPASS123!'), false);
  // Invalid: missing number
  assert.equal(isPasswordCompliant('SecretPass!'), false);
  // Invalid: too short (<8 chars)
  assert.equal(isPasswordCompliant('Ab1!'), false);
  // Invalid: null / non-string / empty
  assert.equal(isPasswordCompliant(null), false);
  assert.equal(isPasswordCompliant(''), false);
  assert.equal(isPasswordCompliant(undefined), false);
});

test('getNowInTimezone parses valid date components and handles fallbacks', (t) => {
  const cst = getNowInTimezone('America/Mexico_City');
  assert.ok(typeof cst.year === 'number' && cst.year >= 2024, 'Year must be valid integer');
  assert.ok(typeof cst.month === 'number' && cst.month >= 1 && cst.month <= 12, 'Month must be 1-12');
  assert.ok(typeof cst.day === 'number' && cst.day >= 1 && cst.day <= 31, 'Day must be 1-31');
  assert.ok(typeof cst.hour === 'number' && cst.hour >= 0 && cst.hour <= 23, 'Hour must be 0-23');
  assert.ok(typeof cst.minute === 'number' && cst.minute >= 0 && cst.minute <= 59, 'Minute must be 0-59');

  // Test UTC
  const utc = getNowInTimezone('UTC');
  assert.ok(utc.year >= 2024);
  assert.ok(utc.month >= 1 && utc.month <= 12);

  // Test fallback for invalid timezone string
  const fallback = getNowInTimezone('Invalid/Timezone_String');
  assert.ok(fallback.year >= 2024);
  assert.ok(fallback.month >= 1 && fallback.month <= 12);
});

test('validateDeliveryDate validates delivery dates and rejects future dates', (t) => {
  // Empty / null should safely return null
  assert.equal(validateDeliveryDate(null), null);
  assert.equal(validateDeliveryDate(undefined), null);
  assert.equal(validateDeliveryDate(''), null);

  // Past valid date: January 1st 2025
  const pastDate = validateDeliveryDate('2025-01-01T00:00:00.000Z');
  assert.ok(pastDate instanceof Date);
  assert.equal(pastDate.getUTCFullYear(), 2025);
  assert.equal(pastDate.getUTCMonth(), 0);
  assert.equal(pastDate.getUTCDate(), 1);

  // Future date: January 1st 2100 (should throw 'Delivery date cannot be in the future.')
  assert.throws(
    () => validateDeliveryDate('2100-01-01T00:00:00.000Z'),
    (err) => {
      return err.message.includes('Delivery date cannot be in the future.');
    }
  );

  // Invalid date format
  assert.throws(
    () => validateDeliveryDate('not-a-date'),
    (err) => {
      return err.message.includes('Invalid delivery date format.');
    }
  );
});

test('getDateInTimezone formats timestamp into accurate integer components', (t) => {
  const { getDateInTimezone } = _test;
  // 2026-06-15T15:30:00.000Z
  const epoch = Date.UTC(2026, 5, 15, 15, 30, 0);
  const result = getDateInTimezone(epoch, 'UTC');
  assert.equal(result.year, 2026);
  assert.equal(result.month, 6);
  assert.equal(result.day, 15);
  assert.equal(result.hour, 15);
  assert.equal(result.minute, 30);
});

test('validateFacilityBooking enforces anticipation window', (t) => {
  const { validateFacilityBooking } = _test;
  const now = Date.now();

  const facWith2DaysAnticipation = {
    anticipationUnit: 'days',
    anticipationValue: 2,
    openingTime: '00:00',
    closingTime: '23:59',
  };

  // 1 day in the future (less than 2 days) -> Should throw failed-precondition
  const oneDayAhead = now + (1 * 24 * 60 * 60 * 1000);
  assert.throws(
    () => validateFacilityBooking({
      facData: facWith2DaysAnticipation,
      startTime: oneDayAhead,
      endTime: oneDayAhead + 3600000,
      now: now,
    }),
    (err) => err.message.includes('advance notice of at least 2 days')
  );

  // 3 days in the future (>= 2 days) -> Should succeed
  const threeDaysAhead = now + (3 * 24 * 60 * 60 * 1000);
  assert.doesNotThrow(
    () => validateFacilityBooking({
      facData: facWith2DaysAnticipation,
      startTime: threeDaysAhead,
      endTime: threeDaysAhead + 3600000,
      now: now,
    })
  );
});

test('validateFacilityBooking enforces daily operating hours window', (t) => {
  const { validateFacilityBooking } = _test;
  const facWithHours = {
    anticipationUnit: 'unrestricted',
    anticipationValue: 0,
    openingTime: '08:00',
    closingTime: '21:00',
  };

  // Valid slot: 10:00 to 12:00 UTC (using UTC for deterministic test)
  const validStart = Date.UTC(2026, 5, 15, 10, 0, 0);
  const validEnd = Date.UTC(2026, 5, 15, 12, 0, 0);
  assert.doesNotThrow(
    () => validateFacilityBooking({
      facData: facWithHours,
      startTime: validStart,
      endTime: validEnd,
      timeZone: 'UTC',
    })
  );

  // Invalid early slot: 07:00 to 09:00 UTC
  const earlyStart = Date.UTC(2026, 5, 15, 7, 0, 0);
  const earlyEnd = Date.UTC(2026, 5, 15, 9, 0, 0);
  assert.throws(
    () => validateFacilityBooking({
      facData: facWithHours,
      startTime: earlyStart,
      endTime: earlyEnd,
      timeZone: 'UTC',
    }),
    (err) => err.message.includes('operating hours (08:00 - 21:00)')
  );

  // Invalid late slot: 20:00 to 22:00 UTC
  const lateStart = Date.UTC(2026, 5, 15, 20, 0, 0);
  const lateEnd = Date.UTC(2026, 5, 15, 22, 0, 0);
  assert.throws(
    () => validateFacilityBooking({
      facData: facWithHours,
      startTime: lateStart,
      endTime: lateEnd,
      timeZone: 'UTC',
    }),
    (err) => err.message.includes('operating hours (08:00 - 21:00)')
  );
});

test('BRAND_COLORS matches AppConfig palette and typography', (t) => {
  const { BRAND_COLORS } = _test;
  assert.ok(BRAND_COLORS, 'BRAND_COLORS must be defined');
  assert.equal(BRAND_COLORS.primary, EXPECTED_BRAND_COLORS.primary);
  assert.equal(BRAND_COLORS.gradientEnd, EXPECTED_BRAND_COLORS.gradientEnd);
  assert.equal(BRAND_COLORS.secondary, EXPECTED_BRAND_COLORS.secondary);
  assert.equal(BRAND_COLORS.accent, EXPECTED_BRAND_COLORS.accent);
  assert.equal(BRAND_COLORS.background, EXPECTED_BRAND_COLORS.background);
  assert.equal(BRAND_COLORS.cardBackground, EXPECTED_BRAND_COLORS.cardBackground);
  assert.equal(BRAND_COLORS.textColor, EXPECTED_BRAND_COLORS.textColor);
  assert.ok(BRAND_COLORS.fontFamily.includes('Plus Jakarta Sans'));
});

test('buildWelcomeEmailHtml uses AppConfig brand colors and typography', (t) => {
  const { buildWelcomeEmailHtml } = _test;

  // 1. Default welcome email template
  const defaultHtml = buildWelcomeEmailHtml({
    branding: DEFAULT_APP_NAME,
    name: 'Carlos Ruiz',
    userRole: 'residente',
    email: 'carlos@example.com',
    password: 'SecurePassword123!',
    addressLinked: 'Oak St #42',
  });

  // Verify brand colors
  assert.ok(defaultHtml.includes(EXPECTED_BRAND_COLORS.primary), `Should contain primary brand color ${EXPECTED_BRAND_COLORS.primary}`);
  assert.ok(defaultHtml.includes(EXPECTED_BRAND_COLORS.gradientEnd), `Should contain gradient end color ${EXPECTED_BRAND_COLORS.gradientEnd}`);
  assert.ok(defaultHtml.includes(EXPECTED_BRAND_COLORS.cardBackground), `Should contain card background color ${EXPECTED_BRAND_COLORS.cardBackground}`);
  assert.ok(defaultHtml.includes('Plus Jakarta Sans'), 'Should use Plus Jakarta Sans typography');

  // 2. Custom body template
  const customHtml = buildWelcomeEmailHtml({
    branding: DEFAULT_APP_NAME,
    name: 'Carlos Ruiz',
    userRole: 'residente',
    email: 'carlos@example.com',
    password: 'SecurePassword123!',
    addressLinked: 'Oak St #42',
    customBody: 'Bienvenido a la comunidad!\nCredenciales enviadas.',
  });

  assert.ok(customHtml.includes(EXPECTED_BRAND_COLORS.primary), 'Custom template should contain primary brand color');
  assert.ok(customHtml.includes(EXPECTED_BRAND_COLORS.gradientEnd), 'Custom template should contain gradient end color');
  assert.ok(customHtml.includes('Plus Jakarta Sans'), 'Custom template should use Plus Jakarta Sans typography');
});

test('Gemini AI configuration uses gemini-3.8-flash on global Vertex AI endpoint', (t) => {
  const { GEMINI_MODEL, GEMINI_LOCATION } = _test;
  assert.equal(GEMINI_MODEL, 'gemini-3.8-flash');
  assert.equal(GEMINI_LOCATION, 'global');
});

test('validateTransparencyDocInput validates visibility, fileType, and strips path traversal', (t) => {
  const { validateTransparencyDocInput } = _test;

  const validAdminDoc = validateTransparencyDocInput({
    docId: 'admin_user_manual_es',
    title: 'Manual de Usuario para Administradores (ES)',
    fileName: '../../etc/Manual_Admin.pdf',
    visibility: 'admin',
    category: 'manuals',
    folderId: 'official_manuals',
    folderName: 'Manuales Oficiales',
  });

  assert.equal(validAdminDoc.docId, 'admin_user_manual_es');
  assert.equal(validAdminDoc.fileName, 'Manual_Admin.pdf');
  assert.equal(validAdminDoc.fileType, 'pdf');
  assert.equal(validAdminDoc.visibility, 'admin');
  assert.equal(validAdminDoc.category, 'manuals');
  assert.equal(validAdminDoc.folderId, 'official_manuals');

  const defaultDoc = validateTransparencyDocInput({
    title: 'Descripción Técnica General',
    fileName: 'Descripcion_Tecnica.pdf',
  });
  assert.equal(defaultDoc.visibility, 'all');
  assert.equal(defaultDoc.folderId, 'root');
  assert.equal(defaultDoc.fileType, 'pdf');

  // Invalid visibility throws
  assert.throws(() => {
    validateTransparencyDocInput({
      title: 'Test',
      fileName: 'test.pdf',
      visibility: 'super_secret',
    });
  }, /Invalid visibility/);

  // Unsupported extension throws
  assert.throws(() => {
    validateTransparencyDocInput({
      title: 'Malicious Script',
      fileName: 'payload.exe',
      visibility: 'all',
    });
  }, /Unsupported fileType/);
});

test('isOneTimeQrCode detects all single-use / supplier QR code variants', (t) => {
  const { isOneTimeQrCode } = _test;

  assert.equal(isOneTimeQrCode({ isOneTimeUse: true, type: 'temporary', accessCategory: 'supplier' }), true);
  assert.equal(isOneTimeQrCode({ isOneTimeUse: true, type: 'temporary', accessCategory: 'visitor' }), true);
  assert.equal(isOneTimeQrCode({ isOneTime: true }), true);
  assert.equal(isOneTimeQrCode({ type: 'one_time' }), true);
  assert.equal(isOneTimeQrCode({ accessCategory: 'supplier', type: 'temporary' }), true);

  assert.equal(isOneTimeQrCode({ isOneTimeUse: false, type: 'temporary', accessCategory: 'visitor' }), false);
  assert.equal(isOneTimeQrCode({ type: 'permanent', accessCategory: 'visitor' }), false);
  assert.equal(isOneTimeQrCode(null), false);
  assert.equal(isOneTimeQrCode(undefined), false);
});

test('evaluateQrValidityStatus validates active passes and rejects used, revoked, and expired passes', (t) => {
  const { evaluateQrValidityStatus } = _test;

  assert.deepEqual(evaluateQrValidityStatus({ status: 'active' }), { isValid: true, reason: null });
  assert.deepEqual(evaluateQrValidityStatus({ status: 'valid', isValid: true }), { isValid: true, reason: null });

  assert.deepEqual(
    evaluateQrValidityStatus({ status: 'deactivated (validated)', isValid: false }),
    { isValid: false, reason: 'QR Code has already been used.' }
  );
  assert.deepEqual(
    evaluateQrValidityStatus({ status: 'used' }),
    { isValid: false, reason: 'QR Code has already been used.' }
  );
  assert.deepEqual(
    evaluateQrValidityStatus({ status: 'deactivated (revoked)' }),
    { isValid: false, reason: 'QR Code has been revoked.' }
  );
  assert.deepEqual(
    evaluateQrValidityStatus({ status: 'revoked' }),
    { isValid: false, reason: 'QR Code has been revoked.' }
  );
  assert.deepEqual(
    evaluateQrValidityStatus({ status: 'deactivated (expired)' }),
    { isValid: false, reason: 'QR Code has expired.' }
  );
  assert.deepEqual(
    evaluateQrValidityStatus({ status: 'active', isValid: false }),
    { isValid: false, reason: 'QR Code is invalid.' }
  );
});

test('getQrExpiryMillis and expireOutdatedQrCodes handle expiration timestamps and batch updates', async (t) => {
  const { getQrExpiryMillis, expireOutdatedQrCodes } = _test;

  const fixedDate = new Date('2026-10-04T23:59:59.000Z');
  assert.equal(getQrExpiryMillis({ expiryTime: fixedDate }), fixedDate.getTime());
  assert.equal(getQrExpiryMillis({ expiresAt: fixedDate.toISOString() }), fixedDate.getTime());
  assert.equal(getQrExpiryMillis({ expiry: { toMillis: () => 123456789 } }), 123456789);
  assert.equal(getQrExpiryMillis({ type: 'permanent' }), 0);

  const updatedDocs = [];
  const mockDocs = [
    {
      ref: { id: 'qr_expired_supplier' },
      data: () => ({
        status: 'active',
        accessCategory: 'supplier',
        isOneTimeUse: true,
        expiryTime: new Date('2026-10-04T23:59:59.000Z'),
      }),
    },
    {
      ref: { id: 'qr_active_future' },
      data: () => ({
        status: 'active',
        accessCategory: 'visitor',
        expiryTime: new Date('2026-10-20T23:59:59.000Z'),
      }),
    },
    {
      ref: { id: 'qr_permanent' },
      data: () => ({
        status: 'active',
        type: 'permanent',
      }),
    },
    {
      ref: { id: 'qr_expired_but_inside' },
      data: () => ({
        status: 'active',
        accessCategory: 'visitor',
        isInside: true,
        expiryTime: new Date('2026-10-10T23:59:59.000Z'),
      }),
    },
  ];

  const mockDb = {
    collection: () => ({
      where: () => ({
        get: async () => ({
          empty: false,
          docs: mockDocs,
        }),
      }),
    }),
    batch: () => ({
      update: (ref, payload) => updatedDocs.push({ id: ref.id, payload }),
      commit: async () => {},
    }),
  };

  const nowMillis = new Date('2026-10-12T12:00:00.000Z').getTime();
  const count = await expireOutdatedQrCodes(mockDb, nowMillis);
  assert.equal(count, 2);
  assert.equal(updatedDocs.length, 2);

  assert.equal(updatedDocs[0].id, 'qr_expired_supplier');
  assert.equal(updatedDocs[0].payload.status, 'deactivated (expired)');
  assert.equal(updatedDocs[0].payload.isValid, false);
  assert.equal(updatedDocs[0].payload.deactivatedAt.toMillis(), nowMillis);
  // 7 days after 2026-10-04T23:59:59.000Z
  assert.equal(
    updatedDocs[0].payload.expireAt.toMillis(),
    new Date('2026-10-04T23:59:59.000Z').getTime() + 7 * 24 * 60 * 60 * 1000
  );

  // Open-visit pass transitions to deactivated (expired) so new entries are blocked,
  // while holding expireAt = null until the visitor exits
  assert.equal(updatedDocs[1].id, 'qr_expired_but_inside');
  assert.equal(updatedDocs[1].payload.status, 'deactivated (expired)');
  assert.equal(updatedDocs[1].payload.isValid, false);
  assert.equal(updatedDocs[1].payload.expireAt, null);
});

test('extractTimestampMillis and isSameCalendarDayInTimezone respect community timezone boundaries', (t) => {
  const { extractTimestampMillis, isSameCalendarDayInTimezone } = _test;

  const sampleDate = new Date('2026-10-20T18:30:00.000Z'); // 12:30 CST in America/Mexico_City
  assert.equal(extractTimestampMillis(sampleDate), sampleDate.getTime());
  assert.equal(extractTimestampMillis({ toMillis: () => 555000 }), 555000);
  assert.equal(extractTimestampMillis({ _seconds: 42 }), 42000);
  assert.equal(extractTimestampMillis(sampleDate.toISOString()), sampleDate.getTime());
  assert.equal(extractTimestampMillis(null), 0);

  // 10:00 AM CST vs 11:30 PM CST on 2026-10-20 (which is 2026-10-21T05:30:00Z in UTC!)
  const morningCst = new Date('2026-10-20T16:00:00.000Z').getTime();
  const lateNightCst = new Date('2026-10-21T05:30:00.000Z').getTime();
  const nextMorningCst = new Date('2026-10-21T14:00:00.000Z').getTime();

  assert.equal(isSameCalendarDayInTimezone(morningCst, lateNightCst, 'America/Mexico_City'), true);
  assert.equal(isSameCalendarDayInTimezone(morningCst, nextMorningCst, 'America/Mexico_City'), false);
});

test('resolveOpenVisitLog handles explicit isInside and legacy same-day QR fallback', (t) => {
  const { resolveOpenVisitLog } = _test;
  const nowMillis = new Date('2026-10-20T22:00:00.000Z').getTime(); // 16:00 CST
  const earlierTodayMillis = new Date('2026-10-20T16:00:00.000Z').getTime(); // 10:00 CST
  const yesterdayMillis = new Date('2026-10-19T16:00:00.000Z').getTime();

  // 1. Explicit isInside: true with directLogSnap
  const directSnap = {
    exists: true,
    id: 'log_explicit_1',
    ref: { id: 'log_explicit_1' },
    data: () => ({
      status: 'allowed',
      timestamp: yesterdayMillis, // Even overnight stays open when explicitly flagged
      exitTimestamp: null,
      isInside: true,
    }),
  };
  const resolvedExplicit = resolveOpenVisitLog({
    qrData: { isInside: true, activeAccessLogId: 'log_explicit_1' },
    directLogSnap: directSnap,
    nowMillis,
    timeZone: 'America/Mexico_City',
  });
  assert.equal(resolvedExplicit.id, 'log_explicit_1');

  // 2. Legacy QR (`isInside` undefined) scanned a 2nd time on the same day -> defaults isInside to true
  const legacySameDayLog = {
    id: 'log_legacy_today',
    ref: { id: 'log_legacy_today' },
    data: () => ({
      status: 'allowed',
      timestamp: earlierTodayMillis,
    }),
  };
  const resolvedLegacySameDay = resolveOpenVisitLog({
    qrData: { status: 'active' }, // Legacy QR: no `isInside` property
    candidateLogDocs: [legacySameDayLog],
    nowMillis,
    timeZone: 'America/Mexico_City',
  });
  assert.equal(resolvedLegacySameDay.id, 'log_legacy_today');

  // 3. Legacy QR whose earlier visit today already recorded exitTimestamp -> treated as new entry (returns null)
  const legacyClosedTodayLog = {
    id: 'log_legacy_closed',
    ref: { id: 'log_legacy_closed' },
    data: () => ({
      status: 'allowed',
      timestamp: earlierTodayMillis,
      exitTimestamp: nowMillis - 10000,
      isInside: false,
    }),
  };
  const resolvedAfterExit = resolveOpenVisitLog({
    qrData: { status: 'active' },
    candidateLogDocs: [legacyClosedTodayLog],
    nowMillis,
    timeZone: 'America/Mexico_City',
  });
  assert.equal(resolvedAfterExit, null);

  // 4. Legacy QR with an old unclosed log from yesterday -> first scan today is an entry (returns null)
  const legacyYesterdayLog = {
    id: 'log_legacy_yesterday',
    ref: { id: 'log_legacy_yesterday' },
    data: () => ({
      status: 'allowed',
      timestamp: yesterdayMillis,
    }),
  };
  const resolvedYesterday = resolveOpenVisitLog({
    qrData: { status: 'active' },
    candidateLogDocs: [legacyYesterdayLog],
    nowMillis,
    timeZone: 'America/Mexico_City',
  });
  assert.equal(resolvedYesterday, null);
});

test('firebase-admin v14 modular services (firestore, auth, messaging, storage, Timestamp, FieldValue) resolve cleanly', (t) => {
  const { admin } = _test;

  assert.equal(typeof admin.firestore, 'function');
  assert.equal(typeof admin.auth, 'function');
  assert.equal(typeof admin.messaging, 'function');
  assert.equal(typeof admin.storage, 'function');

  // Verify Firestore instance and static helpers
  const db = admin.firestore();
  assert.equal(typeof db.collection, 'function');
  assert.equal(typeof db.runTransaction, 'function');
  assert.equal(typeof db.batch, 'function');

  const nowTs = admin.firestore.Timestamp.now();
  assert.ok(nowTs instanceof admin.firestore.Timestamp);
  const fromDateTs = admin.firestore.Timestamp.fromDate(new Date('2026-10-22T00:00:00Z'));
  assert.ok(fromDateTs instanceof admin.firestore.Timestamp);
  assert.equal(typeof admin.firestore.FieldValue.serverTimestamp, 'function');

  // Verify Auth, Messaging, and Storage instances
  const auth = admin.auth();
  assert.equal(typeof auth.setCustomUserClaims, 'function');
  assert.equal(typeof auth.createUser, 'function');

  const messaging = admin.messaging();
  assert.equal(typeof messaging.sendEachForMulticast, 'function');

  const storage = admin.storage();
  assert.equal(typeof storage.bucket, 'function');
});

test('package-lock.json files only reference public registry.npmjs.org tarball URLs for Cloud Build compatibility', () => {
  const fs = require('node:fs');
  const path = require('node:path');

  const lockfilePaths = [
    path.resolve(__dirname, '../package-lock.json'),
    path.resolve(__dirname, '../../scripts/package-lock.json'),
  ];

  for (const lockPath of lockfilePaths) {
    const lockJson = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
    const packages = lockJson.packages || {};
    for (const [pkgKey, meta] of Object.entries(packages)) {
      if (meta && typeof meta.resolved === 'string') {
        assert.ok(
          meta.resolved.startsWith('https://registry.npmjs.org/'),
          `Non-public registry URL found in ${path.relative(process.cwd(), lockPath)} for "${pkgKey}": ${meta.resolved}`
        );
      }
    }
  }
});

test('resolveFacilityRestriction normalizes legacy cooldown, explicit cooldown (incl. hours), and quota rules', () => {
  const { resolveFacilityRestriction } = _test;

  // Null / empty -> unrestricted
  assert.deepEqual(resolveFacilityRestriction(null), {
    restrictionType: 'unrestricted',
    cooldownUnit: 'unrestricted',
    cooldownValue: 0,
    quotaPeriod: 'unrestricted',
    quotaLimit: 0,
  });

  // Legacy facility doc (no restrictionType, only cooldownUnit + cooldownValue)
  assert.deepEqual(resolveFacilityRestriction({ cooldownUnit: 'days', cooldownValue: 7 }), {
    restrictionType: 'cooldown',
    cooldownUnit: 'days',
    cooldownValue: 7,
    quotaPeriod: 'unrestricted',
    quotaLimit: 0,
  });

  // Explicit hours cooldown
  assert.deepEqual(
    resolveFacilityRestriction({ restrictionType: 'cooldown', cooldownUnit: 'hours', cooldownValue: 4 }),
    {
      restrictionType: 'cooldown',
      cooldownUnit: 'hours',
      cooldownValue: 4,
      quotaPeriod: 'unrestricted',
      quotaLimit: 0,
    }
  );

  // Explicit monthly quota
  assert.deepEqual(
    resolveFacilityRestriction({ restrictionType: 'quota', quotaPeriod: 'monthly', quotaLimit: 2 }),
    {
      restrictionType: 'quota',
      cooldownUnit: 'unrestricted',
      cooldownValue: 0,
      quotaPeriod: 'monthly',
      quotaLimit: 2,
    }
  );

  // Invalid values fall back safely to unrestricted
  assert.equal(
    resolveFacilityRestriction({ restrictionType: 'quota', quotaPeriod: 'weekly', quotaLimit: 2 }).restrictionType,
    'unrestricted'
  );
  assert.equal(
    resolveFacilityRestriction({ restrictionType: 'cooldown', cooldownUnit: 'hours', cooldownValue: 0 }).restrictionType,
    'unrestricted'
  );
});

test('addCooldownOffset handles hours, days, month-end clamping, and leap-year clamping', () => {
  const { addCooldownOffset } = _test;

  const base = Date.UTC(2026, 0, 31, 14, 30, 0); // 2026-01-31T14:30:00Z
  assert.equal(addCooldownOffset(base, 'hours', 3), Date.UTC(2026, 0, 31, 17, 30, 0));
  assert.equal(addCooldownOffset(base, 'days', 2), Date.UTC(2026, 1, 2, 14, 30, 0));

  // Jan 31 + 1 month in non-leap year 2026 -> Feb 28, 2026 14:30 UTC
  assert.equal(addCooldownOffset(base, 'months', 1), Date.UTC(2026, 1, 28, 14, 30, 0));

  // Feb 29, 2024 (leap year) + 1 year -> Feb 28, 2025
  const leapDay = Date.UTC(2024, 1, 29, 10, 0, 0);
  assert.equal(addCooldownOffset(leapDay, 'years', 1), Date.UTC(2025, 1, 28, 10, 0, 0));
});

test('isCountedBookingForRestriction counts pending review and confirmed statuses while ignoring rejected/cancelled', () => {
  const { isCountedBookingForRestriction } = _test;

  assert.equal(isCountedBookingForRestriction({ status: 'pending review' }), true);
  assert.equal(isCountedBookingForRestriction({ status: 'pending' }), true);
  assert.equal(isCountedBookingForRestriction({ status: 'approved (upcoming)' }), true);
  assert.equal(isCountedBookingForRestriction({ status: 'approved (in use)' }), true);
  assert.equal(isCountedBookingForRestriction({ status: 'confirmed' }), true);
  assert.equal(isCountedBookingForRestriction({ status: 'closed' }), true);

  assert.equal(isCountedBookingForRestriction({ status: 'rejected' }), false);
  assert.equal(isCountedBookingForRestriction({ status: 'cancelled' }), false);
  assert.equal(isCountedBookingForRestriction({}), false);
});

test('validateFacilityBooking rejects endTime <= startTime even for 24/7 unrestricted facilities', () => {
  const { validateFacilityBooking } = _test;
  const fac24x7 = {
    anticipationUnit: 'unrestricted',
    anticipationValue: 0,
    openingTime: '00:00',
    closingTime: '23:59',
  };
  const slot = Date.UTC(2026, 5, 15, 12, 0, 0);
  assert.throws(
    () => validateFacilityBooking({ facData: fac24x7, startTime: slot, endTime: slot, timeZone: 'UTC' }),
    (err) => err.code === 'invalid-argument' && err.message.includes('End time must be after start time')
  );
});

test('validateHouseholdBookingRestriction enforces symmetric endTime->startTime cooldown and timezone-aware quotas', () => {
  const { validateHouseholdBookingRestriction } = _test;

  // 1. Cooldown in hours: existing booking 10:00 - 12:00 UTC, 2h cooldown
  const facHoursCooldown = {
    restrictionType: 'cooldown',
    cooldownUnit: 'hours',
    cooldownValue: 2,
  };
  const existing = [
    {
      id: 'b_existing',
      status: 'pending review',
      startTime: Date.UTC(2026, 5, 15, 10, 0, 0),
      endTime: Date.UTC(2026, 5, 15, 12, 0, 0),
    },
  ];

  // 13:00 - 14:00 (only 1h after 12:00 end) -> blocked
  assert.throws(
    () =>
      validateHouseholdBookingRestriction({
        facData: facHoursCooldown,
        startTime: Date.UTC(2026, 5, 15, 13, 0, 0),
        endTime: Date.UTC(2026, 5, 15, 14, 0, 0),
        householdBookings: existing,
        timeZone: 'UTC',
      }),
    (err) => err.code === 'failed-precondition' && err.message.includes('wait 2 hours')
  );

  // Exact boundary 14:00 - 16:00 (2h after 12:00 end) -> allowed
  assert.doesNotThrow(() =>
    validateHouseholdBookingRestriction({
      facData: facHoursCooldown,
      startTime: Date.UTC(2026, 5, 15, 14, 0, 0),
      endTime: Date.UTC(2026, 5, 15, 16, 0, 0),
      householdBookings: existing,
      timeZone: 'UTC',
    })
  );

  // Earlier slot 08:30 - 09:00 (only 1h before 10:00 start) -> blocked symmetrically
  assert.throws(
    () =>
      validateHouseholdBookingRestriction({
        facData: facHoursCooldown,
        startTime: Date.UTC(2026, 5, 15, 8, 30, 0),
        endTime: Date.UTC(2026, 5, 15, 9, 0, 0),
        householdBookings: existing,
        timeZone: 'UTC',
      }),
    (err) => err.code === 'failed-precondition'
  );

  // Earlier slot 06:00 - 08:00 (ends 2h before 10:00 start) -> allowed
  assert.doesNotThrow(() =>
    validateHouseholdBookingRestriction({
      facData: facHoursCooldown,
      startTime: Date.UTC(2026, 5, 15, 6, 0, 0),
      endTime: Date.UTC(2026, 5, 15, 8, 0, 0),
      householdBookings: existing,
      timeZone: 'UTC',
    })
  );

  // 2. Daily quota in America/Mexico_City (UTC-6):
  // 2026-06-16T03:00:00Z is 2026-06-15 21:00 in America/Mexico_City!
  const facDailyQuota = {
    restrictionType: 'quota',
    quotaPeriod: 'daily',
    quotaLimit: 1,
  };
  const mxBookings = [
    {
      id: 'b_mx_1',
      status: 'approved (upcoming)',
      startTime: Date.UTC(2026, 5, 15, 18, 0, 0), // 2026-06-15 12:00 CST
      endTime: Date.UTC(2026, 5, 15, 19, 0, 0),
    },
    {
      id: 'b_mx_rejected',
      status: 'rejected',
      startTime: Date.UTC(2026, 5, 16, 18, 0, 0), // rejected does not count
      endTime: Date.UTC(2026, 5, 16, 19, 0, 0),
    },
  ];

  // Same local day in Mexico City (2026-06-15 21:00 CST = 2026-06-16 03:00 UTC) -> blocked
  assert.throws(
    () =>
      validateHouseholdBookingRestriction({
        facData: facDailyQuota,
        startTime: Date.UTC(2026, 5, 16, 3, 0, 0),
        endTime: Date.UTC(2026, 5, 16, 4, 0, 0),
        householdBookings: mxBookings,
        timeZone: 'America/Mexico_City',
      }),
    (err) => err.code === 'failed-precondition' && err.message.includes('daily booking quota (1)')
  );

  // Next local day in Mexico City (2026-06-16 12:00 CST, where only a rejected booking exists) -> allowed
  assert.doesNotThrow(() =>
    validateHouseholdBookingRestriction({
      facData: facDailyQuota,
      startTime: Date.UTC(2026, 5, 16, 18, 0, 0),
      endTime: Date.UTC(2026, 5, 16, 19, 0, 0),
      householdBookings: mxBookings,
      timeZone: 'America/Mexico_City',
    })
  );
});

test('computeAccessLogExpireAtMillis and computeQrCodeExpireAtMillis apply exact 60-day and 7-day windows', () => {
  const {
    ACCESS_LOG_RETENTION_DAYS,
    ACCESS_LOG_RETENTION_MS,
    QR_CODE_RETENTION_DAYS,
    QR_CODE_RETENTION_MS,
    computeAccessLogExpireAtMillis,
    computeQrCodeExpireAtMillis,
  } = _test;

  assert.equal(ACCESS_LOG_RETENTION_DAYS, 60);
  assert.equal(QR_CODE_RETENTION_DAYS, 7);

  const baseMs = Date.UTC(2026, 10, 1, 12, 0, 0);
  assert.equal(computeAccessLogExpireAtMillis(baseMs), baseMs + ACCESS_LOG_RETENTION_MS);
  assert.equal(computeAccessLogExpireAtMillis(new Date(baseMs)), baseMs + 60 * 24 * 60 * 60 * 1000);
  assert.equal(computeQrCodeExpireAtMillis(baseMs), baseMs + QR_CODE_RETENTION_MS);
  assert.equal(computeQrCodeExpireAtMillis(new Date(baseMs)), baseMs + 7 * 24 * 60 * 60 * 1000);
});

test('extractVisitorMediaStoragePath extracts valid visitor_ids/ & visitor_plates/ paths and blocks traversal or out-of-scope folders', () => {
  const { extractVisitorMediaStoragePath } = _test;

  // 1. Valid Firebase Storage REST download URLs (production & emulator)
  assert.equal(
    extractVisitorMediaStoragePath(
      'https://firebasestorage.googleapis.com/v0/b/suburban-life.appspot.com/o/visitor_ids%2Fqr_123_1700000000.jpg?alt=media&token=abc-123'
    ),
    'visitor_ids/qr_123_1700000000.jpg'
  );
  assert.equal(
    extractVisitorMediaStoragePath(
      'http://127.0.0.1:9199/v0/b/demo-suburban.appspot.com/o/visitor_plates%2Fqr_999%2Fplate_photo.jpg?alt=media'
    ),
    'visitor_plates/qr_999/plate_photo.jpg'
  );

  // 2. Valid gs:// URIs and direct bucket-relative paths
  assert.equal(
    extractVisitorMediaStoragePath('gs://suburban-life.appspot.com/visitor_ids/qr_abc_1.jpg'),
    'visitor_ids/qr_abc_1.jpg'
  );
  assert.equal(
    extractVisitorMediaStoragePath('visitor_plates/qr_abc_2.png'),
    'visitor_plates/qr_abc_2.png'
  );

  // 3. Rejects path traversal, double-encoded traversal, null bytes, and prefix spoofing
  assert.equal(
    extractVisitorMediaStoragePath(
      'https://firebasestorage.googleapis.com/v0/b/suburban-life.appspot.com/o/visitor_ids%2F..%2Fdocuments%2Fbylaws.pdf?alt=media'
    ),
    null
  );
  assert.equal(
    extractVisitorMediaStoragePath('visitor_ids/%2e%2e/payments/receipt.jpg'),
    null
  );
  assert.equal(extractVisitorMediaStoragePath('visitor_ids/qr_1\0.jpg'), null);
  assert.equal(extractVisitorMediaStoragePath('visitor_ids_evil/photo.jpg'), null);
  assert.equal(extractVisitorMediaStoragePath('visitor_ids/'), null);

  // 4. Rejects other sensitive Storage folders (documents/, payments/, sanctions/)
  assert.equal(
    extractVisitorMediaStoragePath(
      'https://firebasestorage.googleapis.com/v0/b/suburban-life.appspot.com/o/documents%2Fadmin_only%2Fbudget.pdf?alt=media'
    ),
    null
  );
  assert.equal(extractVisitorMediaStoragePath('payments/addr_1/receipt.jpg'), null);
  assert.equal(extractVisitorMediaStoragePath('sanctions/addr_1/evidence.jpg'), null);
  assert.equal(extractVisitorMediaStoragePath(null), null);
  assert.equal(extractVisitorMediaStoragePath(''), null);
});

test('evaluateQrCleanupAction purges terminal QR passes after 7 days while preserving permanent and open-visit passes', () => {
  const { evaluateQrCleanupAction, QR_CODE_RETENTION_MS } = _test;
  const nowMillis = Date.UTC(2026, 10, 20, 12, 0, 0);

  // 1. Active permanent pass -> keep forever
  assert.deepEqual(
    evaluateQrCleanupAction({ status: 'active', type: 'permanent', expireAt: null }, nowMillis),
    { action: 'keep' }
  );

  // 2. Active temporary pass not yet expired -> keep
  assert.deepEqual(
    evaluateQrCleanupAction(
      {
        status: 'active',
        type: 'temporary',
        expiryTime: new Date(nowMillis + 3600_000),
      },
      nowMillis
    ),
    { action: 'keep' }
  );

  // 3. Expired or revoked pass whose visitor is STILL INSIDE -> never delete!
  assert.deepEqual(
    evaluateQrCleanupAction(
      {
        status: 'deactivated (expired)',
        isInside: true,
        deactivatedAt: new Date(nowMillis - 10 * 24 * 60 * 60 * 1000),
        expireAt: new Date(nowMillis - 3 * 24 * 60 * 60 * 1000),
      },
      nowMillis
    ),
    { action: 'keep' }
  );

  // 4. Revoked pass 8 days after deactivatedAt -> delete
  assert.deepEqual(
    evaluateQrCleanupAction(
      {
        status: 'deactivated (revoked)',
        deactivatedAt: new Date(nowMillis - 8 * 24 * 60 * 60 * 1000),
      },
      nowMillis
    ),
    { action: 'delete' }
  );

  // 5. Validated 1x supplier pass 3 days ago (legacy doc missing expireAt) -> backfill stamp_ttl
  const usedAt = nowMillis - 3 * 24 * 60 * 60 * 1000;
  const backfillAction = evaluateQrCleanupAction(
    {
      status: 'deactivated (validated)',
      usedAt,
    },
    nowMillis
  );
  assert.equal(backfillAction.action, 'stamp_ttl');
  assert.equal(backfillAction.expireAtMillis, usedAt + QR_CODE_RETENTION_MS);

  // 6. Legacy 'active' temporary pass whose expiryTime passed 9 days ago -> delete
  assert.deepEqual(
    evaluateQrCleanupAction(
      {
        status: 'active',
        type: 'temporary',
        expiryTime: new Date(nowMillis - 9 * 24 * 60 * 60 * 1000),
      },
      nowMillis
    ),
    { action: 'delete' }
  );
});

test('Static Config Audit: storage_lifecycle.json and firestore.indexes.json configure 62-day media safety net, 125-day booking attachment safety net, and expireAt exemptions', () => {
  const fs = require('node:fs');
  const path = require('node:path');

  const lifecyclePath = path.resolve(__dirname, '../../storage_lifecycle.json');
  const lifecycleJson = JSON.parse(fs.readFileSync(lifecyclePath, 'utf8'));
  assert.ok(Array.isArray(lifecycleJson.lifecycle?.rule));
  const deleteRule = lifecycleJson.lifecycle.rule[0];
  assert.equal(deleteRule.action.type, 'Delete');
  assert.equal(deleteRule.condition.age, 62);
  assert.deepEqual(deleteRule.condition.matchesPrefix, ['visitor_ids/', 'visitor_plates/']);

  const bookingAttRule = lifecycleJson.lifecycle.rule[1];
  assert.equal(bookingAttRule.action.type, 'Delete');
  assert.equal(bookingAttRule.condition.age, 125);
  assert.deepEqual(bookingAttRule.condition.matchesPrefix, ['booking_attachments/']);

  const indexesPath = path.resolve(__dirname, '../../firestore.indexes.json');
  const indexesJson = JSON.parse(fs.readFileSync(indexesPath, 'utf8'));
  const accessLogTtlOverride = indexesJson.fieldOverrides.find(
    (f) => f.collectionGroup === 'access_logs' && f.fieldPath === 'expireAt'
  );
  const qrTtlOverride = indexesJson.fieldOverrides.find(
    (f) => f.collectionGroup === 'qr_codes' && f.fieldPath === 'expireAt'
  );
  const bookingAttTtlOverride = indexesJson.fieldOverrides.find(
    (f) => f.collectionGroup === 'booking_attachments' && f.fieldPath === 'expireAt'
  );
  assert.deepEqual(accessLogTtlOverride?.indexes, []);
  assert.deepEqual(qrTtlOverride?.indexes, []);
  assert.deepEqual(bookingAttTtlOverride?.indexes, []);
});

test('computeBookingAttachmentExpireAtMillis computes exact 30-day post-endTime retention window', () => {
  const {
    computeBookingAttachmentExpireAtMillis,
    BOOKING_ATTACHMENT_RETENTION_DAYS,
    BOOKING_ATTACHMENT_RETENTION_MS,
  } = _test;

  assert.equal(BOOKING_ATTACHMENT_RETENTION_DAYS, 30);
  assert.equal(BOOKING_ATTACHMENT_RETENTION_MS, 30 * 24 * 60 * 60 * 1000);

  const bookingEndMillis = Date.UTC(2027, 7, 15, 20, 0, 0);
  assert.equal(
    computeBookingAttachmentExpireAtMillis(bookingEndMillis),
    bookingEndMillis + 30 * 24 * 60 * 60 * 1000
  );
  assert.equal(
    computeBookingAttachmentExpireAtMillis(new Date(bookingEndMillis)),
    bookingEndMillis + 30 * 24 * 60 * 60 * 1000
  );
});

test('validateDocumentMagicBytes accepts authentic PDF/Office/Raster headers and rejects spoofed HTML/SVG/Executables', () => {
  const { validateDocumentMagicBytes } = _test;

  // Authentic headers
  assert.equal(validateDocumentMagicBytes(Buffer.from('%PDF-1.7\n...'), 'pdf'), true);
  assert.equal(
    validateDocumentMagicBytes(
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00]),
      'png'
    ),
    true
  );
  assert.equal(validateDocumentMagicBytes(Buffer.from([0xff, 0xd8, 0xff, 0xe0]), 'jpg'), true);
  assert.equal(validateDocumentMagicBytes(Buffer.from([0xff, 0xd8, 0xff, 0xe1]), 'jpeg'), true);
  assert.equal(validateDocumentMagicBytes(Buffer.from('RIFF\x24\x00\x00\x00WEBPVP8 '), 'webp'), true);
  assert.equal(
    validateDocumentMagicBytes(Buffer.from([0x50, 0x4b, 0x03, 0x04, 0x14, 0x00]), 'docx'),
    true
  );
  assert.equal(
    validateDocumentMagicBytes(Buffer.from([0x50, 0x4b, 0x03, 0x04, 0x14, 0x00]), 'xlsx'),
    true
  );
  assert.equal(
    validateDocumentMagicBytes(
      Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0x00]),
      'doc'
    ),
    true
  );
  assert.equal(
    validateDocumentMagicBytes(
      Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0x00]),
      'xls'
    ),
    true
  );

  // Spoofed or disallowed payloads
  assert.equal(validateDocumentMagicBytes(Buffer.from('<html><script>alert(1)</script>'), 'pdf'), false);
  assert.equal(validateDocumentMagicBytes(Buffer.from('<svg onload="alert(1)">'), 'png'), false);
  assert.equal(validateDocumentMagicBytes(Buffer.from('<svg onload="alert(1)">'), 'svg'), false);
  assert.equal(validateDocumentMagicBytes(Buffer.from('MZ\x90\x00'), 'exe'), false);
  assert.equal(validateDocumentMagicBytes(Buffer.from('%PDF'), 'pdf'), false); // truncated
  assert.equal(validateDocumentMagicBytes(null, 'pdf'), false);
});

test('extractBookingAttachmentStoragePath extracts valid booking_attachments/<uid>/<file> paths and blocks traversal or out-of-scope prefixes', () => {
  const { extractBookingAttachmentStoragePath } = _test;

  assert.equal(
    extractBookingAttachmentStoragePath(
      'https://firebasestorage.googleapis.com/v0/b/suburban-life.appspot.com/o/booking_attachments%2Fres_uid_1%2F1710000_abcd.pdf?alt=media&token=xyz'
    ),
    'booking_attachments/res_uid_1/1710000_abcd.pdf'
  );
  assert.equal(
    extractBookingAttachmentStoragePath('gs://suburban-life.appspot.com/booking_attachments/res_uid_1/signed_form.docx'),
    'booking_attachments/res_uid_1/signed_form.docx'
  );
  assert.equal(
    extractBookingAttachmentStoragePath('booking_attachments/res_uid_1/photo_1.jpg'),
    'booking_attachments/res_uid_1/photo_1.jpg'
  );

  // Reject traversal, extra nesting, null bytes, and other folders
  assert.equal(extractBookingAttachmentStoragePath('booking_attachments/../documents/admin_only/secret.pdf'), null);
  assert.equal(extractBookingAttachmentStoragePath('booking_attachments/res_uid_1/../../payments/p1.pdf'), null);
  assert.equal(extractBookingAttachmentStoragePath('booking_attachments/res_uid_1/sub/extra.pdf'), null);
  assert.equal(extractBookingAttachmentStoragePath('booking_attachments/res_uid_1/evil\0.pdf'), null);
  assert.equal(extractBookingAttachmentStoragePath('facility_documents/pool/template.pdf'), null);
  assert.equal(extractBookingAttachmentStoragePath('documents/admin_only/secret.pdf'), null);
  assert.equal(extractBookingAttachmentStoragePath(''), null);
  assert.equal(extractBookingAttachmentStoragePath(null), null);
});
