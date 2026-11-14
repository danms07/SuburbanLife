const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated, onDocumentWritten, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp, getApp, getApps, cert, applicationDefault } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getMessaging } = require('firebase-admin/messaging');
const { getStorage } = require('firebase-admin/storage');
const { GoogleGenAI } = require('@google/genai');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
const path = require('path');

const admin = {
  initializeApp,
  app: getApp,
  get apps() {
    return getApps();
  },
  credential: {
    cert,
    applicationDefault,
  },
  firestore: Object.assign(() => getFirestore(), {
    FieldValue,
    Timestamp,
  }),
  auth: () => getAuth(),
  messaging: () => getMessaging(),
  storage: () => getStorage(),
};

admin.initializeApp();

// Determine if functions are running inside the Firebase Emulator
const isEmulator = process.env.FUNCTIONS_EMULATOR === 'true' ||
  Boolean(process.env.FIREBASE_EMULATOR_HUB) ||
  Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST) ||
  Boolean(process.env.FIRESTORE_EMULATOR_HOST);

// Callable options: disable App Check enforcement in emulator mode for local testing
const callableOptions = isEmulator
  ? { enforceAppCheck: false }
  : { enforceAppCheck: true, consumeAppCheckToken: true };

/**
 * Generates a cryptographically secure random password meeting complexity requirements:
 * - At least 1 uppercase letter (A-Z)
 * - At least 1 lowercase letter (a-z)
 * - At least 1 digit (0-9)
 * - At least 1 special character (!@#$%&*+)
 * - Minimum length: 8 (defaults to 12 chars)
 */
function generateSecurePassword(length = 12) {
  const actualLength = Math.max(8, length);
  const uppers = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const lowers = 'abcdefghijkmnpqrstuvwxyz';
  const digits = '23456789';
  const symbols = '!@#$%&*+';
  const allChars = uppers + lowers + digits + symbols;

  // Guarantee at least 1 character from each required class
  const requiredChars = [
    uppers[crypto.randomInt(0, uppers.length)],
    lowers[crypto.randomInt(0, lowers.length)],
    digits[crypto.randomInt(0, digits.length)],
    symbols[crypto.randomInt(0, symbols.length)],
  ];

  // Fill remaining length from combined character pool
  const remaining = [];
  const randomBytes = crypto.randomBytes(actualLength - requiredChars.length);
  for (let i = 0; i < randomBytes.length; i++) {
    remaining.push(allChars[randomBytes[i] % allChars.length]);
  }

  // Shuffle the combined array using Fisher-Yates
  const combined = requiredChars.concat(remaining);
  for (let i = combined.length - 1; i > 0; i--) {
    const j = crypto.randomInt(0, i + 1);
    const temp = combined[i];
    combined[i] = combined[j];
    combined[j] = temp;
  }

  return combined.join('');
}

/**
 * Validates whether a password satisfies the Firebase Auth password policy:
 * - Length between 8 and 4096 characters
 * - At least 1 uppercase letter (A-Z)
 * - At least 1 lowercase letter (a-z)
 * - At least 1 numeric digit (0-9)
 * - At least 1 special character (non-alphanumeric symbol)
 */
function isPasswordCompliant(password) {
  if (!password || typeof password !== 'string') return false;
  const trimmed = password.trim();
  if (trimmed.length < 8 || trimmed.length > 4096) return false;
  if (!/[A-Z]/.test(trimmed)) return false;
  if (!/[a-z]/.test(trimmed)) return false;
  if (!/[0-9]/.test(trimmed)) return false;
  if (!/[^A-Za-z0-9]/.test(trimmed)) return false;
  return true;
}

const { DEFAULT_APP_NAME, DEFAULT_PROJECT_ID, BRAND_COLORS } = require('./brand_config');
const projectId = process.env.GCLOUD_PROJECT || DEFAULT_PROJECT_ID;
const GEMINI_MODEL = 'gemini-3.8-flash';
const GEMINI_LOCATION = 'global';
const ai = new GoogleGenAI({
  vertexai: true,
  project: projectId,
  location: GEMINI_LOCATION,
});

// Helper: Retrieve SMTP settings from Firestore
async function getSmtpConfig() {
  try {
    const db = admin.firestore();
    const snap = await db.collection('config').doc('smtp_settings').get();
    if (!snap.exists) return null;
    const data = snap.data();
    if (!data || data.enabled !== true || !data.host || !data.user || !data.pass) {
      return null;
    }
    return data;
  } catch (err) {
    console.error('Error fetching SMTP config:', err);
    return null;
  }
}

// Helper: Build a Nodemailer transporter instance
function createSmtpTransporter(config) {
  const port = parseInt(config.port, 10) || (config.secure ? 465 : 587);
  return nodemailer.createTransport({
    host: config.host.toString().trim(),
    port: port,
    secure: config.secure === true || port === 465,
    auth: {
      user: config.user.toString().trim(),
      pass: config.pass.toString().trim(),
    },
    tls: {
      rejectUnauthorized: config.rejectUnauthorized !== false,
    },
  });
}

// Helper: Replace %placeholder% tags in strings
function replacePlaceholders(template, data) {
  if (!template) return '';
  return template
    .replace(/%name%/gi, data.name || '')
    .replace(/%email%/gi, data.email || '')
    .replace(/%password%/gi, data.password || '')
    .replace(/%address%/gi, data.address || 'N/A')
    .replace(/%role%/gi, data.role || 'Residente')
    .replace(/%appName%/gi, data.appName || DEFAULT_APP_NAME);
}

// Helper: Build branded HTML welcome email matching AppConfig
function buildWelcomeEmailHtml({ branding, name, userRole, email, password, addressLinked, customBody }) {
  if (customBody && customBody.toString().trim().length > 0) {
    const escapedBody = customBody
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\n/g, '<br/>');

    return `
        <div style="font-family: ${BRAND_COLORS.fontFamily}; max-width: 600px; margin: 0 auto; padding: 24px; background-color: ${BRAND_COLORS.background}; border-radius: 12px;">
          <div style="background-color: ${BRAND_COLORS.primary}; background: linear-gradient(135deg, ${BRAND_COLORS.primary} 0%, ${BRAND_COLORS.gradientEnd} 100%); padding: 24px; border-radius: 8px 8px 0 0; text-align: center;">
            <h1 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: bold;">${branding}</h1>
          </div>
          <div style="background-color: #ffffff; padding: 28px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.05); color: ${BRAND_COLORS.textColor}; line-height: 1.6; font-size: 14px;">
            ${escapedBody}
            <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 24px 0;" />
            <p style="font-size: 12px; color: #9ca3af; text-align: center; margin: 0;">
              Este es un correo automático generado por la administración de ${branding}. Por favor no respondas directamente a este mensaje.
            </p>
          </div>
        </div>
      `;
  }

  const addressText = addressLinked ? `<li><strong>Dirección asignada:</strong> ${addressLinked}</li>` : '';

  return `
        <div style="font-family: ${BRAND_COLORS.fontFamily}; max-width: 600px; margin: 0 auto; padding: 24px; background-color: ${BRAND_COLORS.background}; border-radius: 12px;">
          <div style="background-color: ${BRAND_COLORS.primary}; background: linear-gradient(135deg, ${BRAND_COLORS.primary} 0%, ${BRAND_COLORS.gradientEnd} 100%); padding: 24px; border-radius: 8px 8px 0 0; text-align: center;">
            <h1 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: bold;">¡Bienvenido(a) a ${branding}!</h1>
          </div>
          <div style="background-color: #ffffff; padding: 28px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.05);">
            <p style="font-size: 16px; color: ${BRAND_COLORS.textColor}; margin-top: 0;">Hola <strong>${name}</strong>,</p>
            <p style="font-size: 14px; color: #4b5563; line-height: 1.6;">
              Tu cuenta de <strong>${userRole}</strong> ha sido creada exitosamente. A continuación encontrarás tus credenciales de acceso para ingresar a la aplicación:
            </p>
            <div style="background-color: ${BRAND_COLORS.cardBackground}; border-left: 4px solid ${BRAND_COLORS.primary}; padding: 16px 20px; margin: 20px 0; border-radius: 6px;">
              <ul style="margin: 0; padding-left: 20px; color: ${BRAND_COLORS.textColor}; font-size: 14px; line-height: 1.8;">
                <li><strong>Correo electrónico:</strong> ${email}</li>
                <li><strong>Contraseña inicial:</strong> <code style="background-color: #ede8f5; padding: 2px 6px; border-radius: 4px; font-weight: bold; color: ${BRAND_COLORS.primary};">${password}</code></li>
                ${addressText}
              </ul>
            </div>
            <p style="font-size: 13px; color: #6b7280; line-height: 1.5;">
              Te recomendamos iniciar sesión y cambiar tu contraseña por una personalizada en la sección de tu perfil.
            </p>
            <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 24px 0;" />
            <p style="font-size: 12px; color: #9ca3af; text-align: center; margin: 0;">
              Este es un correo automático generado por la administración de ${branding}. Por favor no respondas directamente a este mensaje.
            </p>
          </div>
        </div>
      `;
}

// Helper: Send branded HTML and Plain Text welcome email
async function sendWelcomeEmail(smtpConfig, { email, name, password, addressLinked, appName, role }) {
  if (!smtpConfig) return { sent: false, reason: 'SMTP not configured or disabled' };

  try {
    const transporter = createSmtpTransporter(smtpConfig);
    const branding = appName || smtpConfig.senderName || DEFAULT_APP_NAME;
    const fromAddress = smtpConfig.senderEmail && smtpConfig.senderEmail.toString().trim().length > 0
      ? `"${smtpConfig.senderName || branding}" <${smtpConfig.senderEmail.toString().trim()}>`
      : `"${smtpConfig.senderName || branding}" <${smtpConfig.user.toString().trim()}>`;

    const userRole = role || 'residente';
    const placeholderData = {
      name: name || '',
      email: email || '',
      password: password || '',
      address: addressLinked || 'N/A',
      role: userRole,
      appName: branding,
    };

    let subject = `¡Bienvenido(a) a ${branding}! Credenciales de Acceso`;
    if (smtpConfig.customSubject && smtpConfig.customSubject.toString().trim().length > 0) {
      subject = replacePlaceholders(smtpConfig.customSubject.toString().trim(), placeholderData);
    }

    let htmlContent;
    let textContent;

    if (smtpConfig.customBody && smtpConfig.customBody.toString().trim().length > 0) {
      const rawCustomBody = replacePlaceholders(smtpConfig.customBody.toString().trim(), placeholderData);
      textContent = rawCustomBody;
      htmlContent = buildWelcomeEmailHtml({
        branding,
        name,
        userRole,
        email,
        password,
        addressLinked,
        customBody: rawCustomBody,
      });
    } else {
      const addressPlain = addressLinked ? `\nDirección asignada: ${addressLinked}` : '';

      htmlContent = buildWelcomeEmailHtml({
        branding,
        name,
        userRole,
        email,
        password,
        addressLinked,
      });

      textContent = `¡Bienvenido(a) a ${branding}!\n\n` +
        `Hola ${name},\n\n` +
        `Tu cuenta de ${userRole} ha sido creada exitosamente con las siguientes credenciales:\n\n` +
        `- Correo electrónico: ${email}\n` +
        `- Contraseña inicial: ${password}` +
        addressPlain +
        `\n\nTe recomendamos iniciar sesión y actualizar tu contraseña.\n\n` +
        `Administración de ${branding}`;
    }

    await transporter.sendMail({
      from: fromAddress,
      to: email,
      subject: subject,
      text: textContent,
      html: htmlContent,
    });

    return { sent: true };
  } catch (err) {
    console.error(`Failed to send welcome email to ${email}:`, err);
    return { sent: false, error: err.message || 'Failed to send email' };
  }
}

// Callable function to set user roles
exports.setRole = onCall(callableOptions, async (request) => {
  // Check if the caller is an admin
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError(
      'failed-precondition',
      'The function must be called by an authenticated admin.'
    );
  }

  const uid = request.data.uid;
  const role = request.data.role; // 'admin', 'resident', 'guard', 'roommate'

  if (!uid || !role) {
    throw new HttpsError(
      'invalid-argument',
      'The function must be called with uid and role.'
    );
  }

  const validRoles = ['admin', 'resident', 'guard', 'roommate'];
  if (!validRoles.includes(role)) {
    throw new HttpsError(
      'invalid-argument',
      'Invalid role specified.'
    );
  }

  try {
    const claims = {};
    claims[role] = true;
    await admin.auth().setCustomUserClaims(uid, claims);
    
    return { success: true, message: `Role ${role} set for user ${uid}` };
  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

exports.setCustomUserClaims = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError(
      'failed-precondition',
      'The function must be called by an authenticated admin.'
    );
  }

  const { uid, claims } = request.data || {};
  if (!uid || typeof uid !== 'string' || !claims || typeof claims !== 'object' || Array.isArray(claims)) {
    throw new HttpsError(
      'invalid-argument',
      'The function must be called with a valid uid and claims object.'
    );
  }

  const allowedKeys = ['admin', 'resident', 'guard', 'roommate'];
  const sanitizedClaims = {};
  for (const key of allowedKeys) {
    if (Object.prototype.hasOwnProperty.call(claims, key) && typeof claims[key] === 'boolean') {
      sanitizedClaims[key] = claims[key];
    }
  }

  if (uid === request.auth.uid && sanitizedClaims.admin === false) {
    throw new HttpsError(
      'permission-denied',
      'You cannot revoke your own admin role from User Management.'
    );
  }

  try {
    await admin.auth().setCustomUserClaims(uid, sanitizedClaims);
    return { success: true, claims: sanitizedClaims };
  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

// Trigger on new announcement creation
exports.translateAnnouncement = onDocumentCreated('announcements/{announcementId}', async (event) => {
    const snapshot = event.data;
    if (!snapshot) return null;

    const data = snapshot.data();
    const title = data.title;
    const content = data.content;

    if (!title || !content) return null;

    try {
      const prompt = `Translate the following announcement title and content from Spanish to English. 
      Return the result strictly as a JSON object with keys "title" and "content".
      
      Title: ${title}
      Content: ${content}`;

      const result = await ai.models.generateContent({
        model: GEMINI_MODEL,
        contents: prompt,
      });

      const text = result.text;
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        throw new Error('Failed to parse JSON from Gemini response');
      }

      const translated = JSON.parse(jsonMatch[0]);

      return snapshot.ref.update({
        'translatedTitles.en': translated.title,
        'translatedContents.en': translated.content,
      });
    } catch (error) {
      console.error('Translation error:', error);
      return null;
    }
});

exports.createBooking = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in.');
  }

  const rawData = request.data || {};
  const facilityId = typeof rawData.facilityId === 'string' ? rawData.facilityId.trim() : '';
  const startTime = typeof rawData.startTime === 'number' ? rawData.startTime : Number(rawData.startTime);
  const endTime = typeof rawData.endTime === 'number' ? rawData.endTime : Number(rawData.endTime);
  const resubmitBookingId =
    typeof rawData.resubmitBookingId === 'string' && rawData.resubmitBookingId.trim().length > 0
      ? rawData.resubmitBookingId.trim()
      : null;

  if (
    !facilityId ||
    facilityId.length > 128 ||
    facilityId.includes('/') ||
    !Number.isFinite(startTime) ||
    !Number.isFinite(endTime) ||
    startTime <= 0 ||
    endTime <= startTime ||
    (resubmitBookingId && (resubmitBookingId.length > 128 || resubmitBookingId.includes('/')))
  ) {
    throw new HttpsError('invalid-argument', 'Invalid or missing facilityId, startTime, or endTime.');
  }

  const uid = request.auth.uid;

  try {
    // 0. Check payment & sanction standing and resolve household address
    let callerAddressRef = null;
    let callerAddressId = null;
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    if (userDoc.exists) {
      const addressRef = userDoc.data().addressRef;
      if (addressRef) {
        callerAddressRef = addressRef;
        callerAddressId = addressRef.id || String(addressRef.path || '').split('/').pop() || null;
        const addressDoc = typeof addressRef.get === 'function'
          ? await addressRef.get()
          : await admin.firestore().doc(addressRef.path || `addresses/${callerAddressId}`).get();
        const addrData = addressDoc.exists ? addressDoc.data() : null;
        const status = addrData ? addrData.paymentStatus : null;
        const hasActiveSanctions = addrData ? addrData.hasActiveSanctions === true : false;
        const isWithinGrace = addrData ? addrData.isWithinGracePeriod === true : false;
        const isConsideredPaid =
          !hasActiveSanctions &&
          (status === 'paid' || ((status === 'pending' || status === 'reviewing') && isWithinGrace));
        if (!isConsideredPaid) {
          throw new HttpsError(
            'permission-denied',
            'Your account is restricted due to missing payment or active sanctions.'
          );
        }
      }
    }

    // 0b. If resubmitting a rejected booking, verify ownership and status
    let existingBookingRef = null;
    let existingAttachments = [];
    if (resubmitBookingId) {
      existingBookingRef = admin.firestore().collection('bookings').doc(resubmitBookingId);
      const existingSnap = await existingBookingRef.get();
      if (!existingSnap.exists) {
        throw new HttpsError('not-found', 'Booking to resubmit was not found.');
      }
      const existingData = existingSnap.data() || {};
      const sameOwner = existingData.userUid === uid;
      const sameHousehold = Boolean(callerAddressId && existingData.addressId === callerAddressId);
      if (!sameOwner && !sameHousehold) {
        throw new HttpsError('permission-denied', 'You do not have permission to resubmit this booking.');
      }
      if (existingData.status !== 'rejected') {
        throw new HttpsError('failed-precondition', 'Only rejected bookings can be resubmitted.');
      }
      if (existingData.facilityId && existingData.facilityId !== facilityId) {
        throw new HttpsError('invalid-argument', 'Cannot change facility when resubmitting a booking.');
      }
      const existingAttSnap = await admin
        .firestore()
        .collection('booking_attachments')
        .doc(resubmitBookingId)
        .get();
      if (existingAttSnap.exists && Array.isArray(existingAttSnap.data()?.attachments)) {
        existingAttachments = existingAttSnap.data().attachments;
      }
    }

    // 1. Load facility configuration & community timezone
    const facilityDoc = await admin.firestore().collection('facilities').doc(facilityId).get();
    if (!facilityDoc.exists) {
      throw new HttpsError('not-found', 'Facility not found.');
    }

    const facData = facilityDoc.data();
    let timeZone = 'America/Mexico_City';
    try {
      const configDoc = await admin.firestore().collection('config').doc('app_settings').get();
      if (configDoc.exists && configDoc.data().timeZone) {
        timeZone = configDoc.data().timeZone;
      }
    } catch (e) {}

    validateFacilityBooking({ facData, startTime, endTime, timeZone, now: Date.now() });

    // 1b. Validate mandatory & optional amenity document attachments
    const bucket = admin.storage().bucket();
    const effectiveRawAttachments =
      rawData.attachments !== undefined ? rawData.attachments : existingAttachments;
    const normalizedAttachments = await validateAndNormalizeBookingAttachments({
      rawAttachments: effectiveRawAttachments,
      facilityDocuments: facData.facilityDocuments,
      callerUid: uid,
      existingAttachments,
      bucket,
      nowMillis: Date.now(),
    });

    // 2. Household Cooldown / Quota validation
    const restriction = resolveFacilityRestriction(facData);
    if (restriction.restrictionType !== 'unrestricted') {
      const householdBookingsMap = new Map();

      if (callerAddressId) {
        // Direct household bookings attributed with addressId
        const byAddressSnap = await admin
          .firestore()
          .collection('bookings')
          .where('facilityId', '==', facilityId)
          .where('addressId', '==', callerAddressId)
          .get();
        for (const doc of byAddressSnap.docs) {
          if (doc.id !== resubmitBookingId) {
            householdBookingsMap.set(doc.id, doc.data());
          }
        }

        // Legacy fallback: include bookings without addressId created by any user currently linked to callerAddressRef
        const memberUids = new Set([uid]);
        if (callerAddressRef) {
          const linkedUsersSnap = await admin
            .firestore()
            .collection('users')
            .where('addressRef', '==', callerAddressRef)
            .get();
          for (const uDoc of linkedUsersSnap.docs) {
            memberUids.add(uDoc.id);
          }
        }

        for (const memberUid of memberUids) {
          const byMemberSnap = await admin
            .firestore()
            .collection('bookings')
            .where('userUid', '==', memberUid)
            .where('facilityId', '==', facilityId)
            .get();
          for (const doc of byMemberSnap.docs) {
            if (doc.id === resubmitBookingId || householdBookingsMap.has(doc.id)) continue;
            const bData = doc.data() || {};
            if (!bData.addressId || bData.addressId === callerAddressId) {
              householdBookingsMap.set(doc.id, bData);
            }
          }
        }
      } else {
        const byUserSnap = await admin
          .firestore()
          .collection('bookings')
          .where('userUid', '==', uid)
          .where('facilityId', '==', facilityId)
          .get();
        for (const doc of byUserSnap.docs) {
          if (doc.id !== resubmitBookingId) {
            householdBookingsMap.set(doc.id, doc.data());
          }
        }
      }

      validateHouseholdBookingRestriction({
        facData,
        startTime,
        endTime,
        householdBookings: Array.from(householdBookingsMap.values()),
        timeZone,
      });
    }

    // 3. Clashes validation (Capacity & Quantity check): bounded time range
    const quantity = facData.quantity || 1;
    const clashes = await admin
      .firestore()
      .collection('bookings')
      .where('facilityId', '==', facilityId)
      .where('startTime', '<=', endTime)
      .where('startTime', '>=', startTime - 7 * 24 * 60 * 60 * 1000)
      .get();

    const events = [];
    for (const doc of clashes.docs) {
      if (doc.id === resubmitBookingId) continue;
      const b = doc.data();
      // Ignore cancelled or rejected bookings
      if (b.status === 'cancelled' || b.status === 'rejected') {
        continue;
      }
      const bStart = extractTimestampMillis(b.startTime);
      const bEnd = extractTimestampMillis(b.endTime);
      const overlapStart = Math.max(startTime, bStart);
      const overlapEnd = Math.min(endTime, bEnd);
      if (overlapStart < overlapEnd) {
        events.push({ time: overlapStart, type: 1 });
        events.push({ time: overlapEnd, type: -1 });
      }
    }

    // Sort events: time ascending, then end events (-1) before start events (1)
    events.sort((a, b) => {
      if (a.time !== b.time) {
        return a.time - b.time;
      }
      return a.type - b.type;
    });

    let activeCount = 0;
    let peakCount = 0;
    for (const ev of events) {
      activeCount += ev.type;
      if (activeCount > peakCount) {
        peakCount = activeCount;
      }
    }

    if (peakCount + 1 > quantity) {
      throw new HttpsError(
        'failed-precondition',
        'This facility has reached its maximum booking capacity for the requested time slot.'
      );
    }

    const nowMillis = Date.now();
    const expireAtTimestamp = admin.firestore.Timestamp.fromMillis(
      computeBookingAttachmentExpireAtMillis(endTime)
    );

    // 4. Persist booking (update rejected booking or create new booking)
    if (existingBookingRef) {
      const updatedPatch = {
        startTime,
        endTime,
        addressId: callerAddressId || null,
        addressRef: callerAddressRef || null,
        status: 'pending review',
        isConfirmed: false,
        rejectionReason: '',
        notes: '',
        hasAttachments: normalizedAttachments.length > 0,
        attachmentCount: normalizedAttachments.length,
        attachmentsPurgedAt: null,
        updatedAt: nowMillis,
      };
      await existingBookingRef.update(updatedPatch);

      const attRef = admin.firestore().collection('booking_attachments').doc(resubmitBookingId);
      if (normalizedAttachments.length > 0) {
        await attRef.set({
          bookingId: resubmitBookingId,
          facilityId,
          userUid: uid,
          addressId: callerAddressId || null,
          bookingEndTime: endTime,
          attachments: normalizedAttachments,
          updatedAt: nowMillis,
          expireAt: expireAtTimestamp,
        }, { merge: true });
      } else if (existingAttachments.length > 0) {
        await attRef.delete();
      }

      // Delete any superseded Cloud Storage attachments replaced during resubmission
      const retainedPaths = new Set(normalizedAttachments.map((a) => a.storagePath));
      for (const oldAtt of existingAttachments) {
        const oldPath = extractBookingAttachmentStoragePath(oldAtt?.storagePath || oldAtt?.url);
        if (oldPath && !retainedPaths.has(oldPath) && bucket && typeof bucket.file === 'function') {
          try {
            await bucket.file(oldPath).delete({ ignoreNotFound: true });
          } catch (delErr) {
            const code = delErr && (delErr.code || delErr.status);
            if (code !== 404 && code !== 'storage/object-not-found') {
              console.error(`Error deleting superseded booking attachment for ${resubmitBookingId}:`, code || 'unknown');
            }
          }
        }
      }

      return {
        success: true,
        bookingId: resubmitBookingId,
        booking: {
          id: resubmitBookingId,
          bookingId: resubmitBookingId,
          facilityId,
          userUid: uid,
          ...updatedPatch,
        },
      };
    }

    const bookingRef = admin.firestore().collection('bookings').doc();
    const bookingData = {
      id: bookingRef.id,
      bookingId: bookingRef.id,
      facilityId,
      userUid: uid,
      addressId: callerAddressId || null,
      addressRef: callerAddressRef || null,
      startTime,
      endTime,
      status: 'pending review',
      isConfirmed: false,
      approvalMessage: '',
      rejectionReason: '',
      hasAttachments: normalizedAttachments.length > 0,
      attachmentCount: normalizedAttachments.length,
      attachmentsPurgedAt: null,
      timestamp: nowMillis,
    };

    await bookingRef.set(bookingData);

    if (normalizedAttachments.length > 0) {
      await admin.firestore().collection('booking_attachments').doc(bookingRef.id).set({
        bookingId: bookingRef.id,
        facilityId,
        userUid: uid,
        addressId: callerAddressId || null,
        bookingEndTime: endTime,
        attachments: normalizedAttachments,
        createdAt: nowMillis,
        updatedAt: nowMillis,
        expireAt: expireAtTimestamp,
      });
    }

    return { success: true, bookingId: bookingRef.id, booking: bookingData };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', error.message);
  }
});

