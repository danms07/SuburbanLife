const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const { GoogleGenAI } = require('@google/genai');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
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

  const { facilityId, startTime, endTime } = request.data;
  if (!facilityId || !startTime || !endTime) {
    throw new HttpsError('invalid-argument', 'Missing facilityId, startTime, or endTime.');
  }

  const uid = request.auth.uid;

  try {
    // 0. Check payment status
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    if (userDoc.exists) {
      const addressRef = userDoc.data().addressRef;
      if (addressRef) {
        const addressDoc = await addressRef.get();
        const status = addressDoc.exists ? addressDoc.data().paymentStatus : null;
        const isWithinGrace = addressDoc.exists ? addressDoc.data().isWithinGracePeriod === true : false;
        const isConsideredPaid = status === 'paid' ||
          ((status === 'pending' || status === 'reviewing') && isWithinGrace);
        if (!isConsideredPaid) {
          throw new HttpsError('permission-denied', 'Your account is restricted due to missing payment.');
        }
      }
    }

    // 1. Dynamic Cooldown validation fetched from facilities collection
    const facilityDoc = await admin.firestore().collection('facilities').doc(facilityId).get();
    if (!facilityDoc.exists) {
      throw new HttpsError('not-found', 'Facility not found.');
    }
    
    const facData = facilityDoc.data();
    // 1. Anticipation & Operating Hours validation
    let timeZone = 'America/Mexico_City';
    try {
      const configDoc = await admin.firestore().collection('config').doc('app_settings').get();
      if (configDoc.exists && configDoc.data().timeZone) {
        timeZone = configDoc.data().timeZone;
      }
    } catch (e) {}

    validateFacilityBooking({ facData, startTime, endTime, timeZone, now: Date.now() });

    const cooldownUnit = facData.cooldownUnit || 'unrestricted';
    const cooldownValue = facData.cooldownValue || 0;

    if (cooldownUnit !== 'unrestricted') {
      let startTimeBoundary = 0;
      let endTimeBoundary = Infinity;
      if (cooldownUnit === 'days') {
        const ms = cooldownValue * 24 * 60 * 60 * 1000;
        startTimeBoundary = startTime - ms;
        endTimeBoundary = startTime + ms;
      } else if (cooldownUnit === 'months') {
        const dateBefore = new Date(startTime);
        dateBefore.setMonth(dateBefore.getMonth() - cooldownValue);
        startTimeBoundary = dateBefore.getTime();
        const dateAfter = new Date(startTime);
        dateAfter.setMonth(dateAfter.getMonth() + cooldownValue);
        endTimeBoundary = dateAfter.getTime();
      } else if (cooldownUnit === 'years') {
        const dateBefore = new Date(startTime);
        dateBefore.setFullYear(dateBefore.getFullYear() - cooldownValue);
        startTimeBoundary = dateBefore.getTime();
        const dateAfter = new Date(startTime);
        dateAfter.setFullYear(dateAfter.getFullYear() + cooldownValue);
        endTimeBoundary = dateAfter.getTime();
      }

      const recentBookings = await admin.firestore().collection('bookings')
        .where('userUid', '==', uid)
        .where('facilityId', '==', facilityId)
        .where('startTime', '>=', startTimeBoundary)
        .get();

      // The booking restriction should only be applied once the booking is confirmed
      const confirmedBookings = recentBookings.docs.filter((doc) => {
        const b = doc.data();
        const status = (b.status || '').toLowerCase();
        const isConfirmed = status.startsWith('approved') || status === 'confirmed' || status === 'closed';
        if (!isConfirmed) return false;
        const bStart = typeof b.startTime === 'number' ? b.startTime : (b.startTime ? b.startTime.toMillis() : 0);
        return bStart >= startTimeBoundary && bStart <= endTimeBoundary;
      });

      if (confirmedBookings.length > 0) {
        throw new HttpsError(
          'failed-precondition',
          `You are only allowed to book this facility once every ${cooldownValue} ${cooldownUnit}.`
        );
      }
    }

    // 2. Clashes validation (Capacity & Quantity check): bounded time range
    const quantity = facData.quantity || 1;
    const clashes = await admin.firestore().collection('bookings')
      .where('facilityId', '==', facilityId)
      .where('startTime', '<=', endTime)
      .where('startTime', '>=', startTime - (7 * 24 * 60 * 60 * 1000))
      .get();

    const events = [];
    for (const doc of clashes.docs) {
      const b = doc.data();
      // Ignore cancelled or rejected bookings
      if (b.status === 'cancelled' || b.status === 'rejected') {
        continue;
      }
      const overlapStart = Math.max(startTime, b.startTime);
      const overlapEnd = Math.min(endTime, b.endTime);
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

    // 3. Create booking
    const bookingRef = admin.firestore().collection('bookings').doc();
    const bookingData = {
      id: bookingRef.id,
      bookingId: bookingRef.id,
      facilityId,
      userUid: uid,
      startTime,
      endTime,
      status: 'pending review',
      isConfirmed: false,
      approvalMessage: '',
      rejectionReason: '',
      timestamp: Date.now()
    };

    await bookingRef.set(bookingData);

    return { success: true, booking: bookingData };
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
    const bookingRef = admin.firestore().collection('bookings').doc(bookingId);
    const bookingDoc = await bookingRef.get();

    if (!bookingDoc.exists) {
      throw new HttpsError('not-found', 'Booking not found.');
    }

    const b = bookingDoc.data();
    if (b.userUid !== request.auth.uid && request.auth.token.admin !== true) {
      throw new HttpsError('permission-denied', 'You do not have permission to cancel this booking.');
    }

    await bookingRef.update({ status: 'cancelled' });

    // Notify admins via an announcement or notification log
    await admin.firestore().collection('announcements').add({
      title: 'Booking Cancelled',
      content: `Booking ${bookingId} has been cancelled by user ${request.auth.uid}.`,
      creatorUid: 'system',
      timestamp: Date.now(),
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

    if (startMinutes < openingMinutes || endMinutes > closingMinutes || startTz.day !== endTz.day) {
      throw new HttpsError(
        'invalid-argument',
        `Reservation must be within operating hours (${openingTime} - ${closingTime}).`
      );
    }
  }
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

    // Invalidate if one-time use
    if (status === 'allowed' && qrCodeId) {
      const qrDoc = await admin.firestore().collection('qr_codes').doc(qrCodeId).get();
      if (qrDoc.exists && qrDoc.data().isOneTimeUse === true) {
        await qrDoc.ref.update({
          status: 'deactivated (validated)',
        });
        console.log(`Deactivated one-time use QR code ${qrCodeId}`);
      }
    }

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

/**
 * Validates a QR code and registers physical access atomically in Cloud Functions.
 * Enforces:
 * - Guard or Admin caller authentication
 * - QR existence and validity status
 * - Temporary pass expiration against server clock
 * - Linked resident address paymentStatus == 'paid'
 * - Single-use pass invalidation upon entry
 * - Direct immutable audit entry into access_logs
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

  const db = admin.firestore();
  const guardUid = request.auth.uid;
  const qrRef = db.collection('qr_codes').doc(qrId);

  return await db.runTransaction(async (transaction) => {
    // 0. Fetch guard record for audit attribution
    const guardSnap = await transaction.get(db.collection('users').doc(guardUid));
    const guardName = (guardSnap.exists && guardSnap.data()?.name) ? guardSnap.data().name : 'Security Guard';

    const qrSnap = await transaction.get(qrRef);
    if (!qrSnap.exists) {
      return {
        success: false,
        granted: false,
        reason: 'QR Code not found.',
        qrData: null,
      };
    }

    const qrData = qrSnap.data();
    const now = admin.firestore.Timestamp.now();

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

    const guestName = qrData.guestName || qrData.visitorName || 'Guest';
    const accessCategory = qrData.accessCategory || (qrData.type === 'one_time' || qrData.isOneTime ? 'supplier' : 'visitor');
    const vehicleType = qrData.vehicleType || 'walking';
    const vehiclePlates = qrData.vehiclePlates || qrData.vehiclePlate || '';
    const passengers = qrData.passengers || 0;

    // 1. Check validity status
    const isValidFlag = qrData.isValid !== false && qrData.status !== 'used' && qrData.status !== 'revoked';
    if (!isValidFlag) {
      const statusReason = qrData.status === 'used'
        ? 'QR Code has already been used.'
        : (qrData.status === 'revoked' ? 'QR Code has been revoked.' : 'QR Code is invalid.');

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
          visitorIdPhotoUrl: visitorIdPhotoUrl || '',
          visitorPlatePhotoUrl: visitorPlatePhotoUrl || '',
          status: 'denied',
          reason: statusReason,
        });
      }

      return {
        success: true,
        granted: false,
        reason: statusReason,
        qrData: {
          id: qrId,
          visitorName: guestName,
          guestName: guestName,
          vehiclePlate: vehiclePlates,
          vehiclePlates: vehiclePlates,
          type: qrData.type || 'temporary',
          accessCategory: accessCategory,
          creatorUid: qrData.creatorUid || '',
          residentName: residentName,
          addressDisplay: addressDisplay,
        },
      };
    }

    // 2. Check expiration for temporary passes
    if (qrData.expiresAt || qrData.expiryTime) {
      const expTime = qrData.expiresAt || qrData.expiryTime;
      const expMillis = (expTime instanceof admin.firestore.Timestamp)
        ? expTime.toMillis()
        : (typeof expTime === 'string' || typeof expTime === 'number' ? new Date(expTime).getTime() : 0);

      if (expMillis > 0 && now.toMillis() > expMillis) {
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
            visitorIdPhotoUrl: visitorIdPhotoUrl || '',
            visitorPlatePhotoUrl: visitorPlatePhotoUrl || '',
            status: 'denied',
            reason: 'QR Code has expired.',
          });
        }

        return {
          success: true,
          granted: false,
          reason: 'QR Code has expired.',
          qrData: {
            id: qrId,
            visitorName: guestName,
            guestName: guestName,
            vehiclePlate: vehiclePlates,
            vehiclePlates: vehiclePlates,
            type: qrData.type || 'temporary',
            accessCategory: accessCategory,
            creatorUid: qrData.creatorUid || '',
            residentName: residentName,
            addressDisplay: addressDisplay,
          },
        };
      }
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
          visitorIdPhotoUrl: visitorIdPhotoUrl || '',
          visitorPlatePhotoUrl: visitorPlatePhotoUrl || '',
          status: 'denied',
          reason: 'Resident address payment status is restricted or unpaid.',
        });
      }

      return {
        success: true,
        granted: false,
        reason: 'Resident address payment status is restricted or unpaid.',
        qrData: {
          id: qrId,
          visitorName: guestName,
          guestName: guestName,
          vehiclePlate: vehiclePlates,
          vehiclePlates: vehiclePlates,
          type: qrData.type || 'temporary',
          accessCategory: accessCategory,
          creatorUid: qrData.creatorUid || '',
          residentName: residentName,
          addressDisplay: addressDisplay,
        },
      };
    }

    // 4. If mode is validate_only, return validity preview without registering
    if (mode === 'validate_only') {
      return {
        success: true,
        granted: true,
        reason: 'Access granted.',
        qrData: {
          id: qrId,
          visitorName: guestName,
          guestName: guestName,
          vehiclePlate: vehiclePlates,
          vehiclePlates: vehiclePlates,
          type: qrData.type || 'temporary',
          accessCategory: accessCategory,
          creatorUid: qrData.creatorUid || '',
          residentName: residentName,
          addressDisplay: addressDisplay,
          isOneTime: qrData.isOneTime === true || qrData.type === 'one_time',
        },
      };
    }

    // 5. If isAllowed is true and single-use, mark used
    const isOneTime = qrData.isOneTime === true || qrData.type === 'one_time';
    if (isAllowed && isOneTime) {
      transaction.update(qrRef, {
        status: 'used',
        isValid: false,
        usedAt: FieldValue.serverTimestamp(),
      });
    }

    // 6. Write to access_logs
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
      visitorIdPhotoUrl: visitorIdPhotoUrl || '',
      visitorPlatePhotoUrl: visitorPlatePhotoUrl || '',
      status: isAllowed ? 'allowed' : 'denied',
      reason: reason || (isAllowed ? 'Access granted' : 'Denied by guard'),
    });

    return {
      success: true,
      granted: isAllowed,
      reason: isAllowed ? 'Access granted.' : (reason || 'Denied by guard'),
      qrData: {
        id: qrId,
        visitorName: guestName,
        guestName: guestName,
        vehiclePlate: vehiclePlates,
        vehiclePlates: vehiclePlates,
        type: qrData.type || 'temporary',
        accessCategory: accessCategory,
        creatorUid: qrData.creatorUid || '',
        residentName: residentName,
        addressDisplay: addressDisplay,
      },
    };
  });
});

const path = require('path');

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
  recalculateAddressPaymentStatus,
  validateTransparencyDocInput,
  isEmulator,
  callableOptions,
  BRAND_COLORS,
  buildWelcomeEmailHtml,
  GEMINI_MODEL,
  GEMINI_LOCATION,
};

