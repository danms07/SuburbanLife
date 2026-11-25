const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTestFactory = require('firebase-functions-test');
const cloudFunctions = require('../index.js');

const fft = functionsTestFactory();
const { _test } = cloudFunctions;

/**
 * Self-contained in-memory mock environment covering Firestore, Auth, Storage,
 * Realtime Database (RTDB), and FCM multicast delivery for offline notification testing.
 */
function createNotificationTestEnv({
  collections = {},
  authUsers = [],
  rtdbInitial = {},
  failedTokens = new Set(),
} = {}) {
  const store = new Map();
  for (const [colName, docsObj] of Object.entries(collections)) {
    const colMap = new Map();
    for (const [id, data] of Object.entries(docsObj)) {
      colMap.set(id, structuredClone(data));
    }
    store.set(colName, colMap);
  }

  const rtdbRoot = structuredClone(rtdbInitial || {});
  const sentMessages = [];
  const authClaims = new Map();
  const deletedAuthUids = [];
  const deletedStoragePaths = [];
  const savedStorageFiles = new Map();
  const mockUsers = authUsers.map((u) => structuredClone(u));
  let autoCounter = 1;

  function ensureCol(colName) {
    if (!store.has(colName)) store.set(colName, new Map());
    return store.get(colName);
  }

  function applyFieldSentinel(existingVal, incomingVal) {
    if (incomingVal && typeof incomingVal === 'object' && incomingVal.constructor) {
      const ctorName = incomingVal.constructor.name || '';
      if (ctorName === 'ArrayUnionTransform') {
        const current = Array.isArray(existingVal) ? [...existingVal] : [];
        for (const el of incomingVal.elements || []) {
          if (!current.includes(el)) current.push(el);
        }
        return current;
      }
      if (ctorName === 'ArrayRemoveTransform') {
        const elements = incomingVal.elements || [];
        return (Array.isArray(existingVal) ? existingVal : []).filter((x) => !elements.includes(x));
      }
      if (ctorName === 'DeleteTransform') return undefined;
      if (ctorName === 'ServerTimestampTransform') return _test.admin.firestore.Timestamp.now();
    }
    return incomingVal;
  }

  function mergeDoc(existing, patch) {
    const next = { ...(existing || {}) };
    for (const [k, v] of Object.entries(patch)) {
      if (k.includes('.')) {
        const parts = k.split('.');
        let cursor = next;
        for (let i = 0; i < parts.length - 1; i++) {
          cursor[parts[i]] = { ...(cursor[parts[i]] || {}) };
          cursor = cursor[parts[i]];
        }
        cursor[parts[parts.length - 1]] = v;
        continue;
      }
      const resolved = applyFieldSentinel(next[k], v);
      if (resolved === undefined) delete next[k];
      else next[k] = resolved;
    }
    return next;
  }

  function makeDocRef(colName, docId) {
    const id = docId || `auto_${autoCounter++}`;
    return {
      id,
      path: `${colName}/${id}`,
      async get() {
        const col = ensureCol(colName);
        const exists = col.has(id);
        return {
          id,
          ref: this,
          exists,
          data: () => (exists ? { ...col.get(id) } : undefined),
        };
      },
      async set(data, options = {}) {
        const col = ensureCol(colName);
        const prev = options?.merge && col.has(id) ? col.get(id) : {};
        col.set(id, mergeDoc(prev, data));
      },
      async update(patch) {
        const col = ensureCol(colName);
        if (!col.has(id)) throw new Error(`Missing doc ${colName}/${id}`);
        col.set(id, mergeDoc(col.get(id), patch));
      },
      async delete() {
        ensureCol(colName).delete(id);
      },
    };
  }

  function buildQuery(colName, filters = []) {
    return {
      where(field, op, value) {
        return buildQuery(colName, [...filters, { field, op, value }]);
      },
      async get() {
        const col = ensureCol(colName);
        const docs = [];
        for (const [id, data] of col.entries()) {
          const ok = filters.every(({ field, op, value }) => {
            const val = data[field];
            if (op === '==') return val === value;
            if (op === 'in') return Array.isArray(value) && value.includes(val);
            if (op === 'array-contains') return Array.isArray(val) && val.includes(value);
            return true;
          });
          if (ok) {
            docs.push({ id, ref: makeDocRef(colName, id), exists: true, data: () => ({ ...data }) });
          }
        }
        return { empty: docs.length === 0, size: docs.length, docs };
      },
    };
  }

  const dbMock = {
    collection(colName) {
      return {
        ...buildQuery(colName),
        doc: (id) => makeDocRef(colName, id),
        async add(data) {
          const ref = makeDocRef(colName);
          await ref.set(data);
          return ref;
        },
      };
    },
    doc(fullPath) {
      const [colName, id] = fullPath.split('/');
      return makeDocRef(colName, id);
    },
    batch() {
      const ops = [];
      return {
        set: (ref, data, opts) => ops.push(() => ref.set(data, opts)),
        update: (ref, patch) => ops.push(() => ref.update(patch)),
        delete: (ref) => ops.push(() => ref.delete()),
        async commit() {
          for (const op of ops) await op();
        },
      };
    },
  };

  function getRtdbAtPath(pathStr) {
    if (!pathStr) return rtdbRoot;
    const parts = pathStr.split('/').filter(Boolean);
    let cursor = rtdbRoot;
    for (const part of parts) {
      if (!cursor || typeof cursor !== 'object' || !(part in cursor)) return null;
      cursor = cursor[part];
    }
    return cursor;
  }

  function setRtdbAtPath(pathStr, value) {
    const parts = pathStr.split('/').filter(Boolean);
    if (parts.length === 0) return;
    let cursor = rtdbRoot;
    for (let i = 0; i < parts.length - 1; i++) {
      const key = parts[i];
      if (!cursor[key] || typeof cursor[key] !== 'object') {
        if (value === null) return;
        cursor[key] = {};
      }
      cursor = cursor[key];
    }
    const leaf = parts[parts.length - 1];
    if (value === null) delete cursor[leaf];
    else cursor[leaf] = structuredClone(value);
  }

  const rtdbMock = {
    ref(pathStr = '') {
      const cleanPath = String(pathStr || '').replace(/^\/+|\/+$/g, '');
      return {
        async get() {
          const val = getRtdbAtPath(cleanPath);
          const exists = val !== null && val !== undefined &&
            (typeof val !== 'object' || Object.keys(val).length > 0);
          return {
            exists: () => exists,
            val: () => (exists ? structuredClone(val) : null),
          };
        },
        async update(updates) {
          for (const [relPath, val] of Object.entries(updates || {})) {
            const fullPath = cleanPath ? `${cleanPath}/${relPath}` : relPath;
            setRtdbAtPath(fullPath, val);
          }
        },
      };
    },
  };

  const messagingMock = {
    async sendEachForMulticast(message) {
      sentMessages.push(structuredClone(message));
      const responses = message.tokens.map((tok) => {
        if (failedTokens.has(tok)) {
          return {
            success: false,
            error: { code: 'messaging/registration-token-not-registered' },
          };
        }
        return { success: true };
      });
      const successCount = responses.filter((r) => r.success).length;
      return { successCount, failureCount: responses.length - successCount, responses };
    },
  };

  const authMock = {
    async getUser(uid) {
      const found = mockUsers.find((u) => u.uid === uid);
      if (!found) {
        const err = new Error('User not found');
        err.code = 'auth/user-not-found';
        throw err;
      }
      return structuredClone(found);
    },
    async setCustomUserClaims(uid, claims) {
      authClaims.set(uid, { ...claims });
      const found = mockUsers.find((u) => u.uid === uid);
      if (found) found.customClaims = { ...claims };
    },
    async listUsers(maxResults = 1000, pageToken) {
      const start = pageToken ? Number.parseInt(String(pageToken), 10) || 0 : 0;
      const slice = mockUsers.slice(start, start + maxResults);
      const next = start + slice.length;
      return {
        users: slice,
        pageToken: next < mockUsers.length ? String(next) : undefined,
      };
    },
    async deleteUser(uid) {
      deletedAuthUids.push(uid);
    },
  };

  const storageMock = {
    bucket() {
      return {
        file(storagePath) {
          return {
            async save(buffer) {
              savedStorageFiles.set(storagePath, buffer);
            },
            async delete(opts = {}) {
              deletedStoragePaths.push({ storagePath, opts });
              savedStorageFiles.delete(storagePath);
            },
          };
        },
      };
    },
  };

  return {
    dbMock,
    rtdbMock,
    messagingMock,
    authMock,
    storageMock,
    store,
    rtdbRoot,
    sentMessages,
    authClaims,
    deletedAuthUids,
    deletedStoragePaths,
    savedStorageFiles,
    makeDocRef,
  };
}