exports.cancelBooking = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in.');
  }

  const { bookingId } = request.data;
  if (!bookingId) {
    throw new HttpsError('invalid-argument', 'Missing bookingId.');
  }

  try {
    const db = admin.firestore();
    const bookingRef = db.collection('bookings').doc(bookingId);
    const bookingDoc = await bookingRef.get();

    if (!bookingDoc.exists) {
      throw new HttpsError('not-found', 'Booking not found.');
    }

    const b = bookingDoc.data();
    let sameHousehold = false;
    if (b.addressId && request.auth.uid !== b.userUid && request.auth.token.admin !== true) {
      const callerSnap = await db.collection('users').doc(request.auth.uid).get();
      const callerAddrRef = callerSnap.exists ? callerSnap.data()?.addressRef : null;
      const callerAddrId = callerAddrRef
        ? (callerAddrRef.id || String(callerAddrRef.path || '').split('/').pop() || null)
        : null;
      sameHousehold = Boolean(callerAddrId && callerAddrId === b.addressId);
    }

    if (b.userUid !== request.auth.uid && !sameHousehold && request.auth.token.admin !== true) {
      throw new HttpsError('permission-denied', 'You do not have permission to cancel this booking.');
    }

    const nowMillis = Date.now();
    await bookingRef.update({ status: 'cancelled' });

    // Immediately purge any resident booking attachments from Cloud Storage and booking_attachments
    const attRef = db.collection('booking_attachments').doc(bookingId);
    const attSnap = await attRef.get();
    if (attSnap.exists) {
      await cleanupDeletedBookingAttachmentResources({
        db,
        bucket: admin.storage().bucket(),
        bookingId,
        attachmentDocData: attSnap.data() || {},
        nowMillis,
      });
      await attRef.delete();
    }

    // Notify admins via an announcement or notification log
    await db.collection('announcements').add({
      title: 'Booking Cancelled',
      content: `Booking ${bookingId} has been cancelled by user ${request.auth.uid}.`,
      creatorUid: 'system',
      timestamp: nowMillis,
      targetAudience: 'admin',
      readBy: []
    });

    return { success: true };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', error.message);
  }
});

/**
 * Helper: Formats a Date object or timestamp into integer components according to the given IANA timezone.
 */
function getDateInTimezone(date = new Date(), timeZone = 'America/Mexico_City') {
  try {
    const d = date instanceof Date ? date : new Date(date);
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timeZone || 'America/Mexico_City',
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric',
      hour12: false,
    });
    const parts = formatter.formatToParts(d);
    const map = {};
    for (const p of parts) {
      map[p.type] = p.value;
    }
    let hour = parseInt(map.hour, 10);
    if (hour === 24) hour = 0;
    return {
      year: parseInt(map.year, 10),
      month: parseInt(map.month, 10),
      day: parseInt(map.day, 10),
      hour: hour,
      minute: parseInt(map.minute, 10),
      second: parseInt(map.second, 10),
    };
  } catch (err) {
    const d = date instanceof Date ? date : new Date(date);
    return {
      year: d.getFullYear(),
      month: d.getMonth() + 1,
      day: d.getDate(),
      hour: d.getHours(),
      minute: d.getMinutes(),
      second: d.getSeconds(),
    };
  }
}

/**
 * Helper: Formats the current date and time into integer components according to the given IANA timezone.
 */
function getNowInTimezone(timeZone = 'America/Mexico_City') {
  return getDateInTimezone(new Date(), timeZone);
}

/**
 * Helper: Validates facility booking anticipation and daily operating hours windows.
 */
function validateFacilityBooking({ facData, startTime, endTime, timeZone = 'America/Mexico_City', now = Date.now() }) {
  if (
    typeof startTime !== 'number' ||
    typeof endTime !== 'number' ||
    !Number.isFinite(startTime) ||
    !Number.isFinite(endTime) ||
    endTime <= startTime
  ) {
    throw new HttpsError('invalid-argument', 'End time must be after start time.');
  }
  if (!facData) return;

  // 1. Anticipation window
  const anticipationUnit = facData.anticipationUnit || 'unrestricted';
  const anticipationValue = typeof facData.anticipationValue === 'number' ? facData.anticipationValue : 0;
  if (anticipationUnit !== 'unrestricted' && anticipationValue > 0) {
    let anticipationMs = 0;
    if (anticipationUnit === 'hours') {
      anticipationMs = anticipationValue * 60 * 60 * 1000;
    } else if (anticipationUnit === 'days') {
      anticipationMs = anticipationValue * 24 * 60 * 60 * 1000;
    } else if (anticipationUnit === 'weeks') {
      anticipationMs = anticipationValue * 7 * 24 * 60 * 60 * 1000;
    }
    if (startTime < now + anticipationMs) {
      throw new HttpsError(
        'failed-precondition',
        `This facility requires advance notice of at least ${anticipationValue} ${anticipationUnit}.`
      );
    }
  }

  // 2. Daily operating hours window
  const openingTime = facData.openingTime || '00:00';
  const closingTime = facData.closingTime || '23:59';
  if (openingTime !== '00:00' || closingTime !== '23:59') {
    const [openH, openM] = openingTime.split(':').map(Number);
    const [closeH, closeM] = closingTime.split(':').map(Number);
    const openingMinutes = openH * 60 + openM;
    const closingMinutes = closeH * 60 + closeM;

    const startTz = getDateInTimezone(startTime, timeZone);
    const endTz = getDateInTimezone(endTime, timeZone);

    const startMinutes = startTz.hour * 60 + startTz.minute;
    const endMinutes = endTz.hour * 60 + endTz.minute;

    if (
      startMinutes < openingMinutes ||
      endMinutes > closingMinutes ||
      endMinutes <= startMinutes ||
      startTz.day !== endTz.day ||
      startTz.month !== endTz.month ||
      startTz.year !== endTz.year
    ) {
      throw new HttpsError(
        'invalid-argument',
        `Reservation must be within operating hours (${openingTime} - ${closingTime}).`
      );
    }
  }
}

/**
 * Normalizes a facility document's booking restriction configuration, preserving
 * backward compatibility with legacy documents that only specify cooldownUnit/cooldownValue.
 */
function resolveFacilityRestriction(facData) {
  const unrestricted = {
    restrictionType: 'unrestricted',
    cooldownUnit: 'unrestricted',
    cooldownValue: 0,
    quotaPeriod: 'unrestricted',
    quotaLimit: 0,
  };
  if (!facData) return unrestricted;

  const explicitType = String(facData.restrictionType || '').trim().toLowerCase();
  const cooldownUnit = String(facData.cooldownUnit || 'unrestricted').trim().toLowerCase();
  const cooldownValue =
    typeof facData.cooldownValue === 'number'
      ? Math.floor(facData.cooldownValue)
      : parseInt(String(facData.cooldownValue || '0'), 10) || 0;
  const quotaPeriod = String(facData.quotaPeriod || 'unrestricted').trim().toLowerCase();
  const quotaLimit =
    typeof facData.quotaLimit === 'number'
      ? Math.floor(facData.quotaLimit)
      : parseInt(String(facData.quotaLimit || '0'), 10) || 0;

  if (explicitType === 'quota') {
    if (['daily', 'monthly', 'yearly'].includes(quotaPeriod) && quotaLimit > 0) {
      return {
        restrictionType: 'quota',
        cooldownUnit: 'unrestricted',
        cooldownValue: 0,
        quotaPeriod,
        quotaLimit,
      };
    }
    return unrestricted;
  }

  if (explicitType === 'cooldown' || (!explicitType && cooldownUnit !== 'unrestricted' && cooldownValue > 0)) {
    if (['hours', 'days', 'months', 'years'].includes(cooldownUnit) && cooldownValue > 0) {
      return {
        restrictionType: 'cooldown',
        cooldownUnit,
        cooldownValue,
        quotaPeriod: 'unrestricted',
        quotaLimit: 0,
      };
    }
  }

  return unrestricted;
}

/**
 * Returns true if a booking record counts toward household cooldown or quota limits.
 * Both pending review and approved/confirmed/closed bookings count; rejected and cancelled do not.
 */
function isCountedBookingForRestriction(booking) {
  if (!booking) return false;
  const status = String(booking.status || '').trim().toLowerCase();
  if (!status || status === 'rejected' || status === 'cancelled') return false;
  return (
    status === 'pending' ||
    status === 'pending review' ||
    status.startsWith('approved') ||
    status === 'confirmed' ||
    status === 'closed'
  );
}

/**
 * Adds a cooldown duration (hours | days | months | years) to a millisecond epoch timestamp,
 * safely clamping calendar month-end rollovers for months and years.
 */
function addCooldownOffset(timestampMs, unit, value) {
  if (!value || value <= 0) return timestampMs;
  if (unit === 'hours') {
    return timestampMs + value * 60 * 60 * 1000;
  }
  if (unit === 'days') {
    return timestampMs + value * 24 * 60 * 60 * 1000;
  }
  const d = new Date(timestampMs);
  if (unit === 'months') {
    const targetMonthIndex = d.getUTCFullYear() * 12 + d.getUTCMonth() + value;
    const targetYear = Math.floor(targetMonthIndex / 12);
    const targetMonth = targetMonthIndex % 12;
    const maxDay = new Date(Date.UTC(targetYear, targetMonth + 1, 0)).getUTCDate();
    const clampedDay = Math.min(d.getUTCDate(), maxDay);
    return Date.UTC(
      targetYear,
      targetMonth,
      clampedDay,
      d.getUTCHours(),
      d.getUTCMinutes(),
      d.getUTCSeconds(),
      d.getUTCMilliseconds()
    );
  }
  if (unit === 'years') {
    const targetYear = d.getUTCFullYear() + value;
    const targetMonth = d.getUTCMonth();
    const maxDay = new Date(Date.UTC(targetYear, targetMonth + 1, 0)).getUTCDate();
    const clampedDay = Math.min(d.getUTCDate(), maxDay);
    return Date.UTC(
      targetYear,
      targetMonth,
      clampedDay,
      d.getUTCHours(),
      d.getUTCMinutes(),
      d.getUTCSeconds(),
      d.getUTCMilliseconds()
    );
  }
  return timestampMs;
}

/**
 * Validates that a requested booking [startTime, endTime] satisfies the facility's
 * household Cooldown (endTime -> startTime gap) or Calendar-Period Quota rule.
 */
function validateHouseholdBookingRestriction({
  facData,
  startTime,
  endTime,
  householdBookings = [],
  timeZone = 'America/Mexico_City',
}) {
  const restriction = resolveFacilityRestriction(facData);
  if (restriction.restrictionType === 'unrestricted') {
    return restriction;
  }

  const counted = householdBookings.filter(isCountedBookingForRestriction);

  if (restriction.restrictionType === 'cooldown') {
    const { cooldownUnit, cooldownValue } = restriction;
    for (const b of counted) {
      const bStart = extractTimestampMillis(b.startTime);
      if (!bStart) continue;
      const rawEnd = extractTimestampMillis(b.endTime);
      const bEnd = rawEnd > bStart ? rawEnd : bStart;

      const okAfterExisting = startTime >= addCooldownOffset(bEnd, cooldownUnit, cooldownValue);
      const okBeforeExisting = bStart >= addCooldownOffset(endTime, cooldownUnit, cooldownValue);

      if (!okAfterExisting && !okBeforeExisting) {
        throw new HttpsError(
          'failed-precondition',
          `After booking this facility, your household must wait ${cooldownValue} ${cooldownUnit} before booking again.`
        );
      }
    }
    return restriction;
  }

  if (restriction.restrictionType === 'quota') {
    const { quotaPeriod, quotaLimit } = restriction;
    const reqTz = getDateInTimezone(startTime, timeZone);
    let usedCount = 0;

    for (const b of counted) {
      const bStart = extractTimestampMillis(b.startTime);
      if (!bStart) continue;
      const bTz = getDateInTimezone(bStart, timeZone);

      const sameYear = bTz.year === reqTz.year;
      const sameMonth = sameYear && bTz.month === reqTz.month;
      const sameDay = sameMonth && bTz.day === reqTz.day;

      if (
        (quotaPeriod === 'daily' && sameDay) ||
        (quotaPeriod === 'monthly' && sameMonth) ||
        (quotaPeriod === 'yearly' && sameYear)
      ) {
        usedCount++;
      }
    }

    if (usedCount >= quotaLimit) {
      throw new HttpsError(
        'failed-precondition',
        `Your household has reached the ${quotaPeriod} booking quota (${quotaLimit}) for this facility.`
      );
    }
    return { ...restriction, usedCount };
  }

  return restriction;
}

