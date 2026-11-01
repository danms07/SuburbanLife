const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTestFactory = require('firebase-functions-test');
const cloudFunctions = require('../index.js');

const fft = functionsTestFactory();
const { _test } = cloudFunctions;

/**
 * Lightweight in-memory mock of Firebase Admin Firestore, Auth, and Storage
 * injected via `_test.admin` so callable Cloud Function wrappers (`onCall`)
 * execute end-to-end offline without network calls.
 */
function createMockAdminEnvironment(initialCollections = {}) {
  const store = new Map();
  for (const [colName, docsObj] of Object.entries(initialCollections)) {
    const colMap = new Map();
    for (const [docId, docData] of Object.entries(docsObj)) {
      colMap.set(docId, structuredClone(docData));
    }
    store.set(colName, colMap);
  }

  const authClaims = new Map();
  const createdAuthUsers = [];
  const deletedAuthUids = [];
  const savedStorageFiles = new Map();
  let autoIdCounter = 1;

  function ensureCollection(colName) {
    if (!store.has(colName)) {
      store.set(colName, new Map());
    }
    return store.get(colName);
  }

  function applyFieldSentinel(existingVal, incomingVal) {
    if (incomingVal && typeof incomingVal === 'object' && incomingVal.constructor) {
      const ctorName = incomingVal.constructor.name || '';
      if (ctorName === 'ArrayUnionTransform') {
        const current = Array.isArray(existingVal) ? [...existingVal] : [];
        const elements = incomingVal.elements || [];
        for (const el of elements) {
          if (!current.includes(el)) current.push(el);
        }
        return current;
      }
      if (ctorName === 'ArrayRemoveTransform') {
        const current = Array.isArray(existingVal) ? [...existingVal] : [];
        const elements = incomingVal.elements || [];
        return current.filter((item) => !elements.includes(item));
      }
      if (ctorName === 'DeleteTransform') {
        return undefined;
      }
      if (ctorName === 'ServerTimestampTransform') {
        return _test.admin.firestore.Timestamp.now();
      }
    }
    return incomingVal;
  }

  function mergeDoc(existing, patch) {
    const next = { ...(existing || {}) };
    for (const [key, val] of Object.entries(patch)) {
      const resolved = applyFieldSentinel(next[key], val);
      if (resolved === undefined) {
        delete next[key];
      } else {
        next[key] = resolved;
      }
    }
    return next;
  }

  function makeDocRef(colName, docId) {
    const resolvedId = docId || `auto_doc_${autoIdCounter++}`;
    return {
      id: resolvedId,
      path: `${colName}/${resolvedId}`,
      async get() {
        const col = ensureCollection(colName);
        const exists = col.has(resolvedId);
        const raw = exists ? col.get(resolvedId) : undefined;
        return {
          id: resolvedId,
          ref: this,
          exists,
          data: () => (exists ? { ...raw } : undefined),
        };
      },
      async set(data, options = {}) {
        const col = ensureCollection(colName);
        const prev = options && options.merge && col.has(resolvedId) ? col.get(resolvedId) : {};
        col.set(resolvedId, mergeDoc(prev, data));
      },
      async update(patch) {
        const col = ensureCollection(colName);
        if (!col.has(resolvedId)) {
          throw new Error(`Document ${colName}/${resolvedId} does not exist`);
        }
        col.set(resolvedId, mergeDoc(col.get(resolvedId), patch));
      },
      async delete() {
        ensureCollection(colName).delete(resolvedId);
      },
    };
  }

  function matchesFilter(docData, filter) {
    const fieldVal = docData[filter.field];
    const targetVal = filter.value;
    switch (filter.op) {
      case '==': {
        if (fieldVal && targetVal && typeof fieldVal === 'object' && typeof targetVal === 'object' && fieldVal.path && targetVal.path) {
          return fieldVal.path === targetVal.path;
        }
        return fieldVal === targetVal;
      }
      case 'in':
        return Array.isArray(targetVal) && targetVal.includes(fieldVal);
      case 'array-contains':
        return Array.isArray(fieldVal) && fieldVal.includes(targetVal);
      case '>=':
        return fieldVal >= targetVal;
      case '<=':
        return fieldVal <= targetVal;
      case '<':
        return fieldVal < targetVal;
      default:
        return true;
    }
  }

  function buildQuery(colName, filters = [], orderSpec = null, limitCount = null) {
    return {
      where(field, op, value) {
        return buildQuery(colName, [...filters, { field, op, value }], orderSpec, limitCount);
      },
      orderBy(field, direction = 'asc') {
        return buildQuery(colName, filters, { field, direction }, limitCount);
      },
      limit(n) {
        return buildQuery(colName, filters, orderSpec, n);
      },
      async get() {
        const col = ensureCollection(colName);
        let entries = Array.from(col.entries()).filter(([, data]) =>
          filters.every((f) => matchesFilter(data, f))
        );
        if (orderSpec) {
          entries.sort(([, a], [, b]) => {
            const va = a[orderSpec.field] ?? 0;
            const vb = b[orderSpec.field] ?? 0;
            const vaNum = typeof va?.toMillis === 'function' ? va.toMillis() : va;
            const vbNum = typeof vb?.toMillis === 'function' ? vb.toMillis() : vb;
            if (vaNum === vbNum) return 0;
            const cmp = vaNum < vbNum ? -1 : 1;
            return orderSpec.direction === 'desc' ? -cmp : cmp;
          });
        }
        if (typeof limitCount === 'number') {
          entries = entries.slice(0, limitCount);
        }
        const docs = entries.map(([id, data]) => ({
          id,
          ref: makeDocRef(colName, id),
          exists: true,
          data: () => ({ ...data }),
        }));
        return {
          empty: docs.length === 0,
          size: docs.length,
          docs,
        };
      },
    };
  }

  const dbMock = {
    collection(colName) {
      const baseQuery = buildQuery(colName);
      return {
        ...baseQuery,
        doc(docId) {
          return makeDocRef(colName, docId);
        },
        async add(data) {
          const ref = makeDocRef(colName);
          await ref.set(data);
          return ref;
        },
      };
    },
    doc(fullPath) {
      const parts = fullPath.split('/');
      return makeDocRef(parts[0], parts[1]);
    },
    batch() {
      const ops = [];
      return {
        set(ref, data, opts) {
          ops.push(() => ref.set(data, opts));
        },
        update(ref, patch) {
          ops.push(() => ref.update(patch));
        },
        delete(ref) {
          ops.push(() => ref.delete());
        },
        async commit() {
          for (const op of ops) {
            await op();
          }
        },
      };
    },
    async runTransaction(updateFn) {
      const stagedWrites = [];
      const tx = {
        async get(refOrQuery) {
          return refOrQuery.get();
        },
        set(ref, data, opts) {
          stagedWrites.push(() => ref.set(data, opts));
        },
        update(ref, patch) {
          stagedWrites.push(() => ref.update(patch));
        },
        delete(ref) {
          stagedWrites.push(() => ref.delete());
        },
      };
      const result = await updateFn(tx);
      for (const write of stagedWrites) {
        await write();
      }
      return result;
    },
  };

  const authMock = {
    async setCustomUserClaims(uid, claims) {
      authClaims.set(uid, { ...claims });
    },
    async createUser({ email, password, displayName }) {
      const uid = `auth_uid_${autoIdCounter++}`;
      createdAuthUsers.push({ uid, email, hasPassword: Boolean(password), displayName });
      return { uid, email, displayName };
    },
    async updateUser(uid, patch) {
      return { uid, ...patch };
    },
    async deleteUser(uid) {
      deletedAuthUids.push(uid);
    },
  };

  const storageMock = {
    bucket() {
      return {
        name: 'test-catania-bucket',
        file(storagePath) {
          return {
            async save(buffer, options) {
              savedStorageFiles.set(storagePath, { buffer, options });
            },
          };
        },
      };
    },
  };

  return {
    dbMock,
    authMock,
    storageMock,
    store,
    authClaims,
    createdAuthUsers,
    deletedAuthUids,
    savedStorageFiles,
    makeDocRef,
  };
}

