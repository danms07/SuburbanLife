const test = require('node:test');
const assert = require('node:assert/strict');
const {
  parseCliArgs,
  extractAddressId,
  isAdminOfficeAddress,
  buildRoleClaims,
  resolveUserAddressUpdate,
} = require('../set_role.js');

test('parseCliArgs parses positional arguments and optional flags', () => {
  const parsed = parseCliArgs([
    'node',
    'scripts/set_role.js',
    'famorpm@mail.com',
    'admin',
    '--emulator',
    '--with-resident',
    '--password=Secret123!',
    '--name=Francisco',
  ]);

  assert.equal(parsed.identifier, 'famorpm@mail.com');
  assert.equal(parsed.role, 'admin');
  assert.equal(parsed.isEmulator, true);
  assert.equal(parsed.withResident, true);
  assert.equal(parsed.passwordArg, 'Secret123!');
  assert.equal(parsed.nameArg, 'Francisco');
  assert.equal(parsed.showHelp, false);
});

test('extractAddressId handles strings, Firestore DocumentReferences, and nulls', () => {
  assert.equal(extractAddressId(null), null);
  assert.equal(extractAddressId(''), null);
  assert.equal(extractAddressId('addresses/MqLBbleqAI34DjZAezxH'), 'MqLBbleqAI34DjZAezxH');
  assert.equal(extractAddressId('MqLBbleqAI34DjZAezxH'), 'MqLBbleqAI34DjZAezxH');
  assert.equal(extractAddressId({ id: 'admin_office' }), 'admin_office');
  assert.equal(extractAddressId({ path: 'addresses/doc_456' }), 'doc_456');
});

test('isAdminOfficeAddress identifies fixed admin office documents', () => {
  assert.equal(isAdminOfficeAddress('admin_office', null), true);
  assert.equal(isAdminOfficeAddress('custom_id', { streetName: 'Admin office' }), true);
  assert.equal(isAdminOfficeAddress('custom_id', { streetName: 'Oficina de administración' }), true);
  assert.equal(isAdminOfficeAddress('MqLBbleqAI34DjZAezxH', { streetName: 'Montecarotto' }), false);
});

test('buildRoleClaims preserves resident claim when promoting a resident to admin', () => {
  const dualClaims = buildRoleClaims({ resident: true }, 'admin', true, false);
  assert.deepEqual(dualClaims, { admin: true, resident: true });

  const pureAdminClaims = buildRoleClaims({}, 'admin', false, false);
  assert.deepEqual(pureAdminClaims, { admin: true });

  const forcedDualClaims = buildRoleClaims({}, 'admin', false, true);
  assert.deepEqual(forcedDualClaims, { admin: true, resident: true });

  const demotedResidentClaims = buildRoleClaims({ admin: true, resident: true, customKey: 1 }, 'resident', true, false);
  assert.deepEqual(demotedResidentClaims, { resident: true, customKey: 1 });
});

test('resolveUserAddressUpdate keeps or restores residential address for admin', () => {
  const houseRef = { id: 'MqLBbleqAI34DjZAezxH' };
  const adminOfficeRef = { id: 'admin_office' };

  // 1. User already points to residential address -> keep it untouched
  const keepHouse = resolveUserAddressUpdate(
    'admin',
    houseRef,
    { streetName: 'Montecarotto', number: 138 },
    [houseRef],
    adminOfficeRef
  );
  assert.equal(keepHouse.shouldUpdate, false);
  assert.equal(keepHouse.addressRef, houseRef);
  assert.equal(keepHouse.source, 'existing_residential');

  // 2. User addressRef was overwritten to admin_office, but owns a residential address -> restore houseRef
  const restoreHouse = resolveUserAddressUpdate(
    'admin',
    adminOfficeRef,
    { streetName: 'Admin office', number: 0 },
    [houseRef],
    adminOfficeRef
  );
  assert.equal(restoreHouse.shouldUpdate, true);
  assert.equal(restoreHouse.addressRef, houseRef);
  assert.equal(restoreHouse.source, 'owned_residential');

  // 3. Pure admin with no house -> link to admin_office
  const pureAdmin = resolveUserAddressUpdate(
    'admin',
    null,
    null,
    [],
    adminOfficeRef
  );
  assert.equal(pureAdmin.shouldUpdate, true);
  assert.equal(pureAdmin.addressRef, adminOfficeRef);
  assert.equal(pureAdmin.source, 'admin_office');
});

test('resolveUserAddressUpdate detaches admin_office when demoting to resident or guard', () => {
  const houseRef = { id: 'MqLBbleqAI34DjZAezxH' };
  const adminOfficeRef = { id: 'admin_office' };

  const demoteWithHouse = resolveUserAddressUpdate(
    'resident',
    adminOfficeRef,
    { streetName: 'Admin office', number: 0 },
    [houseRef],
    adminOfficeRef
  );
  assert.equal(demoteWithHouse.shouldUpdate, true);
  assert.equal(demoteWithHouse.addressRef, houseRef);
  assert.equal(demoteWithHouse.source, 'owned_residential');

  const demotePureAdmin = resolveUserAddressUpdate(
    'resident',
    adminOfficeRef,
    { streetName: 'Admin office', number: 0 },
    [],
    adminOfficeRef
  );
  assert.equal(demotePureAdmin.shouldUpdate, true);
  assert.equal(demotePureAdmin.addressRef, null);
  assert.equal(demotePureAdmin.source, 'cleared_admin_office');
});