function installNotificationTestEnv(t, env) {
  const origFirestore = _test.admin.firestore;
  const origAuth = _test.admin.auth;
  const origStorage = _test.admin.storage;
  const origMessaging = _test.admin.messaging;
  const origDatabase = _test.admin.database;

  _test.admin.firestore = Object.assign(() => env.dbMock, {
    FieldValue: origFirestore.FieldValue,
    Timestamp: origFirestore.Timestamp,
  });
  _test.admin.auth = () => env.authMock;
  _test.admin.storage = () => env.storageMock;
  _test.admin.messaging = () => env.messagingMock;
  _test.admin.database = () => env.rtdbMock;

  t.after(() => {
    _test.admin.firestore = origFirestore;
    _test.admin.auth = origAuth;
    _test.admin.storage = origStorage;
    _test.admin.messaging = origMessaging;
    _test.admin.database = origDatabase;
  });
}

test.after(() => {
  fft.cleanup();
});

test('dispatchNotification deduplicates, respects pushEnabled & category opt-outs while mirroring RTDB, localizes ES/EN, chunks >500 tokens, and removes dead tokens', async (t) => {
  const bulkTokens = Array.from({ length: 505 }, (_, i) => `tok_en_${i}`);
  const env = createNotificationTestEnv({
    collections: {
      users: {
        u_en: { role: 'resident', fcmTokens: bulkTokens },
        u_es: { role: 'resident', fcmTokens: ['tok_es_live', 'tok_es_dead'] },
        u_muted_master: { role: 'resident', fcmTokens: ['tok_muted_master'] },
        u_muted_cat: { role: 'resident', fcmTokens: ['tok_muted_cat'] },
      },
    },
    rtdbInitial: {
      user_notification_settings: {
        u_en: { locale: 'en', pushEnabled: true, categories: { payments: true, reviews: true } },
        u_es: { locale: 'es', pushEnabled: true, categories: { reviews: true } },
        u_muted_master: { locale: 'en', pushEnabled: false, categories: { reviews: true } },
        u_muted_cat: { locale: 'es', pushEnabled: true, categories: { reviews: false } },
      },
    },
    failedTokens: new Set(['tok_es_dead']),
  });
  installNotificationTestEnv(t, env);

  const res = await _test.dispatchNotification({
    admin: _test.admin,
    recipientUids: ['u_en', 'u_en', 'u_es', 'u_muted_master', 'u_muted_cat', 'unknown', 'u_actor'],
    excludeUids: ['u_actor'],
    notificationKey: 'notif_test_1',
    category: 'reviews',
    type: 'payment_approved',
    targetRoute: 'payments',
    entityId: 'pay_1',
    titles: { es: 'Pago aprobado', en: 'Payment approved' },
    bodies: { es: 'Cuerpo ES', en: 'Body EN' },
  });

  // 1. All 4 real non-actor recipients mirrored to RTDB (including muted master/category users!)
  assert.equal(res.mirroredCount, 4);
  assert.equal(res.skippedOptOutCount, 2);
  for (const uid of ['u_en', 'u_es', 'u_muted_master', 'u_muted_cat']) {
    const entry = env.rtdbRoot.notifications?.[uid]?.notif_test_1;
    assert.ok(entry, `Expected RTDB record for ${uid}`);
    assert.equal(entry.titles.es, 'Pago aprobado');
    assert.equal(entry.titles.en, 'Payment approved');
    assert.equal(entry.isRead, false);
    assert.equal(entry.targetRoute, 'payments');
  }
  assert.equal(env.rtdbRoot.notifications?.u_actor, undefined);
  assert.equal(env.rtdbRoot.notifications?.unknown, undefined);

  // 2. FCM messages split by locale and chunked <= 500 tokens per batch, muted tokens omitted
  const esBatches = env.sentMessages.filter((m) => m.notification.title === 'Pago aprobado');
  const enBatches = env.sentMessages.filter((m) => m.notification.title === 'Payment approved');
  assert.equal(esBatches.length, 1);
  assert.deepEqual(esBatches[0].tokens, ['tok_es_live', 'tok_es_dead']);
  assert.equal(esBatches[0].android.notification.channelId, 'reviews');
  assert.equal(enBatches.length, 2);
  assert.equal(enBatches[0].tokens.length, 500);
  assert.equal(enBatches[1].tokens.length, 5);
  assert.equal(
    env.sentMessages.some((m) => m.tokens.includes('tok_muted_master') || m.tokens.includes('tok_muted_cat')),
    false
  );

  // 3. Dead token pruned from Firestore users doc via FieldValue.arrayRemove
  const updatedEsUser = (await env.makeDocRef('users', 'u_es').get()).data();
  assert.deepEqual(updatedEsUser.fcmTokens, ['tok_es_live']);
});