/**
 * Helper: Validates that a delivery date is valid and not in the future.
 * Returns parsed Date object, or null if no deliveryDate was provided.
 */
function validateDeliveryDate(deliveryDate) {
  if (!deliveryDate) return null;
  const d = new Date(deliveryDate);
  if (isNaN(d.getTime())) {
    throw new HttpsError('invalid-argument', 'Invalid delivery date format.');
  }
  if (d.getTime() > Date.now()) {
    throw new HttpsError('invalid-argument', 'Delivery date cannot be in the future.');
  }
  return d;
}

/**
 * Helper: Recalculates payment status for an address based on deliveryDate and payments collection records,
 * incorporating configured cutoff day, grace period, and timezone.
 */
async function recalculateAddressPaymentStatus(addressRef, isApproval = false, preloadedSettings = null) {
  if (!addressRef) return;
  const db = admin.firestore();
  const addressDoc = typeof addressRef.get === 'function' ? await addressRef.get() : await db.doc(addressRef.path || addressRef).get();
  if (!addressDoc.exists) return;

  const addressData = addressDoc.data();
  const deliveryTimestamp = addressData ? addressData.deliveryDate : null;
  const targetRef = addressDoc.ref;

  let newStatus = 'paid';
  let isWithinGracePeriod = true;
  if (deliveryTimestamp) {
    const deliveryDate = deliveryTimestamp instanceof admin.firestore.Timestamp
      ? deliveryTimestamp.toDate()
      : (deliveryTimestamp.toDate ? deliveryTimestamp.toDate() : new Date(deliveryTimestamp));

    if (deliveryDate && !isNaN(deliveryDate.getTime())) {
      // Fetch or use preloaded app_settings (cutoff day, grace period, timezone)
      let appSettings = preloadedSettings;
      if (!appSettings) {
        try {
          const configDoc = await db.collection('config').doc('app_settings').get();
          appSettings = configDoc.exists ? configDoc.data() : {};
        } catch (e) {
          appSettings = {};
        }
      }

      const cutoffDay = (appSettings && typeof appSettings.paymentCutoffDay === 'number') ? appSettings.paymentCutoffDay : 1;
      const gracePeriodDays = (appSettings && typeof appSettings.gracePeriodDays === 'number') ? appSettings.gracePeriodDays : 10;
      const timeZone = (appSettings && appSettings.timeZone) ? appSettings.timeZone : 'America/Mexico_City';

      const nowTz = getNowInTimezone(timeZone);
      const currentPeriodStr = `${nowTz.year}-${String(nowTz.month).padStart(2, '0')}`;
      const graceThresholdDay = cutoffDay + gracePeriodDays;

      const requiredPeriods = [];
      let current = new Date(deliveryDate.getFullYear(), deliveryDate.getMonth(), 1);
      const target = new Date(nowTz.year, nowTz.month - 1, 1);

      while (current <= target) {
        const yyyy = current.getFullYear();
        const mm = String(current.getMonth() + 1).padStart(2, '0');
        requiredPeriods.push(`${yyyy}-${mm}`);
        current.setMonth(current.getMonth() + 1);
      }

      const paymentsQuery = await db.collection('payments')
        .where('addressRef', '==', targetRef)
        .get();

      const paymentsMap = {};
      paymentsQuery.forEach((doc) => {
        const pData = doc.data();
        if (pData.concept && pData.concept !== 'monthly quota') {
          return;
        }
        const status = pData.status;
        const periodsList = [];
        if (Array.isArray(pData.periods)) {
          pData.periods.forEach((p) => {
            if (p && typeof p === 'string' && p.trim()) periodsList.push(p.trim());
          });
        } else if (pData.period && typeof pData.period === 'string') {
          pData.period.split(',').forEach((p) => {
            if (p && p.trim()) periodsList.push(p.trim());
          });
        }

        if (status && periodsList.length > 0) {
          periodsList.forEach((period) => {
            const existing = paymentsMap[period];
            if (!existing || status === 'approved' || (status === 'pending' && existing === 'rejected')) {
              paymentsMap[period] = status;
            }
          });
        }
      });

      let hasPending = false;
      let hasPendingPast = false;
      let hasUnpaidPast = false;
      let hasUnpaidCurrent = false;
      let hasPendingGrace = false;

      for (const period of requiredPeriods) {
        const status = paymentsMap[period];
        const isCurrentPeriod = period === currentPeriodStr;

        if (isCurrentPeriod) {
          if (status === 'approved') {
            // Current month is approved and paid
          } else if (status === 'pending') {
            hasPending = true;
          } else {
            // status is null or rejected for the current active month
            if (nowTz.day <= graceThresholdDay) {
              hasPendingGrace = true;
            } else {
              hasUnpaidCurrent = true;
            }
          }
        } else {
          // Historical past periods
          if (!status || status === 'rejected') {
            hasUnpaidPast = true;
          } else if (status === 'pending') {
            hasPending = true;
            hasPendingPast = true;
          }
        }
      }

      if (hasUnpaidPast || hasUnpaidCurrent) {
        newStatus = 'restricted';
      } else if (hasPending || hasPendingGrace) {
        newStatus = 'pending';
      } else {
        newStatus = 'paid';
      }

      isWithinGracePeriod = !hasUnpaidPast && !hasPendingPast && (nowTz.day <= graceThresholdDay);
    }
  }

  // Active sanctions check: Any active or pending_review sanction restricts the address immediately
  let hasActiveSanctions = false;
  let activeSanctionsCount = 0;
  try {
    const sanctionsQuery = await db.collection('sanctions')
      .where('addressRef', '==', targetRef)
      .where('status', 'in', ['active', 'pending_review'])
      .get();
    activeSanctionsCount = sanctionsQuery.size;
    hasActiveSanctions = activeSanctionsCount > 0;
  } catch (err) {
    console.error('Error checking active sanctions in recalculateAddressPaymentStatus:', err);
  }

  if (hasActiveSanctions) {
    newStatus = 'restricted';
  }

  const updateData = {
    paymentStatus: newStatus,
    isWithinGracePeriod: isWithinGracePeriod,
    hasActiveSanctions: hasActiveSanctions,
    activeSanctionsCount: activeSanctionsCount,
  };
  if (isApproval) {
    updateData.lastPaymentApproval = Date.now();
  }

  await targetRef.update(updateData);
  return newStatus;
}

/**
 * Scheduled Cloud Function: Runs daily at 00:00 CST (America/Mexico_City).
 * Evaluates payment cutoffs and grace periods across all active residential addresses.
 */
exports.checkMonthlyPaymentStatuses = onSchedule({
  schedule: '0 0 * * *',
  timeZone: 'America/Mexico_City',
}, async (event) => {
  const db = admin.firestore();
  let appSettings = {};
  try {
    const appSettingsDoc = await db.collection('config').doc('app_settings').get();
    if (appSettingsDoc.exists) {
      appSettings = appSettingsDoc.data() || {};
    }
  } catch (err) {
    console.error('Error loading app_settings in checkMonthlyPaymentStatuses:', err);
  }

  try {
    const addressesSnap = await db.collection('addresses').get();
    const tasks = [];
    for (const doc of addressesSnap.docs) {
      const data = doc.data();
      if (data && (data.deliveryDate || data.residentUid)) {
        tasks.push(recalculateAddressPaymentStatus(doc.ref, false, appSettings));
      }
    }
    await Promise.all(tasks);
    console.log(`checkMonthlyPaymentStatuses completed successfully for ${tasks.length} addresses.`);
  } catch (error) {
    console.error('Error executing checkMonthlyPaymentStatuses scheduled job:', error);
  }

  try {
    const expiredCount = await expireOutdatedQrCodes(db);
    if (expiredCount > 0) {
      console.log(`Expired ${expiredCount} outdated QR codes.`);
    }
  } catch (qrError) {
    console.error('Error expiring outdated QR codes in scheduled job:', qrError);
  }

  try {
    const purgedQrCount = await purgeExpiredQrCodes(db);
    if (purgedQrCount > 0) {
      console.log(`Purged ${purgedQrCount} terminal QR codes past 7-day retention.`);
    }
  } catch (qrPurgeError) {
    console.error('Error purging expired QR codes in scheduled job:', qrPurgeError);
  }

  try {
    const bucket = admin.storage().bucket();
    const purgedLogsCount = await purgeExpiredAccessLogs(db, bucket);
    if (purgedLogsCount > 0) {
      console.log(`Purged ${purgedLogsCount} access logs and associated media past 60-day retention.`);
    }
  } catch (logPurgeError) {
    console.error('Error purging expired access logs in scheduled job:', logPurgeError);
  }

  try {
    const bucket = admin.storage().bucket();
    const purgedBookingAttCount = await purgeExpiredBookingAttachments(db, bucket);
    if (purgedBookingAttCount > 0) {
      console.log(`Purged ${purgedBookingAttCount} booking attachment records past 30-day post-booking retention.`);
    }
  } catch (attPurgeError) {
    console.error('Error purging expired booking attachments in scheduled job:', attPurgeError);
  }
});

/**
 * Trigger: Automatically recalculates address payment status whenever a payment is added, updated, or deleted.
 */
exports.onPaymentWritten = onDocumentWritten('payments/{paymentId}', async (event) => {
  const afterData = event.data?.after?.data();
  const beforeData = event.data?.before?.data();
  const addressRef = afterData?.addressRef || beforeData?.addressRef;

  if (addressRef) {
    try {
      await recalculateAddressPaymentStatus(addressRef, false);
    } catch (err) {
      console.error('Error auto-recalculating payment status in onPaymentWritten trigger:', err);
    }
  }
});

/**
 * Trigger: Automatically recalculates address payment status whenever a sanction is added, updated, or deleted.
 */
exports.onSanctionWritten = onDocumentWritten('sanctions/{sanctionId}', async (event) => {
  const afterData = event.data?.after?.data();
  const beforeData = event.data?.before?.data();
  const addressRef = afterData?.addressRef || beforeData?.addressRef;

  if (addressRef) {
    try {
      await recalculateAddressPaymentStatus(addressRef, false);
    } catch (err) {
      console.error('Error auto-recalculating payment status in onSanctionWritten trigger:', err);
    }
  }
});

exports.approvePayment = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { paymentId, residentUid } = request.data;
  if (!paymentId || !residentUid) {
    throw new HttpsError('invalid-argument', 'Missing paymentId or residentUid.');
  }

  const currentAdminUid = request.auth.uid;

  try {
    const paymentRef = admin.firestore().collection('payments').doc(paymentId);
    const paymentDoc = await paymentRef.get();
    if (!paymentDoc.exists) {
      throw new HttpsError('not-found', 'Payment record not found.');
    }

    const paymentData = paymentDoc.data();
    const uploaderUid = paymentData.uploaderUid || residentUid;

    if (uploaderUid === currentAdminUid) {
      throw new HttpsError(
        'permission-denied',
        'Segregation of duties: You cannot approve a payment proof that you uploaded.'
      );
    }

    await paymentRef.update({
      status: 'approved',
      approvalDate: Date.now()
    });

    if (paymentData.concept === 'sanction' && paymentData.sanctionId) {
      try {
        await admin.firestore().collection('sanctions').doc(paymentData.sanctionId).update({
          status: 'paid',
          resolvedAt: Date.now(),
          updatedAt: Date.now(),
        });
      } catch (sanctionErr) {
        console.error('Error updating sanction status to paid in approvePayment:', sanctionErr);
      }
    }

    const userDoc = await admin.firestore().collection('users').doc(residentUid).get();
    if (userDoc.exists) {
      const addressRef = userDoc.data().addressRef;
      if (addressRef) {
        await recalculateAddressPaymentStatus(addressRef, true);
      }
    }

    return { success: true };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', error.message);
  }
});

exports.addRoommate = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in.');
  }

  if (request.auth.token.resident !== true) {
    throw new HttpsError('failed-precondition', 'Only primary residents can add roommates.');
  }

  const residentUid = request.auth.uid;
  let { email, roommateUid } = request.data;

  if (!email && !roommateUid) {
    throw new HttpsError('invalid-argument', 'Missing email or roommateUid.');
  }

  try {
    // 1. Verify caller is a resident
    const residentDoc = await admin.firestore().collection('users').doc(residentUid).get();
    if (!residentDoc.exists) {
      throw new HttpsError('not-found', 'Resident user not found.');
    }
    const residentData = residentDoc.data();
    const addressRef = residentData.addressRef;

    if (!addressRef) {
      throw new HttpsError('failed-precondition', 'Resident is not linked to any address.');
    }

    let targetUid = roommateUid ? roommateUid.replace(/^roommate_uid:/, '').replace(/^roommate:/, '').trim() : null;

    // 2. Find target user by email or by roommateUid
    if (!targetUid && email) {
      const userQuery = await admin.firestore().collection('users').where('email', '==', email.trim()).get();
      if (userQuery.empty) {
        throw new HttpsError('not-found', 'No user found with that email.');
      }
      targetUid = userQuery.docs[0].id;
    }

    const roommateDoc = await admin.firestore().collection('users').doc(targetUid).get();
    if (!roommateDoc.exists) {
      throw new HttpsError('not-found', 'No user found with that ID.');
    }

    if (targetUid === residentUid) {
      throw new HttpsError('invalid-argument', 'You cannot add yourself as a roommate.');
    }

    // 3. Set role claim
    await admin.auth().setCustomUserClaims(targetUid, { roommate: true });

    // 4. Link address (roommate inherits address's payment status) and set role to roommate
    await admin.firestore().collection('users').doc(targetUid).update({
      addressRef: addressRef,
      role: 'roommate',
    });

    // 5. Add to resident's familyMembers array
    await admin.firestore().collection('users').doc(residentUid).update({
      familyMembers: FieldValue.arrayUnion(targetUid)
    });

    return { success: true };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', error.message);
  }
});

exports.notifyAccessResult = onDocumentCreated('access_logs/{logId}', async (event) => {
  const snapshot = event.data;
  if (!snapshot) return null;

  const data = snapshot.data();
  const { creatorUid, status, qrCodeId } = data;

  // Invalidate one-time use QR code first, independent of FCM push notification availability.
  // Skip immediate invalidation if isInside === true so the visitor can still scan out on exit.
  if (status === 'allowed' && qrCodeId && data.isInside !== true) {
    try {
      const qrDoc = await admin.firestore().collection('qr_codes').doc(qrCodeId).get();
      if (qrDoc.exists) {
        const qrData = qrDoc.data() || {};
        if (isOneTimeQrCode(qrData) && qrData.status !== 'deactivated (validated)') {
          await qrDoc.ref.update({
            status: 'deactivated (validated)',
            isValid: false,
            usedAt: FieldValue.serverTimestamp(),
          });
          console.log(`Deactivated one-time use QR code ${qrCodeId}`);
        }
      }
    } catch (qrError) {
      console.error(`Error invalidating one-time QR code ${qrCodeId} in notifyAccessResult:`, qrError);
    }
  }

  if (!creatorUid) return null;

  try {
    const userDoc = await admin.firestore().collection('users').doc(creatorUid).get();
    if (!userDoc.exists) return null;

    const userData = userDoc.data();
    const fcmTokens = userData.fcmTokens;

    if (!fcmTokens || !Array.isArray(fcmTokens) || fcmTokens.length === 0) {
      console.log(`No FCM tokens found for user ${creatorUid}`);
      return null;
    }

    const title = status === 'allowed' ? 'Acceso Permitido / Access Granted' : 'Acceso Denegado / Access Denied';
    const body = `El visitante con código ${qrCodeId || ''} ha sido ${status === 'allowed' ? 'permitido' : 'denegado'}.`;

    const message = {
      notification: {
        title,
        body,
      },
      tokens: fcmTokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`${response.successCount} messages were sent successfully`);

    return null;
  } catch (error) {
    console.error('Error sending access notification:', error);
    return null;
  }
});

exports.adminUpdatePassword = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { uid, newPassword } = request.data;
  if (!uid || !newPassword) {
    throw new HttpsError('invalid-argument', 'Missing uid or newPassword.');
  }

  const cleanNewPassword = newPassword.toString().trim();
  if (!isPasswordCompliant(cleanNewPassword)) {
    throw new HttpsError(
      'invalid-argument',
      'Password does not meet complexity requirements (min. 8 characters, uppercase, lowercase, number, and special character).'
    );
  }

  try {
    await admin.auth().updateUser(uid, { password: cleanNewPassword });
    return { success: true };
  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

exports.adminCreateUser = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { name, email, password, role, streetName, number, addressId, deliveryDate } = request.data;
  if (!name || !email || !password || !role) {
    throw new HttpsError('invalid-argument', 'Missing name, email, password, or role.');
  }

  const cleanName = name.toString().trim();
  const cleanEmail = email.toString().trim().toLowerCase();
  const cleanPassword = password.toString().trim();
  const cleanRole = role.toString().trim().toLowerCase();

  if (!isPasswordCompliant(cleanPassword)) {
    throw new HttpsError(
      'invalid-argument',
      'Password does not meet complexity requirements (min. 8 characters, uppercase, lowercase, number, and special character).'
    );
  }

  if (!['resident', 'guard', 'admin'].includes(cleanRole)) {
    throw new HttpsError('invalid-argument', `Invalid role: ${cleanRole}. Must be resident, guard, or admin.`);
  }

  let parsedDeliveryDate = null;
  if (cleanRole === 'resident' && deliveryDate) {
    parsedDeliveryDate = validateDeliveryDate(deliveryDate);
  }

  const db = admin.firestore();

  try {
    let addressRef = null;
    let addressDisplay = null;

    // 1. Handle Role Specific Address Requirements
    if (cleanRole === 'admin') {
      // Admin users are linked to the fixed address "admin office" / "Oficina de administración"
      // Make sure to create this address if it does not exist before the admin user is created
      const adminOfficeSnap = await db.collection('addresses').where('streetName', '==', 'Admin office').get();
      
      if (adminOfficeSnap.empty) {
        const adminOfficeEsSnap = await db.collection('addresses').where('streetName', '==', 'Oficina de administración').get();
        if (adminOfficeEsSnap.empty) {
          const newDocRef = db.collection('addresses').doc('admin_office');
          await newDocRef.set({
            id: 'admin_office',
            streetName: 'Admin office',
            number: 0,
            paymentStatus: 'paid',
            createdAt: Date.now(),
          });
          addressRef = newDocRef;
        } else {
          addressRef = adminOfficeEsSnap.docs[0].ref;
        }
      } else {
        addressRef = adminOfficeSnap.docs[0].ref;
      }
      addressDisplay = 'Admin office';
    } else if (cleanRole === 'resident') {
      // Resident requires an existing physical address in the neighborhood
      let targetAddressDoc = null;
      if (addressId) {
        const doc = await db.collection('addresses').doc(addressId).get();
        if (doc.exists) {
          targetAddressDoc = doc;
        }
      }

      if (!targetAddressDoc && streetName && number !== undefined) {
        const numVal = isNaN(Number(number)) ? number : Number(number);
        let addressQuery = await db.collection('addresses')
          .where('streetName', '==', streetName.toString().trim())
          .where('number', '==', numVal)
          .get();

        if (addressQuery.empty && typeof numVal === 'number') {
          addressQuery = await db.collection('addresses')
            .where('streetName', '==', streetName.toString().trim())
            .where('number', '==', number.toString().trim())
            .get();
        }

        if (!addressQuery.empty) {
          targetAddressDoc = addressQuery.docs[0];
        }
      }

      if (!targetAddressDoc) {
        throw new HttpsError('not-found', 'Specified address was not found in database.');
      }

      const addressData = targetAddressDoc.data();
      const currentResident = addressData.residentUid;
      if (currentResident && currentResident.toString().trim().length > 0) {
        throw new HttpsError('already-exists', `The address "${addressData.streetName} #${addressData.number}" is already claimed by another resident.`);
      }

      addressRef = targetAddressDoc.ref;
      addressDisplay = `${addressData.streetName} #${addressData.number}`;
    }

    // 2. Create user in Firebase Authentication
    const userRecord = await admin.auth().createUser({
      email: cleanEmail,
      password: cleanPassword,
      displayName: cleanName,
    });

    // 3. Set Custom User Claims based on selected role
    const claims = {};
    if (cleanRole === 'admin') claims.admin = true;
    if (cleanRole === 'guard') claims.guard = true;
    if (cleanRole === 'resident') claims.resident = true;

    await admin.auth().setCustomUserClaims(userRecord.uid, claims);

    // 4. Update address if resident (claim address and initialize paymentStatus as 'paid';
    // deferring full payment status recalculation to checkMonthlyPaymentStatuses to give admins time to upload receipts)
    if (cleanRole === 'resident' && addressRef) {
      const addressUpdate = {
        residentUid: userRecord.uid,
        paymentStatus: 'paid',
        isWithinGracePeriod: true,
      };
      if (parsedDeliveryDate) {
        addressUpdate.deliveryDate = admin.firestore.Timestamp.fromDate(parsedDeliveryDate);
      }
      await addressRef.update(addressUpdate);
    }

    // 5. Create user document in Firestore users collection
    const userDocData = {
      uid: userRecord.uid,
      name: cleanName,
      email: cleanEmail,
      role: cleanRole,
      createdAt: Date.now(),
    };
    if (addressRef) {
      userDocData.addressRef = addressRef;
    }

    await db.collection('users').doc(userRecord.uid).set(userDocData);

    // 6. Send Welcome Email if SMTP is configured
    let emailSent = false;
    let emailError = null;
    const smtpConfig = await getSmtpConfig();
    if (smtpConfig) {
      const roleDisplayMap = {
        'admin': 'administrador',
        'guard': 'guardia de seguridad',
        'resident': 'residente',
      };
      const emailResult = await sendWelcomeEmail(smtpConfig, {
        email: cleanEmail,
        name: cleanName,
        password: cleanPassword,
        addressLinked: addressDisplay,
        appName: DEFAULT_APP_NAME,
        role: roleDisplayMap[cleanRole] || cleanRole,
      });
      emailSent = emailResult.sent === true;
      emailError = emailResult.error || null;
    }

    return {
      success: true,
      uid: userRecord.uid,
      role: cleanRole,
      addressLinked: addressDisplay,
      emailSent,
      emailError,
    };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error('adminCreateUser error:', error);
    throw new HttpsError('internal', error.message || 'Failed to create user account.');
  }
});

