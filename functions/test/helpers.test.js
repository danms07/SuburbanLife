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