test('onPaymentWritten notifies admins (excl uploader) on pending create, skips admin-on-behalf direct approved, and notifies uploader on outcome', async (t) => {
  const env = createNotificationTestEnv({
    collections: {
      users: {
        admin_1: { role: 'admin', fcmTokens: ['tok_a1'] },
        admin_dual_uploader: { role: 'admin', fcmTokens: ['tok_a2'] },
        resident_1: { role: 'resident', fcmTokens: ['tok_r1'] },
      },
    },
    authUsers: [
      { uid: 'admin_claims_only', customClaims: { admin: true } },
    ],
    rtdbInitial: {
      user_notification_settings: {
        admin_1: { locale: 'en', pushEnabled: true },
        resident_1: { locale: 'es', pushEnabled: true },
      },
    },
  });
  installNotificationTestEnv(t, env);

  // 1. Direct admin-on-behalf approved payment -> no admin review or approval push
  await cloudFunctions.onPaymentWritten.run({
    id: 'evt_pay_direct',
    params: { paymentId: 'pay_direct' },
    data: {
      before: { data: () => undefined },
      after: { data: () => ({ status: 'approved', residentUid: 'resident_1', uploaderUid: 'admin_1' }) },
    },
  });
  assert.equal(env.sentMessages.length, 0);

  // 2. Dual-role admin uploads own pending payment -> notifies admin_1 & admin_claims_only, NOT admin_dual_uploader
  await cloudFunctions.onPaymentWritten.run({
    id: 'evt_pay_pending',
    params: { paymentId: 'pay_pending' },
    data: {
      before: { data: () => undefined },
      after: {
        data: () => ({
          status: 'pending',
          concept: 'monthly quota',
          period: '2026-11',
          residentUid: 'admin_dual_uploader',
          uploaderUid: 'admin_dual_uploader',
        }),
      },
    },
  });
  assert.ok(env.rtdbRoot.notifications?.admin_1?.evt_pay_pending);
  assert.ok(env.rtdbRoot.notifications?.admin_claims_only?.evt_pay_pending);
  assert.equal(env.rtdbRoot.notifications?.admin_dual_uploader, undefined);
  assert.equal(env.rtdbRoot.notifications.admin_1.evt_pay_pending.targetRoute, 'admin_payments');

  // 3. Payment transitions pending -> rejected -> notifies uploader resident_1
  await cloudFunctions.onPaymentWritten.run({
    id: 'evt_pay_rej',
    params: { paymentId: 'pay_res_1' },
    data: {
      before: { data: () => ({ status: 'pending', residentUid: 'resident_1', uploaderUid: 'resident_1' }) },
      after: {
        data: () => ({
          status: 'rejected',
          concept: 'monthly quota',
          period: '2026-11',
          rejectionReason: 'Blurry receipt',
          residentUid: 'resident_1',
          uploaderUid: 'resident_1',
        }),
      },
    },
  });
  const residentNotif = env.rtdbRoot.notifications?.resident_1?.evt_pay_rej;
  assert.ok(residentNotif);
  assert.equal(residentNotif.category, 'reviews');
  assert.equal(residentNotif.targetRoute, 'payments');
  assert.match(residentNotif.bodies.es, /Blurry receipt/);
});