exports.adminProvisionGuard = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { name, email, password } = request.data;
  if (!name || !email || !password) {
    throw new HttpsError('invalid-argument', 'Missing name, email, or password.');
  }

  const cleanPassword = password.toString().trim();
  if (!isPasswordCompliant(cleanPassword)) {
    throw new HttpsError(
      'invalid-argument',
      'Password does not meet complexity requirements (min. 8 characters, uppercase, lowercase, number, and special character).'
    );
  }

  try {
    const userRecord = await admin.auth().createUser({
      email,
      password: cleanPassword,
      displayName: name,
    });

    await admin.auth().setCustomUserClaims(userRecord.uid, { guard: true });

    await admin.firestore().collection('users').doc(userRecord.uid).set({
      'uid': userRecord.uid,
      'name': name,
      'email': email,
      'role': 'guard',
      'createdAt': Date.now(),
    });

    // Optionally send welcome email if SMTP is configured
    const smtpConfig = await getSmtpConfig();
    if (smtpConfig) {
      sendWelcomeEmail(smtpConfig, {
        email,
        name,
        password,
        role: 'guardia de seguridad',
        appName: DEFAULT_APP_NAME,
      }).catch(err => console.error('Error sending guard welcome email:', err));
    }

    return { success: true, uid: userRecord.uid };
  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

exports.adminTestSmtpConnection = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { host, port, secure, user, pass, senderEmail, senderName, testRecipient, customSubject, customBody } = request.data;
  if (!host || !user || !pass || !testRecipient) {
    throw new HttpsError('invalid-argument', 'Must provide host, user, pass, and testRecipient.');
  }

  try {
    const config = {
      host: host.toString().trim(),
      port: parseInt(port, 10) || 587,
      secure: secure === true,
      user: user.toString().trim(),
      pass: pass.toString().trim(),
      senderEmail: senderEmail ? senderEmail.toString().trim() : undefined,
      senderName: senderName ? senderName.toString().trim() : undefined,
      customSubject: customSubject ? customSubject.toString() : undefined,
      customBody: customBody ? customBody.toString() : undefined,
    };

    const transporter = createSmtpTransporter(config);
    // 1. Verify handshake
    await transporter.verify();

    // 2. Send test email
    const fromAddress = config.senderEmail && config.senderEmail.length > 0
      ? `"${config.senderName || DEFAULT_APP_NAME}" <${config.senderEmail}>`
      : `"${config.senderName || DEFAULT_APP_NAME}" <${config.user}>`;

    const sampleData = {
      name: 'Usuario de Prueba',
      email: testRecipient.toString().trim(),
      password: 'SamplePass#2026',
      address: 'Calle Ejemplo #101',
      role: 'Residente',
      appName: config.senderName || DEFAULT_APP_NAME,
    };

    let subject = `${DEFAULT_APP_NAME} - Test de Configuración SMTP`;
    if (config.customSubject && config.customSubject.trim().length > 0) {
      subject = `[Test] ${replacePlaceholders(config.customSubject, sampleData)}`;
    }

    let textBody = `Este es un correo de prueba enviado desde la configuración de administración de ${DEFAULT_APP_NAME} para verificar el servicio SMTP.`;
    let htmlBody = `
      <div style="font-family: ${BRAND_COLORS.fontFamily}; max-width: 600px; margin: 0 auto; padding: 24px; background-color: ${BRAND_COLORS.background}; border-radius: 12px;">
        <div style="background-color: #25d366; padding: 20px; border-radius: 8px 8px 0 0; text-align: center;">
          <h2 style="color: #ffffff; margin: 0; font-size: 22px;">¡Conexión SMTP Exitosa!</h2>
        </div>
        <div style="background-color: #ffffff; padding: 24px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.05);">
          <p style="font-size: 15px; color: ${BRAND_COLORS.textColor};">Tu servidor SMTP ha sido verificado correctamente.</p>
          <p style="font-size: 14px; color: #4b5563; line-height: 1.6;">
            Los correos automáticos de bienvenida con credenciales para nuevos residentes y guardias están listos para ser enviados.
          </p>
          <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 20px 0;" />
          <p style="font-size: 12px; color: #9ca3af; text-align: center; margin: 0;">
            ${DEFAULT_APP_NAME} Administration System
          </p>
        </div>
      </div>
    `;

    if (config.customBody && config.customBody.trim().length > 0) {
      const renderedBody = replacePlaceholders(config.customBody, sampleData);
      textBody = `[Email de Prueba con Mensaje Personalizado]\n\n${renderedBody}`;
      const escapedBody = renderedBody
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/\n/g, '<br/>');

      htmlBody = `
        <div style="font-family: ${BRAND_COLORS.fontFamily}; max-width: 600px; margin: 0 auto; padding: 24px; background-color: ${BRAND_COLORS.background}; border-radius: 12px;">
          <div style="background-color: #25d366; padding: 16px 20px; border-radius: 8px 8px 0 0; text-align: center;">
            <h2 style="color: #ffffff; margin: 0; font-size: 20px;">¡Conexión SMTP Exitosa & Vista Previa!</h2>
          </div>
          <div style="background-color: #ffffff; padding: 24px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.05); color: ${BRAND_COLORS.textColor}; line-height: 1.6; font-size: 14px;">
            <p style="font-size: 13px; color: #059669; font-weight: bold; margin-top: 0;">
              ✓ Tu mensaje personalizado se visualiza así con datos de muestra:
            </p>
            <div style="background-color: #f9fafb; border: 1px dashed #d1d5db; border-radius: 6px; padding: 16px; margin: 16px 0;">
              ${escapedBody}
            </div>
            <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 20px 0;" />
            <p style="font-size: 12px; color: #9ca3af; text-align: center; margin: 0;">
              ${DEFAULT_APP_NAME} Administration System
            </p>
          </div>
        </div>
      `;
    }

    const info = await transporter.sendMail({
      from: fromAddress,
      to: testRecipient.toString().trim(),
      subject: subject,
      text: textBody,
      html: htmlBody,
    });

    return {
      success: true,
      message: 'SMTP handshake and test email sent successfully.',
      messageId: info.messageId,
    };
  } catch (err) {
    console.error('SMTP test error:', err);
    throw new HttpsError('internal', err.message || 'SMTP connection failed.');
  }
});

exports.adminDeleteUser = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { uid } = request.data;
  if (!uid) {
    throw new HttpsError('invalid-argument', 'Missing uid.');
  }

  try {
    const db = admin.firestore();
    const userDoc = await db.collection('users').doc(uid).get();

    if (userDoc.exists) {
      const userData = userDoc.data();
      const batch = db.batch();

      // 1. If primary resident with linked address, unbind address and reset status
      if (userData.addressRef) {
        batch.update(userData.addressRef, {
          residentUid: null,
          paymentStatus: 'restricted'
        });
      }

      // 2. If they have registered roommates / family members, clear their addressRef and claims
      const familyMembers = userData.familyMembers || [];
      for (const roommateUid of familyMembers) {
        const roommateRef = db.collection('users').doc(roommateUid);
        batch.update(roommateRef, {
          addressRef: null
        });
        await admin.auth().setCustomUserClaims(roommateUid, {});
      }

      // 3. If this user is a roommate in another resident's familyMembers list, remove them
      const residentQuery = await db.collection('users')
        .where('familyMembers', 'array-contains', uid)
        .get();
      for (const resDoc of residentQuery.docs) {
        batch.update(resDoc.ref, {
          familyMembers: FieldValue.arrayRemove(uid)
        });
      }

      // 4. Delete Firestore user document
      batch.delete(userDoc.ref);
      await batch.commit();
    }

    try {
      await admin.auth().deleteUser(uid);
    } catch (authError) {
      if (authError.code !== 'auth/user-not-found') {
        throw authError;
      }
    }

    return { success: true };
  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

exports.unbindAddress = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in.');
  }

  const targetUid = request.data.uid;
  if (!targetUid) {
    throw new HttpsError('invalid-argument', 'Missing uid.');
  }

  const callerUid = request.auth.uid;
  const isAdmin = request.auth.token.admin === true;

  // Enforce permissions: caller must be Admin, or must be targetUid themselves
  if (callerUid !== targetUid && !isAdmin) {
    throw new HttpsError('permission-denied', 'You do not have permission to unbind this address.');
  }

  try {
    const userDoc = await admin.firestore().collection('users').doc(targetUid).get();
    if (!userDoc.exists) {
      throw new HttpsError('not-found', 'User not found.');
    }

    const userData = userDoc.data();
    const addressRef = userData.addressRef;

    if (!addressRef) {
      return { success: true, message: 'User has no linked address.' };
    }

    const db = admin.firestore();
    const batch = db.batch();

    // 1. Set residentUid = null on the address document
    batch.update(addressRef, {
      residentUid: null,
      paymentStatus: 'restricted'
    });

    // 2. Clear addressRef and familyMembers on primary resident user document
    batch.update(userDoc.ref, {
      addressRef: null,
      familyMembers: FieldValue.delete()
    });

    // Clear resident custom claims
    await admin.auth().setCustomUserClaims(targetUid, {});

    // 3. Clear addressRef on roommates in familyMembers
    const familyMembers = userData.familyMembers || [];
    for (const roommateUid of familyMembers) {
      const roommateRef = db.collection('users').doc(roommateUid);
      batch.update(roommateRef, {
        addressRef: null,
        role: FieldValue.delete()
      });
      await admin.auth().setCustomUserClaims(roommateUid, {});
    }

    await batch.commit();
    return { success: true, message: 'Address unlinked successfully.' };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', error.message);
  }
});

exports.deleteOwnAccount = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in.');
  }

  const uid = request.auth.uid;

  try {
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    if (userDoc.exists) {
      const userData = userDoc.data();
      if (userData.addressRef) {
        throw new HttpsError('failed-precondition', 'Cannot delete account while linked to an address.');
      }
      await userDoc.ref.delete();
    }
    await admin.auth().deleteUser(uid);
    return { success: true };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', error.message);
  }
});

exports.removeRoommate = onCall(callableOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in.');
  }

  const { roommateUid } = request.data;
  if (!roommateUid) {
    throw new HttpsError('invalid-argument', 'Missing roommateUid.');
  }

  const callerUid = request.auth.uid;
  const isAdmin = request.auth.token.admin === true;

  try {
    const db = admin.firestore();
    const roommateDoc = await db.collection('users').doc(roommateUid).get();
    if (!roommateDoc.exists) {
      throw new HttpsError('not-found', 'Roommate user not found.');
    }

    // Find the resident who has this roommate in their family group
    const residentQuery = await db.collection('users')
      .where('familyMembers', 'array-contains', roommateUid)
      .get();

    let residentDoc = null;
    let residentUid = null;

    if (!residentQuery.empty) {
      residentDoc = residentQuery.docs[0];
      residentUid = residentDoc.id;
    }

    if (!residentUid && !isAdmin) {
      throw new HttpsError('failed-precondition', 'Roommate is not associated with any family group you manage.');
    }

    // Enforce authorization: must be admin OR the primary resident of that family group
    if (residentUid && callerUid !== residentUid && !isAdmin) {
      throw new HttpsError('permission-denied', 'You do not have permission to remove this roommate.');
    }

    const batch = db.batch();

    // 1. Remove roommateUid from resident's familyMembers list (if resident document found)
    if (residentDoc && residentDoc.data().familyMembers) {
      batch.update(residentDoc.ref, {
        familyMembers: FieldValue.arrayRemove(roommateUid)
      });
    }

    // 2. Clear addressRef and role on roommate's user document
    batch.update(roommateDoc.ref, {
      addressRef: null,
      role: FieldValue.delete()
    });

    await batch.commit();

    // 3. Clear roommate auth custom claims
    await admin.auth().setCustomUserClaims(roommateUid, {});

    return { success: true };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', error.message);
  }
});

exports.adminBulkImportResidents = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { users } = request.data;
  if (!users || !Array.isArray(users) || users.length === 0) {
    throw new HttpsError('invalid-argument', 'Must provide a non-empty array of user objects.');
  }

  const results = [];
  let successCount = 0;
  let failureCount = 0;
  const smtpConfig = await getSmtpConfig();
  const db = admin.firestore();

  // Pre-fetch all addresses once for fast, zero-query in-memory lookups
  const allAddressesSnap = await db.collection('addresses').get();
  const addressMap = new Map();
  for (const doc of allAddressesSnap.docs) {
    const d = doc.data();
    if (d.streetName && d.number !== undefined && d.number !== null) {
      const key = `${d.streetName.toString().trim().toLowerCase()}::${d.number.toString().trim()}`;
      addressMap.set(key, doc);
    }
  }

  for (const userRow of users) {
    const name = (userRow.name || userRow.fullName || '').toString().trim();
    const email = (userRow.email || '').toString().trim().toLowerCase();
    const rawPassword = (userRow.password || '').toString().trim();
    const streetName = (userRow.streetName || userRow.street || '').toString().trim();
    const numberStr = (userRow.number || userRow.houseNumber || '').toString().trim();

    if (!name || !email || !email.includes('@')) {
      results.push({
        email: email || 'unknown',
        name: name || 'unknown',
        status: 'error',
        emailSent: false,
        error: 'Invalid name or email address.',
      });
      failureCount++;
      continue;
    }

    // Determine password: if not specified or does not satisfy complexity policy, generate a cryptographically secure random password
    let password = rawPassword;
    let isAutoGenerated = false;
    if (!isPasswordCompliant(password)) {
      password = generateSecurePassword(12);
      isAutoGenerated = true;
    }

    try {
      let addressRef = null;
      let addressMatched = false;

      // 1. Verify address existence if streetName and number are provided (do NOT create new addresses!)
      if (streetName && numberStr) {
        const lookupKey = `${streetName.toLowerCase()}::${numberStr}`;
        const matchedDoc = addressMap.get(lookupKey);

        if (!matchedDoc) {
          // Reject row: Address does not exist in DB records
          results.push({
            name,
            email,
            password: rawPassword,
            streetName,
            number: numberStr,
            status: 'error',
            assignedPassword: password,
            emailSent: false,
            error: `Address "${streetName} #${numberStr}" not found in database.`,
          });
          failureCount++;
          continue;
        }

        const existingDoc = matchedDoc;
        addressRef = existingDoc.ref;
        addressMatched = true;
      }

      // 2. Create user account in Firebase Auth
      const userRecord = await admin.auth().createUser({
        email,
        password,
        displayName: name,
      });

      // Grant resident custom claim since the beginning (no ownership claim needed)
      await admin.auth().setCustomUserClaims(userRecord.uid, { resident: true });

      // 3. Mark existing address document as claimed by resident
      if (addressRef) {
        await addressRef.update({
          residentUid: userRecord.uid,
          paymentStatus: 'paid',
        });
      }

      // 4. Create user document in Firestore users collection
      const userDocData = {
        uid: userRecord.uid,
        name: name,
        email: email,
        role: 'resident',
        createdAt: Date.now(),
      };
      if (addressRef) {
        userDocData.addressRef = addressRef;
      }

      await db.collection('users').doc(userRecord.uid).set(userDocData);

      // 5. Send welcome email if SMTP service is active
      let emailResult = { sent: false };
      if (smtpConfig) {
        emailResult = await sendWelcomeEmail(smtpConfig, {
          email,
          name,
          password,
          addressLinked: addressMatched ? `${streetName} #${numberStr}` : null,
          appName: DEFAULT_APP_NAME,
          role: 'residente',
        });
      }

      results.push({
        name,
        email,
        password: rawPassword,
        streetName,
        number: numberStr,
        status: 'ok',
        assignedPassword: password,
        isAutoGeneratedPassword: isAutoGenerated,
        isDeterministicPassword: isAutoGenerated,
        addressLinked: addressMatched ? `${streetName} #${numberStr}` : null,
        uid: userRecord.uid,
        emailSent: emailResult.sent === true,
        emailError: emailResult.error || '',
        error: '',
      });
      successCount++;
    } catch (err) {
      console.error(`Error creating user ${email}:`, err);
      results.push({
        name,
        email,
        password: rawPassword,
        streetName,
        number: numberStr,
        status: 'error',
        assignedPassword: password,
        emailSent: false,
        error: err.message || 'Failed to create user account.',
      });
      failureCount++;
    }
  }

  return {
    success: true,
    totalProcessed: users.length,
    successCount,
    failureCount,
    results,
  };
});

