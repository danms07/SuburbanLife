const crypto = require('crypto');

const NOTIFICATION_CATEGORIES = Object.freeze({
  REVIEWS: 'reviews',
  SANCTIONS: 'sanctions',
  QR_ACCESS: 'qr_access',
  ROOMMATES: 'roommates',
  TRANSPARENCY: 'transparency',
  ANNOUNCEMENTS: 'announcements',
  ADMIN_REVIEWS: 'admin_reviews',
});

const VALID_NOTIFICATION_CATEGORIES = new Set(Object.values(NOTIFICATION_CATEGORIES));

const ALLOWED_TARGET_ROUTES = new Set([
  'home',
  'notifications',
  'payments',
  'sanctions',
  'bookings',
  'qr_codes',
  'roommates',
  'transparency',
  'announcements',
  'admin_claims',
  'admin_payments',
  'admin_bookings',
]);

const NOTIFICATION_RETENTION_DAYS = 30;
const NOTIFICATION_RETENTION_MS = NOTIFICATION_RETENTION_DAYS * 24 * 60 * 60 * 1000;
const MAX_NOTIFICATIONS_PER_USER = 100;
const MAX_MULTICAST_TOKENS = 500;

const STALE_TOKEN_ERROR_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/mismatched-credential',
]);

const DEFAULT_SETTINGS = Object.freeze({
  locale: 'es',
  pushEnabled: true,
  inAppBannerEnabled: true,
});

/**
 * Strips ASCII control chars and normalizes whitespace before truncating text
 * safely within FCM/RTDB display bounds.
 */
function truncateText(value, maxLen = 200) {
  if (value === null || value === undefined) return '';
  const cleaned = String(value)
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001F\u007F]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!cleaned) return '';
  if (cleaned.length <= maxLen) return cleaned;
  if (maxLen <= 3) return cleaned.slice(0, maxLen);
  return `${cleaned.slice(0, maxLen - 3).trimEnd()}...`;
}

/**
 * Sanitizes an identifier for safe use as a Firebase RTDB key.
 */
function sanitizeRtdbKey(rawKey) {
  const normalized = typeof rawKey === 'string'
    ? rawKey.replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 128)
    : '';
  return normalized || crypto.randomUUID();
}

/**
 * Enforces strict target-route allow-listing to prevent arbitrary navigation targets.
 */
function sanitizeTargetRoute(route) {
  if (typeof route === 'string' && ALLOWED_TARGET_ROUTES.has(route)) {
    return route;
  }
  return 'home';
}

/**
 * Sanitizes primitive metadata fields so RTDB rules accept all server writes.
 */
function sanitizeMetadata(rawMetadata) {
  if (!rawMetadata || typeof rawMetadata !== 'object' || Array.isArray(rawMetadata)) {
    return null;
  }
  const clean = {};
  for (const [key, val] of Object.entries(rawMetadata)) {
    const safeKey = String(key).replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 48);
    if (!safeKey || val === null || val === undefined) continue;
    if (typeof val === 'string') {
      const trimmed = truncateText(val, 160);
      if (trimmed) clean[safeKey] = trimmed;
    } else if (typeof val === 'number' && Number.isFinite(val)) {
      clean[safeKey] = val;
    } else if (typeof val === 'boolean') {
      clean[safeKey] = val;
    }
  }
  return Object.keys(clean).length > 0 ? clean : null;
}

/**
 * Builds bounded bilingual ES/EN copy objects.
 */
function buildLocalizedText(esText, enText, maxLen = 220) {
  const esClean = truncateText(esText || enText, maxLen);
  const enClean = truncateText(enText || esText, maxLen);
  return {
    es: esClean,
    en: enClean,
  };
}

function getPaymentConceptLabels(concept) {
  switch (String(concept || '').toLowerCase()) {
    case 'sanction':
      return { es: 'pago de sanción', en: 'sanction payment' };
    case 'amenity':
    case 'booking':
      return { es: 'pago de amenidad', en: 'amenity payment' };
    case 'extraordinary':
      return { es: 'cuota extraordinaria', en: 'extraordinary fee' };
    default:
      return { es: 'cuota mensual', en: 'monthly fee' };
  }
}