function installMockAdmin(t, env) {
  const originalFirestore = _test.admin.firestore;
  const originalAuth = _test.admin.auth;
  const originalStorage = _test.admin.storage;

  _test.admin.firestore = Object.assign(() => env.dbMock, {
    FieldValue: originalFirestore.FieldValue,
    Timestamp: originalFirestore.Timestamp,
  });
  _test.admin.auth = () => env.authMock;
  _test.admin.storage = () => env.storageMock;

  t.after(() => {
    _test.admin.firestore = originalFirestore;
    _test.admin.auth = originalAuth;
    _test.admin.storage = originalStorage;
  });
}

async function assertHttpsErrorCode(promise, expectedCode) {
  await assert.rejects(
    promise,
    (err) => {
      assert.equal(err.code, expectedCode, `Expected HttpsError "${expectedCode}" but got "${err.code}": ${err.message}`);
      return true;
    }
  );
}

test.after(() => {
  fft.cleanup();
});

test('Unauthenticated requests are rejected across all protected callable Cloud Functions', async (t) => {
  const env = createMockAdminEnvironment();
  installMockAdmin(t, env);

  const expectations = [
    ['setRole', { uid: 'u1', role: 'resident' }, 'failed-precondition'],
    ['setCustomUserClaims', { uid: 'u1', claims: { resident: true } }, 'failed-precondition'],
    ['approvePayment', { paymentId: 'p1', residentUid: 'u1' }, 'failed-precondition'],
    ['addRoommate', { email: 'r@test.com' }, 'unauthenticated'],
    ['removeRoommate', { roommateUid: 'r1' }, 'unauthenticated'],
    ['unbindAddress', { uid: 'u1' }, 'unauthenticated'],
    ['deleteOwnAccount', {}, 'unauthenticated'],
    ['createBooking', { facilityId: 'pool', startTime: 1000, endTime: 2000 }, 'unauthenticated'],
    ['cancelBooking', { bookingId: 'b1' }, 'unauthenticated'],
    ['validateAndRegisterQrAccess', { qrId: 'qr1' }, 'permission-denied'],
    ['syncTransparencyDocument', { title: 'Doc', fileName: 'a.pdf', url: 'https://example.com/a.pdf' }, 'permission-denied'],
    ['adminCreateUser', { name: 'A', email: 'a@b.com', password: 'Password1!', role: 'guard' }, 'failed-precondition'],
    ['adminDeleteUser', { uid: 'u1' }, 'failed-precondition'],
  ];

  for (const [fnName, payload, expectedCode] of expectations) {
    const wrapped = fft.wrap(cloudFunctions[fnName]);
    await assertHttpsErrorCode(wrapped({ data: payload, auth: null }), expectedCode);
  }
});