exports.adminBulkImportAddresses = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { items } = request.data;
  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new HttpsError('invalid-argument', 'Must provide a non-empty array of address items.');
  }

  const db = admin.firestore();
  let createdCount = 0;
  let skippedCount = 0;
  const results = [];

  // Fetch all current addresses for collision checks
  const existingSnap = await db.collection('addresses').get();
  const existingSet = new Set();
  existingSnap.docs.forEach(doc => {
    const d = doc.data();
    if (d.streetName && d.number !== undefined && d.number !== null) {
      const key = `${d.streetName.toString().trim().toLowerCase()}::${d.number.toString().trim()}`;
      existingSet.add(key);
    }
  });

  const batchList = [];
  let currentBatch = db.batch();
  let operationCount = 0;

  for (const item of items) {
    const streetName = (item.streetName || item.street || '').toString().trim();
    const initialNum = parseInt(item.initialNumber ?? item.number, 10);
    const finalNum = parseInt(item.finalNumber ?? item.number, 10);

    let exclusions = [];
    if (item.exclusions) {
      if (Array.isArray(item.exclusions)) {
        exclusions = item.exclusions.map(n => parseInt(n, 10));
      } else if (typeof item.exclusions === 'string') {
        exclusions = item.exclusions.split(',').map(n => parseInt(n.trim(), 10)).filter(n => !isNaN(n));
      }
    }

    if (!streetName || isNaN(initialNum) || isNaN(finalNum)) {
      results.push({
        streetName,
        range: `${initialNum || ''}-${finalNum || ''}`,
        status: 'error',
        error: 'Invalid street name or house numbers.',
      });
      continue;
    }

    let itemCreated = 0;
    let itemSkipped = 0;

    for (let num = Math.min(initialNum, finalNum); num <= Math.max(initialNum, finalNum); num++) {
      if (exclusions.includes(num)) {
        itemSkipped++;
        continue;
      }

      const checkKey = `${streetName.toLowerCase()}::${num}`;
      if (existingSet.has(checkKey)) {
        itemSkipped++;
        skippedCount++;
        continue;
      }

      const docRef = db.collection('addresses').doc();
      currentBatch.set(docRef, {
        id: docRef.id,
        streetName: streetName,
        number: num,
        residentUid: null,
        paymentStatus: 'pending',
        createdAt: FieldValue.serverTimestamp(),
      });
      existingSet.add(checkKey);
      itemCreated++;
      createdCount++;
      operationCount++;

      if (operationCount === 500) {
        batchList.push(currentBatch);
        currentBatch = db.batch();
        operationCount = 0;
      }
    }

    results.push({
      streetName,
      range: initialNum === finalNum ? `${initialNum}` : `${initialNum}-${finalNum}`,
      created: itemCreated,
      skipped: itemSkipped,
      status: 'ok',
    });
  }

  if (operationCount > 0) {
    batchList.push(currentBatch);
  }

  for (const b of batchList) {
    await b.commit();
  }

  return {
    success: true,
    totalProcessed: items.length,
    createdCount,
    skippedCount,
    results,
  };
});

const BULK_PAYMENT_MONTH_MAP = {
  // English
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  // Spanish
  'ene': 1, 'abr': 4, 'ago': 8, 'set': 9, 'dic': 12,
};

/**
 * Normalizes a street name for case- and diacritic-insensitive matching.
 */
function normalizeStreetName(street) {
  if (!street || typeof street !== 'string') return '';
  return street
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\s+/g, ' ');
}

/**
 * Parses a period header string (e.g. 'Nov-24', 'ene-25', '2024-11', 'Dec-2024')
 * into canonical 'YYYY-MM' format. Returns null if invalid.
 */
function parsePeriodHeader(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const str = raw.trim().toLowerCase();

  // 1. Direct YYYY-MM or YYYY/MM match
  const isoMatch = str.match(/^(\d{4})[-/](\d{1,2})$/);
  if (isoMatch) {
    const y = parseInt(isoMatch[1], 10);
    const m = parseInt(isoMatch[2], 10);
    if (m >= 1 && m <= 12) {
      return `${y}-${String(m).padStart(2, '0')}`;
    }
    return null;
  }

  // 2. mmm-yy, mmm-yyyy, mmm/yy, mmm yy, mmm_yy
  const textMatch = str.match(/^([a-z]{3,4})[-/_\s]?(\d{2}|\d{4})$/);
  if (textMatch) {
    const monthKey = textMatch[1];
    const yearRaw = parseInt(textMatch[2], 10);
    const monthNum = BULK_PAYMENT_MONTH_MAP[monthKey];
    if (!monthNum) return null;

    let fullYear = yearRaw;
    if (textMatch[2].length === 2) {
      fullYear = yearRaw < 70 ? 2000 + yearRaw : 1900 + yearRaw;
    }
    return `${fullYear}-${String(monthNum).padStart(2, '0')}`;
  }

  return null;
}

/**
 * Callable Cloud Function: Pre-checks a payment bulk import CSV dataset.
 * Resolves addresses, matches existing payments, and detects amount discrepancies.
 */
exports.adminPreCheckPaymentImport = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { items } = request.data || {};
  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new HttpsError('invalid-argument', 'Must provide a non-empty array of items.');
  }

  const db = admin.firestore();

  // Pre-fetch all addresses into in-memory map
  const allAddressesSnap = await db.collection('addresses').get();
  const addressMap = new Map();
  for (const doc of allAddressesSnap.docs) {
    const d = doc.data();
    if (d.streetName && d.number !== undefined && d.number !== null) {
      const key = `${normalizeStreetName(d.streetName)}::${parseInt(d.number, 10)}`;
      addressMap.set(key, doc);
    }
  }

  const unmatchedAddresses = [];
  const mismatches = [];
  let matchedAddressesCount = 0;
  let identicalPeriodsCount = 0;
  let newPeriodsCount = 0;

  for (const item of items) {
    const streetName = (item.streetName || item.street || '').toString().trim();
    const num = parseInt(item.number, 10);
    const periodAmounts = item.periodAmounts || {};

    const key = `${normalizeStreetName(streetName)}::${num}`;
    const addressDoc = addressMap.get(key);

    if (!addressDoc) {
      unmatchedAddresses.push({ street: streetName, number: item.number });
      continue;
    }

    matchedAddressesCount++;

    // Query existing payments for this address
    const paymentsSnap = await db.collection('payments')
      .where('addressRef', '==', addressDoc.ref)
      .get();

    const existingPeriodAmounts = {};
    for (const pDoc of paymentsSnap.docs) {
      const p = pDoc.data();
      if (p.concept && p.concept !== 'monthly quota') continue;
      if (p.status !== 'approved' && p.status !== 'paid') continue;

      const periods = [];
      if (Array.isArray(p.periods)) {
        for (const pr of p.periods) {
          if (pr && typeof pr === 'string') periods.push(pr.trim());
        }
      } else if (p.period) {
        for (const pr of p.period.toString().split(',')) {
          if (pr.trim()) periods.push(pr.trim());
        }
      }

      const paymentAmount = typeof p.amount === 'number' ? p.amount : 0;
      const perPeriodAmount = periods.length > 1 ? (paymentAmount / periods.length) : paymentAmount;

      for (const pr of periods) {
        existingPeriodAmounts[pr] = {
          paymentDocId: pDoc.id,
          amount: perPeriodAmount,
          isMultiPeriod: periods.length > 1,
        };
      }
    }

    for (const [periodKey, rawAmount] of Object.entries(periodAmounts)) {
      const csvAmount = typeof rawAmount === 'number' ? rawAmount : parseFloat(rawAmount);
      if (isNaN(csvAmount) || csvAmount <= 0) continue;

      const existing = existingPeriodAmounts[periodKey];
      if (existing) {
        const existingRounded = Math.round(existing.amount * 100) / 100;
        const csvRounded = Math.round(csvAmount * 100) / 100;

        if (existingRounded === csvRounded) {
          identicalPeriodsCount++;
        } else {
          mismatches.push({
            street: addressDoc.data().streetName,
            number: addressDoc.data().number,
            addressId: addressDoc.id,
            periodKey,
            existingAmount: existingRounded,
            csvAmount: csvRounded,
            existingPaymentId: existing.paymentDocId,
            isMultiPeriod: existing.isMultiPeriod,
          });
        }
      } else {
        newPeriodsCount++;
      }
    }
  }

  return {
    matchedAddressesCount,
    unmatchedAddresses,
    mismatches,
    identicalPeriodsCount,
    newPeriodsCount,
  };
});

/**
 * Callable Cloud Function: Executes bulk import of previous payments.
 * Handles duplicate skips, applies manual reconciliation decisions, and recalculates address statuses.
 */