function buildPaymentReviewNotification(paymentId, paymentData = {}) {
  const isApproved = paymentData.status === 'approved';
  const concept = getPaymentConceptLabels(paymentData.concept);
  const period = truncateText(paymentData.period || '', 32);
  const periodSuffixEs = period ? ` (${period})` : '';
  const periodSuffixEn = period ? ` (${period})` : '';
  const reason = truncateText(paymentData.rejectionReason || '', 90);

  return {
    category: NOTIFICATION_CATEGORIES.REVIEWS,
    type: isApproved ? 'payment_approved' : 'payment_rejected',
    targetRoute: 'payments',
    entityId: paymentId,
    titles: buildLocalizedText(
      isApproved ? 'Pago aprobado' : 'Pago rechazado',
      isApproved ? 'Payment approved' : 'Payment rejected',
      120
    ),
    bodies: buildLocalizedText(
      isApproved
        ? `Tu ${concept.es}${periodSuffixEs} fue aprobado.`
        : reason
          ? `Tu ${concept.es}${periodSuffixEs} fue rechazado: ${reason}`
          : `Tu ${concept.es}${periodSuffixEs} fue rechazado. Revisa el detalle en la app.`,
      isApproved
        ? `Your ${concept.en}${periodSuffixEn} was approved.`
        : reason
          ? `Your ${concept.en}${periodSuffixEn} was rejected: ${reason}`
          : `Your ${concept.en}${periodSuffixEn} was rejected. Check details in the app.`,
      220
    ),
    metadata: {
      paymentId,
      status: paymentData.status || '',
      concept: paymentData.concept || '',
      period,
    },
  };
}

function buildBookingReviewNotification(bookingId, bookingData = {}) {
  const isApproved = bookingData.status === 'approved (upcoming)';
  const facilityLabel = truncateText(
    bookingData.facilityName || bookingData.facilityId || '',
    60
  );
  const reason = truncateText(bookingData.rejectionReason || bookingData.notes || '', 90);

  return {
    category: NOTIFICATION_CATEGORIES.REVIEWS,
    type: isApproved ? 'booking_approved' : 'booking_rejected',
    targetRoute: 'bookings',
    entityId: bookingId,
    titles: buildLocalizedText(
      isApproved ? 'Reserva aprobada' : 'Reserva rechazada',
      isApproved ? 'Booking approved' : 'Booking rejected',
      120
    ),
    bodies: buildLocalizedText(
      isApproved
        ? (facilityLabel
          ? `Tu reserva en ${facilityLabel} fue aprobada.`
          : 'Tu solicitud de reserva fue aprobada.')
        : reason
          ? `Tu reserva${facilityLabel ? ` (${facilityLabel})` : ''} fue rechazada: ${reason}`
          : `Tu solicitud de reserva${facilityLabel ? ` (${facilityLabel})` : ''} fue rechazada.`,
      isApproved
        ? (facilityLabel
          ? `Your booking for ${facilityLabel} was approved.`
          : 'Your booking request was approved.')
        : reason
          ? `Your booking${facilityLabel ? ` (${facilityLabel})` : ''} was rejected: ${reason}`
          : `Your booking request${facilityLabel ? ` (${facilityLabel})` : ''} was rejected.`,
      220
    ),
    metadata: {
      bookingId,
      status: bookingData.status || '',
      facilityId: bookingData.facilityId || '',
    },
  };
}

function buildOwnershipClaimReviewNotification(claimId, {
  approved,
  reason = '',
  addressLabel = '',
} = {}) {
  const safeAddr = truncateText(addressLabel, 64);
  const safeReason = truncateText(reason, 90);

  return {
    category: NOTIFICATION_CATEGORIES.REVIEWS,
    type: approved ? 'ownership_claim_approved' : 'ownership_claim_rejected',
    targetRoute: 'home',
    entityId: claimId,
    titles: buildLocalizedText(
      approved ? 'Solicitud de residencia aprobada' : 'Solicitud de residencia rechazada',
      approved ? 'Residence claim approved' : 'Residence claim rejected',
      120
    ),
    bodies: buildLocalizedText(
      approved
        ? (safeAddr
          ? `Tu solicitud para ${safeAddr} fue aprobada.`
          : 'Tu solicitud de residencia fue aprobada. Ya tienes acceso completo.')
        : safeReason
          ? `Tu solicitud${safeAddr ? ` para ${safeAddr}` : ''} fue rechazada: ${safeReason}`
          : `Tu solicitud de residencia${safeAddr ? ` para ${safeAddr}` : ''} fue rechazada.`,
      approved
        ? (safeAddr
          ? `Your residence claim for ${safeAddr} was approved.`
          : 'Your residence claim was approved. Full access is now enabled.')
        : safeReason
          ? `Your residence claim${safeAddr ? ` for ${safeAddr}` : ''} was rejected: ${safeReason}`
          : `Your residence claim${safeAddr ? ` for ${safeAddr}` : ''} was rejected.`,
      220
    ),
    metadata: {
      claimId,
      approved: Boolean(approved),
    },
  };
}