test('RBAC: Non-admin resident cannot escalate privileges or invoke admin/guard callables', async (t) => {
  const env = createMockAdminEnvironment({
    users: {
      res_caller: { uid: 'res_caller', role: 'resident' },
      other_user: { uid: 'other_user', role: 'resident' },
    },
  });
  installMockAdmin(t, env);

  const residentAuth = {
    uid: 'res_caller',
    token: { resident: true, admin: false, guard: false },
  };

  await assertHttpsErrorCode(
    fft.wrap(cloudFunctions.setRole)({ data: { uid: 'res_caller', role: 'admin' }, auth: residentAuth }),
    'failed-precondition'
  );
  await assertHttpsErrorCode(
    fft.wrap(cloudFunctions.setCustomUserClaims)({ data: { uid: 'res_caller', claims: { admin: true } }, auth: residentAuth }),
    'failed-precondition'
  );
  await assertHttpsErrorCode(
    fft.wrap(cloudFunctions.approvePayment)({ data: { paymentId: 'pay_1', residentUid: 'res_caller' }, auth: residentAuth }),
    'failed-precondition'
  );
  await assertHttpsErrorCode(
    fft.wrap(cloudFunctions.validateAndRegisterQrAccess)({ data: { qrId: 'qr_1' }, auth: residentAuth }),
    'permission-denied'
  );
  await assertHttpsErrorCode(
    fft.wrap(cloudFunctions.syncTransparencyDocument)({ data: { title: 'T', fileName: 'f.pdf', url: 'https://x.test/f.pdf' }, auth: residentAuth }),
    'permission-denied'
  );
  // Resident cannot unbind a DIFFERENT resident's address
  await assertHttpsErrorCode(
    fft.wrap(cloudFunctions.unbindAddress)({ data: { uid: 'other_user' }, auth: residentAuth }),
    'permission-denied'
  );
});