test('reviewOwnershipClaim + onOwnershipClaimCreated + onOwnershipClaimDeleted handle approvals, rejections with reason, dual-role claims, and idempotency', async (t) => {
  const env = createNotificationTestEnv({
    collections: {
      users: {
        admin_1: { role: 'admin', fcmTokens: ['tok_a1'] },
        claimant_1: { role: 'admin', fcmTokens: ['tok_c1'] },
        claimant_2: { role: 'resident', fcmTokens: ['tok_c2'] },
        claimant_legacy: { role: 'resident', fcmTokens: ['tok_c3'] },
      },
      addresses: {
        addr_1: { streetName: 'Roble', number: '12', residentUid: null },
        addr_legacy: { streetName: 'Pino', number: '8', residentUid: 'claimant_legacy' },
      },
      ownership_claims: {
        claim_1: {
          userUid: 'claimant_1',
          addressRef: 'addresses/addr_1',
          proofUrl: 'https://firebasestorage.googleapis.com/v0/b/b/o/ownership_proofs%2Fclaimant_1%2Fproof.jpg?alt=media',
          status: 'pending',
          deliveryDate: 1700000000000,
        },
        claim_2: {
          userUid: 'claimant_2',
          addressRef: 'addresses/addr_1',
          proofUrl: 'ownership_proofs/claimant_2/p2.jpg',
          status: 'pending',
        },
      },
    },
    authUsers: [
      { uid: 'claimant_1', customClaims: { admin: true } },
      { uid: 'claimant_2', customClaims: {} },
    ],
  });
  await env.storageMock.bucket().file('ownership_proofs/claimant_1/proof.jpg').save(Buffer.from('img'));
  installNotificationTestEnv(t, env);

  // 1. Creation notifies admins excluding claimant_1
  await cloudFunctions.onOwnershipClaimCreated.run({
    id: 'evt_claim_new',
    params: { claimId: 'claim_1' },
    data: { data: () => ({ userUid: 'claimant_1', status: 'pending' }) },
  });
  assert.ok(env.rtdbRoot.notifications?.admin_1?.evt_claim_new);
  assert.equal(env.rtdbRoot.notifications?.claimant_1, undefined);

  // 2. Approve via reviewOwnershipClaim -> preserves existing admin claim, binds address, deletes proof, mirrors RTDB
  const wrappedReview = fft.wrap(cloudFunctions.reviewOwnershipClaim);
  const approveRes = await wrappedReview({
    data: { claimId: 'claim_1', action: 'approve' },
    auth: { uid: 'admin_1', token: { admin: true } },
  });
  assert.equal(approveRes.success, true);
  assert.deepEqual(env.authClaims.get('claimant_1'), { admin: true, resident: true });
  const addr1 = (await env.makeDocRef('addresses', 'addr_1').get()).data();
  assert.equal(addr1.residentUid, 'claimant_1');
  assert.equal(addr1.deliveryDate, 1700000000000);
  assert.equal(env.savedStorageFiles.has('ownership_proofs/claimant_1/proof.jpg'), false);
  assert.equal((await env.makeDocRef('ownership_claims', 'claim_1').get()).exists, false);
  assert.ok(env.rtdbRoot.notifications?.claimant_1?.claim_approved_claim_1);

  // 3. Subsequent onOwnershipClaimDeleted event sees `claim_approved_claim_1` and never double-sends
  const sendCountBeforeDeleteTrigger = env.sentMessages.length;
  await cloudFunctions.onOwnershipClaimDeleted.run({
    id: 'evt_claim_del_1',
    params: { claimId: 'claim_1' },
    data: { data: () => ({ userUid: 'claimant_1', addressRef: 'addresses/addr_1' }) },
  });
  assert.equal(env.sentMessages.length, sendCountBeforeDeleteTrigger);

  // 4. Reject via reviewOwnershipClaim -> includes reason, deletes claim, notifies claimant_2
  const rejectRes = await wrappedReview({
    data: { claimId: 'claim_2', action: 'reject', reason: 'Wrong deed document' },
    auth: { uid: 'admin_1', token: { admin: true } },
  });
  assert.equal(rejectRes.success, true);
  assert.ok(env.rtdbRoot.notifications?.claimant_2?.claim_rejected_claim_2);
  assert.match(env.rtdbRoot.notifications.claimant_2.claim_rejected_claim_2.bodies.es, /Wrong deed document/);

  // 5. Legacy delete approval fallback -> verifies addresses.residentUid === claimant_legacy and notifies once
  await cloudFunctions.onOwnershipClaimDeleted.run({
    id: 'evt_claim_legacy',
    params: { claimId: 'claim_legacy_1' },
    data: { data: () => ({ userUid: 'claimant_legacy', addressRef: 'addresses/addr_legacy' }) },
  });
  assert.ok(env.rtdbRoot.notifications?.claimant_legacy?.claim_approved_claim_legacy_1);
});