function buildSanctionNotification(sanctionId, sanctionData = {}) {
  const rawAmount = Number(sanctionData.amount);
  const amountLabel = Number.isFinite(rawAmount) && rawAmount > 0
    ? `$${rawAmount.toFixed(2)}`
    : '';
  const summary = truncateText(
    sanctionData.reason || sanctionData.description || sanctionData.title || '',
    90
  );

  return {
    category: NOTIFICATION_CATEGORIES.SANCTIONS,
    type: 'sanction_created',
    targetRoute: 'sanctions',
    entityId: sanctionId,
    titles: buildLocalizedText('Nueva sanción aplicada', 'New sanction issued', 120),
    bodies: buildLocalizedText(
      [
        amountLabel ? `Se registró una sanción por ${amountLabel}.` : 'Se registró una nueva sanción en tu domicilio.',
        summary,
      ].filter(Boolean).join(' '),
      [
        amountLabel ? `A sanction of ${amountLabel} was issued to your residence.` : 'A new sanction was issued to your residence.',
        summary,
      ].filter(Boolean).join(' '),
      220
    ),
    metadata: {
      sanctionId,
      status: sanctionData.status || 'active',
    },
  };
}

function buildTransparencyNotification(docId, docData = {}, effectiveVisibility = 'all') {
  const esTitle = truncateText(docData.title || docData.fileName || 'Documento', 100);
  const enTitle = truncateText(
    (docData.translatedTitles && docData.translatedTitles.en) || docData.title || docData.fileName || 'Document',
    100
  );
  const isAdminOnly = effectiveVisibility === 'admin';

  return {
    category: NOTIFICATION_CATEGORIES.TRANSPARENCY,
    type: 'transparency_document',
    targetRoute: 'transparency',
    entityId: docId,
    titles: buildLocalizedText(
      isAdminOnly ? 'Nuevo documento administrativo' : 'Nuevo documento de transparencia',
      isAdminOnly ? 'New admin-only document' : 'New transparency document',
      120
    ),
    bodies: buildLocalizedText(
      isAdminOnly
        ? `"${esTitle}" fue publicado solo para administración.`
        : `"${esTitle}" ya está disponible en Transparencia.`,
      isAdminOnly
        ? `"${enTitle}" was published for admins only.`
        : `"${enTitle}" is now available in Transparency.`,
      220
    ),
    metadata: {
      docId,
      visibility: effectiveVisibility,
    },
  };
}

function buildQrAccessNotification(logId, logData = {}, { isExit = false } = {}) {
  const guestLabel = truncateText(logData.guestName || logData.accessCategory || '', 60);
  const isAllowed = logData.status === 'allowed';

  if (isExit) {
    return {
      category: NOTIFICATION_CATEGORIES.QR_ACCESS,
      type: 'qr_exit',
      targetRoute: 'qr_codes',
      entityId: logId,
      titles: buildLocalizedText('Salida de visitante registrada', 'Visitor exit recorded', 120),
      bodies: buildLocalizedText(
        guestLabel
          ? `${guestLabel} registró su salida del fraccionamiento.`
          : 'Tu visitante registró su salida del fraccionamiento.',
        guestLabel
          ? `${guestLabel} checked out of the community.`
          : 'Your visitor checked out of the community.',
        220
      ),
      metadata: {
        qrCodeId: logData.qrCodeId || '',
        status: 'exit',
        isExit: true,
      },
    };
  }

  return {
    category: NOTIFICATION_CATEGORIES.QR_ACCESS,
    type: isAllowed ? 'qr_entry_allowed' : 'qr_entry_denied',
    targetRoute: 'qr_codes',
    entityId: logId,
    titles: buildLocalizedText(
      isAllowed ? 'Acceso QR permitido' : 'Acceso QR denegado',
      isAllowed ? 'QR entry granted' : 'QR entry denied',
      120
    ),
    bodies: buildLocalizedText(
      isAllowed
        ? (guestLabel ? `${guestLabel} ingresó con tu pase QR.` : 'Se permitió el acceso con tu pase QR.')
        : (guestLabel ? `Se denegó el ingreso para ${guestLabel}.` : 'Se denegó el acceso con tu pase QR.'),
      isAllowed
        ? (guestLabel ? `${guestLabel} entered using your QR pass.` : 'Entry was granted for your QR pass.')
        : (guestLabel ? `Entry was denied for ${guestLabel}.` : 'Entry was denied for your QR pass.'),
      220
    ),
    metadata: {
      qrCodeId: logData.qrCodeId || '',
      status: logData.status || '',
      isExit: false,
    },
  };
}