test('setRole and setCustomUserClaims enforce role allow-lists, strip rogue claims, and block self-admin revocation', async (t) => {
  const env = createMockAdminEnvironment();
  installMockAdmin(t, env);

  const adminAuth = { uid: 'admin_1', token: { admin: true } };
  const setRoleWrapped = fft.wrap(cloudFunctions.setRole);
  const setClaimsWrapped = fft.wrap(cloudFunctions.setCustomUserClaims);

  await assertHttpsErrorCode(
    setRoleWrapped({ data: { uid: 'u1', role: 'superroot' }, auth: adminAuth }),
    'invalid-argument'
  );

  const roleRes = await setRoleWrapped({ data: { uid: 'u1', role: 'guard' }, auth: adminAuth });
  assert.equal(roleRes.success, true);
  assert.deepEqual(env.authClaims.get('u1'), { guard: true });

  // Self-admin revocation must fail with permission-denied
  await assertHttpsErrorCode(
    setClaimsWrapped({ data: { uid: 'admin_1', claims: { admin: false, resident: true } }, auth: adminAuth }),
    'permission-denied'
  );

  // Unrecognized keys (e.g., superAdmin) are stripped before writing Firebase Auth claims
  const claimRes = await setClaimsWrapped({
    data: { uid: 'u2', claims: { admin: true, resident: true, superAdmin: true } },
    auth: adminAuth,
  });
  assert.equal(claimRes.success, true);
  assert.deepEqual(env.authClaims.get('u2'), { admin: true, resident: true });
});

test('approvePayment enforces Segregation of Duties and resolves linked sanctions on valid approval', async (t) => {
  const env = createMockAdminEnvironment();
  const addrRef = env.makeDocRef('addresses', 'addr_1');
  await addrRef.set({
    id: 'addr_1',
    streetName: 'Loreto',
    number: 101,
    residentUid: 'res_1',
    paymentStatus: 'restricted',
    deliveryDate: null,
  });
  await env.makeDocRef('users', 'res_1').set({
    uid: 'res_1',
    role: 'resident',
    addressRef: addrRef,
  });
  await env.makeDocRef('sanctions', 'sanc_1').set({
    id: 'sanc_1',
    addressRef: addrRef,
    status: 'pending_review',
    amount: 500,
  });
  await env.makeDocRef('payments', 'pay_self').set({
    id: 'pay_self',
    residentUid: 'admin_1',
    uploaderUid: 'admin_1',
    status: 'pending',
    amount: 1500,
  });
  await env.makeDocRef('payments', 'pay_sanc').set({
    id: 'pay_sanc',
    residentUid: 'res_1',
    uploaderUid: 'res_1',
    addressRef: addrRef,
    concept: 'sanction',
    sanctionId: 'sanc_1',
    status: 'pending',
    amount: 500,
  });
  installMockAdmin(t, env);

  const approveWrapped = fft.wrap(cloudFunctions.approvePayment);
  const adminAuth = { uid: 'admin_1', token: { admin: true } };

  // 1. Admin cannot approve their own uploaded payment proof
  await assertHttpsErrorCode(
    approveWrapped({ data: { paymentId: 'pay_self', residentUid: 'admin_1' }, auth: adminAuth }),
    'permission-denied'
  );

  // 2. Non-existent payment returns not-found (not swallowed into internal)
  await assertHttpsErrorCode(
    approveWrapped({ data: { paymentId: 'missing_pay', residentUid: 'res_1' }, auth: adminAuth }),
    'not-found'
  );

  // 3. Valid sanction payment approval marks payment approved, sanction paid, and restores address to paid
  const res = await approveWrapped({
    data: { paymentId: 'pay_sanc', residentUid: 'res_1' },
    auth: adminAuth,
  });
  assert.equal(res.success, true);

  const updatedPayment = env.store.get('payments').get('pay_sanc');
  assert.equal(updatedPayment.status, 'approved');

  const updatedSanction = env.store.get('sanctions').get('sanc_1');
  assert.equal(updatedSanction.status, 'paid');

  const updatedAddress = env.store.get('addresses').get('addr_1');
  assert.equal(updatedAddress.paymentStatus, 'paid');
});