test('onBookingWritten notifies admins on pending review / resubmission and notifies requester on approval/rejection', async (t) => {
  const env = createNotificationTestEnv({
    collections: {
      users: {
        admin_1: { role: 'admin', fcmTokens: ['tok_a1'] },
        res_1: { role: 'resident', fcmTokens: ['tok_r1'] },
      },
    },
  });
  installNotificationTestEnv(t, env);

  await cloudFunctions.onBookingWritten.run({
    id: 'evt_bk_pending',
    params: { bookingId: 'bk_1' },
    data: {
      before: { data: () => ({ status: 'rejected' }) },
      after: { data: () => ({ status: 'pending review', userUid: 'res_1', facilityName: 'Clubhouse' }) },
    },
  });
  assert.equal(env.rtdbRoot.notifications?.admin_1?.evt_bk_pending?.targetRoute, 'admin_bookings');

  await cloudFunctions.onBookingWritten.run({
    id: 'evt_bk_approved',
    params: { bookingId: 'bk_1' },
    data: {
      before: { data: () => ({ status: 'pending review', userUid: 'res_1', facilityName: 'Clubhouse' }) },
      after: { data: () => ({ status: 'approved (upcoming)', userUid: 'res_1', facilityName: 'Clubhouse' }) },
    },
  });
  assert.equal(env.rtdbRoot.notifications?.res_1?.evt_bk_approved?.targetRoute, 'bookings');
  assert.equal(env.rtdbRoot.notifications?.res_1?.evt_bk_approved?.type, 'booking_approved');
});

test('onSanctionWritten notifies ONLY primary address resident (not roommate or non-create updates)', async (t) => {
  const env = createNotificationTestEnv({
    collections: {
      addresses: {
        addr_10: { residentUid: 'primary_uid' },
      },
      users: {
        primary_uid: { role: 'resident', fcmTokens: ['tok_primary'] },
        roommate_uid: { role: 'roommate', fcmTokens: ['tok_roommate'] },
      },
    },
  });
  installNotificationTestEnv(t, env);

  await cloudFunctions.onSanctionWritten.run({
    id: 'evt_sanction_1',
    params: { sanctionId: 'sanc_1' },
    data: {
      before: { data: () => undefined },
      after: {
        data: () => ({
          status: 'active',
          amount: 500,
          reason: 'Late noise',
          addressRef: env.makeDocRef('addresses', 'addr_10'),
          residentUid: 'roommate_uid', // Simulates client authorizedUids.first containing roommate
        }),
      },
    },
  });
  assert.ok(env.rtdbRoot.notifications?.primary_uid?.evt_sanction_1);
  assert.equal(env.rtdbRoot.notifications?.roommate_uid, undefined);
  assert.equal(env.rtdbRoot.notifications.primary_uid.evt_sanction_1.targetRoute, 'sanctions');
});

