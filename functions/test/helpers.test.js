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
  assert.equal(count, 1);
  assert.equal(updatedDocs.length, 1);
  assert.equal(updatedDocs[0].id, 'qr_expired_supplier');
  assert.deepEqual(updatedDocs[0].payload, {
    status: 'deactivated (expired)',
    isValid: false,
  });
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