exports.adminBulkImportPayments = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { items, reconciliationDecisions } = request.data || {};
  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new HttpsError('invalid-argument', 'Must provide a non-empty array of items.');
  }

  const decisionsMap = reconciliationDecisions || {};
  const db = admin.firestore();
  const currentAdminUid = request.auth.uid;

  // Pre-fetch all addresses
  const allAddressesSnap = await db.collection('addresses').get();
  const addressMap = new Map();
  for (const doc of allAddressesSnap.docs) {
    const d = doc.data();
    if (d.streetName && d.number !== undefined && d.number !== null) {
      const key = `${normalizeStreetName(d.streetName)}::${parseInt(d.number, 10)}`;
      addressMap.set(key, doc);
    }
  }

  const results = [];
  let successCount = 0;
  let failureCount = 0;
  let skippedPeriodsCount = 0;
  let totalPaymentsCreated = 0;
  const addressesToRecalculate = new Set();

  for (const item of items) {
    const streetName = (item.streetName || item.street || '').toString().trim();
    const num = parseInt(item.number, 10);
    const periodAmounts = item.periodAmounts || {};

    const key = `${normalizeStreetName(streetName)}::${num}`;
    const addressDoc = addressMap.get(key);

    if (!addressDoc) {
      results.push({
        street: streetName,
        number: item.number,
        status: 'error',
        importedPeriods: [],
        skippedPeriods: [],
        message: `Address "${streetName} #${item.number}" not found in database records.`,
      });
      failureCount++;
      continue;
    }

    const canonicalStreet = addressDoc.data().streetName;
    const canonicalNum = addressDoc.data().number;
    const addressId = addressDoc.id;
    const residentUid = addressDoc.data().residentUid || null;

    // Query existing payments for this address
    const paymentsSnap = await db.collection('payments')
      .where('addressRef', '==', addressDoc.ref)
      .get();

    const existingPeriodAmounts = {};
    for (const pDoc of paymentsSnap.docs) {
      const p = pDoc.data();
      if (p.concept && p.concept !== 'monthly quota') continue;
      if (p.status !== 'approved' && p.status !== 'paid') continue;

      const periods = [];
      if (Array.isArray(p.periods)) {
        for (const pr of p.periods) {
          if (pr && typeof pr === 'string') periods.push(pr.trim());
        }
      } else if (p.period) {
        for (const pr of p.period.toString().split(',')) {
          if (pr.trim()) periods.push(pr.trim());
        }
      }

      const paymentAmount = typeof p.amount === 'number' ? p.amount : 0;
      const perPeriodAmount = periods.length > 1 ? (paymentAmount / periods.length) : paymentAmount;

      for (const pr of periods) {
        existingPeriodAmounts[pr] = {
          paymentDocId: pDoc.id,
          amount: perPeriodAmount,
          docRef: pDoc.ref,
          periods: periods,
          isMultiPeriod: periods.length > 1,
        };
      }
    }

    const periodsToCreate = [];
    const importedPeriodsLabels = [];
    const skippedPeriodsLabels = [];

    for (const [periodKey, rawAmount] of Object.entries(periodAmounts)) {
      const csvAmount = typeof rawAmount === 'number' ? rawAmount : parseFloat(rawAmount);
      if (isNaN(csvAmount) || csvAmount <= 0) {
        continue;
      }

      const existing = existingPeriodAmounts[periodKey];
      if (existing) {
        const existingRounded = Math.round(existing.amount * 100) / 100;
        const csvRounded = Math.round(csvAmount * 100) / 100;

        if (existingRounded === csvRounded) {
          skippedPeriodsLabels.push(`${periodKey} (Already Paid)`);
          skippedPeriodsCount++;
        } else {
          const decisionKey = `${addressId}::${periodKey}`;
          const decision = decisionsMap[decisionKey];

          if (decision === 'overwrite') {
            if (!existing.isMultiPeriod) {
              await existing.docRef.update({
                amount: csvAmount,
                updatedAt: FieldValue.serverTimestamp(),
                reconciledBy: currentAdminUid,
                notes: 'Amount updated via bulk payment import reconciliation',
              });
              importedPeriodsLabels.push(`${periodKey} ($${csvAmount} Overwritten)`);
              addressesToRecalculate.add(addressDoc);
            } else {
              periodsToCreate.push({ periodKey, amount: csvAmount });
              importedPeriodsLabels.push(`${periodKey} ($${csvAmount} Overwritten)`);
            }
          } else {
            skippedPeriodsLabels.push(`${periodKey} (Kept Existing $${existingRounded})`);
            skippedPeriodsCount++;
          }
        }
      } else {
        periodsToCreate.push({ periodKey, amount: csvAmount });
        importedPeriodsLabels.push(`${periodKey} ($${csvAmount})`);
      }
    }

    if (periodsToCreate.length > 0) {
      const sortedPeriodKeys = periodsToCreate.map(p => p.periodKey).sort();
      const totalAmount = periodsToCreate.reduce((sum, p) => sum + p.amount, 0);
      const paymentId = `${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;

      await db.collection('payments').doc(paymentId).set({
        id: paymentId,
        addressRef: addressDoc.ref,
        residentUid: residentUid,
        uploaderUid: currentAdminUid,
        concept: 'monthly quota',
        status: 'approved',
        periods: sortedPeriodKeys,
        period: sortedPeriodKeys.join(', '),
        amount: totalAmount,
        folio: `BULK-${paymentId}`,
        source: 'bulk_csv_import',
        notes: 'Bulk previous payments historical import',
        paymentDate: Timestamp.now(),
        timestamp: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      });

      totalPaymentsCreated++;
      addressesToRecalculate.add(addressDoc);
    }

    const hasImported = importedPeriodsLabels.length > 0;
    const hasSkipped = skippedPeriodsLabels.length > 0;

    results.push({
      street: canonicalStreet,
      number: canonicalNum,
      status: hasImported ? 'ok' : (hasSkipped ? 'skipped' : 'no_data'),
      importedPeriods: importedPeriodsLabels,
      skippedPeriods: skippedPeriodsLabels,
      message: hasImported
        ? `Imported ${importedPeriodsLabels.length} period(s).`
        : (hasSkipped ? 'All periods already paid.' : 'No amounts specified.'),
    });

    if (hasImported || hasSkipped) {
      successCount++;
    }
  }

  // Recalculate payment status for affected addresses
  for (const addrDoc of addressesToRecalculate) {
    try {
      await recalculateAddressPaymentStatus(addrDoc.ref, true);
    } catch (recalcErr) {
      console.error(`Error recalculating address ${addrDoc.id} in bulk import:`, recalcErr);
    }
  }

  return {
    successCount,
    failureCount,
    skippedPeriodsCount,
    totalPaymentsCreated,
    results,
  };
});

/**
 * Determines whether a QR code document represents a single-use pass.
 */
function isOneTimeQrCode(qrData) {
  if (!qrData || typeof qrData !== 'object') return false;
  return (
    qrData.isOneTimeUse === true ||
    qrData.isOneTime === true ||
    qrData.type === 'one_time' ||
    qrData.accessCategory === 'supplier'
  );
}

/**
 * Evaluates whether a QR code's status and isValid flags permit entry.
 */
function evaluateQrValidityStatus(qrData) {
  if (!qrData || typeof qrData !== 'object') {
    return { isValid: false, reason: 'QR Code is invalid.' };
  }
  const status = typeof qrData.status === 'string' ? qrData.status.trim().toLowerCase() : 'active';
  if (status === 'used' || status === 'deactivated (validated)') {
    return { isValid: false, reason: 'QR Code has already been used.' };
  }
  if (status === 'revoked' || status === 'deactivated (revoked)') {
    return { isValid: false, reason: 'QR Code has been revoked.' };
  }
  if (status === 'expired' || status === 'deactivated (expired)') {
    return { isValid: false, reason: 'QR Code has expired.' };
  }
  if (qrData.isValid === false || status === 'deactivated' || (status !== 'active' && status !== 'valid')) {
    return { isValid: false, reason: 'QR Code is invalid.' };
  }
  return { isValid: true, reason: null };
}

/**
 * Extracts the expiration timestamp in milliseconds from a QR code document.
 */
function getQrExpiryMillis(qrData) {
  if (!qrData || typeof qrData !== 'object') return 0;
  const expTime = qrData.expiresAt || qrData.expiryTime || qrData.expiry;
  if (!expTime) return 0;
  if (typeof expTime.toMillis === 'function') {
    return expTime.toMillis();
  }
  if (expTime instanceof Date) {
    return expTime.getTime();
  }
  if (typeof expTime === 'string' || typeof expTime === 'number') {
    const parsed = new Date(expTime).getTime();
    return isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

const ACCESS_LOG_RETENTION_DAYS = 60;
const ACCESS_LOG_RETENTION_MS = ACCESS_LOG_RETENTION_DAYS * 24 * 60 * 60 * 1000;
const QR_CODE_RETENTION_DAYS = 7;
const QR_CODE_RETENTION_MS = QR_CODE_RETENTION_DAYS * 24 * 60 * 60 * 1000;
const ALLOWED_VISITOR_MEDIA_PREFIXES = ['visitor_ids/', 'visitor_plates/'];
const TERMINAL_QR_STATUSES = [
  'deactivated (expired)',
  'expired',
  'deactivated (validated)',
  'used',
  'deactivated (revoked)',
  'revoked',
  'deactivated',
];

/**
 * Computes the millisecond expiration timestamp for an access log (+60 days).
 */
function computeAccessLogExpireAtMillis(baseInput = Date.now()) {
  const baseMillis =
    typeof baseInput === 'number' ? baseInput : (extractTimestampMillis(baseInput) || Date.now());
  return baseMillis + ACCESS_LOG_RETENTION_MS;
}

/**
 * Computes the millisecond expiration timestamp for a terminal QR code (+7 days).
 */
function computeQrCodeExpireAtMillis(baseInput = Date.now()) {
  const baseMillis =
    typeof baseInput === 'number' ? baseInput : (extractTimestampMillis(baseInput) || Date.now());
  return baseMillis + QR_CODE_RETENTION_MS;
}

/**
 * Safely extracts and validates a Cloud Storage object path strictly within
 * `visitor_ids/` or `visitor_plates/`. Rejects traversal sequences, null bytes,
 * backslashes, and paths outside visitor media directories.
 */
function extractVisitorMediaStoragePath(rawUrl) {
  if (!rawUrl || typeof rawUrl !== 'string') return null;
  const trimmed = rawUrl.trim();
  if (!trimmed || trimmed.includes('\0') || /%00/i.test(trimmed)) {
    return null;
  }

  let candidate = null;
  try {
    if (/^https?:\/\//i.test(trimmed)) {
      const parsed = new URL(trimmed);
      const restMatch = parsed.pathname.match(/^\/v0\/b\/[^/]+\/o\/(.+)$/);
      if (restMatch) {
        candidate = decodeURIComponent(restMatch[1]);
      } else if (parsed.hostname === 'storage.googleapis.com') {
        const gcsMatch = parsed.pathname.match(/^\/[^/]+\/(.+)$/);
        if (gcsMatch) {
          candidate = decodeURIComponent(gcsMatch[1]);
        }
      } else if (
        parsed.pathname.startsWith('/visitor_ids/') ||
        parsed.pathname.startsWith('/visitor_plates/')
      ) {
        candidate = decodeURIComponent(parsed.pathname.slice(1));
      }
    } else if (/^gs:\/\//i.test(trimmed)) {
      const gsMatch = trimmed.match(/^gs:\/\/[^/]+\/(.+)$/);
      if (gsMatch) {
        candidate = decodeURIComponent(gsMatch[1]);
      }
    } else if (!trimmed.includes('://')) {
      candidate = decodeURIComponent(trimmed);
    }
  } catch (_) {
    return null;
  }

  if (!candidate || typeof candidate !== 'string') return null;
  if (
    candidate.includes('\0') ||
    candidate.includes('\\') ||
    candidate.startsWith('/') ||
    candidate.endsWith('/')
  ) {
    return null;
  }

  const segments = candidate.split('/');
  if (segments.some((seg) => !seg || seg === '.' || seg === '..')) {
    return null;
  }

  const normalized = path.posix.normalize(candidate);
  if (normalized !== candidate) {
    return null;
  }

  const matchedPrefix = ALLOWED_VISITOR_MEDIA_PREFIXES.find((prefix) =>
    normalized.startsWith(prefix)
  );
  if (!matchedPrefix) {
    return null;
  }

  const relativeName = normalized.slice(matchedPrefix.length);
  if (!relativeName || !path.posix.basename(normalized)) {
    return null;
  }

  return normalized;
}

/**
 * Returns true if a QR code document is in a terminal (inactive) status.
 */
function isTerminalQrStatus(qrData) {
  if (!qrData || typeof qrData !== 'object') return false;
  const rawStatus = typeof qrData.status === 'string' ? qrData.status.trim().toLowerCase() : 'active';
  if (TERMINAL_QR_STATUSES.includes(rawStatus)) {
    return true;
  }
  return qrData.isValid === false;
}

/**
 * Determines the retention action ('keep' | 'delete' | 'stamp_ttl') for a QR code document.
 * - Preserves any pass with an active open visit (`isInside === true`).
 * - Preserves active permanent passes and non-expired temporary passes.
 * - Deletes terminal passes once their 7-day retention window has elapsed.
 * - Backfills `expireAt` on legacy terminal passes missing an explicit TTL field.
 */
function evaluateQrCleanupAction(qrData, nowMillis = Date.now()) {
  if (!qrData || typeof qrData !== 'object') {
    return { action: 'keep' };
  }
  if (qrData.isInside === true) {
    return { action: 'keep' };
  }

  const expMillis = getQrExpiryMillis(qrData);
  const terminal = isTerminalQrStatus(qrData);

  if (!terminal) {
    if (expMillis > 0 && nowMillis >= computeQrCodeExpireAtMillis(expMillis)) {
      return { action: 'delete' };
    }
    return { action: 'keep' };
  }

  const expireAtMillis = extractTimestampMillis(qrData.expireAt);
  if (expireAtMillis > 0) {
    return nowMillis >= expireAtMillis ? { action: 'delete' } : { action: 'keep' };
  }

  const refMillis =
    extractTimestampMillis(qrData.deactivatedAt) ||
    extractTimestampMillis(qrData.usedAt) ||
    extractTimestampMillis(qrData.revokedAt) ||
    expMillis;

  if (refMillis > 0) {
    const targetExpireAt = computeQrCodeExpireAtMillis(refMillis);
    if (nowMillis >= targetExpireAt) {
      return { action: 'delete' };
    }
    return { action: 'stamp_ttl', expireAtMillis: targetExpireAt };
  }

  // Legacy terminal pass with no terminal/expiry timestamp: grant a 7-day window from first sweep
  return { action: 'stamp_ttl', expireAtMillis: computeQrCodeExpireAtMillis(nowMillis) };
}

/**
 * Marks active QR codes whose expiration time has passed as 'deactivated (expired)'
 * and stamps their 7-day TTL `expireAt` (unless a visitor is currently inside).
 */
async function expireOutdatedQrCodes(db, nowMillis = Date.now()) {
  const activeSnap = await db.collection('qr_codes').where('status', '==', 'active').get();
  if (activeSnap.empty) return 0;

  let expiredCount = 0;
  let batch = db.batch();
  let opCount = 0;
  const batches = [];

  for (const doc of activeSnap.docs) {
    const data = doc.data() || {};
    const expMillis = getQrExpiryMillis(data);
    if (expMillis > 0 && nowMillis > expMillis) {
      batch.update(doc.ref, {
        status: 'deactivated (expired)',
        isValid: false,
        deactivatedAt: admin.firestore.Timestamp.fromMillis(nowMillis),
        expireAt: data.isInside === true
          ? null
          : admin.firestore.Timestamp.fromMillis(computeQrCodeExpireAtMillis(expMillis)),
      });
      expiredCount++;
      opCount++;
      if (opCount === 500) {
        batches.push(batch);
        batch = db.batch();
        opCount = 0;
      }
    }
  }

  if (opCount > 0) {
    batches.push(batch);
  }

  for (const b of batches) {
    await b.commit();
  }

  return expiredCount;
}

/**
 * Purges terminal QR codes (`expired`, `validated`, `revoked`) whose 7-day retention
 * period has elapsed, and stamps `expireAt` on legacy terminal documents missing TTL metadata.
 */
async function purgeExpiredQrCodes(db, nowMillis = Date.now()) {
  const terminalSnap = await db
    .collection('qr_codes')
    .where('status', 'in', TERMINAL_QR_STATUSES)
    .get();
  if (terminalSnap.empty) return 0;

  let deletedCount = 0;
  let batch = db.batch();
  let opCount = 0;
  const batches = [];

  for (const doc of terminalSnap.docs) {
    const data = doc.data() || {};
    const decision = evaluateQrCleanupAction(data, nowMillis);
    if (decision.action === 'delete') {
      batch.delete(doc.ref);
      deletedCount++;
      opCount++;
    } else if (decision.action === 'stamp_ttl' && decision.expireAtMillis > 0) {
      batch.update(doc.ref, {
        expireAt: admin.firestore.Timestamp.fromMillis(decision.expireAtMillis),
      });
      opCount++;
    }

    if (opCount === 500) {
      batches.push(batch);
      batch = db.batch();
      opCount = 0;
    }
  }

  if (opCount > 0) {
    batches.push(batch);
  }

  for (const b of batches) {
    await b.commit();
  }

  return deletedCount;
}

/**
 * Cascading cleanup executed when an `access_logs` document expires or is deleted:
 * 1. Deletes allow-listed `visitor_ids/` and `visitor_plates/` Cloud Storage files idempotently.
 * 2. Self-heals the linked `qr_codes` document if it was still marked `isInside: true` for this log.
 */
async function cleanupDeletedAccessLogResources({
  db,
  bucket,
  logId,
  logData,
  nowMillis = Date.now(),
}) {
  if (!logData || typeof logData !== 'object') {
    return { deletedFilesCount: 0, qrHealed: false };
  }

  const mediaPaths = new Set();
  const idPath = extractVisitorMediaStoragePath(logData.visitorIdPhotoUrl);
  if (idPath) mediaPaths.add(idPath);
  const platePath = extractVisitorMediaStoragePath(logData.visitorPlatePhotoUrl);
  if (platePath) mediaPaths.add(platePath);

  let deletedFilesCount = 0;
  if (bucket && mediaPaths.size > 0) {
    for (const storagePath of mediaPaths) {
      try {
        await bucket.file(storagePath).delete({ ignoreNotFound: true });
        deletedFilesCount++;
      } catch (err) {
        const code = err && (err.code || err.status);
        if (code !== 404 && code !== 'storage/object-not-found') {
          console.error(`Error deleting visitor media for access log ${logId}:`, code || 'unknown');
        }
      }
    }
  }

  let qrHealed = false;
  const rawQrId = logData.qrCodeId || logData.qrId;
  const qrCodeId = typeof rawQrId === 'string' ? rawQrId.trim() : '';
  if (db && logData.isInside === true && qrCodeId) {
    try {
      const qrRef = db.collection('qr_codes').doc(qrCodeId);
      await db.runTransaction(async (transaction) => {
        const qrSnap = await transaction.get(qrRef);
        if (!qrSnap.exists) return;
        const qrData = qrSnap.data() || {};
        if (
          qrData.isInside === true &&
          (!qrData.activeAccessLogId || qrData.activeAccessLogId === logId)
        ) {
          const expMillis = getQrExpiryMillis(qrData);
          const qrPatch = {
            isInside: false,
            activeAccessLogId: null,
          };

          if (isOneTimeQrCode(qrData) && !isTerminalQrStatus(qrData)) {
            qrPatch.status = 'deactivated (validated)';
            qrPatch.isValid = false;
            qrPatch.deactivatedAt = admin.firestore.Timestamp.fromMillis(nowMillis);
            qrPatch.expireAt = admin.firestore.Timestamp.fromMillis(computeQrCodeExpireAtMillis(nowMillis));
          } else if (expMillis > 0 && nowMillis > expMillis) {
            if (!isTerminalQrStatus(qrData)) {
              qrPatch.status = 'deactivated (expired)';
              qrPatch.isValid = false;
              qrPatch.deactivatedAt = admin.firestore.Timestamp.fromMillis(nowMillis);
            }
            qrPatch.expireAt = admin.firestore.Timestamp.fromMillis(computeQrCodeExpireAtMillis(nowMillis));
          } else if (isTerminalQrStatus(qrData) && !qrData.expireAt) {
            qrPatch.expireAt = admin.firestore.Timestamp.fromMillis(computeQrCodeExpireAtMillis(nowMillis));
          } else if (expMillis > nowMillis) {
            qrPatch.expireAt = admin.firestore.Timestamp.fromMillis(computeQrCodeExpireAtMillis(expMillis));
          }

          transaction.update(qrRef, qrPatch);
          qrHealed = true;
        }
      });
    } catch (qrErr) {
      console.error(`Error healing QR inside state for deleted access log ${logId}:`, qrErr.message || 'unknown');
    }
  }

  return { deletedFilesCount, qrHealed };
}

/**
 * Daily fallback job that deletes `access_logs` older than 60 days (including legacy
 * documents without `expireAt`) and cleans up their associated Cloud Storage media.
 */
async function purgeExpiredAccessLogs(
  db,
  bucket,
  nowMillis = Date.now(),
  batchLimit = 250,
  maxBatches = 4
) {
  const cutoffMillis = nowMillis - ACCESS_LOG_RETENTION_MS;
  const cutoffTimestamp = admin.firestore.Timestamp.fromMillis(cutoffMillis);
  const skippedIds = new Set();
  let totalDeleted = 0;

  for (let i = 0; i < maxBatches; i++) {
    const snap = await db
      .collection('access_logs')
      .where('timestamp', '<=', cutoffTimestamp)
      .limit(batchLimit)
      .get();
    if (snap.empty) break;

    const eligibleDocs = [];
    for (const doc of snap.docs) {
      if (skippedIds.has(doc.id)) continue;
      const data = doc.data() || {};
      const expireAtMillis = extractTimestampMillis(data.expireAt);
      if (expireAtMillis > 0) {
        if (nowMillis >= expireAtMillis) {
          eligibleDocs.push(doc);
        } else {
          skippedIds.add(doc.id);
        }
      } else {
        const refMillis =
          extractTimestampMillis(data.exitTimestamp) || extractTimestampMillis(data.timestamp);
        if (refMillis > 0 && nowMillis >= refMillis + ACCESS_LOG_RETENTION_MS) {
          eligibleDocs.push(doc);
        } else {
          skippedIds.add(doc.id);
        }
      }
    }

    if (eligibleDocs.length === 0) break;

    for (const doc of eligibleDocs) {
      await cleanupDeletedAccessLogResources({
        db,
        bucket,
        logId: doc.id,
        logData: doc.data() || {},
        nowMillis,
      });
    }

    const batch = db.batch();
    for (const doc of eligibleDocs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    totalDeleted += eligibleDocs.length;

    if (snap.size < batchLimit) break;
  }

  return totalDeleted;
}

/**
 * Firestore Trigger: Cleans up linked visitor ID/plate photos in Cloud Storage and
 * heals open `qr_codes` state whenever an `access_logs` document is deleted (via TTL or Admin).
 */
exports.onAccessLogDeleted = onDocumentDeleted('access_logs/{logId}', async (event) => {
  const logData = event.data ? event.data.data() : null;
  if (!logData) return;

  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  await cleanupDeletedAccessLogResources({
    db,
    bucket,
    logId: event.params.logId,
    logData,
  });
});

const BOOKING_ATTACHMENT_RETENTION_DAYS = 30;
const BOOKING_ATTACHMENT_RETENTION_MS = BOOKING_ATTACHMENT_RETENTION_DAYS * 24 * 60 * 60 * 1000;
const ALLOWED_BOOKING_DOC_EXTENSIONS = [
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'jpg',
  'jpeg',
  'png',
  'webp',
];
const MAX_BOOKING_ATTACHMENTS_COUNT = 10;
const MAX_BOOKING_ATTACHMENT_SIZE_BYTES = 10 * 1024 * 1024; // 10 MB

/**
 * Computes the millisecond expiration timestamp for booking attachments (+30 days after booking endTime).
 */
function computeBookingAttachmentExpireAtMillis(endTimeInput = Date.now()) {
  const endMillis =
    typeof endTimeInput === 'number' ? endTimeInput : (extractTimestampMillis(endTimeInput) || Date.now());
  return endMillis + BOOKING_ATTACHMENT_RETENTION_MS;
}

/**
 * Validates file header magic bytes against the declared allow-listed extension.
 * Rejects spoofed content (e.g., HTML/SVG/JS renamed to .pdf or .png).
 */
function validateDocumentMagicBytes(buffer, extension) {
  if (!buffer || !(Buffer.isBuffer(buffer) || buffer instanceof Uint8Array)) {
    return false;
  }
  const bytes = Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer);
  const ext = String(extension || '').trim().toLowerCase().replace(/^\./, '');

  switch (ext) {
    case 'pdf':
      return bytes.length >= 5 && bytes.subarray(0, 5).toString('ascii') === '%PDF-';
    case 'png':
      return (
        bytes.length >= 8 &&
        bytes[0] === 0x89 &&
        bytes[1] === 0x50 &&
        bytes[2] === 0x4e &&
        bytes[3] === 0x47 &&
        bytes[4] === 0x0d &&
        bytes[5] === 0x0a &&
        bytes[6] === 0x1a &&
        bytes[7] === 0x0a
      );
    case 'jpg':
    case 'jpeg':
      return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
    case 'webp':
      return (
        bytes.length >= 12 &&
        bytes.subarray(0, 4).toString('ascii') === 'RIFF' &&
        bytes.subarray(8, 12).toString('ascii') === 'WEBP'
      );
    case 'docx':
    case 'xlsx':
      // OOXML ZIP archive header (PK\x03\x04)
      return (
        bytes.length >= 4 &&
        bytes[0] === 0x50 &&
        bytes[1] === 0x4b &&
        bytes[2] === 0x03 &&
        bytes[3] === 0x04
      );
    case 'doc':
    case 'xls':
      // OLE2 Compound File Binary signature
      return (
        bytes.length >= 8 &&
        bytes[0] === 0xd0 &&
        bytes[1] === 0xcf &&
        bytes[2] === 0x11 &&
        bytes[3] === 0xe0 &&
        bytes[4] === 0xa1 &&
        bytes[5] === 0xb1 &&
        bytes[6] === 0x1a &&
        bytes[7] === 0xe1
      );
    default:
      return false;
  }
}

/**
 * Safely extracts and validates a Cloud Storage object path strictly within
 * `booking_attachments/<uid>/<filename>`. Rejects traversal sequences, null bytes,
 * backslashes, extra nesting, and paths outside `booking_attachments/`.
 */
function extractBookingAttachmentStoragePath(rawInput) {
  if (!rawInput || typeof rawInput !== 'string') return null;
  const trimmed = rawInput.trim();
  if (!trimmed || trimmed.includes('\0') || /%00/i.test(trimmed)) {
    return null;
  }

  let candidate = null;
  try {
    if (/^https?:\/\//i.test(trimmed)) {
      const parsed = new URL(trimmed);
      const restMatch = parsed.pathname.match(/^\/v0\/b\/[^/]+\/o\/(.+)$/);
      if (restMatch) {
        candidate = decodeURIComponent(restMatch[1]);
      } else if (parsed.hostname === 'storage.googleapis.com') {
        const gcsMatch = parsed.pathname.match(/^\/[^/]+\/(.+)$/);
        if (gcsMatch) {
          candidate = decodeURIComponent(gcsMatch[1]);
        }
      } else if (parsed.pathname.startsWith('/booking_attachments/')) {
        candidate = decodeURIComponent(parsed.pathname.slice(1));
      }
    } else if (/^gs:\/\//i.test(trimmed)) {
      const gsMatch = trimmed.match(/^gs:\/\/[^/]+\/(.+)$/);
      if (gsMatch) {
        candidate = decodeURIComponent(gsMatch[1]);
      }
    } else if (!trimmed.includes('://')) {
      candidate = decodeURIComponent(trimmed);
    }
  } catch (_) {
    return null;
  }

  if (!candidate || typeof candidate !== 'string') return null;
  if (
    candidate.includes('\0') ||
    candidate.includes('\\') ||
    candidate.startsWith('/') ||
    candidate.endsWith('/')
  ) {
    return null;
  }

  const segments = candidate.split('/');
  if (segments.length !== 3 || segments[0] !== 'booking_attachments') {
    return null;
  }
  if (segments.some((seg) => !seg || seg === '.' || seg === '..')) {
    return null;
  }

  const normalized = path.posix.normalize(candidate);
  if (normalized !== candidate) {
    return null;
  }

  if (!/^booking_attachments\/[A-Za-z0-9_-]{1,128}\/[A-Za-z0-9._-]{1,200}$/.test(normalized)) {
    return null;
  }

  return normalized;
}

/**
 * Validates and normalizes resident booking attachments against the facility's
 * configured `facilityDocuments` requirements (`mandatory_return`, `optional_return`, `informative`).
 * Verifies ownership of `booking_attachments/<callerUid>/...` paths and inspects Storage magic bytes.
 */
async function validateAndNormalizeBookingAttachments({
  rawAttachments,
  facilityDocuments,
  callerUid,
  existingAttachments = [],
  bucket = null,
  nowMillis = Date.now(),
}) {
  const templates = Array.isArray(facilityDocuments) ? facilityDocuments : [];
  const templateById = new Map();
  for (const rawTpl of templates) {
    if (!rawTpl || typeof rawTpl !== 'object') continue;
    const docId = String(rawTpl.docId || '').trim();
    if (!docId) continue;
    const rawMode = String(rawTpl.requirementMode || 'informative').trim().toLowerCase();
    const requirementMode = ['mandatory_return', 'optional_return', 'informative'].includes(rawMode)
      ? rawMode
      : 'informative';
    templateById.set(docId, {
      docId,
      title: String(rawTpl.title || rawTpl.fileName || docId).trim().slice(0, 200),
      requirementMode,
    });
  }

  if (rawAttachments !== undefined && rawAttachments !== null && !Array.isArray(rawAttachments)) {
    throw new HttpsError('invalid-argument', 'Booking attachments must be an array.');
  }
  const incomingList = Array.isArray(rawAttachments) ? rawAttachments : [];
  if (incomingList.length > MAX_BOOKING_ATTACHMENTS_COUNT) {
    throw new HttpsError(
      'invalid-argument',
      `Too many booking attachments (maximum ${MAX_BOOKING_ATTACHMENTS_COUNT}).`
    );
  }

  const existingPaths = new Set();
  if (Array.isArray(existingAttachments)) {
    for (const prev of existingAttachments) {
      const prevPath = extractBookingAttachmentStoragePath(prev?.storagePath || prev?.url);
      if (prevPath) existingPaths.add(prevPath);
    }
  }

  const seenDocIds = new Set();
  const normalized = [];

  for (const item of incomingList) {
    if (!item || typeof item !== 'object') {
      throw new HttpsError('invalid-argument', 'Each booking attachment must be an object.');
    }

    const facilityDocId = String(item.facilityDocId || '').trim();
    if (!facilityDocId || facilityDocId.length > 128) {
      throw new HttpsError('invalid-argument', 'Attachment is missing a valid facilityDocId.');
    }
    const template = templateById.get(facilityDocId);
    if (!template) {
      throw new HttpsError(
        'invalid-argument',
        `Attachment references unknown facility document "${facilityDocId}".`
      );
    }
    if (template.requirementMode === 'informative') {
      throw new HttpsError(
        'invalid-argument',
        `Facility document "${template.title}" is informative-only and does not accept uploads.`
      );
    }
    if (seenDocIds.has(facilityDocId)) {
      throw new HttpsError(
        'invalid-argument',
        `Duplicate attachment provided for facility document "${template.title}".`
      );
    }
    seenDocIds.add(facilityDocId);

    const baseName = path.posix.basename(String(item.fileName || '').trim());
    const safeFileName = baseName.replace(/[^a-zA-Z0-9._-]/g, '_');
    if (!safeFileName || safeFileName === '.' || safeFileName === '..' || safeFileName.length > 200) {
      throw new HttpsError('invalid-argument', 'Attachment fileName is invalid.');
    }

    const extFromName = safeFileName.includes('.')
      ? safeFileName.split('.').pop().toLowerCase()
      : '';
    const fileType = String(item.fileType || extFromName || '')
      .trim()
      .toLowerCase()
      .replace(/^\./, '');
    if (!ALLOWED_BOOKING_DOC_EXTENSIONS.includes(fileType)) {
      throw new HttpsError(
        'invalid-argument',
        `Unsupported attachment fileType "${fileType}". Allowed: ${ALLOWED_BOOKING_DOC_EXTENSIONS.join(', ')}.`
      );
    }
    if (extFromName) {
      const normalizedExtFromName = extFromName === 'jpeg' ? 'jpg' : extFromName;
      const normalizedDeclared = fileType === 'jpeg' ? 'jpg' : fileType;
      if (normalizedExtFromName !== normalizedDeclared) {
        throw new HttpsError('invalid-argument', 'Attachment fileName extension does not match fileType.');
      }
    }

    const numericSize = Number(item.fileSize);
    if (!Number.isFinite(numericSize) || numericSize <= 0 || numericSize > MAX_BOOKING_ATTACHMENT_SIZE_BYTES) {
      throw new HttpsError('invalid-argument', 'Attachment fileSize must be between 1 byte and 10 MB.');
    }

    const cleanUrl = String(item.url || '').trim();
    if (
      !cleanUrl ||
      cleanUrl.length > 2048 ||
      !(
        cleanUrl.startsWith('https://') ||
        cleanUrl.startsWith('http://127.0.0.1:') ||
        cleanUrl.startsWith('http://localhost:')
      )
    ) {
      throw new HttpsError('invalid-argument', 'Attachment URL must be a valid Storage download URL.');
    }

    const cleanStoragePath = extractBookingAttachmentStoragePath(item.storagePath || cleanUrl);
    if (!cleanStoragePath) {
      throw new HttpsError('invalid-argument', 'Attachment storagePath is invalid or outside booking_attachments/.');
    }

    const isCallerOwnedPath = cleanStoragePath.startsWith(`booking_attachments/${callerUid}/`);
    const isUnchangedExistingPath = existingPaths.has(cleanStoragePath);
    if (!isCallerOwnedPath && !isUnchangedExistingPath) {
      throw new HttpsError(
        'permission-denied',
        'Attachment storagePath must belong to the authenticated caller.'
      );
    }

    // TODO(security): Integrate with an antivirus API and CDR tool to scan and strip active macros/scripts from untrusted resident uploads.
    if (!isUnchangedExistingPath && bucket && typeof bucket.file === 'function') {
      const fileRef = bucket.file(cleanStoragePath);
      if (fileRef && typeof fileRef.download === 'function') {
        let headerBuf;
        try {
          const [downloaded] = await fileRef.download({ start: 0, end: 15 });
          headerBuf = downloaded;
        } catch (dlErr) {
          const code = dlErr && (dlErr.code || dlErr.status);
          if (code === 404 || code === 'storage/object-not-found') {
            throw new HttpsError('invalid-argument', 'Uploaded attachment file was not found in Cloud Storage.');
          }
          throw dlErr;
        }

        if (!validateDocumentMagicBytes(headerBuf, fileType)) {
          if (typeof fileRef.delete === 'function') {
            await fileRef.delete({ ignoreNotFound: true }).catch(() => {});
          }
          throw new HttpsError(
            'invalid-argument',
            `Attachment content does not match declared file type (${fileType}).`
          );
        }
      }
    }

    const uploadedAtNum = Number(item.uploadedAt);
    normalized.push({
      facilityDocId,
      title: template.title,
      requirementMode: template.requirementMode,
      fileName: safeFileName,
      fileType,
      fileSize: Math.floor(numericSize),
      url: cleanUrl,
      storagePath: cleanStoragePath,
      uploadedAt: Number.isFinite(uploadedAtNum) && uploadedAtNum > 0
        ? Math.floor(uploadedAtNum)
        : nowMillis,
    });
  }

  for (const template of templateById.values()) {
    if (template.requirementMode === 'mandatory_return' && !seenDocIds.has(template.docId)) {
      throw new HttpsError(
        'failed-precondition',
        `Missing mandatory document attachment: ${template.title}`
      );
    }
  }

  return normalized;
}

/**
 * Cascading cleanup executed when a `booking_attachments` document is deleted
 * (via cancellation, Firestore TTL, daily scheduled sweep, or admin action):
 * 1. Deletes allow-listed `booking_attachments/<uid>/<file>` Storage objects idempotently.
 * 2. Marks `attachmentsPurgedAt` on `bookings/{bookingId}` if the parent booking still exists.
 */
async function cleanupDeletedBookingAttachmentResources({
  db,
  bucket,
  bookingId,
  attachmentDocData,
  nowMillis = Date.now(),
}) {
  if (!attachmentDocData || typeof attachmentDocData !== 'object') {
    return { deletedFilesCount: 0, bookingUpdated: false };
  }

  const rawList = Array.isArray(attachmentDocData.attachments)
    ? attachmentDocData.attachments
    : [];
  const storagePaths = new Set();
  for (const att of rawList) {
    const cleanPath = extractBookingAttachmentStoragePath(att?.storagePath || att?.url);
    if (cleanPath) storagePaths.add(cleanPath);
  }

  let deletedFilesCount = 0;
  if (bucket && typeof bucket.file === 'function' && storagePaths.size > 0) {
    for (const storagePath of storagePaths) {
      try {
        await bucket.file(storagePath).delete({ ignoreNotFound: true });
        deletedFilesCount++;
      } catch (err) {
        const code = err && (err.code || err.status);
        if (code !== 404 && code !== 'storage/object-not-found') {
          console.error(`Error deleting booking attachment file for booking ${bookingId}:`, code || 'unknown');
        }
      }
    }
  }

  let bookingUpdated = false;
  if (db && bookingId && typeof bookingId === 'string') {
    try {
      const bookingRef = db.collection('bookings').doc(bookingId);
      const bookingSnap = await bookingRef.get();
      if (bookingSnap.exists) {
        const bData = bookingSnap.data() || {};
        if (!bData.attachmentsPurgedAt) {
          await bookingRef.update({ attachmentsPurgedAt: nowMillis });
          bookingUpdated = true;
        }
      }
    } catch (bErr) {
      console.error(`Error updating attachmentsPurgedAt for booking ${bookingId}:`, bErr.message || 'unknown');
    }
  }

  return { deletedFilesCount, bookingUpdated };
}

/**
 * Daily fallback job that deletes `booking_attachments` whose booking `endTime + 30 days`
 * retention window has elapsed, cleaning up their Cloud Storage files and stamping
 * `attachmentsPurgedAt` on the parent `bookings/{bookingId}` document.
 */
async function purgeExpiredBookingAttachments(
  db,
  bucket,
  nowMillis = Date.now(),
  batchLimit = 250,
  maxBatches = 4
) {
  const cutoffEndTimeMillis = nowMillis - BOOKING_ATTACHMENT_RETENTION_MS;
  const skippedIds = new Set();
  let totalDeleted = 0;

  for (let i = 0; i < maxBatches; i++) {
    const snap = await db
      .collection('booking_attachments')
      .where('bookingEndTime', '<=', cutoffEndTimeMillis)
      .limit(batchLimit)
      .get();
    if (snap.empty) break;

    const eligibleDocs = [];
    for (const doc of snap.docs) {
      if (skippedIds.has(doc.id)) continue;
      const data = doc.data() || {};
      const expireAtMillis = extractTimestampMillis(data.expireAt);
      if (expireAtMillis > 0) {
        if (nowMillis >= expireAtMillis) {
          eligibleDocs.push(doc);
        } else {
          skippedIds.add(doc.id);
        }
      } else {
        const endMillis = extractTimestampMillis(data.bookingEndTime);
        if (endMillis > 0 && nowMillis >= endMillis + BOOKING_ATTACHMENT_RETENTION_MS) {
          eligibleDocs.push(doc);
        } else {
          skippedIds.add(doc.id);
        }
      }
    }

    if (eligibleDocs.length === 0) break;

    for (const doc of eligibleDocs) {
      await cleanupDeletedBookingAttachmentResources({
        db,
        bucket,
        bookingId: doc.id,
        attachmentDocData: doc.data() || {},
        nowMillis,
      });
    }

    const batch = db.batch();
    for (const doc of eligibleDocs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    totalDeleted += eligibleDocs.length;

    if (snap.size < batchLimit) break;
  }

  return totalDeleted;
}

/**
 * Firestore Trigger: Cleans up linked resident booking attachments in Cloud Storage
 * and stamps `attachmentsPurgedAt` whenever a `booking_attachments/{bookingId}` document
 * is deleted (via Firestore TTL, cancellation, or Admin).
 */
exports.onBookingAttachmentDeleted = onDocumentDeleted(
  'booking_attachments/{bookingId}',
  async (event) => {
    const attachmentDocData = event.data ? event.data.data() : null;
    if (!attachmentDocData) return;

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    await cleanupDeletedBookingAttachmentResources({
      db,
      bucket,
      bookingId: event.params.bookingId,
      attachmentDocData,
    });
  }
);

/**
 * Extracts a millisecond epoch timestamp from Firestore Timestamp, Date, number, ISO string, or serialized map.
 */
function extractTimestampMillis(val) {
  if (!val) return 0;
  if (typeof val.toMillis === 'function') {
    return val.toMillis();
  }
  if (val instanceof Date) {
    return val.getTime();
  }
  if (typeof val === 'object' && typeof val._seconds === 'number') {
    return val._seconds * 1000;
  }
  if (typeof val === 'number') {
    return val;
  }
  if (typeof val === 'string') {
    const parsed = new Date(val).getTime();
    return isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

/**
 * Checks whether two millisecond epoch timestamps fall on the same calendar day in the given IANA timezone.
 */
function isSameCalendarDayInTimezone(tsMillisA, tsMillisB, timeZone = 'America/Mexico_City') {
  if (!tsMillisA || !tsMillisB) return false;
  const dateA = getDateInTimezone(tsMillisA, timeZone);
  const dateB = getDateInTimezone(tsMillisB, timeZone);
  return dateA.year === dateB.year && dateA.month === dateB.month && dateA.day === dateB.day;
}

/**
 * Determines whether a QR pass currently has an open visit (inside the community) and returns the open log snapshot.
 * - Explicit open visit: `qrData.isInside === true` (via `directLogSnap` or latest open allowed doc in `candidateLogDocs`).
 * - Legacy fallback: when `qrData.isInside` is undefined/null (legacy QR created before exit tracking),
 *   a second scan within the same calendar day defaults `isInside` to `true` if the latest allowed log today
 *   has no `exitTimestamp` and `isInside !== false`.
 */
function resolveOpenVisitLog({
  qrData,
  directLogSnap = null,
  candidateLogDocs = [],
  nowMillis = Date.now(),
  timeZone = 'America/Mexico_City',
}) {
  if (!qrData || typeof qrData !== 'object') return null;

  if (qrData.isInside === true) {
    if (directLogSnap && directLogSnap.exists) {
      const d = directLogSnap.data() || {};
      if (!d.exitTimestamp && d.isInside !== false) {
        return directLogSnap;
      }
    }
    for (const doc of candidateLogDocs) {
      const d = doc.data ? (doc.data() || {}) : doc;
      if (d.status === 'allowed' && !d.exitTimestamp && d.isInside !== false) {
        return doc;
      }
    }
    return null;
  }

  // Legacy QR fallback: `isInside` not present on QR document -> check same-day allowed log without exitTimestamp
  if (qrData.isInside === undefined || qrData.isInside === null) {
    for (const doc of candidateLogDocs) {
      const d = doc.data ? (doc.data() || {}) : doc;
      const logMillis = extractTimestampMillis(d.timestamp);
      if (!isSameCalendarDayInTimezone(logMillis, nowMillis, timeZone)) {
        continue;
      }
      if (d.status === 'allowed') {
        if (!d.exitTimestamp && d.isInside !== false) {
          return doc;
        }
        // Latest allowed log today already exited
        return null;
      }
    }
  }

  return null;
}

/**
 * Validates a QR code and registers physical access or exit atomically in Cloud Functions.
 * Enforces:
 * - Guard or Admin caller authentication
 * - Automatic Exit detection when `scanOnExitEnabled` is active (including legacy same-day QR fallback)
 * - QR existence and validity status on entry
 * - Temporary pass expiration against server clock on entry
 * - Linked resident address paymentStatus == 'paid' on entry
 * - Single-use pass invalidation upon entry (or upon exit when `scanOnExitEnabled` is active)
 * - Atomic audit entry / exit timestamp and 60-day `expireAt` TTL update in access_logs
 * - 7-day `expireAt` TTL stamping on terminal qr_codes (held null while `isInside == true`)
 */
exports.validateAndRegisterQrAccess = onCall(callableOptions, async (request) => {
  if (!request.auth || (!request.auth.token.guard && !request.auth.token.admin)) {
    throw new HttpsError('permission-denied', 'Function must be called by an authenticated guard or admin.');
  }

  const {
    qrId,
    isAllowed = true,
    visitorIdPhotoUrl = '',
    visitorPlatePhotoUrl = '',
    reason = '',
    mode = 'validate_and_register', // 'validate_only' or 'validate_and_register'
  } = request.data || {};

  if (!qrId || typeof qrId !== 'string') {
    throw new HttpsError('invalid-argument', 'Valid qrId must be provided.');
  }

  const sanitizedReason = typeof reason === 'string' ? reason.trim().slice(0, 500) : '';

  const db = admin.firestore();
  const guardUid = request.auth.uid;
  const qrRef = db.collection('qr_codes').doc(qrId);

  return await db.runTransaction(async (transaction) => {
    // 0. Fetch guard record, app settings, and QR document first (all reads before writes)
    const guardSnap = await transaction.get(db.collection('users').doc(guardUid));
    const guardName = (guardSnap.exists && guardSnap.data()?.name) ? guardSnap.data().name : 'Security Guard';

    const appSettingsSnap = await transaction.get(db.collection('config').doc('app_settings'));
    const appSettings = appSettingsSnap.exists ? (appSettingsSnap.data() || {}) : {};
    const scanOnExitEnabled = appSettings.scanOnExitEnabled === true;
    const timeZone = appSettings.timeZone || 'America/Mexico_City';

    const qrSnap = await transaction.get(qrRef);
    if (!qrSnap.exists) {
      return {
        success: false,
        granted: false,
        isExit: false,
        reason: 'QR Code not found.',
        qrData: null,
      };
    }

    const qrData = qrSnap.data();
    const now = admin.firestore.Timestamp.now();
    const nowMillis = now.toMillis();
    const accessLogExpireAt = admin.firestore.Timestamp.fromMillis(computeAccessLogExpireAtMillis(nowMillis));

    // Resolve Resident and Address data
    let residentName = '';
    let addressDisplay = '';
    let streetName = '';
    let houseNumber = '';
    let addressRef = null;
    let isPaymentRestricted = false;

    if (qrData.creatorUid) {
      const userRef = db.collection('users').doc(qrData.creatorUid);
      const userSnap = await transaction.get(userRef);
      if (userSnap.exists) {
        const userData = userSnap.data();
        residentName = userData.name || '';
        if (userData.addressRef) {
          addressRef = userData.addressRef;
          const addrRef = typeof userData.addressRef === 'string'
            ? db.doc(userData.addressRef)
            : userData.addressRef;
          const addrSnap = await transaction.get(addrRef);
          if (addrSnap.exists) {
            const addrData = addrSnap.data();
            streetName = addrData.streetName || '';
            houseNumber = addrData.number != null ? addrData.number.toString() : '';
            addressDisplay = `${streetName} #${houseNumber}`.trim();
            if (addrData.paymentStatus) {
              const isWithinGrace = addrData.isWithinGracePeriod === true;
              const isConsideredPaid = addrData.paymentStatus === 'paid' ||
                ((addrData.paymentStatus === 'pending' || addrData.paymentStatus === 'reviewing') && isWithinGrace);
              if (!isConsideredPaid) {
                isPaymentRestricted = true;
              }
            }
          }
        }
      }
    }

    // Perform open visit read if scanOnExitEnabled is active
    let directLogSnap = null;
    let candidateLogDocs = [];
    if (scanOnExitEnabled) {
      if (qrData.isInside === true && qrData.activeAccessLogId) {
        directLogSnap = await transaction.get(db.collection('access_logs').doc(qrData.activeAccessLogId));
      }
      const needsQuery = !directLogSnap || !directLogSnap.exists || Boolean((directLogSnap.data() || {}).exitTimestamp);
      if (needsQuery && (qrData.isInside === true || qrData.isInside === undefined || qrData.isInside === null)) {
        const recentLogsQuery = db.collection('access_logs')
          .where('qrCodeId', '==', qrId)
          .orderBy('timestamp', 'desc')
          .limit(5);
        const recentLogsSnap = await transaction.get(recentLogsQuery);
        candidateLogDocs = recentLogsSnap.docs || [];
      }
    }

    const isOneTime = isOneTimeQrCode(qrData);
    const guestName = qrData.guestName || qrData.visitorName || 'Guest';
    const accessCategory = qrData.accessCategory || (isOneTime ? 'supplier' : 'visitor');
    const vehicleType = qrData.vehicleType || 'walking';
    const vehiclePlates = qrData.vehiclePlates || qrData.vehiclePlate || '';
    const passengers = qrData.passengers || 0;
    const expMillis = getQrExpiryMillis(qrData);

    const responseQrData = {
      id: qrId,
      visitorName: guestName,
      guestName: guestName,
      vehicleType: vehicleType,
      vehiclePlate: vehiclePlates,
      vehiclePlates: vehiclePlates,
      passengers: passengers,
      type: qrData.type || 'temporary',
      accessCategory: accessCategory,
      creatorUid: qrData.creatorUid || '',
      residentName: residentName,
      addressDisplay: addressDisplay,
      isOneTime: isOneTime,
      isOneTimeUse: isOneTime,
    };

    // EXIT BRANCH: Automatic exit detection when scanOnExitEnabled is active
    if (scanOnExitEnabled) {
      const openLogSnap = resolveOpenVisitLog({
        qrData,
        directLogSnap,
        candidateLogDocs,
        nowMillis,
        timeZone,
      });

      if (openLogSnap || qrData.isInside === true) {
        const openLogData = openLogSnap ? (openLogSnap.data() || {}) : {};
        const openLogSummary = {
          id: openLogSnap ? openLogSnap.id : '',
          entryTimestampMillis: extractTimestampMillis(openLogData.timestamp),
          guardName: openLogData.guardName || '',
          visitorIdPhotoUrl: openLogData.visitorIdPhotoUrl || '',
          visitorPlatePhotoUrl: openLogData.visitorPlatePhotoUrl || '',
          reason: openLogData.reason || '',
        };

        if (mode === 'validate_only') {
          return {
            success: true,
            granted: true,
            isExit: true,
            reason: 'Exit scan ready.',
            qrData: responseQrData,
            openLog: openLogSummary,
          };
        }

        // Register exit on the open access log and extend 60-day TTL from exit time
        if (openLogSnap) {
          transaction.update(openLogSnap.ref, {
            exitTimestamp: FieldValue.serverTimestamp(),
            expireAt: accessLogExpireAt,
            isInside: false,
            exitGuardUid: guardUid,
            exitGuardName: guardName,
            exitReason: sanitizedReason,
          });
        }

        const qrExitUpdates = {
          isInside: false,
          activeAccessLogId: null,
        };
        if (isOneTime) {
          qrExitUpdates.status = 'deactivated (validated)';
          qrExitUpdates.isValid = false;
          qrExitUpdates.usedAt = FieldValue.serverTimestamp();
          qrExitUpdates.deactivatedAt = FieldValue.serverTimestamp();
          qrExitUpdates.expireAt = admin.firestore.Timestamp.fromMillis(
            computeQrCodeExpireAtMillis(nowMillis)
          );
        } else if (expMillis > 0 && nowMillis > expMillis) {
          if (qrData.status === 'active') {
            qrExitUpdates.status = 'deactivated (expired)';
            qrExitUpdates.isValid = false;
            qrExitUpdates.deactivatedAt = FieldValue.serverTimestamp();
          }
          qrExitUpdates.expireAt = admin.firestore.Timestamp.fromMillis(
            computeQrCodeExpireAtMillis(Math.max(expMillis, nowMillis))
          );
        } else if (expMillis > nowMillis) {
          qrExitUpdates.expireAt = admin.firestore.Timestamp.fromMillis(
            computeQrCodeExpireAtMillis(expMillis)
          );
        } else {
          qrExitUpdates.expireAt = null;
        }
        transaction.update(qrRef, qrExitUpdates);

        return {
          success: true,
          granted: true,
          isExit: true,
          reason: 'Exit registered.',
          qrData: responseQrData,
          openLog: openLogSummary,
        };
      }
    }

    // ENTRY BRANCH
    // 1. Check validity status
    const validityCheck = evaluateQrValidityStatus(qrData);
    if (!validityCheck.isValid) {
      const statusReason = validityCheck.reason;

      if (mode === 'validate_and_register') {
        const logRef = db.collection('access_logs').doc();
        transaction.set(logRef, {
          qrCodeId: qrId,
          guardUid: guardUid,
          guardName: guardName,
          creatorUid: qrData.creatorUid || 'unknown',
          residentName: residentName,
          guestName: guestName,
          accessCategory: accessCategory,
          vehicleType: vehicleType,
          vehiclePlates: vehiclePlates,
          passengers: passengers,
          streetName: streetName,
          number: houseNumber,
          addressDisplay: addressDisplay,
          addressRef: addressRef,
          timestamp: FieldValue.serverTimestamp(),
          exitTimestamp: null,
          expireAt: accessLogExpireAt,
          isInside: false,
          visitorIdPhotoUrl: visitorIdPhotoUrl || '',
          visitorPlatePhotoUrl: visitorPlatePhotoUrl || '',
          status: 'denied',
          reason: statusReason,
        });
      }

      return {
        success: true,
        granted: false,
        isExit: false,
        reason: statusReason,
        qrData: responseQrData,
      };
    }

    // 2. Check expiration for temporary passes
    if (expMillis > 0 && nowMillis > expMillis) {
      if (qrData.status === 'active') {
        transaction.update(qrRef, {
          status: 'deactivated (expired)',
          isValid: false,
          deactivatedAt: FieldValue.serverTimestamp(),
          expireAt: admin.firestore.Timestamp.fromMillis(computeQrCodeExpireAtMillis(expMillis)),
        });
      }

      if (mode === 'validate_and_register') {
        const logRef = db.collection('access_logs').doc();
        transaction.set(logRef, {
          qrCodeId: qrId,
          guardUid: guardUid,
          guardName: guardName,
          creatorUid: qrData.creatorUid || 'unknown',
          residentName: residentName,
          guestName: guestName,
          accessCategory: accessCategory,
          vehicleType: vehicleType,
          vehiclePlates: vehiclePlates,
          passengers: passengers,
          streetName: streetName,
          number: houseNumber,
          addressDisplay: addressDisplay,
          addressRef: addressRef,
          timestamp: FieldValue.serverTimestamp(),
          exitTimestamp: null,
          expireAt: accessLogExpireAt,
          isInside: false,
          visitorIdPhotoUrl: visitorIdPhotoUrl || '',
          visitorPlatePhotoUrl: visitorPlatePhotoUrl || '',
          status: 'denied',
          reason: 'QR Code has expired.',
        });
      }

      return {
        success: true,
        granted: false,
        isExit: false,
        reason: 'QR Code has expired.',
        qrData: responseQrData,
      };
    }

    // 3. Verify creator resident address payment standing
    if (isPaymentRestricted) {
      if (mode === 'validate_and_register') {
        const logRef = db.collection('access_logs').doc();
        transaction.set(logRef, {
          qrCodeId: qrId,
          guardUid: guardUid,
          guardName: guardName,
          creatorUid: qrData.creatorUid,
          residentName: residentName,
          guestName: guestName,
          accessCategory: accessCategory,
          vehicleType: vehicleType,
          vehiclePlates: vehiclePlates,
          passengers: passengers,
          streetName: streetName,
          number: houseNumber,
          addressDisplay: addressDisplay,
          addressRef: addressRef,
          timestamp: FieldValue.serverTimestamp(),
          exitTimestamp: null,
          expireAt: accessLogExpireAt,
          isInside: false,
          visitorIdPhotoUrl: visitorIdPhotoUrl || '',
          visitorPlatePhotoUrl: visitorPlatePhotoUrl || '',
          status: 'denied',
          reason: 'Resident address payment status is restricted or unpaid.',
        });
      }

      return {
        success: true,
        granted: false,
        isExit: false,
        reason: 'Resident address payment status is restricted or unpaid.',
        qrData: responseQrData,
      };
    }

    // 4. If mode is validate_only, return validity preview without registering
    if (mode === 'validate_only') {
      return {
        success: true,
        granted: true,
        isExit: false,
        reason: 'Access granted.',
        qrData: responseQrData,
      };
    }

    // 5. Prepare access_logs reference and update qr_codes state
    const logRef = db.collection('access_logs').doc();
    const markInside = Boolean(isAllowed && scanOnExitEnabled);

    if (isAllowed) {
      if (scanOnExitEnabled) {
        transaction.update(qrRef, {
          isInside: true,
          activeAccessLogId: logRef.id,
          expireAt: null,
        });
      } else if (isOneTime) {
        transaction.update(qrRef, {
          status: 'deactivated (validated)',
          isValid: false,
          usedAt: FieldValue.serverTimestamp(),
          deactivatedAt: FieldValue.serverTimestamp(),
          expireAt: admin.firestore.Timestamp.fromMillis(computeQrCodeExpireAtMillis(nowMillis)),
          isInside: false,
          activeAccessLogId: null,
        });
      } else if (qrData.isInside === true || qrData.activeAccessLogId) {
        transaction.update(qrRef, {
          isInside: false,
          activeAccessLogId: null,
          expireAt: expMillis > 0
            ? admin.firestore.Timestamp.fromMillis(computeQrCodeExpireAtMillis(expMillis))
            : null,
        });
      }
    }

    // 6. Write to access_logs
    transaction.set(logRef, {
      qrCodeId: qrId,
      guardUid: guardUid,
      guardName: guardName,
      creatorUid: qrData.creatorUid || 'unknown',
      residentName: residentName,
      guestName: guestName,
      accessCategory: accessCategory,
      vehicleType: vehicleType,
      vehiclePlates: vehiclePlates,
      passengers: passengers,
      streetName: streetName,
      number: houseNumber,
      addressDisplay: addressDisplay,
      addressRef: addressRef,
      timestamp: FieldValue.serverTimestamp(),
      exitTimestamp: null,
      expireAt: accessLogExpireAt,
      isInside: markInside,
      visitorIdPhotoUrl: visitorIdPhotoUrl || '',
      visitorPlatePhotoUrl: visitorPlatePhotoUrl || '',
      status: isAllowed ? 'allowed' : 'denied',
      reason: sanitizedReason || (isAllowed ? 'Access granted' : 'Denied by guard'),
    });

    return {
      success: true,
      granted: isAllowed,
      isExit: false,
      reason: isAllowed ? 'Access granted.' : (sanitizedReason || 'Denied by guard'),
      qrData: responseQrData,
    };
  });
});