test('onTransparencyDocumentWritten respects parent folder inheritance, promotions admin->all, skips overwrites, and excludes guards', async (t) => {
  const env = createNotificationTestEnv({
    collections: {
      document_folders: {
        admin_folder: { visibility: 'admin', parentId: 'root' },
        public_folder: { visibility: 'all', parentId: 'root' },
      },
      users: {
        admin_uploader: { role: 'admin', fcmTokens: ['tok_up'] },
        admin_other: { role: 'admin', fcmTokens: ['tok_ao'] },
        resident_1: { role: 'resident', fcmTokens: ['tok_r1'] },
        roommate_1: { role: 'roommate', fcmTokens: ['tok_rm1'] },
        guard_1: { role: 'guard', fcmTokens: ['tok_g1'] },
      },
    },
  });
  installNotificationTestEnv(t, env);

  // 1. Creation with doc visibility 'all' inside an 'admin' folder -> effective visibility 'admin'
  await cloudFunctions.onTransparencyDocumentWritten.run({
    id: 'evt_doc_admin_folder',
    params: { docId: 'doc_1' },
    data: {
      before: { data: () => undefined },
      after: {
        data: () => ({
          title: 'Reglamento Interno',
          visibility: 'all',
          folderId: 'admin_folder',
          uploaderUid: 'admin_uploader',
        }),
      },
    },
  });
  assert.ok(env.rtdbRoot.notifications?.admin_other?.evt_doc_admin_folder);
  assert.equal(env.rtdbRoot.notifications?.admin_uploader, undefined);
  assert.equal(env.rtdbRoot.notifications?.resident_1, undefined);
  assert.equal(env.rtdbRoot.notifications?.guard_1, undefined);

  // 2. Routine overwrite on an already-'all' doc -> skipped
  await cloudFunctions.onTransparencyDocumentWritten.run({
    id: 'evt_doc_overwrite',
    params: { docId: 'doc_2' },
    data: {
      before: { data: () => ({ title: 'A', visibility: 'all', folderId: 'public_folder' }) },
      after: { data: () => ({ title: 'A v2', visibility: 'all', folderId: 'public_folder', uploaderUid: 'admin_uploader' }) },
    },
  });
  assert.equal(env.rtdbRoot.notifications?.resident_1, undefined);

  // 3. Visibility promotion 'admin' -> 'all' -> notifies admin_other, resident_1, roommate_1 (NOT guard_1!)
  await cloudFunctions.onTransparencyDocumentWritten.run({
    id: 'evt_doc_promote',
    params: { docId: 'doc_3' },
    data: {
      before: { data: () => ({ title: 'Balance', visibility: 'admin', folderId: 'public_folder' }) },
      after: { data: () => ({ title: 'Balance', visibility: 'all', folderId: 'public_folder', uploaderUid: 'admin_uploader' }) },
    },
  });
  assert.ok(env.rtdbRoot.notifications?.admin_other?.evt_doc_promote);
  assert.ok(env.rtdbRoot.notifications?.resident_1?.evt_doc_promote);
  assert.ok(env.rtdbRoot.notifications?.roommate_1?.evt_doc_promote);
  assert.equal(env.rtdbRoot.notifications?.guard_1, undefined);
  assert.equal(env.rtdbRoot.notifications?.admin_uploader, undefined);
});

test('notifyAccessResult handles QR entry & exit without PII and keeps one-time QR deactivation intact', async (t) => {
  const env = createNotificationTestEnv({
    collections: {
      qr_codes: {
        qr_once: { isOneTime: true, status: 'active' },
      },
      users: {
        res_1: { role: 'resident', fcmTokens: ['tok_r1'] },
      },
    },
  });
  installNotificationTestEnv(t, env);

  // 1. Allowed entry while isInside !== true deactivates one-time QR + notifies creator without plates/guard PII
  await cloudFunctions.notifyAccessResult.run({
    id: 'evt_qr_entry',
    params: { logId: 'log_1' },
    data: {
      before: { data: () => undefined },
      after: {
        data: () => ({
          creatorUid: 'res_1',
          qrCodeId: 'qr_once',
          status: 'allowed',
          isInside: false,
          guestName: 'Carlos',
          vehiclePlates: 'XYZ-9999',
          guardName: 'Guardia Uno',
          visitorPlatePhotoUrl: 'https://secret-plate.jpg',
        }),
      },
    },
  });
  assert.equal((await env.makeDocRef('qr_codes', 'qr_once').get()).data().status, 'deactivated (validated)');
  const entryNotif = env.rtdbRoot.notifications?.res_1?.evt_qr_entry;
  assert.ok(entryNotif);
  assert.equal(entryNotif.targetRoute, 'qr_codes');
  assert.doesNotMatch(JSON.stringify(entryNotif), /XYZ-9999|Guardia Uno|secret-plate/);

  // 2. Exit update (`!before.exitTimestamp && after.exitTimestamp`) sends exit notification
  await cloudFunctions.notifyAccessResult.run({
    id: 'evt_qr_exit',
    params: { logId: 'log_1' },
    data: {
      before: { data: () => ({ creatorUid: 'res_1', qrCodeId: 'qr_once', exitTimestamp: null }) },
      after: { data: () => ({ creatorUid: 'res_1', qrCodeId: 'qr_once', guestName: 'Carlos', exitTimestamp: 1700000100000 }) },
    },
  });
  const exitNotif = env.rtdbRoot.notifications?.res_1?.evt_qr_exit;
  assert.ok(exitNotif);
  assert.equal(exitNotif.type, 'qr_exit');
});

