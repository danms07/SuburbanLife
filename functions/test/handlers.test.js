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
      case '<=':
      case '<': {
        if (fieldVal === undefined || fieldVal === null) return false;
        const normalizeComparable = (val) => {
          if (val && typeof val === 'object') {
            if (typeof val.toMillis === 'function') return val.toMillis();
            if (val instanceof Date) return val.getTime();
            if (typeof val._seconds === 'number') {
              return val._seconds * 1000 + Math.floor((val._nanoseconds || 0) / 1e6);
            }
          }
          return val;
        };
        const left = normalizeComparable(fieldVal);
        const right = normalizeComparable(targetVal);
        if (filter.op === '>=') return left >= right;
        if (filter.op === '<=') return left <= right;
        return left < right;
      }
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

  const deletedStoragePaths = [];
  const storageMock = {
    bucket() {
      return {
        name: 'test-catania-bucket',
        file(storagePath) {
          return {
            async save(buffer, options) {
              savedStorageFiles.set(storagePath, { buffer, options });
            },
            async download(options = {}) {
              if (!savedStorageFiles.has(storagePath)) {
                const err = new Error(`Not Found: ${storagePath}`);
                err.code = 404;
                throw err;
              }
              const entry = savedStorageFiles.get(storagePath);
              const buf = Buffer.isBuffer(entry.buffer)
                ? entry.buffer
                : Buffer.from(entry.buffer || '');
              const start = typeof options.start === 'number' ? options.start : 0;
              const end =
                typeof options.end === 'number' ? options.end + 1 : buf.length;
              return [buf.subarray(start, end)];
            },
            async delete(options = {}) {
              deletedStoragePaths.push({ storagePath, options });
              if (!savedStorageFiles.has(storagePath)) {
                if (options && options.ignoreNotFound) {
                  return;
                }
                const err = new Error(`Not Found: ${storagePath}`);
                err.code = 404;
                throw err;
              }
              savedStorageFiles.delete(storagePath);
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
    deletedStoragePaths,
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

test('createBooking enforces household-wide cooldown (incl. roommate & legacy bookings), sanctions, and resubmitBookingId', async (t) => {
  const env = createMockAdminEnvironment();
  const addrRef = env.makeDocRef('addresses', 'addr_household_1');
  const otherAddrRef = env.makeDocRef('addresses', 'addr_household_2');

  await env.makeDocRef('config', 'app_settings').set({ timeZone: 'UTC' });
  await addrRef.set({
    id: 'addr_household_1',
    streetName: 'Loreto',
    number: 12,
    paymentStatus: 'paid',
    hasActiveSanctions: false,
  });
  await otherAddrRef.set({
    id: 'addr_household_2',
    streetName: 'Loreto',
    number: 14,
    paymentStatus: 'paid',
    hasActiveSanctions: false,
  });

  await env.makeDocRef('users', 'primary_uid').set({
    uid: 'primary_uid',
    name: 'Primary Resident',
    role: 'resident',
    addressRef: addrRef,
  });
  await env.makeDocRef('users', 'roommate_uid').set({
    uid: 'roommate_uid',
    name: 'Linked Roommate',
    role: 'roommate',
    addressRef: addrRef,
  });
  await env.makeDocRef('users', 'neighbor_uid').set({
    uid: 'neighbor_uid',
    name: 'Neighbor Resident',
    role: 'resident',
    addressRef: otherAddrRef,
  });

  // Facility with 4-hour cooldown and capacity 2 (so capacity doesn't block, only household cooldown)
  await env.makeDocRef('facilities', 'bbq_hours').set({
    id: 'bbq_hours',
    name: 'BBQ Grill 1',
    quantity: 2,
    restrictionType: 'cooldown',
    cooldownUnit: 'hours',
    cooldownValue: 4,
    openingTime: '00:00',
    closingTime: '23:59',
    anticipationUnit: 'unrestricted',
    anticipationValue: 0,
  });

  // Seed a legacy pre-refactor booking (no addressId) created by primary_uid: 10:00 - 12:00 UTC
  const dayBase = Date.UTC(2027, 4, 10, 0, 0, 0);
  await env.makeDocRef('bookings', 'legacy_b1').set({
    facilityId: 'bbq_hours',
    userUid: 'primary_uid',
    startTime: dayBase + 10 * 3600_000,
    endTime: dayBase + 12 * 3600_000,
    status: 'pending review',
    isConfirmed: false,
  });

  installMockAdmin(t, env);
  const createWrapped = fft.wrap(cloudFunctions.createBooking);
  const primaryAuth = { uid: 'primary_uid', token: { resident: true } };
  const roommateAuth = { uid: 'roommate_uid', token: { roommate: true } };
  const neighborAuth = { uid: 'neighbor_uid', token: { resident: true } };

  // 1. Linked roommate tries to book 14:00 - 16:00 (only 2h after primary's 12:00 end; needs 4h) -> blocked!
  await assertHttpsErrorCode(
    createWrapped({
      data: {
        facilityId: 'bbq_hours',
        startTime: dayBase + 14 * 3600_000,
        endTime: dayBase + 16 * 3600_000,
      },
      auth: roommateAuth,
    }),
    'failed-precondition'
  );

  // 2. Neighbor at a different address CAN book 14:00 - 16:00 (different household, capacity=2)
  const neighborRes = await createWrapped({
    data: {
      facilityId: 'bbq_hours',
      startTime: dayBase + 14 * 3600_000,
      endTime: dayBase + 16 * 3600_000,
    },
    auth: neighborAuth,
  });
  assert.equal(neighborRes.success, true);

  // 3. Linked roommate books at 16:00 - 18:00 (exact 4h gap after 12:00 end) -> allowed & persists addressId
  const roommateRes = await createWrapped({
    data: {
      facilityId: 'bbq_hours',
      startTime: dayBase + 16 * 3600_000,
      endTime: dayBase + 18 * 3600_000,
    },
    auth: roommateAuth,
  });
  assert.equal(roommateRes.success, true);
  const savedRoommateBooking = env.store.get('bookings').get(roommateRes.bookingId);
  assert.equal(savedRoommateBooking.addressId, 'addr_household_1');

  // 4. Rejected booking resubmission via resubmitBookingId
  await env.makeDocRef('bookings', 'rejected_b1').set({
    facilityId: 'bbq_hours',
    userUid: 'primary_uid',
    addressId: 'addr_household_1',
    startTime: dayBase + 10 * 3600_000,
    endTime: dayBase + 12 * 3600_000,
    status: 'rejected',
    rejectionReason: 'Rainstorm',
    isConfirmed: false,
  });

  // Neighbor cannot hijack primary_uid's rejected booking
  await assertHttpsErrorCode(
    createWrapped({
      data: {
        facilityId: 'bbq_hours',
        startTime: dayBase + 22 * 3600_000,
        endTime: dayBase + 23 * 3600_000,
        resubmitBookingId: 'rejected_b1',
      },
      auth: neighborAuth,
    }),
    'permission-denied'
  );

  // Primary resident resubmits rejected_b1 to 22:00 - 23:00 (4h after roommate's 18:00 end) -> updates in place
  const resubmitRes = await createWrapped({
    data: {
      facilityId: 'bbq_hours',
      startTime: dayBase + 22 * 3600_000,
      endTime: dayBase + 23 * 3600_000,
      resubmitBookingId: 'rejected_b1',
    },
    auth: primaryAuth,
  });
  assert.equal(resubmitRes.bookingId, 'rejected_b1');
  const resubmittedDoc = env.store.get('bookings').get('rejected_b1');
  assert.equal(resubmittedDoc.status, 'pending review');
  assert.equal(resubmittedDoc.startTime, dayBase + 22 * 3600_000);

  // 5. Active sanction on household blocks new bookings with permission-denied
  await addrRef.update({ hasActiveSanctions: true });
  await assertHttpsErrorCode(
    createWrapped({
      data: {
        facilityId: 'bbq_hours',
        startTime: dayBase + 48 * 3600_000,
        endTime: dayBase + 50 * 3600_000,
      },
      auth: primaryAuth,
    }),
    'permission-denied'
  );
});

test('createBooking enforces household calendar-period quota (daily/monthly/yearly) and frees quota when rejected/cancelled', async (t) => {
  const env = createMockAdminEnvironment();
  const addrRef = env.makeDocRef('addresses', 'addr_quota_1');

  await env.makeDocRef('config', 'app_settings').set({ timeZone: 'UTC' });
  await addrRef.set({
    id: 'addr_quota_1',
    streetName: 'Catania',
    number: 5,
    paymentStatus: 'paid',
    hasActiveSanctions: false,
  });
  await env.makeDocRef('users', 'res_q1').set({
    uid: 'res_q1',
    name: 'Quota Resident',
    role: 'resident',
    addressRef: addrRef,
  });
  await env.makeDocRef('users', 'room_q1').set({
    uid: 'room_q1',
    name: 'Quota Roommate',
    role: 'roommate',
    addressRef: addrRef,
  });

  // Facility with monthly quota of 2 bookings per household
  await env.makeDocRef('facilities', 'grill_quota').set({
    id: 'grill_quota',
    name: 'Grill Monthly Quota',
    quantity: 1,
    restrictionType: 'quota',
    quotaPeriod: 'monthly',
    quotaLimit: 2,
    openingTime: '08:00',
    closingTime: '22:00',
    anticipationUnit: 'unrestricted',
    anticipationValue: 0,
  });

  installMockAdmin(t, env);
  const createWrapped = fft.wrap(cloudFunctions.createBooking);
  const resAuth = { uid: 'res_q1', token: { resident: true } };
  const roomAuth = { uid: 'room_q1', token: { roommate: true } };

  // 1st booking in June 2027 (by primary resident) -> succeeds
  const b1 = await createWrapped({
    data: {
      facilityId: 'grill_quota',
      startTime: Date.UTC(2027, 5, 5, 10, 0, 0),
      endTime: Date.UTC(2027, 5, 5, 12, 0, 0),
    },
    auth: resAuth,
  });
  assert.equal(b1.success, true);

  // 2nd booking in June 2027 (by linked roommate) -> succeeds (reaches 2/2 monthly quota)
  const b2 = await createWrapped({
    data: {
      facilityId: 'grill_quota',
      startTime: Date.UTC(2027, 5, 12, 10, 0, 0),
      endTime: Date.UTC(2027, 5, 12, 12, 0, 0),
    },
    auth: roomAuth,
  });
  assert.equal(b2.success, true);

  // 3rd booking in June 2027 -> rejected due to monthly quota of 2
  await assertHttpsErrorCode(
    createWrapped({
      data: {
        facilityId: 'grill_quota',
        startTime: Date.UTC(2027, 5, 20, 10, 0, 0),
        endTime: Date.UTC(2027, 5, 20, 12, 0, 0),
      },
      auth: resAuth,
    }),
    'failed-precondition'
  );

  // Booking in July 2027 (next calendar month) -> succeeds!
  const julyRes = await createWrapped({
    data: {
      facilityId: 'grill_quota',
      startTime: Date.UTC(2027, 6, 3, 10, 0, 0),
      endTime: Date.UTC(2027, 6, 3, 12, 0, 0),
    },
    auth: resAuth,
  });
  assert.equal(julyRes.success, true);

  // Admin rejects 2nd June booking -> frees 1 June slot so household can book June 20!
  await env.makeDocRef('bookings', b2.bookingId).update({ status: 'rejected' });
  const b3 = await createWrapped({
    data: {
      facilityId: 'grill_quota',
      startTime: Date.UTC(2027, 5, 20, 10, 0, 0),
      endTime: Date.UTC(2027, 5, 20, 12, 0, 0),
    },
    auth: resAuth,
  });
  assert.equal(b3.success, true);
});

test('validateAndRegisterQrAccess stamps 60d access_logs expireAt, holds qr_codes expireAt null while inside, and stamps 7d QR TTL upon exit or denial', async (t) => {
  const env = createMockAdminEnvironment({
    config: {
      app_settings: {
        scanOnExitEnabled: true,
        timeZone: 'America/Mexico_City',
      },
    },
    users: {
      res_ttl_1: {
        uid: 'res_ttl_1',
        name: 'Resident TTL',
        role: 'resident',
      },
      guard_ttl_1: {
        uid: 'guard_ttl_1',
        name: 'Guard Uno',
        role: 'guard',
      },
    },
  });

  const futureExpiry = new Date(Date.now() + 12 * 3600 * 1000);
  await env.makeDocRef('qr_codes', 'qr_supplier_exit').set({
    creatorUid: 'res_ttl_1',
    guestName: 'Acme Plumbing',
    accessCategory: 'supplier',
    isOneTimeUse: true,
    type: 'temporary',
    status: 'active',
    expiryTime: futureExpiry,
    expireAt: _test.admin.firestore.Timestamp.fromMillis(
      futureExpiry.getTime() + _test.QR_CODE_RETENTION_MS
    ),
  });

  const pastExpiry = new Date(Date.now() - 2 * 3600 * 1000);
  await env.makeDocRef('qr_codes', 'qr_expired_denied').set({
    creatorUid: 'res_ttl_1',
    guestName: 'Late Visitor',
    accessCategory: 'visitor',
    type: 'temporary',
    status: 'active',
    expiryTime: pastExpiry,
  });

  installMockAdmin(t, env);
  const validateWrapped = fft.wrap(cloudFunctions.validateAndRegisterQrAccess);
  const guardAuth = { uid: 'guard_ttl_1', token: { guard: true } };

  // 1. Entry scan on 1x supplier pass with scanOnExitEnabled=true:
  //    access_logs gets 60d expireAt; qr_codes stays active with expireAt=null while inside
  const entryRes = await validateWrapped({
    data: {
      qrId: 'qr_supplier_exit',
      mode: 'validate_and_register',
      visitorIdPhotoUrl:
        'https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/visitor_ids%2Fqr_supplier_exit_1.jpg?alt=media',
      visitorPlatePhotoUrl:
        'https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/visitor_plates%2Fqr_supplier_exit_1.jpg?alt=media',
    },
    auth: guardAuth,
  });
  assert.equal(entryRes.granted, true);
  assert.equal(entryRes.isExit, false);

  const qrDuringVisit = (await env.makeDocRef('qr_codes', 'qr_supplier_exit').get()).data();
  assert.equal(qrDuringVisit.isInside, true);
  assert.equal(qrDuringVisit.expireAt, null);

  const openLogId = qrDuringVisit.activeAccessLogId;
  assert.ok(openLogId);
  const entryLogData = (await env.makeDocRef('access_logs', openLogId).get()).data();
  const entryTsMillis = _test.extractTimestampMillis(entryLogData.timestamp);
  assert.ok(
    Math.abs(entryLogData.expireAt.toMillis() - (entryTsMillis + _test.ACCESS_LOG_RETENTION_MS)) < 2000
  );

  // 2. Exit scan: refreshes access_logs.expireAt to exitTimestamp + 60d AND stamps 7d expireAt on 1x supplier QR
  const exitRes = await validateWrapped({
    data: {
      qrId: 'qr_supplier_exit',
      mode: 'validate_and_register',
      reason: 'Completed repair',
    },
    auth: guardAuth,
  });
  assert.equal(exitRes.granted, true);
  assert.equal(exitRes.isExit, true);

  const closedLogData = (await env.makeDocRef('access_logs', openLogId).get()).data();
  assert.equal(closedLogData.isInside, false);
  const exitTsMillis = _test.extractTimestampMillis(closedLogData.exitTimestamp);
  assert.ok(
    Math.abs(closedLogData.expireAt.toMillis() - (exitTsMillis + _test.ACCESS_LOG_RETENTION_MS)) < 2000
  );

  const qrAfterExit = (await env.makeDocRef('qr_codes', 'qr_supplier_exit').get()).data();
  assert.equal(qrAfterExit.status, 'deactivated (validated)');
  assert.equal(qrAfterExit.isInside, false);
  const usedAtMillis = _test.extractTimestampMillis(qrAfterExit.usedAt);
  assert.ok(
    Math.abs(qrAfterExit.expireAt.toMillis() - (usedAtMillis + _test.QR_CODE_RETENTION_MS)) < 2000
  );

  // 3. Denied scan on expired QR: stamps 60d expireAt on denied access_log & 7d expireAt on qr_codes
  const deniedRes = await validateWrapped({
    data: {
      qrId: 'qr_expired_denied',
      mode: 'validate_and_register',
    },
    auth: guardAuth,
  });
  assert.equal(deniedRes.granted, false);

  const expiredQrAfterScan = (await env.makeDocRef('qr_codes', 'qr_expired_denied').get()).data();
  assert.equal(expiredQrAfterScan.status, 'deactivated (expired)');
  assert.equal(
    expiredQrAfterScan.expireAt.toMillis(),
    pastExpiry.getTime() + _test.QR_CODE_RETENTION_MS
  );

  const allLogs = Array.from(env.store.get('access_logs').values());
  const deniedLog = allLogs.find((l) => l.qrCodeId === 'qr_expired_denied');
  assert.ok(deniedLog);
  assert.equal(deniedLog.status, 'denied');
  const deniedTsMillis = _test.extractTimestampMillis(deniedLog.timestamp);
  assert.ok(
    Math.abs(deniedLog.expireAt.toMillis() - (deniedTsMillis + _test.ACCESS_LOG_RETENTION_MS)) < 2000
  );
});

test('onAccessLogDeleted cascades visitor_ids/ & visitor_plates/ deletions, ignores 404s, blocks out-of-scope paths, and heals open-visit QR state', async (t) => {
  const env = createMockAdminEnvironment();
  installMockAdmin(t, env);

  const bucket = env.storageMock.bucket();
  await bucket.file('visitor_ids/qr_open_1_id.jpg').save(Buffer.from('id-bytes'));
  await bucket.file('documents/admin_only/protected.pdf').save(Buffer.from('secret-doc'));

  await env.makeDocRef('qr_codes', 'qr_open_1').set({
    status: 'deactivated (expired)',
    isInside: true,
    activeAccessLogId: 'log_ttl_expired_1',
    expireAt: null,
  });

  await cloudFunctions.onAccessLogDeleted.run({
    params: { logId: 'log_ttl_expired_1' },
    data: {
      data: () => ({
        qrCodeId: 'qr_open_1',
        status: 'allowed',
        isInside: true,
        visitorIdPhotoUrl:
          'https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/visitor_ids%2Fqr_open_1_id.jpg?alt=media',
        // Missing object in Storage -> must succeed idempotently via ignoreNotFound: true
        visitorPlatePhotoUrl:
          'https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/visitor_plates%2Falready_gone.jpg?alt=media',
      }),
    },
  });

  // 1. visitor_ids file was deleted and missing visitor_plates file did not throw
  assert.equal(env.savedStorageFiles.has('visitor_ids/qr_open_1_id.jpg'), false);
  assert.deepEqual(
    env.deletedStoragePaths.map((d) => d.storagePath),
    ['visitor_ids/qr_open_1_id.jpg', 'visitor_plates/already_gone.jpg']
  );

  // 2. Linked QR pass with stale isInside=true was healed and received a 7-day expireAt
  const healedQr = (await env.makeDocRef('qr_codes', 'qr_open_1').get()).data();
  assert.equal(healedQr.isInside, false);
  assert.equal(healedQr.activeAccessLogId, null);
  assert.ok(healedQr.expireAt && typeof healedQr.expireAt.toMillis === 'function');

  // 3. Out-of-scope URL (documents/admin_only/protected.pdf) is strictly ignored and never deleted
  await cloudFunctions.onAccessLogDeleted.run({
    params: { logId: 'log_malicious_url' },
    data: {
      data: () => ({
        visitorIdPhotoUrl:
          'https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/documents%2Fadmin_only%2Fprotected.pdf?alt=media',
        visitorPlatePhotoUrl: 'visitor_ids/../documents/admin_only/protected.pdf',
      }),
    },
  });
  assert.equal(env.savedStorageFiles.has('documents/admin_only/protected.pdf'), true);
});

test('purgeExpiredAccessLogs and purgeExpiredQrCodes delete expired records while preserving recent logs, active permanent passes, and open visits', async (t) => {
  const env = createMockAdminEnvironment();
  installMockAdmin(t, env);

  const nowMillis = Date.UTC(2026, 11, 1, 6, 0, 0);
  const Timestamp = _test.admin.firestore.Timestamp;
  const bucket = env.storageMock.bucket();

  await bucket.file('visitor_ids/old_ttl_id.jpg').save(Buffer.from('old1'));
  await bucket.file('visitor_plates/legacy_old_plate.jpg').save(Buffer.from('old2'));
  await bucket.file('visitor_ids/recent_id.jpg').save(Buffer.from('recent'));

  // Access logs:
  // 1) Expired via expireAt
  await env.makeDocRef('access_logs', 'log_expired_ttl').set({
    status: 'allowed',
    timestamp: Timestamp.fromMillis(nowMillis - 65 * 24 * 60 * 60 * 1000),
    expireAt: Timestamp.fromMillis(nowMillis - 5 * 24 * 60 * 60 * 1000),
    visitorIdPhotoUrl: 'visitor_ids/old_ttl_id.jpg',
  });
  // 2) Legacy expired log without expireAt (61 days old)
  await env.makeDocRef('access_logs', 'log_legacy_61d').set({
    status: 'allowed',
    timestamp: Timestamp.fromMillis(nowMillis - 61 * 24 * 60 * 60 * 1000),
    visitorPlatePhotoUrl: 'visitor_plates/legacy_old_plate.jpg',
  });
  // 3) Recent log (15 days old) -> must be preserved
  await env.makeDocRef('access_logs', 'log_recent_15d').set({
    status: 'allowed',
    timestamp: Timestamp.fromMillis(nowMillis - 15 * 24 * 60 * 60 * 1000),
    expireAt: Timestamp.fromMillis(nowMillis + 45 * 24 * 60 * 60 * 1000),
    visitorIdPhotoUrl: 'visitor_ids/recent_id.jpg',
  });

  const deletedLogCount = await _test.purgeExpiredAccessLogs(env.dbMock, bucket, nowMillis);
  assert.equal(deletedLogCount, 2);
  assert.equal((await env.makeDocRef('access_logs', 'log_expired_ttl').get()).exists, false);
  assert.equal((await env.makeDocRef('access_logs', 'log_legacy_61d').get()).exists, false);
  assert.equal((await env.makeDocRef('access_logs', 'log_recent_15d').get()).exists, true);
  assert.equal(env.savedStorageFiles.has('visitor_ids/old_ttl_id.jpg'), false);
  assert.equal(env.savedStorageFiles.has('visitor_plates/legacy_old_plate.jpg'), false);
  assert.equal(env.savedStorageFiles.has('visitor_ids/recent_id.jpg'), true);

  // QR codes:
  // 1) Revoked 8 days ago (expired TTL) -> delete
  await env.makeDocRef('qr_codes', 'qr_revoked_8d').set({
    status: 'deactivated (revoked)',
    deactivatedAt: Timestamp.fromMillis(nowMillis - 8 * 24 * 60 * 60 * 1000),
    expireAt: Timestamp.fromMillis(nowMillis - 1 * 24 * 60 * 60 * 1000),
  });
  // 2) Legacy validated 10 days ago without expireAt -> delete
  await env.makeDocRef('qr_codes', 'qr_legacy_used_10d').set({
    status: 'used',
    usedAt: nowMillis - 10 * 24 * 60 * 60 * 1000,
  });
  // 3) Legacy revoked 2 days ago without expireAt -> keep & backfill expireAt
  await env.makeDocRef('qr_codes', 'qr_legacy_revoked_2d').set({
    status: 'revoked',
    timestamp: nowMillis - 2 * 24 * 60 * 60 * 1000,
  });
  // 4) Active permanent pass -> keep forever (expireAt remains null/unset)
  await env.makeDocRef('qr_codes', 'qr_perm_active').set({
    status: 'active',
    type: 'permanent',
    expireAt: null,
  });
  // 5) Expired pass whose visitor is still inside -> keep!
  await env.makeDocRef('qr_codes', 'qr_inside_protected').set({
    status: 'deactivated (expired)',
    isInside: true,
    expireAt: Timestamp.fromMillis(nowMillis - 2 * 24 * 60 * 60 * 1000),
  });

  const deletedQrCount = await _test.purgeExpiredQrCodes(env.dbMock, nowMillis);
  assert.equal(deletedQrCount, 2);

  assert.equal((await env.makeDocRef('qr_codes', 'qr_revoked_8d').get()).exists, false);
  assert.equal((await env.makeDocRef('qr_codes', 'qr_legacy_used_10d').get()).exists, false);
  assert.equal((await env.makeDocRef('qr_codes', 'qr_perm_active').get()).exists, true);
  assert.equal((await env.makeDocRef('qr_codes', 'qr_inside_protected').get()).exists, true);

  const backfilledQr = (await env.makeDocRef('qr_codes', 'qr_legacy_revoked_2d').get()).data();
  assert.ok(backfilledQr.expireAt && typeof backfilledQr.expireAt.toMillis === 'function');
});

test('createBooking validates mandatory/optional/informative facilityDocuments, verifies Storage magic bytes, isolates booking_attachments, cleans up superseded files on resubmit, and purges on cancelBooking', async (t) => {
  const env = createMockAdminEnvironment();
  const addrRef = env.makeDocRef('addresses', 'addr_doc_1');
  await env.makeDocRef('config', 'app_settings').set({ timeZone: 'UTC' });
  await addrRef.set({
    id: 'addr_doc_1',
    streetName: 'Taormina',
    number: 9,
    paymentStatus: 'paid',
    hasActiveSanctions: false,
  });
  await env.makeDocRef('users', 'res_doc_1').set({
    uid: 'res_doc_1',
    name: 'Doc Resident',
    role: 'resident',
    addressRef: addrRef,
  });
  await env.makeDocRef('users', 'room_doc_1').set({
    uid: 'room_doc_1',
    name: 'Doc Roommate',
    role: 'roommate',
    addressRef: addrRef,
  });

  await env.makeDocRef('facilities', 'salon_eventos').set({
    id: 'salon_eventos',
    name: 'Event Hall',
    quantity: 2,
    openingTime: '08:00',
    closingTime: '22:00',
    anticipationUnit: 'unrestricted',
    anticipationValue: 0,
    facilityDocuments: [
      {
        docId: 'doc_liability',
        title: 'Signed Liability Waiver',
        requirementMode: 'mandatory_return',
        fileName: 'liability_waiver.pdf',
        fileType: 'pdf',
        fileSize: 24500,
        url: 'https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/facility_documents%2Fsalon_eventos%2Fwaiver.pdf?alt=media',
        storagePath: 'facility_documents/salon_eventos/waiver.pdf',
      },
      {
        docId: 'doc_guests',
        title: 'Guest List Spreadsheet',
        requirementMode: 'optional_return',
        fileName: 'guest_list.xlsx',
        fileType: 'xlsx',
        fileSize: 12000,
        url: 'https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/facility_documents%2Fsalon_eventos%2Fguests.xlsx?alt=media',
        storagePath: 'facility_documents/salon_eventos/guests.xlsx',
      },
      {
        docId: 'doc_bylaws',
        title: 'Noise Rules Reference',
        requirementMode: 'informative',
        fileName: 'noise_rules.pdf',
        fileType: 'pdf',
        fileSize: 18000,
        url: 'https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/facility_documents%2Fsalon_eventos%2Fnoise.pdf?alt=media',
        storagePath: 'facility_documents/salon_eventos/noise.pdf',
      },
    ],
  });

  installMockAdmin(t, env);
  const bucket = env.storageMock.bucket();
  const createWrapped = fft.wrap(cloudFunctions.createBooking);
  const cancelWrapped = fft.wrap(cloudFunctions.cancelBooking);
  const resAuth = { uid: 'res_doc_1', token: { resident: true } };
  const roomAuth = { uid: 'room_doc_1', token: { roommate: true } };

  const startMs = Date.UTC(2027, 8, 10, 14, 0, 0);
  const endMs = Date.UTC(2027, 8, 10, 18, 0, 0);

  // 1. Missing mandatory_return attachment -> blocked with failed-precondition
  await assertHttpsErrorCode(
    createWrapped({
      data: { facilityId: 'salon_eventos', startTime: startMs, endTime: endMs, attachments: [] },
      auth: resAuth,
    }),
    'failed-precondition'
  );

  // 2. Attempting to upload against an informative-only document -> invalid-argument
  const validPdfPath = 'booking_attachments/res_doc_1/1700001_waiver_v1.pdf';
  await bucket.file(validPdfPath).save(Buffer.from('%PDF-1.7\nSigned by resident'));
  await assertHttpsErrorCode(
    createWrapped({
      data: {
        facilityId: 'salon_eventos',
        startTime: startMs,
        endTime: endMs,
        attachments: [
          {
            facilityDocId: 'doc_bylaws',
            fileName: 'noise.pdf',
            fileType: 'pdf',
            fileSize: 120,
            url: `https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/${encodeURIComponent(validPdfPath)}?alt=media`,
            storagePath: validPdfPath,
          },
        ],
      },
      auth: resAuth,
    }),
    'invalid-argument'
  );

  // 3. Cross-user storagePath (pointing to another user's folder) -> permission-denied
  const otherUserPath = 'booking_attachments/other_user_99/stolen.pdf';
  await bucket.file(otherUserPath).save(Buffer.from('%PDF-1.7\nOther user'));
  await assertHttpsErrorCode(
    createWrapped({
      data: {
        facilityId: 'salon_eventos',
        startTime: startMs,
        endTime: endMs,
        attachments: [
          {
            facilityDocId: 'doc_liability',
            fileName: 'stolen.pdf',
            fileType: 'pdf',
            fileSize: 120,
            url: `https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/${encodeURIComponent(otherUserPath)}?alt=media`,
            storagePath: otherUserPath,
          },
        ],
      },
      auth: resAuth,
    }),
    'permission-denied'
  );

  // 4. Spoofed HTML content uploaded as .pdf -> rejected via server-side magic-byte check & deleted from Storage!
  const spoofedPath = 'booking_attachments/res_doc_1/spoofed_xss.pdf';
  await bucket.file(spoofedPath).save(Buffer.from('<html><script>alert(1)</script></html>'));
  await assertHttpsErrorCode(
    createWrapped({
      data: {
        facilityId: 'salon_eventos',
        startTime: startMs,
        endTime: endMs,
        attachments: [
          {
            facilityDocId: 'doc_liability',
            fileName: 'spoofed_xss.pdf',
            fileType: 'pdf',
            fileSize: 40,
            url: `https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/${encodeURIComponent(spoofedPath)}?alt=media`,
            storagePath: spoofedPath,
          },
        ],
      },
      auth: resAuth,
    }),
    'invalid-argument'
  );
  assert.equal(env.savedStorageFiles.has(spoofedPath), false, 'Spoofed file must be deleted on validation failure');

  // 5. Valid mandatory PDF + optional XLSX -> succeeds, writes summary on bookings and details in booking_attachments
  const validXlsxPath = 'booking_attachments/res_doc_1/1700002_guests.xlsx';
  await bucket.file(validXlsxPath).save(Buffer.from([0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00]));

  const created = await createWrapped({
    data: {
      facilityId: 'salon_eventos',
      startTime: startMs,
      endTime: endMs,
      attachments: [
        {
          facilityDocId: 'doc_liability',
          fileName: '../../signed_waiver.pdf', // path basename sanitized automatically
          fileType: 'pdf',
          fileSize: 28,
          url: `https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/${encodeURIComponent(validPdfPath)}?alt=media`,
          storagePath: validPdfPath,
        },
        {
          facilityDocId: 'doc_guests',
          fileName: 'guests_october.xlsx',
          fileType: 'xlsx',
          fileSize: 8,
          url: `https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/${encodeURIComponent(validXlsxPath)}?alt=media`,
          storagePath: validXlsxPath,
        },
      ],
    },
    auth: resAuth,
  });

  assert.equal(created.success, true);
  const savedBooking = env.store.get('bookings').get(created.bookingId);
  assert.equal(savedBooking.hasAttachments, true);
  assert.equal(savedBooking.attachmentCount, 2);
  assert.equal(savedBooking.attachmentsPurgedAt, null);
  // Neighbor-readable bookings doc must NOT leak raw attachment URLs
  assert.equal(savedBooking.attachments, undefined);

  const savedAttDoc = env.store.get('booking_attachments').get(created.bookingId);
  assert.ok(savedAttDoc, 'booking_attachments/{bookingId} must be created');
  assert.equal(savedAttDoc.userUid, 'res_doc_1');
  assert.equal(savedAttDoc.addressId, 'addr_doc_1');
  assert.equal(savedAttDoc.attachments.length, 2);
  assert.equal(savedAttDoc.attachments[0].fileName, 'signed_waiver.pdf');
  assert.equal(
    savedAttDoc.expireAt.toMillis(),
    endMs + 30 * 24 * 60 * 60 * 1000
  );

  // 6. Admin rejects booking ("Missing witness signature"); household roommate resubmits replacing waiver while keeping guests.xlsx
  await env.makeDocRef('bookings', created.bookingId).update({
    status: 'rejected',
    rejectionReason: 'Missing witness signature',
  });

  const replacementPdfPath = 'booking_attachments/room_doc_1/1700009_waiver_v2.pdf';
  await bucket.file(replacementPdfPath).save(Buffer.from('%PDF-1.7\nSigned with witness'));

  const newEndMs = Date.UTC(2027, 8, 12, 19, 0, 0);
  const resubmitted = await createWrapped({
    data: {
      facilityId: 'salon_eventos',
      startTime: Date.UTC(2027, 8, 12, 15, 0, 0),
      endTime: newEndMs,
      resubmitBookingId: created.bookingId,
      attachments: [
        {
          facilityDocId: 'doc_liability',
          fileName: 'signed_waiver_v2.pdf',
          fileType: 'pdf',
          fileSize: 30,
          url: `https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/${encodeURIComponent(replacementPdfPath)}?alt=media`,
          storagePath: replacementPdfPath,
        },
        {
          // Unchanged attachment originally uploaded by primary resident
          facilityDocId: 'doc_guests',
          fileName: 'guests_october.xlsx',
          fileType: 'xlsx',
          fileSize: 8,
          url: `https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/${encodeURIComponent(validXlsxPath)}?alt=media`,
          storagePath: validXlsxPath,
        },
      ],
    },
    auth: roomAuth,
  });

  assert.equal(resubmitted.bookingId, created.bookingId);
  // Superseded v1 PDF must be deleted from Storage, while v2 PDF and unchanged XLSX remain!
  assert.equal(env.savedStorageFiles.has(validPdfPath), false);
  assert.equal(env.savedStorageFiles.has(replacementPdfPath), true);
  assert.equal(env.savedStorageFiles.has(validXlsxPath), true);

  const updatedAttDoc = env.store.get('booking_attachments').get(created.bookingId);
  assert.equal(updatedAttDoc.expireAt.toMillis(), newEndMs + 30 * 24 * 60 * 60 * 1000);

  // 7. Cancelling the booking immediately deletes remaining Storage files, removes booking_attachments doc, and stamps attachmentsPurgedAt
  const cancelRes = await cancelWrapped({
    data: { bookingId: created.bookingId },
    auth: resAuth,
  });
  assert.equal(cancelRes.success, true);
  assert.equal(env.savedStorageFiles.has(replacementPdfPath), false);
  assert.equal(env.savedStorageFiles.has(validXlsxPath), false);
  assert.equal((await env.makeDocRef('booking_attachments', created.bookingId).get()).exists, false);
  const cancelledBooking = env.store.get('bookings').get(created.bookingId);
  assert.equal(cancelledBooking.status, 'cancelled');
  assert.equal(typeof cancelledBooking.attachmentsPurgedAt, 'number');
});

test('onBookingAttachmentDeleted and purgeExpiredBookingAttachments clean up Storage files after 30 days post-booking while preserving active/upcoming bookings', async (t) => {
  const env = createMockAdminEnvironment();
  installMockAdmin(t, env);

  const nowMillis = Date.UTC(2027, 10, 1, 12, 0, 0);
  const Timestamp = _test.admin.firestore.Timestamp;
  const bucket = env.storageMock.bucket();

  await bucket.file('booking_attachments/res_1/expired_form.pdf').save(Buffer.from('%PDF-1.7 old'));
  await bucket.file('booking_attachments/res_1/future_form.pdf').save(Buffer.from('%PDF-1.7 future'));
  await bucket.file('booking_attachments/res_2/ttl_trigger_form.jpg').save(Buffer.from([0xff, 0xd8, 0xff]));
  await bucket.file('documents/admin_only/do_not_touch.pdf').save(Buffer.from('%PDF-1.7 admin'));

  // 1) Booking ended 31 days ago -> eligible for daily sweep
  const expiredEnd = nowMillis - 31 * 24 * 60 * 60 * 1000;
  await env.makeDocRef('bookings', 'bk_expired_31d').set({
    id: 'bk_expired_31d',
    status: 'closed',
    hasAttachments: true,
    attachmentCount: 1,
    attachmentsPurgedAt: null,
  });
  await env.makeDocRef('booking_attachments', 'bk_expired_31d').set({
    bookingId: 'bk_expired_31d',
    bookingEndTime: expiredEnd,
    expireAt: Timestamp.fromMillis(expiredEnd + 30 * 24 * 60 * 60 * 1000),
    attachments: [
      {
        facilityDocId: 'doc_1',
        storagePath: 'booking_attachments/res_1/expired_form.pdf',
        url: 'https://firebasestorage.googleapis.com/v0/b/test-catania-bucket/o/booking_attachments%2Fres_1%2Fexpired_form.pdf?alt=media',
      },
    ],
  });

  // 2) Booking ended 10 days ago (within 30-day window) -> must be preserved!
  const recentEnd = nowMillis - 10 * 24 * 60 * 60 * 1000;
  await env.makeDocRef('bookings', 'bk_recent_10d').set({
    id: 'bk_recent_10d',
    status: 'closed',
    hasAttachments: true,
    attachmentCount: 1,
    attachmentsPurgedAt: null,
  });
  await env.makeDocRef('booking_attachments', 'bk_recent_10d').set({
    bookingId: 'bk_recent_10d',
    bookingEndTime: recentEnd,
    expireAt: Timestamp.fromMillis(recentEnd + 30 * 24 * 60 * 60 * 1000),
    attachments: [
      {
        facilityDocId: 'doc_1',
        storagePath: 'booking_attachments/res_1/future_form.pdf',
      },
    ],
  });

  const purgedCount = await _test.purgeExpiredBookingAttachments(env.dbMock, bucket, nowMillis);
  assert.equal(purgedCount, 1);
  assert.equal((await env.makeDocRef('booking_attachments', 'bk_expired_31d').get()).exists, false);
  assert.equal((await env.makeDocRef('booking_attachments', 'bk_recent_10d').get()).exists, true);
  assert.equal(env.savedStorageFiles.has('booking_attachments/res_1/expired_form.pdf'), false);
  assert.equal(env.savedStorageFiles.has('booking_attachments/res_1/future_form.pdf'), true);
  assert.equal(
    typeof (await env.makeDocRef('bookings', 'bk_expired_31d').get()).data().attachmentsPurgedAt,
    'number'
  );

  // 3) Direct Firestore TTL deletion trigger (`onBookingAttachmentDeleted`): deletes valid attachment, ignores 404s, blocks out-of-scope paths
  await env.makeDocRef('bookings', 'bk_ttl_trigger').set({
    id: 'bk_ttl_trigger',
    status: 'closed',
    hasAttachments: true,
    attachmentCount: 1,
    attachmentsPurgedAt: null,
  });
  await cloudFunctions.onBookingAttachmentDeleted.run({
    params: { bookingId: 'bk_ttl_trigger' },
    data: {
      data: () => ({
        bookingId: 'bk_ttl_trigger',
        attachments: [
          { storagePath: 'booking_attachments/res_2/ttl_trigger_form.jpg' },
          { storagePath: 'booking_attachments/res_2/already_deleted_404.pdf' },
          { storagePath: 'documents/admin_only/do_not_touch.pdf' },
        ],
      }),
    },
  });

  assert.equal(env.savedStorageFiles.has('booking_attachments/res_2/ttl_trigger_form.jpg'), false);
  assert.equal(env.savedStorageFiles.has('documents/admin_only/do_not_touch.pdf'), true);
  assert.equal(
    typeof (await env.makeDocRef('bookings', 'bk_ttl_trigger').get()).data().attachmentsPurgedAt,
    'number'
  );
});

test('adminPreCheckPaymentImport and adminBulkImportPayments enforce RBAC and validate arguments', async (t) => {
  // 1) Unauthenticated rejection
  await assert.rejects(
    () => cloudFunctions.adminPreCheckPaymentImport.run({ auth: null, data: { items: [] } }),
    /authenticated admin/
  );
  await assert.rejects(
    () => cloudFunctions.adminBulkImportPayments.run({ auth: null, data: { items: [] } }),
    /authenticated admin/
  );

  // 2) Non-admin resident rejection
  await assert.rejects(
    () => cloudFunctions.adminPreCheckPaymentImport.run({ auth: { uid: 'res_1', token: { resident: true } }, data: { items: [{ streetName: 'Main', number: 1 }] } }),
    /authenticated admin/
  );
  await assert.rejects(
    () => cloudFunctions.adminBulkImportPayments.run({ auth: { uid: 'res_1', token: { resident: true } }, data: { items: [{ streetName: 'Main', number: 1 }] } }),
    /authenticated admin/
  );

  // 3) Empty items rejection
  await assert.rejects(
    () => cloudFunctions.adminPreCheckPaymentImport.run({ auth: { uid: 'admin_1', token: { admin: true } }, data: { items: [] } }),
    /non-empty array/
  );
  await assert.rejects(
    () => cloudFunctions.adminBulkImportPayments.run({ auth: { uid: 'admin_1', token: { admin: true } }, data: { items: [] } }),
    /non-empty array/
  );
});