const ALLOWED_DOCUMENT_VISIBILITIES = ['all', 'admin'];
const ALLOWED_DOCUMENT_FILE_TYPES = ['pdf', 'md', 'txt', 'docx', 'xlsx', 'csv', 'png', 'jpg', 'jpeg', 'webp'];
const MAX_DOCUMENT_SIZE_BYTES = 10 * 1024 * 1024; // 10 MB limit

/**
 * Validates and normalizes input parameters for publishing/syncing a document
 * into the Transparency section.
 */
function validateTransparencyDocInput(data) {
  if (!data || typeof data !== 'object') {
    throw new HttpsError('invalid-argument', 'Document payload must be a valid object.');
  }

  const rawTitle = (data.title || '').toString().trim();
  if (!rawTitle || rawTitle.length > 200) {
    throw new HttpsError('invalid-argument', 'Document title is required and must be at most 200 characters.');
  }

  const rawFileName = path.basename((data.fileName || '').toString().trim());
  const safeFileName = rawFileName.replace(/[^a-zA-Z0-9._-]/g, '_');
  if (!safeFileName || safeFileName === '.' || safeFileName === '..' || safeFileName.length > 200) {
    throw new HttpsError('invalid-argument', 'A valid fileName is required.');
  }

  const extFromFile = safeFileName.includes('.')
    ? safeFileName.split('.').pop().toLowerCase()
    : '';
  const fileType = ((data.fileType || extFromFile || 'pdf').toString().trim().toLowerCase());
  if (!ALLOWED_DOCUMENT_FILE_TYPES.includes(fileType)) {
    throw new HttpsError(
      'invalid-argument',
      `Unsupported fileType "${fileType}". Allowed types: ${ALLOWED_DOCUMENT_FILE_TYPES.join(', ')}`
    );
  }

  const visibility = ((data.visibility || 'all').toString().trim().toLowerCase());
  if (!ALLOWED_DOCUMENT_VISIBILITIES.includes(visibility)) {
    throw new HttpsError(
      'invalid-argument',
      `Invalid visibility "${visibility}". Allowed values: ${ALLOWED_DOCUMENT_VISIBILITIES.join(', ')}`
    );
  }

  const rawDocId = (data.docId || data.id || '').toString().trim();
  const safeDocId = rawDocId ? rawDocId.replace(/[^a-zA-Z0-9_-]/g, '_') : '';

  const category = ((data.category || 'manuals').toString().trim().toLowerCase()).replace(/[^a-z0-9_-]/g, '_');
  const categoryName = (data.categoryName || 'Manuales / Manuals').toString().trim().slice(0, 100);
  const folderId = ((data.folderId || 'root').toString().trim()).replace(/[^a-zA-Z0-9_-]/g, '_') || 'root';
  const folderName = (data.folderName || '').toString().trim().slice(0, 120);

  return {
    docId: safeDocId,
    title: rawTitle,
    fileName: safeFileName,
    fileType,
    visibility,
    category: category || 'manuals',
    categoryName,
    folderId,
    folderName,
  };
}