test('addRoommate & removeRoommate notify both sides on add/admin removal and only roommate on resident removal', async (t) => {
  const env = createNotificationTestEnv({
    collections: {
      users: {
        res_1: { role: 'resident', addressRef: 'addresses/a1', familyMembers: [], fcmTokens: ['tok_r1'] },
        rm_1: { role: 'resident', addressRef: null, fcmTokens: ['tok_rm1'] },
        admin_1: { role: 'admin', fcmTokens: ['tok_a1'] },
      },
    },
  });
  installNotificationTestEnv(t, env);

  const wrappedAdd = fft.wrap(cloudFunctions.addRoommate);
  const wrappedRemove = fft.wrap(cloudFunctions.removeRoommate);

  await wrappedAdd({
    data: { roommateUid: 'rm_1' },
    auth: { uid: 'res_1', token: { resident: true } },
  });
  assert.equal(Object.keys(env.rtdbRoot.notifications?.rm_1 || {}).length, 1);
  assert.equal(Object.keys(env.rtdbRoot.notifications?.res_1 || {}).length, 1);

  // Resident removes roommate -> notifies removed roommate only
  await wrappedRemove({
    data: { roommateUid: 'rm_1' },
    auth: { uid: 'res_1', token: { resident: true } },
  });
  assert.equal(Object.keys(env.rtdbRoot.notifications?.rm_1 || {}).length, 2);
  assert.equal(Object.keys(env.rtdbRoot.notifications?.res_1 || {}).length, 1);

  // Re-add then Admin removes -> notifies both rm_1 AND res_1
  await wrappedAdd({
    data: { roommateUid: 'rm_1' },
    auth: { uid: 'res_1', token: { resident: true } },
  });
  await wrappedRemove({
    data: { roommateUid: 'rm_1' },
    auth: { uid: 'admin_1', token: { admin: true } },
  });
  assert.equal(Object.keys(env.rtdbRoot.notifications?.rm_1 || {}).length, 4);
  assert.equal(Object.keys(env.rtdbRoot.notifications?.res_1 || {}).length, 3);
});

test('translateAnnouncement dispatches to intended audiences (excluding Guards) even if translation fails', async (t) => {
  const env = createNotificationTestEnv({
    collections: {
      users: {
        admin_creator: { role: 'admin', fcmTokens: ['tok_ac'] },
        admin_2: { role: 'admin', fcmTokens: ['tok_a2'] },
        res_1: { role: 'resident', fcmTokens: ['tok_r1'] },
        rm_1: { role: 'roommate', fcmTokens: ['tok_rm1'] },
        guard_1: { role: 'guard', fcmTokens: ['tok_g1'] },
      },
    },
  });
  installNotificationTestEnv(t, env);

  const origModels = _test.ai.models;
  t.after(() => {
    _test.ai.models = origModels;
  });

  // 1. Admin-only system alert (e.g., cancelBooking) when AI throws -> still notifies admins only
  _test.ai.models = {
    async generateContent() {
      throw new Error('Simulated offline AI failure');
    },
  };
  await cloudFunctions.translateAnnouncement.run({
    id: 'evt_ann_admin',
    params: { announcementId: 'ann_1' },
    data: {
      ref: { update: async () => {} },
      data: () => ({
        title: 'Booking Cancelled',
        content: 'Booking b1 cancelled',
        targetAudience: 'admin',
        creatorUid: 'system',
      }),
    },
  });
  assert.ok(env.rtdbRoot.notifications?.admin_creator?.evt_ann_admin);
  assert.ok(env.rtdbRoot.notifications?.admin_2?.evt_ann_admin);
  assert.equal(env.rtdbRoot.notifications?.res_1, undefined);
  assert.equal(env.rtdbRoot.notifications?.guard_1, undefined);

  // 2. Public announcement with AI translation -> populates bilingual text and excludes creatorUid & Guards
  _test.ai.models = {
    async generateContent() {
      return { text: '{"title":"Maintenance","content":"Water shutoff"}' };
    },
  };
  await cloudFunctions.translateAnnouncement.run({
    id: 'evt_ann_all',
    params: { announcementId: 'ann_2' },
    data: {
      ref: { update: async () => {} },
      data: () => ({
        title: 'Mantenimiento',
        content: 'Corte de agua',
        targetAudience: 'all',
        creatorUid: 'admin_creator',
      }),
    },
  });
  assert.ok(env.rtdbRoot.notifications?.admin_2?.evt_ann_all);
  assert.ok(env.rtdbRoot.notifications?.res_1?.evt_ann_all);
  assert.ok(env.rtdbRoot.notifications?.rm_1?.evt_ann_all);
  assert.equal(env.rtdbRoot.notifications.res_1.evt_ann_all.titles.en, 'Maintenance');
  assert.equal(env.rtdbRoot.notifications.res_1.evt_ann_all.bodies.en, 'Water shutoff');
  assert.equal(env.rtdbRoot.notifications?.admin_creator?.evt_ann_all, undefined);
  assert.equal(env.rtdbRoot.notifications?.guard_1, undefined);
});