function buildRoommateNotification({ targetRole, isRemoval = false, initiatedByAdmin = false } = {}) {
  if (!isRemoval) {
    if (targetRole === 'roommate') {
      return {
        category: NOTIFICATION_CATEGORIES.ROOMMATES,
        type: 'roommate_added_self',
        targetRoute: 'roommates',
        titles: buildLocalizedText(
          'Fuiste agregado como compañero',
          'You were added as a roommate',
          120
        ),
        bodies: buildLocalizedText(
          'Ahora estás vinculado a una residencia y puedes gestionar pases e información del domicilio.',
          'You are now linked to a residence and can manage household passes and info.',
          220
        ),
      };
    }
    return {
      category: NOTIFICATION_CATEGORIES.ROOMMATES,
      type: 'roommate_added_resident',
      targetRoute: 'roommates',
      titles: buildLocalizedText(
        'Compañero agregado al domicilio',
        'Roommate added to household',
        120
      ),
      bodies: buildLocalizedText(
        'Se vinculó un nuevo compañero de vivienda a tu domicilio.',
        'A new roommate has been linked to your residence.',
        220
      ),
    };
  }

  if (targetRole === 'roommate') {
    return {
      category: NOTIFICATION_CATEGORIES.ROOMMATES,
      type: 'roommate_removed_self',
      targetRoute: 'home',
      titles: buildLocalizedText(
        'Fuiste removido del domicilio',
        'Removed from residence',
        120
      ),
      bodies: buildLocalizedText(
        initiatedByAdmin
          ? 'Un administrador te desvinculó de tu domicilio anterior.'
          : 'Fuiste desvinculado de tu domicilio anterior.',
        initiatedByAdmin
          ? 'An administrator unlinked you from your previous residence.'
          : 'You were unlinked from your previous residence.',
        220
      ),
    };
  }

  return {
    category: NOTIFICATION_CATEGORIES.ROOMMATES,
    type: 'roommate_removed_by_admin',
    targetRoute: 'roommates',
    titles: buildLocalizedText(
      'Compañero removido por administración',
      'Roommate removed by admin',
      120
    ),
    bodies: buildLocalizedText(
      'Un administrador removió a un compañero de tu grupo familiar.',
      'An administrator removed a roommate from your household.',
      220
    ),
  };
}

function buildAnnouncementNotification(announcementId, data = {}) {
  const esTitle = truncateText(data.title || 'Nuevo aviso', 100);
  const enTitle = truncateText(
    (data.translatedTitles && data.translatedTitles.en) || data.title || 'New announcement',
    100
  );
  const esBody = truncateText(data.content || esTitle, 180);
  const enBody = truncateText(
    (data.translatedContents && data.translatedContents.en) || data.content || enTitle,
    180
  );

  return {
    category: NOTIFICATION_CATEGORIES.ANNOUNCEMENTS,
    type: 'announcement_created',
    targetRoute: 'announcements',
    entityId: announcementId,
    titles: buildLocalizedText(esTitle, enTitle, 120),
    bodies: buildLocalizedText(esBody, enBody, 220),
    metadata: {
      announcementId,
      targetAudience: data.targetAudience || 'all',
    },
  };
}

function buildAdminReviewRequestNotification(requestType, entityId, data = {}) {
  if (requestType === 'payment') {
    const concept = getPaymentConceptLabels(data.concept);
    const period = truncateText(data.period || '', 32);
    const periodSuffix = period ? ` (${period})` : '';
    return {
      category: NOTIFICATION_CATEGORIES.ADMIN_REVIEWS,
      type: 'admin_pending_payment',
      targetRoute: 'admin_payments',
      entityId,
      titles: buildLocalizedText(
        'Pago pendiente por revisar',
        'Payment awaiting review',
        120
      ),
      bodies: buildLocalizedText(
        `Hay un nuevo comprobante de ${concept.es}${periodSuffix} pendiente de revisión.`,
        `A new ${concept.en}${periodSuffix} proof is awaiting review.`,
        220
      ),
      metadata: { requestType: 'payment', entityId },
    };
  }

  if (requestType === 'claim') {
    return {
      category: NOTIFICATION_CATEGORIES.ADMIN_REVIEWS,
      type: 'admin_pending_claim',
      targetRoute: 'admin_claims',
      entityId,
      titles: buildLocalizedText(
        'Nueva solicitud de residencia',
        'New residence claim',
        120
      ),
      bodies: buildLocalizedText(
        'Un usuario subió un comprobante para reclamar un domicilio.',
        'A user submitted an ownership proof claim for review.',
        220
      ),
      metadata: { requestType: 'claim', entityId },
    };
  }

  const facilityLabel = truncateText(data.facilityName || data.facilityId || '', 60);
  return {
    category: NOTIFICATION_CATEGORIES.ADMIN_REVIEWS,
    type: 'admin_pending_booking',
    targetRoute: 'admin_bookings',
    entityId,
    titles: buildLocalizedText(
      'Nueva solicitud de reserva',
      'New booking request',
      120
    ),
    bodies: buildLocalizedText(
      facilityLabel
        ? `Nueva solicitud de reserva para ${facilityLabel} pendiente de revisión.`
        : 'Hay una nueva solicitud de reserva pendiente de revisión.',
      facilityLabel
        ? `A new booking request for ${facilityLabel} is awaiting review.`
        : 'A new booking request is awaiting review.',
      220
    ),
    metadata: { requestType: 'booking', entityId },
  };
}

/**
 * Extracts an address document ID from a Firestore DocumentReference, document path, or ID string.
 */
