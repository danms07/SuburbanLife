const test = require('node:test');
const assert = require('node:assert/strict');
const {
  extractAddressId,
  buildResidentUsersMap,
  isLinkedToResident,
  evaluateAddressUpdate,
  buildUpdatePayload,
  parseCliArgs,
} = require('../set_resident_addresses_paid.js');

test('extractAddressId extracts ID from various reference formats', () => {
  assert.equal(extractAddressId(null), null);
  assert.equal(extractAddressId(undefined), null);
  assert.equal(extractAddressId(''), null);
  assert.equal(extractAddressId('addresses/1st_Avenue_99'), '1st_Avenue_99');
  assert.equal(extractAddressId('1st_Avenue_99'), '1st_Avenue_99');
  assert.equal(extractAddressId({ id: 'doc_123' }), 'doc_123');
  assert.equal(extractAddressId({ path: 'addresses/doc_123' }), null);
});

test('buildResidentUsersMap indexes residents and roommates correctly', () => {
  const users = [
    {
      id: 'res_1',
      role: 'resident',
      name: 'John Doe',
      email: 'john@example.com',
      addressRef: { id: 'addr_1' },
    },
    {
      id: 'room_1',
      role: 'roommate',
      name: 'Jane Doe',
      email: 'jane@example.com',
      addressRef: 'addresses/addr_1',
    },
    {
      id: 'guard_1',
      role: 'guard',
      name: 'Guard Bob',
      email: 'guard@example.com',
      addressRef: { id: 'guard_house' },
    },
    {
      id: 'admin_1',
      role: 'admin',
      name: 'Admin Alice',
      email: 'admin@example.com',
      addressRef: { id: 'admin_office' },
    },
    {
      id: 'unlinked_res',
      role: 'resident',
      name: 'Unlinked',
      email: 'unlinked@example.com',
      addressRef: null,
    },
  ];

  const map = buildResidentUsersMap(users);
  assert.equal(map.size, 1);
  assert.ok(map.has('addr_1'));
  // Resident takes precedence over roommate
  assert.equal(map.get('addr_1').uid, 'res_1');
  assert.equal(map.get('addr_1').email, 'john@example.com');
  // Admin office should never be mapped as resident address
  assert.equal(map.has('admin_office'), false);
});

test('isLinkedToResident identifies linked vs unclaimed addresses', () => {
  const residentMap = new Map([
    ['addr_reverse', { uid: 'user_rev_1', name: 'Reverse Linked', email: 'rev@test.com' }],
  ]);

  // 1. Direct link on address document
  const directlyLinked = isLinkedToResident({ residentUid: 'user_direct_1' }, 'addr_direct', residentMap);
  assert.equal(directlyLinked.isLinked, true);
  assert.equal(directlyLinked.residentUid, 'user_direct_1');

  // 2. Reverse link via users collection map
  const reverseLinked = isLinkedToResident({ residentUid: null }, 'addr_reverse', residentMap);
  assert.equal(reverseLinked.isLinked, true);
  assert.equal(reverseLinked.residentUid, 'user_rev_1');

  // 3. Unclaimed address
  const unclaimed1 = isLinkedToResident({ residentUid: null }, 'addr_unclaimed', residentMap);
  assert.equal(unclaimed1.isLinked, false);
  assert.equal(unclaimed1.residentUid, null);

  const unclaimed2 = isLinkedToResident({ residentUid: '   ' }, 'addr_empty_str', residentMap);
  assert.equal(unclaimed2.isLinked, false);

  const unclaimed3 = isLinkedToResident(null, 'addr_null', residentMap);
  assert.equal(unclaimed3.isLinked, false);

  // 4. Admin office exclusions
  const adminDoc1 = isLinkedToResident({ residentUid: 'admin_uid' }, 'admin_office', residentMap);
  assert.equal(adminDoc1.isLinked, false);

  const adminDoc2 = isLinkedToResident({ streetName: 'Admin office', residentUid: 'admin_uid' }, 'custom_id', residentMap);
  assert.equal(adminDoc2.isLinked, false);

  const adminDoc3 = isLinkedToResident({ streetName: 'Oficina de administración', residentUid: 'admin_uid' }, 'custom_id_2', residentMap);
  assert.equal(adminDoc3.isLinked, false);
});