/**
 * Callable Cloud Function: syncTransparencyDocument
 * Populates or updates a document in the Transparency section (`documents` collection),
 * optionally uploading the binary PDF/file to Cloud Storage using the Service Account
 * and enforcing document visibility ('all' vs 'admin').
 */
exports.syncTransparencyDocument = onCall(callableOptions, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Only administrators can sync transparency documents.');
  }

  const validated = validateTransparencyDocInput(request.data || {});
  const db = admin.firestore();
  const uploaderUid = request.auth.uid;

  let downloadUrl = (request.data.url || '').toString().trim();
  let storagePath = (request.data.storagePath || '').toString().trim();
  let fileSize = typeof request.data.fileSize === 'number' && request.data.fileSize >= 0
    ? request.data.fileSize
    : 0;

  // If base64 file content is provided, upload directly to Cloud Storage via Admin SDK
  if (request.data.fileBase64 && typeof request.data.fileBase64 === 'string') {
    const fileBuffer = Buffer.from(request.data.fileBase64, 'base64');
    if (fileBuffer.length === 0 || fileBuffer.length > MAX_DOCUMENT_SIZE_BYTES) {
      throw new HttpsError('invalid-argument', 'File size must be between 1 byte and 10 MB.');
    }

    // Validate PDF magic bytes header (%PDF-) when fileType is pdf
    if (validated.fileType === 'pdf') {
      const magicHeader = fileBuffer.subarray(0, 5).toString('ascii');
      if (magicHeader !== '%PDF-') {
        throw new HttpsError('invalid-argument', 'Invalid PDF content: missing %PDF- magic header.');
      }
    }

    // TODO(security): Integrate with an antivirus API and CDR tool to scan and strip active macros/scripts if untrusted uploads are accepted.
    fileSize = fileBuffer.length;
    const prefix = validated.visibility === 'admin' ? 'documents/admin_only' : 'documents';
    const uniqueId = crypto.randomUUID();
    storagePath = `${prefix}/${validated.docId || uniqueId}_${validated.fileName}`;

    const bucket = admin.storage().bucket();
    const fileRef = bucket.file(storagePath);
    const downloadToken = crypto.randomUUID();

    await fileRef.save(fileBuffer, {
      resumable: false,
      metadata: {
        contentType: validated.fileType === 'pdf' ? 'application/pdf' : 'application/octet-stream',
        contentDisposition: `attachment; filename="${validated.fileName}"`,
        metadata: {
          firebaseStorageDownloadTokens: downloadToken,
          visibility: validated.visibility,
          uploaderUid,
        },
      },
    });

    const encodedPath = encodeURIComponent(storagePath);
    downloadUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${downloadToken}`;
  }

  if (!downloadUrl) {
    throw new HttpsError('invalid-argument', 'Either fileBase64 or a valid Storage url must be provided.');
  }

  // Ensure document category exists
  if (validated.category) {
    const catRef = db.collection('document_categories').doc(validated.category);
    const catSnap = await catRef.get();
    if (!catSnap.exists) {
      await catRef.set({
        name: validated.categoryName || validated.category,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  }

  // Ensure target virtual folder exists if not root
  if (validated.folderId !== 'root' && validated.folderName) {
    const folderRef = db.collection('document_folders').doc(validated.folderId);
    const folderSnap = await folderRef.get();
    if (!folderSnap.exists) {
      await folderRef.set({
        name: validated.folderName,
        parentId: 'root',
        createdAt: FieldValue.serverTimestamp(),
        createdBy: uploaderUid,
      });
    }
  }

  const docRef = validated.docId
    ? db.collection('documents').doc(validated.docId)
    : db.collection('documents').doc();

  const existingSnap = await docRef.get();
  const now = FieldValue.serverTimestamp();

  const docData = {
    title: validated.title,
    fileName: validated.fileName,
    fileType: validated.fileType,
    fileSize,
    category: validated.category,
    folderId: validated.folderId,
    visibility: validated.visibility,
    url: downloadUrl,
    storagePath,
    publicationDate: now,
    updatedAt: now,
    uploaderUid,
  };

  if (!existingSnap.exists) {
    docData.uploadedAt = now;
  }

  await docRef.set(docData, { merge: true });

  return {
    success: true,
    docId: docRef.id,
    visibility: validated.visibility,
    url: downloadUrl,
    storagePath,
  };
});

// Export internal helper functions and configurations for unit testing
exports._test = {
  generateSecurePassword,
  isPasswordCompliant,
  replacePlaceholders,
  getDateInTimezone,
  getNowInTimezone,
  validateDeliveryDate,
  validateFacilityBooking,
  resolveFacilityRestriction,
  isCountedBookingForRestriction,
  addCooldownOffset,
  validateHouseholdBookingRestriction,
  recalculateAddressPaymentStatus,
  validateTransparencyDocInput,
  isEmulator,
  callableOptions,
  BRAND_COLORS,
  buildWelcomeEmailHtml,
  GEMINI_MODEL,
  GEMINI_LOCATION,
  isOneTimeQrCode,
  evaluateQrValidityStatus,
  getQrExpiryMillis,
  expireOutdatedQrCodes,
  extractTimestampMillis,
  isSameCalendarDayInTimezone,
  resolveOpenVisitLog,
  ACCESS_LOG_RETENTION_DAYS,
  ACCESS_LOG_RETENTION_MS,
  QR_CODE_RETENTION_DAYS,
  QR_CODE_RETENTION_MS,
  TERMINAL_QR_STATUSES,
  computeAccessLogExpireAtMillis,
  computeQrCodeExpireAtMillis,
  extractVisitorMediaStoragePath,
  isTerminalQrStatus,
  evaluateQrCleanupAction,
  purgeExpiredQrCodes,
  cleanupDeletedAccessLogResources,
  purgeExpiredAccessLogs,
  BOOKING_ATTACHMENT_RETENTION_DAYS,
  BOOKING_ATTACHMENT_RETENTION_MS,
  ALLOWED_BOOKING_DOC_EXTENSIONS,
  MAX_BOOKING_ATTACHMENTS_COUNT,
  MAX_BOOKING_ATTACHMENT_SIZE_BYTES,
  computeBookingAttachmentExpireAtMillis,
  validateDocumentMagicBytes,
  extractBookingAttachmentStoragePath,
  validateAndNormalizeBookingAttachments,
  cleanupDeletedBookingAttachmentResources,
  purgeExpiredBookingAttachments,
  parsePeriodHeader,
  normalizeStreetName,
  admin,
};