test('pruneOldRtdbNotifications enforces 30-day & 100-item retention and deleteOwnAccount wipes user RTDB nodes', async (t) => {
  const nowMillis = Date.UTC(2026, 10, 18, 12, 0, 0);
  const oldTs = nowMillis - 31 * 24 * 60 * 60 * 1000;
  const recentNotifs = {};
  for (let i = 0; i < 105; i++) {
    recentNotifs[`n_${String(i).padStart(3, '0')}`] = { createdAt: nowMillis - (105 - i) * 1000 };
  }
  recentNotifs.n_old_expired = { createdAt: oldTs };

  const env = createNotificationTestEnv({
    collections: {
      users: {
        u_del: { role: 'resident', addressRef: null },
      },
    },
    rtdbInitial: {
      notifications: {
        u_keep: recentNotifs,
        u_del: { some_notif: { createdAt: nowMillis } },
      },
      user_notification_settings: {
        u_keep: { locale: 'es', pushEnabled: true },
        u_del: { locale: 'en', pushEnabled: true },
      },
    },
  });
  installNotificationTestEnv(t, env);

  const pruned = await _test.pruneOldRtdbNotifications(env.rtdbMock, nowMillis);
  // 1 expired (>30d) + 5 excess over 100 cap = 6 removed, newest 100 remain
  assert.equal(pruned, 6);
  const remaining = Object.keys(env.rtdbRoot.notifications.u_keep);
  assert.equal(remaining.length, 100);
  assert.equal(remaining.includes('n_old_expired'), false);
  assert.equal(remaining.includes('n_000'), false);
  assert.equal(remaining.includes('n_104'), true);

  const wrappedDelete = fft.wrap(cloudFunctions.deleteOwnAccount);
  await wrappedDelete({ data: {}, auth: { uid: 'u_del', token: {} } });
  assert.equal(env.rtdbRoot.notifications?.u_del, undefined);
  assert.equal(env.rtdbRoot.user_notification_settings?.u_del, undefined);
});

test('cleanupOldRtdbNotifications runs RTDB pruning independently while checkMonthlyPaymentStatuses skips RTDB notifications', async (t) => {
  const endpoint = cloudFunctions.cleanupOldRtdbNotifications.__endpoint;
  assert.equal(endpoint.scheduleTrigger.schedule, '0 0 * * *');
  assert.equal(endpoint.scheduleTrigger.timeZone, 'America/Mexico_City');
  assert.equal(endpoint.timeoutSeconds, 300);

  const nowMillis = Date.now();
  const oldTs = nowMillis - 31 * 24 * 60 * 60 * 1000;
  const recentNotifs = {};
  for (let i = 0; i < 105; i++) {
    recentNotifs[`n_${String(i).padStart(3, '0')}`] = { createdAt: nowMillis - (105 - i) * 1000 };
  }
  recentNotifs.n_old_expired = { createdAt: oldTs };

  const env = createNotificationTestEnv({
    collections: {
      config: {
        app_settings: { paymentCutoffDay: 1, gracePeriodDays: 10, timeZone: 'America/Mexico_City' },
      },
    },
    rtdbInitial: {
      notifications: {
        u_sched: recentNotifs,
      },
    },
  });
  installNotificationTestEnv(t, env);

  // 1. checkMonthlyPaymentStatuses must not touch RTDB notifications
  await cloudFunctions.checkMonthlyPaymentStatuses.run({});
  assert.equal(Object.keys(env.rtdbRoot.notifications.u_sched).length, 106);

  // 2. cleanupOldRtdbNotifications prunes expired and excess entries independently
  await cloudFunctions.cleanupOldRtdbNotifications.run({});
  const remaining = Object.keys(env.rtdbRoot.notifications.u_sched);
  assert.equal(remaining.length, 100);
  assert.equal(remaining.includes('n_old_expired'), false);
  assert.equal(remaining.includes('n_000'), false);
  assert.equal(remaining.includes('n_104'), true);

  // 3. Direct runRtdbNotificationCleanup helper returns count
  env.rtdbRoot.notifications.u_sched.n_extra_old = { createdAt: oldTs };
  const summary = await _test.runRtdbNotificationCleanup(env.rtdbMock, nowMillis);
  assert.equal(summary.prunedNotifsCount, 1);
});
