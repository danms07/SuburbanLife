const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const FIRESTORE_RULES_PATH = path.join(REPO_ROOT, 'firestore.rules');
const STORAGE_RULES_PATH = path.join(REPO_ROOT, 'storage.rules');

/**
 * Extracts the body inside a top-level `match <pattern> { ... }` block.
 */
function extractMatchBlock(rulesSource, matchHeader) {
  const startIdx = rulesSource.indexOf(matchHeader);
  assert.notEqual(startIdx, -1, `Expected to find "${matchHeader}" in security rules`);
  const openBraceIdx = rulesSource.indexOf('{', startIdx + matchHeader.length);
  let depth = 0;
  for (let i = openBraceIdx; i < rulesSource.length; i++) {
    if (rulesSource[i] === '{') depth++;
    else if (rulesSource[i] === '}') {
      depth--;
      if (depth === 0) {
        return rulesSource.slice(openBraceIdx + 1, i);
      }
    }
  }
  assert.fail(`Unbalanced braces for "${matchHeader}"`);
}

test('Static Audit: firestore.rules enforces RBAC, field-level immutability, and SMTP secret isolation', () => {
  const source = fs.readFileSync(FIRESTORE_RULES_PATH, 'utf8');

  // 1. Users collection: blocks self-role escalation on both create and update
  const usersBlock = extractMatchBlock(source, 'match /users/{userId}');
  assert.match(usersBlock, /request\.resource\.data\.role\s*==\s*'resident'/);
  assert.match(usersBlock, /request\.resource\.data\.addressRef\s*==\s*null/);
  assert.match(
    usersBlock,
    /!request\.resource\.data\.diff\(resource\.data\)\.affectedKeys\(\)\.hasAny\(\['role',\s*'addressRef',\s*'familyMembers',\s*'admin',\s*'guard',\s*'resident',\s*'createdAt'\]\)/
  );
  assert.match(usersBlock, /allow delete:\s*if isAdmin\(\);/);

  // 2. Transparency documents & folders: admin-only writes and visibility != 'admin' guard for residents
  for (const header of ['match /documents/{documentId}', 'match /document_folders/{folderId}']) {
    const block = extractMatchBlock(source, header);
    assert.match(block, /allow write:\s*if isAdmin\(\);/);
    assert.match(block, /resource\.data\.visibility\s*!=\s*'admin'/);
  }

  // 3. Config collection: protects smtp_settings from non-admin reads and locks writes to admins
  const configBlock = extractMatchBlock(source, 'match /config/{configId}');
  assert.match(configBlock, /configId\s*!=\s*'smtp_settings'/);
  assert.match(configBlock, /allow write:\s*if isAdmin\(\);/);

  // 4. Sanctions collection: prevents residents from self-clearing sanctions to 'paid'
  const sanctionsBlock = extractMatchBlock(source, 'match /sanctions/{sanctionId}');
  assert.match(sanctionsBlock, /allow create,\s*delete:\s*if isAdmin\(\);/);
  assert.match(sanctionsBlock, /resource\.data\.status\s*==\s*'active'/);
  assert.match(sanctionsBlock, /hasOnly\(\['status',\s*'paymentId'\]\)/);
  assert.match(sanctionsBlock, /request\.resource\.data\.status\s*==\s*'pending_review'/);

  // 5. Access logs: restricted to guard/admin reads and admin-only direct writes
  const logsBlock = extractMatchBlock(source, 'match /access_logs/{logId}');
  assert.match(logsBlock, /allow read:\s*if isGuard\(\)\s*\|\|\s*isAdmin\(\);/);
  assert.match(logsBlock, /allow write:\s*if isAdmin\(\);/);

  // 6. Bookings collection: household addressId read access for residents/roommates and admin-only direct writes
  const bookingsBlock = extractMatchBlock(source, 'match /bookings/{bookingId}');
  assert.match(bookingsBlock, /isCallerAddressResident\(resource\.data\.addressId\)/);
  assert.match(bookingsBlock, /allow write:\s*if isAdmin\(\);/);
});

test('Static Audit: storage.rules enforces 10 MB upload cap, MIME allow-list, /sanctions/ coverage, and path ownership', () => {
  const source = fs.readFileSync(STORAGE_RULES_PATH, 'utf8');

  assert.match(source, /request\.resource\.size\s*<\s*10\s*\*\s*1024\s*\*\s*1024/);
  assert.match(source, /request\.resource\.contentType\.matches\('image\/\.\*'\)/);
  assert.match(source, /request\.resource\.contentType\s*==\s*'application\/pdf'/);

  const adminDocsBlock = extractMatchBlock(source, 'match /documents/admin_only/{allPaths=**}');
  assert.match(adminDocsBlock, /allow read,\s*write:\s*if isAdmin\(\);/);

  const sanctionsBlock = extractMatchBlock(source, 'match /sanctions/{addressId}/{allPaths=**}');
  assert.match(sanctionsBlock, /isAdmin\(\)\s*&&\s*isValidUploadSize\(\)\s*&&\s*isAllowedProofOrPhoto\(\)/);

  const paymentsBlock = extractMatchBlock(source, 'match /payments/{ownerOrAddressId}/{allPaths=**}');
  assert.match(paymentsBlock, /request\.auth\.uid\s*==\s*ownerOrAddressId/);
  assert.match(paymentsBlock, /allow delete:\s*if isAdmin\(\);/);
});

/**
 * Builds an unsigned Emulator-only JWT accepted exclusively by the local
 * Firebase Firestore Emulator (`alg: "none"`). Never used outside 127.0.0.1/localhost.
 */