function extractAddressId(addressRefOrId) {
  if (!addressRefOrId) return null;
  if (typeof addressRefOrId === 'string') {
    const trimmed = addressRefOrId.trim();
    if (!trimmed) return null;
    return trimmed.includes('/') ? trimmed.split('/').pop() : trimmed;
  }
  if (typeof addressRefOrId === 'object') {
    if (typeof addressRefOrId.id === 'string' && addressRefOrId.id.trim()) {
      return addressRefOrId.id.trim();
    }
    if (typeof addressRefOrId.path === 'string' && addressRefOrId.path.trim()) {
      return addressRefOrId.path.trim().split('/').pop();
    }
  }
  return null;
}

/**
 * Resolves the primary resident UID of an address (`addresses/{addressId}.residentUid`),
 * falling back to `fallbackResidentUid` only if the address record does not have one.
 */
async function resolveAddressPrimaryResidentUid(db, addressRefOrId, fallbackResidentUid = null) {
  const fallback = typeof fallbackResidentUid === 'string' && fallbackResidentUid.trim()
    ? fallbackResidentUid.trim()
    : null;
  const addressId = extractAddressId(addressRefOrId);
  if (!db || !addressId) {
    return fallback;
  }

  try {
    const addrSnap = await db.collection('addresses').doc(addressId).get();
    if (addrSnap.exists) {
      const residentUid = addrSnap.data()?.residentUid;
      if (typeof residentUid === 'string' && residentUid.trim()) {
        return residentUid.trim();
      }
    }
  } catch (err) {
    console.error(`Failed to resolve primary resident for address ${addressId}:`, err);
  }
  return fallback;
}

/**
 * Resolves all active UIDs matching any role in `allowedRoles`, excluding `excludeUids` and `'unknown'`.
 * When `'admin'` is eligible, also checks Auth custom claims (`admin === true`) to cover dual-role
 * admins whose Firestore `role` field may not explicitly list `'admin'`.
 */
async function resolveEligibleUidsByRoles(db, auth, allowedRoles, { excludeUids = [] } = {}) {
  const roles = Array.isArray(allowedRoles)
    ? [...new Set(allowedRoles.map((r) => String(r || '').trim().toLowerCase()).filter(Boolean))]
    : [];
  const excluded = new Set(
    (excludeUids || [])
      .map((u) => (typeof u === 'string' ? u.trim() : ''))
      .filter(Boolean)
  );
  excluded.add('unknown');

  const uidSet = new Set();
  const preloadedUserDocs = new Map();

  if (!db || roles.length === 0) {
    return { uids: [], preloadedUserDocs };
  }

  try {
    const userSnap = await db.collection('users').where('role', 'in', roles).get();
    for (const doc of userSnap.docs || []) {
      const uid = doc.id;
      preloadedUserDocs.set(uid, doc.data() || {});
      if (!excluded.has(uid)) {
        uidSet.add(uid);
      }
    }
  } catch (err) {
    console.error('Error querying users by role for notifications:', err);
  }

  // Catch any Auth-claims-only admins (e.g., dual-role residents promoted via setCustomUserClaims).
  if (roles.includes('admin') && auth && typeof auth.listUsers === 'function') {
    try {
      let nextPageToken;
      do {
        const result = await auth.listUsers(1000, nextPageToken);
        for (const userRecord of result.users || []) {
          if (userRecord.customClaims && userRecord.customClaims.admin === true) {
            if (!excluded.has(userRecord.uid)) {
              uidSet.add(userRecord.uid);
            }
          }
        }
        nextPageToken = result.pageToken;
      } while (nextPageToken);
    } catch (err) {
      console.error('Error listing auth admin users for notifications:', err);
    }
  }

  return { uids: Array.from(uidSet), preloadedUserDocs };
}

/**
 * Normalizes Transparency document/folder visibility (`'admin'` or `'all'`).
 * Null/undefined maps to `'all'` to match `firestore.rules` and UI backfill behavior.
 */
function normalizeVisibility(rawVisibility) {
  return String(rawVisibility || 'all').trim().toLowerCase() === 'admin' ? 'admin' : 'all';
}

/**
 * Resolves effective visibility of a Transparency document by intersecting `doc.visibility`
 * with parent folder chain (`document_folders/{folderId}`) and `official_manuals`.
 */