test('addRoommate and removeRoommate link QR-prefixed UID, enforce self-add guard, and unlink cleanly', async (t) => {
  const env = createMockAdminEnvironment();
  const addrRef = env.makeDocRef('addresses', 'addr_202');
  await addrRef.set({ id: 'addr_202', streetName: 'Catania', number: 202, paymentStatus: 'paid' });
  await env.makeDocRef('users', 'primary_res').set({
    uid: 'primary_res',
    role: 'resident',
    addressRef: addrRef,
    familyMembers: [],
  });
  await env.makeDocRef('users', 'roommate_candidate').set({
    uid: 'roommate_candidate',
    name: 'Sofia Roommate',
    email: 'sofia@test.com',
    role: 'resident',
    addressRef: null,
  });
  installMockAdmin(t, env);

  const residentAuth = { uid: 'primary_res', token: { resident: true } };
  const addWrapped = fft.wrap(cloudFunctions.addRoommate);
  const removeWrapped = fft.wrap(cloudFunctions.removeRoommate);

  // Cannot add oneself as roommate
  await assertHttpsErrorCode(
    addWrapped({ data: { roommateUid: 'roommate_uid:primary_res' }, auth: residentAuth }),
    'invalid-argument'
  );

  // Strips 'roommate_uid:' prefix from scanned QR code and binds household
  const addRes = await addWrapped({
    data: { roommateUid: 'roommate_uid:roommate_candidate' },
    auth: residentAuth,
  });
  assert.equal(addRes.success, true);
  assert.deepEqual(env.authClaims.get('roommate_candidate'), { roommate: true });
  assert.equal(env.store.get('users').get('roommate_candidate').role, 'roommate');
  assert.equal(env.store.get('users').get('roommate_candidate').addressRef.id, 'addr_202');
  assert.deepEqual(env.store.get('users').get('primary_res').familyMembers, ['roommate_candidate']);

  // Primary resident removes roommate
  const remRes = await removeWrapped({
    data: { roommateUid: 'roommate_candidate' },
    auth: residentAuth,
  });
  assert.equal(remRes.success, true);
  assert.equal(env.store.get('users').get('roommate_candidate').addressRef, null);
  assert.deepEqual(env.store.get('users').get('primary_res').familyMembers, []);
  assert.deepEqual(env.authClaims.get('roommate_candidate'), {});
});