test('evaluateAddressUpdate accurately detects required status transitions', () => {
  const residentMap = new Map([
    ['addr_1', { uid: 'u1' }],
    ['addr_2', { uid: 'u2' }],
    ['addr_3', { uid: 'u3' }],
  ]);

  // Unlinked address
  const unlinked = evaluateAddressUpdate({ residentUid: null }, 'addr_unlinked', residentMap);
  assert.equal(unlinked.isLinked, false);
  assert.equal(unlinked.needsUpdate, false);

  // Linked address with pending status
  const pending = evaluateAddressUpdate(
    { residentUid: 'u1', paymentStatus: 'pending' },
    'addr_1',
    residentMap
  );
  assert.equal(pending.isLinked, true);
  assert.equal(pending.needsUpdate, true);
  assert.equal(pending.currentStatus, 'pending');

  // Linked address with restricted status
  const restricted = evaluateAddressUpdate(
    { residentUid: 'u2', paymentStatus: 'restricted' },
    'addr_2',
    residentMap
  );
  assert.equal(restricted.isLinked, true);
  assert.equal(restricted.needsUpdate, true);
  assert.equal(restricted.currentStatus, 'restricted');

  // Linked address already paid (no force)
  const paidNoForce = evaluateAddressUpdate(
    { residentUid: 'u3', paymentStatus: 'paid' },
    'addr_3',
    residentMap,
    { force: false }
  );
  assert.equal(paidNoForce.isLinked, true);
  assert.equal(paidNoForce.needsUpdate, false);
  assert.equal(paidNoForce.currentStatus, 'paid');

  // Linked address already paid (with force: true)
  const paidWithForce = evaluateAddressUpdate(
    { residentUid: 'u3', paymentStatus: 'paid' },
    'addr_3',
    residentMap,
    { force: true }
  );
  assert.equal(paidWithForce.isLinked, true);
  assert.equal(paidWithForce.needsUpdate, true);
  assert.equal(paidWithForce.currentStatus, 'paid');
});

test('buildUpdatePayload produces correct Firestore update fields', () => {
  const mockTimestamp = { _seconds: 1234567890 };

  // Case 1: Address already had residentUid
  const payload1 = buildUpdatePayload(
    { residentUid: 'u1', streetName: 'Main St', number: 10 },
    'u1',
    mockTimestamp
  );
  assert.equal(payload1.paymentStatus, 'paid');
  assert.equal(payload1.isWithinGracePeriod, true);
  assert.equal(payload1.updatedAt, mockTimestamp);
  assert.equal(payload1.residentUid, undefined); // should not re-set if already present

  // Case 2: Address was linked via user collection and lacked residentUid on doc
  const payload2 = buildUpdatePayload(
    { residentUid: null, streetName: 'Main St', number: 12 },
    'u2',
    mockTimestamp
  );
  assert.equal(payload2.paymentStatus, 'paid');
  assert.equal(payload2.isWithinGracePeriod, true);
  assert.equal(payload2.residentUid, 'u2');
  assert.equal(payload2.updatedAt, mockTimestamp);
});

test('parseCliArgs handles all supported CLI flags and defaults', () => {
  const defaults = parseCliArgs([]);
  assert.equal(defaults.isDryRun, false);
  assert.equal(defaults.isForce, false);
  assert.equal(defaults.isHelp, false);
  assert.equal(defaults.isQuiet, false);

  const custom = parseCliArgs([
    '--emulator',
    '--dry-run',
    '--force',
    '--quiet',
    '--project=my-test-project',
  ]);
  assert.equal(custom.isEmulator, true);
  assert.equal(custom.isDryRun, true);
  assert.equal(custom.isForce, true);
  assert.equal(custom.isQuiet, true);
  assert.equal(custom.projectId, 'my-test-project');

  const shortFlags = parseCliArgs(['-e', '-d', '-f', '-q', '-h']);
  assert.equal(shortFlags.isEmulator, true);
  assert.equal(shortFlags.isDryRun, true);
  assert.equal(shortFlags.isForce, true);
  assert.equal(shortFlags.isQuiet, true);
  assert.equal(shortFlags.isHelp, true);
});