async function resolveEffectiveDocVisibility(db, docData, { depth = 0, visited = new Set() } = {}) {
  if (!docData) return 'admin';
  if (normalizeVisibility(docData.visibility) === 'admin') {
    return 'admin';
  }

  const folderId = typeof docData.folderId === 'string' ? docData.folderId.trim() : 'root';
  if (!folderId || folderId === 'root') {
    return 'all';
  }
  if (folderId === 'official_manuals') {
    return 'admin';
  }
  if (!db || depth >= 10 || visited.has(folderId)) {
    return 'all';
  }

  const nextVisited = new Set(visited);
  nextVisited.add(folderId);

  try {
    const folderSnap = await db.collection('document_folders').doc(folderId).get();
    if (!folderSnap.exists) return 'all';
    const folderData = folderSnap.data() || {};
    if (normalizeVisibility(folderData.visibility) === 'admin') {
      return 'admin';
    }
    const parentId = typeof folderData.parentId === 'string' ? folderData.parentId.trim() : 'root';
    if (!parentId || parentId === 'root') {
      return 'all';
    }
    return resolveEffectiveDocVisibility(
      db,
      { visibility: 'all', folderId: parentId },
      { depth: depth + 1, visited: nextVisited }
    );
  } catch (err) {
    console.error(`Error resolving folder visibility for folder ${folderId}:`, err);
    return 'admin';
  }
}

function getSafeRtdb(adminRef) {
  if (!adminRef || typeof adminRef.database !== 'function') return null;
  try {
    return adminRef.database();
  } catch (err) {
    if (process.env.K_SERVICE || process.env.FUNCTION_TARGET || process.env.FUNCTIONS_EMULATOR) {
      console.error('RTDB instance unavailable:', err);
    }
    return null;
  }
}

/**
 * Reads `/user_notification_settings/{uid}` from RTDB in parallel with safe defaults.
 */
async function resolveRecipientSettingsMap(dbRtdb, uids) {
  const settingsMap = new Map();
  for (const uid of uids) {
    settingsMap.set(uid, {
      locale: DEFAULT_SETTINGS.locale,
      pushEnabled: DEFAULT_SETTINGS.pushEnabled,
      inAppBannerEnabled: DEFAULT_SETTINGS.inAppBannerEnabled,
      categories: {},
    });
  }
  if (!dbRtdb || uids.length === 0) {
    return settingsMap;
  }

  await Promise.all(
    uids.map(async (uid) => {
      try {
        const snap = await dbRtdb.ref(`user_notification_settings/${uid}`).get();
        if (snap && snap.exists()) {
          const val = snap.val() || {};
          settingsMap.set(uid, {
            locale: val.locale === 'en' ? 'en' : 'es',
            pushEnabled: val.pushEnabled !== false,
            inAppBannerEnabled: val.inAppBannerEnabled !== false,
            categories:
              val.categories && typeof val.categories === 'object' ? val.categories : {},
          });
        }
      } catch (err) {
        console.error(`Error reading notification settings for user ${uid}:`, err);
      }
    })
  );

  return settingsMap;
}

/**
 * Central dispatcher:
 * 1. Deduplicates & excludes actors/`unknown`.
 * 2. Checks RTDB preferences (`locale`, `pushEnabled`, category opt-out) and optional idempotency key.
 * 3. Atomically mirrors bilingual entries to RTDB `/notifications/{uid}/{notifId}` even if pushes are muted.
 * 4. Sends single-language localized FCM multicast batches (<= 500 tokens) to opted-in users.
 * 5. Cleans dead/unregistered FCM tokens via `FieldValue.arrayRemove`.
 */