function buildLocalEmulatorJwt(uid, claims = {}) {
  const projectId = process.env.GCLOUD_PROJECT || 'demo-suburban';
  const encodePart = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const nowSec = Math.floor(Date.now() / 1000);
  const header = { alg: 'none', typ: 'JWT' };
  const payload = {
    iss: `https://securetoken.google.com/${projectId}`,
    aud: projectId,
    sub: uid,
    user_id: uid,
    iat: nowSec,
    exp: nowSec + 3600,
    ...claims,
  };
  return `${encodePart(header)}.${encodePart(payload)}.`;
}

function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === null) fields[k] = { nullValue: null };
    else if (typeof v === 'boolean') fields[k] = { booleanValue: v };
    else if (typeof v === 'number') fields[k] = Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
    else if (typeof v === 'string') fields[k] = { stringValue: v };
    else if (Array.isArray(v)) {
      fields[k] = { arrayValue: { values: v.map((item) => ({ stringValue: String(item) })) } };
    }
  }
  return { fields };
}

test('Live Emulator Audit: evaluates Firestore Security Rules against unauthenticated, resident, and admin tokens', async (t) => {
  const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
  if (!emulatorHost) {
    t.skip('FIRESTORE_EMULATOR_HOST not set; run via scripts/run_rollout_tests.sh for live emulator evaluation.');
    return;
  }

  // Enforce strict loopback binding per secure testing policy (never 0.0.0.0 or remote hosts)
  assert.match(
    emulatorHost,
    /^(127\.0\.0\.1|localhost):\d+$/,
    `FIRESTORE_EMULATOR_HOST must bind to 127.0.0.1 or localhost, got "${emulatorHost}"`
  );

  const projectId = process.env.GCLOUD_PROJECT || 'demo-suburban';
  const baseUrl = `http://${emulatorHost}/v1/projects/${projectId}/databases/(default)/documents`;

  async function restRequest(method, docPath, { token, body } = {}) {
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;
    const res = await fetch(`${baseUrl}/${docPath}`, {
      method,
      headers,
      body: body ? JSON.stringify(toFirestoreFields(body)) : undefined,
    });
    return res.status;
  }

  // Seed isolated rules-test documents using Emulator admin bypass token ("owner")
  await restRequest('PATCH', 'config/smtp_settings', {
    token: 'owner',
    body: { host: 'smtp.example.test', enabled: true },
  });
  await restRequest('PATCH', 'config/app_settings', {
    token: 'owner',
    body: { paymentCutoffDay: 10, gracePeriodDays: 5 },
  });
  await restRequest('PATCH', 'documents/rules_admin_doc', {
    token: 'owner',
    body: { title: 'Board Minutes', visibility: 'admin' },
  });
  await restRequest('PATCH', 'documents/rules_public_doc', {
    token: 'owner',
    body: { title: 'Community Bylaws', visibility: 'all' },
  });
  await restRequest('PATCH', 'users/rules_res_1', {
    token: 'owner',
    body: { uid: 'rules_res_1', name: 'Rule Resident', email: 'r@test.local', role: 'resident' },
  });
  await restRequest('PATCH', 'sanctions/rules_sanc_1', {
    token: 'owner',
    body: { id: 'rules_sanc_1', residentUid: 'rules_res_1', authorizedUids: ['rules_res_1'], status: 'active', amount: 300 },
  });

  const residentJwt = buildLocalEmulatorJwt('rules_res_1', { resident: true });
  const adminJwt = buildLocalEmulatorJwt('rules_admin_1', { admin: true });

  // 1. Unauthenticated access is denied
  assert.equal(await restRequest('GET', 'users/rules_res_1'), 403);
  assert.equal(await restRequest('GET', 'documents/rules_public_doc'), 403);

  // 2. SMTP credentials doc is hidden from residents, while app_settings is readable
  assert.equal(await restRequest('GET', 'config/smtp_settings', { token: residentJwt }), 403);
  assert.equal(await restRequest('GET', 'config/app_settings', { token: residentJwt }), 200);
  assert.equal(await restRequest('GET', 'config/smtp_settings', { token: adminJwt }), 200);

  // 3. Transparency visibility isolation: resident blocked from 'admin' doc, allowed on 'all' doc
  assert.equal(await restRequest('GET', 'documents/rules_admin_doc', { token: residentJwt }), 403);
  assert.equal(await restRequest('GET', 'documents/rules_public_doc', { token: residentJwt }), 200);
  assert.equal(await restRequest('GET', 'documents/rules_admin_doc', { token: adminJwt }), 200);

  // 4. Resident cannot escalate their own role to 'admin'
  assert.equal(
    await restRequest('PATCH', 'users/rules_res_1?updateMask.fieldPaths=role', {
      token: residentJwt,
      body: { role: 'admin' },
    }),
    403
  );

  // 5. Resident can submit sanction receipt (active -> pending_review) but CANNOT self-clear to 'paid'
  assert.equal(
    await restRequest('PATCH', 'sanctions/rules_sanc_1?updateMask.fieldPaths=status', {
      token: residentJwt,
      body: { status: 'paid' },
    }),
    403
  );
  assert.equal(
    await restRequest('PATCH', 'sanctions/rules_sanc_1?updateMask.fieldPaths=status&updateMask.fieldPaths=paymentId', {
      token: residentJwt,
      body: { status: 'pending_review', paymentId: 'pay_123' },
    }),
    200
  );
});