test('validateAndRegisterQrAccess handles restricted resident denial, entry tracking, and exit deactivation', async (t) => {
  const env = createMockAdminEnvironment();
  const paidAddrRef = env.makeDocRef('addresses', 'addr_paid');
  const restrictedAddrRef = env.makeDocRef('addresses', 'addr_restricted');

  await env.makeDocRef('config', 'app_settings').set({ scanOnExitEnabled: true, timeZone: 'America/Mexico_City' });
  await env.makeDocRef('users', 'guard_1').set({ uid: 'guard_1', name: 'Officer Mendez', role: 'guard' });
  await paidAddrRef.set({ id: 'addr_paid', streetName: 'Loreto', number: 10, paymentStatus: 'paid' });
  await restrictedAddrRef.set({ id: 'addr_restricted', streetName: 'Loreto', number: 99, paymentStatus: 'restricted', isWithinGracePeriod: false });

  await env.makeDocRef('users', 'res_paid').set({ uid: 'res_paid', name: 'Paid Owner', addressRef: paidAddrRef });
  await env.makeDocRef('users', 'res_unpaid').set({ uid: 'res_unpaid', name: 'Unpaid Owner', addressRef: restrictedAddrRef });

  // 1. Supplier one-time pass for paid resident
  await env.makeDocRef('qr_codes', 'qr_supplier_1').set({
    id: 'qr_supplier_1',
    creatorUid: 'res_paid',
    guestName: 'Water Delivery',
    accessCategory: 'supplier',
    isOneTime: true,
    status: 'active',
    isValid: true,
    expiresAt: Date.now() + 3600_000,
  });

  // 2. Pass created by restricted resident
  await env.makeDocRef('qr_codes', 'qr_restricted_1').set({
    id: 'qr_restricted_1',
    creatorUid: 'res_unpaid',
    guestName: 'Blocked Visitor',
    accessCategory: 'visitor',
    status: 'active',
    isValid: true,
    expiresAt: Date.now() + 3600_000,
  });

  installMockAdmin(t, env);
  const validateWrapped = fft.wrap(cloudFunctions.validateAndRegisterQrAccess);
  const guardAuth = { uid: 'guard_1', token: { guard: true } };

  // Restricted resident QR must be denied and logged
  const deniedRes = await validateWrapped({
    data: { qrId: 'qr_restricted_1', mode: 'validate_and_register' },
    auth: guardAuth,
  });
  assert.equal(deniedRes.granted, false);
  assert.match(deniedRes.reason, /restricted/i);

  // Entry scan for supplier pass with scanOnExitEnabled: marks isInside=true and keeps pass active for exit scan
  const entryRes = await validateWrapped({
    data: { qrId: 'qr_supplier_1', mode: 'validate_and_register' },
    auth: guardAuth,
  });
  assert.equal(entryRes.granted, true);
  assert.equal(entryRes.isExit, false);

  const qrAfterEntry = env.store.get('qr_codes').get('qr_supplier_1');
  assert.equal(qrAfterEntry.isInside, true);
  assert.ok(qrAfterEntry.activeAccessLogId);
  assert.equal(qrAfterEntry.status, 'active');

  // Second scan automatically registers EXIT and deactivates one-time supplier pass
  const exitRes = await validateWrapped({
    data: { qrId: 'qr_supplier_1', mode: 'validate_and_register', reason: 'Left gate' },
    auth: guardAuth,
  });
  assert.equal(exitRes.granted, true);
  assert.equal(exitRes.isExit, true);

  const qrAfterExit = env.store.get('qr_codes').get('qr_supplier_1');
  assert.equal(qrAfterExit.isInside, false);
  assert.equal(qrAfterExit.status, 'deactivated (validated)');
  assert.equal(qrAfterExit.isValid, false);

  const closedLog = env.store.get('access_logs').get(qrAfterEntry.activeAccessLogId);
  assert.equal(closedLog.isInside, false);
  assert.equal(closedLog.exitGuardName, 'Officer Mendez');
  assert.equal(closedLog.exitReason, 'Left gate');
});

test('syncTransparencyDocument validates PDF magic header, strips path traversal, and isolates admin_only storage prefix', async (t) => {
  const env = createMockAdminEnvironment();
  installMockAdmin(t, env);

  const syncWrapped = fft.wrap(cloudFunctions.syncTransparencyDocument);
  const adminAuth = { uid: 'admin_1', token: { admin: true } };

  // 1. Fake PDF without %PDF- magic bytes must be rejected
  const invalidPdfBase64 = Buffer.from('NOT_A_PDF_HEADER').toString('base64');
  await assertHttpsErrorCode(
    syncWrapped({
      data: {
        title: 'Spoofed File',
        fileName: 'spoof.pdf',
        fileType: 'pdf',
        visibility: 'all',
        fileBase64: invalidPdfBase64,
      },
      auth: adminAuth,
    }),
    'invalid-argument'
  );

  // 2. Valid PDF with traversal characters in fileName and visibility='admin' uploads under documents/admin_only/
  const validPdfBase64 = Buffer.from('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n').toString('base64');
  const res = await syncWrapped({
    data: {
      docId: 'audit_2026',
      title: 'Internal Board Audit',
      fileName: '../../etc/secret_audit.pdf',
      fileType: 'pdf',
      visibility: 'admin',
      fileBase64: validPdfBase64,
    },
    auth: adminAuth,
  });

  assert.equal(res.success, true);
  assert.equal(res.visibility, 'admin');
  assert.equal(res.storagePath, 'documents/admin_only/audit_2026_secret_audit.pdf');
  assert.ok(env.savedStorageFiles.has('documents/admin_only/audit_2026_secret_audit.pdf'));

  const savedMeta = env.savedStorageFiles.get('documents/admin_only/audit_2026_secret_audit.pdf').options.metadata;
  assert.equal(savedMeta.contentType, 'application/pdf');
  assert.match(savedMeta.contentDisposition, /^attachment;/);
  assert.equal(savedMeta.metadata.visibility, 'admin');

  const storedDoc = env.store.get('documents').get('audit_2026');
  assert.equal(storedDoc.fileName, 'secret_audit.pdf');
  assert.equal(storedDoc.visibility, 'admin');
});