async function dispatchNotification({
  admin: adminRef,
  recipientUids = [],
  excludeUids = [],
  preloadedUserDocs = null,
  notificationKey = null,
  skipIfExists = false,
  category,
  type,
  titles,
  bodies,
  targetRoute = 'home',
  entityId = null,
  metadata = null,
  nowMillis = Date.now(),
  skipRtdbMirror = false,
}) {
  if (!adminRef || !VALID_NOTIFICATION_CATEGORIES.has(category)) {
    return { sentCount: 0, mirroredCount: 0, skippedOptOutCount: 0 };
  }

  const excluded = new Set(
    (excludeUids || [])
      .map((u) => (typeof u === 'string' ? u.trim() : ''))
      .filter(Boolean)
  );
  excluded.add('unknown');

  let eligibleUids = [...new Set(
    (recipientUids || [])
      .map((u) => (typeof u === 'string' ? u.trim() : ''))
      .filter((u) => u && !excluded.has(u))
  )];

  if (eligibleUids.length === 0) {
    return { sentCount: 0, mirroredCount: 0, skippedOptOutCount: 0 };
  }

  const db = adminRef.firestore();
  const dbRtdb = getSafeRtdb(adminRef);
  const safeKey = sanitizeRtdbKey(notificationKey);
  const safeRoute = sanitizeTargetRoute(targetRoute);
  const safeEntityId = entityId ? truncateText(String(entityId), 128) : '';
  const safeTitles = buildLocalizedText(titles?.es, titles?.en, 120);
  const safeBodies = buildLocalizedText(bodies?.es, bodies?.en, 220);
  const safeMetadata = sanitizeMetadata(metadata);

  if (notificationKey && skipIfExists && dbRtdb) {
    const checks = await Promise.all(
      eligibleUids.map(async (uid) => {
        try {
          const snap = await dbRtdb.ref(`notifications/${uid}/${safeKey}`).get();
          return snap && snap.exists() ? null : uid;
        } catch (err) {
          console.error(`Error checking idempotency key ${safeKey} for user ${uid}:`, err);
          return uid;
        }
      })
    );
    eligibleUids = checks.filter(Boolean);
    if (eligibleUids.length === 0) {
      return { sentCount: 0, mirroredCount: 0, skippedOptOutCount: 0 };
    }
  }

  const settingsMap = await resolveRecipientSettingsMap(dbRtdb, eligibleUids);

  const userDocMap = new Map(preloadedUserDocs || []);
  const missingUids = eligibleUids.filter((uid) => !userDocMap.has(uid));
  if (missingUids.length > 0 && db) {
    await Promise.all(
      missingUids.map(async (uid) => {
        try {
          const snap = await db.collection('users').doc(uid).get();
          if (snap.exists) {
            userDocMap.set(uid, snap.data() || {});
          }
        } catch (err) {
          console.error(`Error loading user document ${uid} for notifications:`, err);
        }
      })
    );
  }

  // 1. Always mirror to RTDB inbox for eligible users (unless explicitly suppressed).
  let mirroredCount = 0;
  if (!skipRtdbMirror && dbRtdb) {
    const rtdbUpdates = {};
    for (const uid of eligibleUids) {
      const record = {
        type: String(type || 'general').slice(0, 64),
        category,
        titles: safeTitles,
        bodies: safeBodies,
        targetRoute: safeRoute,
        createdAt: nowMillis,
        isRead: false,
        readAt: null,
      };
      if (safeEntityId) record.entityId = safeEntityId;
      if (safeMetadata) record.metadata = safeMetadata;
      rtdbUpdates[`notifications/${uid}/${safeKey}`] = record;
    }

    try {
      await dbRtdb.ref().update(rtdbUpdates);
      mirroredCount = eligibleUids.length;
    } catch (rtdbErr) {
      console.error('Error mirroring notifications to RTDB:', rtdbErr);
    }
  }

  // 2. Partition FCM tokens by recipient locale, respecting Master Push & Category opt-outs.
  const tokenLocaleBuckets = {
    es: new Map(), // token -> Set<uid>
    en: new Map(),
  };
  let skippedOptOutCount = 0;

  for (const uid of eligibleUids) {
    const userSettings = settingsMap.get(uid) || {
      locale: 'es',
      pushEnabled: true,
      categories: {},
    };
    const isPushAllowed = userSettings.pushEnabled !== false;
    const isCategoryAllowed = userSettings.categories?.[category] !== false;

    if (!isPushAllowed || !isCategoryAllowed) {
      skippedOptOutCount += 1;
      continue;
    }

    const userData = userDocMap.get(uid);
    const tokens = Array.isArray(userData?.fcmTokens) ? userData.fcmTokens : [];
    const bucket = tokenLocaleBuckets[userSettings.locale === 'en' ? 'en' : 'es'];

    for (const rawToken of tokens) {
      if (typeof rawToken !== 'string') continue;
      const token = rawToken.trim();
      if (!token) continue;
      if (!bucket.has(token)) {
        bucket.set(token, new Set());
      }
      bucket.get(token).add(uid);
    }
  }

  const messaging = typeof adminRef.messaging === 'function' ? adminRef.messaging() : null;
  if (!messaging || typeof messaging.sendEachForMulticast !== 'function') {
    return { sentCount: 0, mirroredCount, skippedOptOutCount };
  }

  let sentCount = 0;
  const staleTokensByUid = new Map();

  for (const locale of ['es', 'en']) {
    const tokenMap = tokenLocaleBuckets[locale];
    const allTokens = Array.from(tokenMap.keys());
    if (allTokens.length === 0) continue;

    const locTitle = locale === 'en' ? safeTitles.en : safeTitles.es;
    const locBody = locale === 'en' ? safeBodies.en : safeBodies.es;

    for (let i = 0; i < allTokens.length; i += MAX_MULTICAST_TOKENS) {
      const chunk = allTokens.slice(i, i + MAX_MULTICAST_TOKENS);
      const message = {
        notification: {
          title: locTitle,
          body: locBody,
        },
        data: {
          notificationId: safeKey,
          category,
          type: String(type || 'general').slice(0, 64),
          targetRoute: safeRoute,
          entityId: safeEntityId,
          title: locTitle,
          body: locBody,
        },
        android: {
          priority: 'high',
          notification: {
            channelId: category,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
        webpush: {
          notification: {
            icon: '/icons/Icon-192.png',
          },
          fcmOptions: {
            link: `/?notificationRoute=${encodeURIComponent(safeRoute)}`,
          },
        },
        tokens: chunk,
      };

      try {
        const resp = await messaging.sendEachForMulticast(message);
        sentCount += resp?.successCount || 0;
        const responses = Array.isArray(resp?.responses) ? resp.responses : [];
        responses.forEach((itemResp, idx) => {
          if (itemResp && !itemResp.success && STALE_TOKEN_ERROR_CODES.has(itemResp.error?.code)) {
            const badToken = chunk[idx];
            const owningUids = tokenMap.get(badToken);
            if (owningUids) {
              for (const uid of owningUids) {
                if (!staleTokensByUid.has(uid)) {
                  staleTokensByUid.set(uid, new Set());
                }
                staleTokensByUid.get(uid).add(badToken);
              }
            }
          }
        });
      } catch (sendErr) {
        console.error(`Error sending FCM multicast (${locale}):`, sendErr);
      }
    }
  }

  // 3. Remove dead/unregistered tokens from `users/{uid}.fcmTokens`.
  const ArrayRemove = adminRef.firestore?.FieldValue?.arrayRemove;
  if (db && typeof ArrayRemove === 'function' && staleTokensByUid.size > 0) {
    await Promise.all(
      Array.from(staleTokensByUid.entries()).map(async ([uid, badSet]) => {
        try {
          await db.collection('users').doc(uid).update({
            fcmTokens: ArrayRemove(...Array.from(badSet)),
          });
        } catch (cleanupErr) {
          console.error(`Failed cleaning stale tokens for user ${uid}:`, cleanupErr);
        }
      })
    );
  }

  return { sentCount, mirroredCount, skippedOptOutCount };
}

/**
 * Deletes `/notifications/{uid}` entries older than 30 days and enforces a hard cap of
 * the newest 100 entries per user to stay well within Firebase RTDB free-tier storage.
 */
async function pruneOldRtdbNotifications(dbRtdb, nowMillis = Date.now()) {
  if (!dbRtdb) return 0;
  const cutoffMillis = nowMillis - NOTIFICATION_RETENTION_MS;
  let prunedCount = 0;

  try {
    const rootSnap = await dbRtdb.ref('notifications').get();
    if (!rootSnap || !rootSnap.exists()) return 0;

    const allUsers = rootSnap.val() || {};
    const updates = {};

    for (const [uid, userNotifs] of Object.entries(allUsers)) {
      if (!userNotifs || typeof userNotifs !== 'object') continue;
      const entries = Object.entries(userNotifs)
        .map(([notifId, item]) => ({
          notifId,
          createdAt: typeof item?.createdAt === 'number' ? item.createdAt : 0,
        }))
        .sort((a, b) => a.createdAt - b.createdAt);

      const excessCount = Math.max(0, entries.length - MAX_NOTIFICATIONS_PER_USER);
      entries.forEach((entry, index) => {
        if (entry.createdAt < cutoffMillis || index < excessCount) {
          updates[`notifications/${uid}/${entry.notifId}`] = null;
          prunedCount += 1;
        }
      });
    }

    if (prunedCount > 0) {
      await dbRtdb.ref().update(updates);
    }
  } catch (err) {
    console.error('Error pruning old RTDB notifications:', err);
  }

  return prunedCount;
}

/**
 * Removes RTDB notifications and preferences for a deleted account.
 */
async function cleanupUserRtdbNotificationData(dbRtdb, uid) {
  if (!dbRtdb || !uid) return;
  try {
    await dbRtdb.ref().update({
      [`notifications/${uid}`]: null,
      [`user_notification_settings/${uid}`]: null,
    });
  } catch (err) {
    console.error(`Error cleaning RTDB notification data for deleted user ${uid}:`, err);
  }
}

module.exports = {
  NOTIFICATION_CATEGORIES,
  VALID_NOTIFICATION_CATEGORIES,
  ALLOWED_TARGET_ROUTES,
  NOTIFICATION_RETENTION_DAYS,
  NOTIFICATION_RETENTION_MS,
  MAX_NOTIFICATIONS_PER_USER,
  MAX_MULTICAST_TOKENS,
  STALE_TOKEN_ERROR_CODES,
  truncateText,
  sanitizeRtdbKey,
  sanitizeTargetRoute,
  sanitizeMetadata,
  buildLocalizedText,
  buildPaymentReviewNotification,
  buildBookingReviewNotification,
  buildOwnershipClaimReviewNotification,
  buildSanctionNotification,
  buildTransparencyNotification,
  buildQrAccessNotification,
  buildRoommateNotification,
  buildAnnouncementNotification,
  buildAdminReviewRequestNotification,
  extractAddressId,
  resolveAddressPrimaryResidentUid,
  resolveEligibleUidsByRoles,
  normalizeVisibility,
  resolveEffectiveDocVisibility,
  getSafeRtdb,
  resolveRecipientSettingsMap,
  dispatchNotification,
  pruneOldRtdbNotifications,
  cleanupUserRtdbNotificationData,
};
