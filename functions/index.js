const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const { GoogleGenAI } = require('@google/genai');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
admin.initializeApp();

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

const projectId = process.env.GCLOUD_PROJECT || 'suburban-life';
const ai = new GoogleGenAI({
  vertexai: true,
  project: projectId,
  location: 'us-central1',
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
    .replace(/%appName%/gi, data.appName || 'Suburban Life');
}

// Helper: Send branded HTML and Plain Text welcome email
async function sendWelcomeEmail(smtpConfig, { email, name, password, addressLinked, appName, role }) {
  if (!smtpConfig) return { sent: false, reason: 'SMTP not configured or disabled' };

  try {
    const transporter = createSmtpTransporter(smtpConfig);
    const branding = appName || smtpConfig.senderName || 'Suburban Life';
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

      const escapedBody = rawCustomBody
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/\n/g, '<br/>');

      htmlContent = `
        <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 24px; background-color: #f8f9fa; border-radius: 12px;">
          <div style="background-color: #2864be; padding: 24px; border-radius: 8px 8px 0 0; text-align: center;">
            <h1 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: bold;">${branding}</h1>
          </div>
          <div style="background-color: #ffffff; padding: 28px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.05); color: #1f2937; line-height: 1.6; font-size: 14px;">
            ${escapedBody}
            <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 24px 0;" />
            <p style="font-size: 12px; color: #9ca3af; text-align: center; margin: 0;">
              Este es un correo automático generado por la administración de ${branding}. Por favor no respondas directamente a este mensaje.
            </p>
          </div>
        </div>
      `;
    } else {
      const addressText = addressLinked ? `<li><strong>Dirección asignada:</strong> ${addressLinked}</li>` : '';
      const addressPlain = addressLinked ? `\nDirección asignada: ${addressLinked}` : '';

      htmlContent = `
        <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 24px; background-color: #f8f9fa; border-radius: 12px;">
          <div style="background-color: #2864be; padding: 24px; border-radius: 8px 8px 0 0; text-align: center;">
            <h1 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: bold;">¡Bienvenido(a) a ${branding}!</h1>
          </div>
          <div style="background-color: #ffffff; padding: 28px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.05);">
            <p style="font-size: 16px; color: #1f2937; margin-top: 0;">Hola <strong>${name}</strong>,</p>
            <p style="font-size: 14px; color: #4b5563; line-height: 1.6;">
              Tu cuenta de <strong>${userRole}</strong> ha sido creada exitosamente. A continuación encontrarás tus credenciales de acceso para ingresar a la aplicación:
            </p>
            <div style="background-color: #f3f4f6; border-left: 4px solid #2864be; padding: 16px 20px; margin: 20px 0; border-radius: 6px;">
              <ul style="margin: 0; padding-left: 20px; color: #1f2937; font-size: 14px; line-height: 1.8;">
                <li><strong>Correo electrónico:</strong> ${email}</li>
                <li><strong>Contraseña inicial:</strong> <code style="background-color: #e5e7eb; padding: 2px 6px; border-radius: 4px; font-weight: bold; color: #1e3a8a;">${password}</code></li>
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
exports.setRole = onCall({ enforceAppCheck: true }, async (request) => {
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
        model: 'gemini-2.5-flash',
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

exports.createBooking = onCall({ enforceAppCheck: true }, async (request) => {
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
        if (!status || status.toString().trim() === '' || status === 'restricted') {
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
    const cooldownUnit = facData.cooldownUnit || 'unrestricted';
    const cooldownValue = facData.cooldownValue || 0;

    if (cooldownUnit !== 'unrestricted') {
      let startTimeBoundary = 0;
      if (cooldownUnit === 'days') {
        startTimeBoundary = startTime - (cooldownValue * 24 * 60 * 60 * 1000);
      } else if (cooldownUnit === 'months') {
        const date = new Date(startTime);
        date.setMonth(date.getMonth() - cooldownValue);
        startTimeBoundary = date.getTime();
      } else if (cooldownUnit === 'years') {
        const date = new Date(startTime);
        date.setFullYear(date.getFullYear() - cooldownValue);
        startTimeBoundary = date.getTime();
      }

      const recentBookings = await admin.firestore().collection('bookings')
        .where('userUid', '==', uid)
        .where('facilityId', '==', facilityId)
        .where('startTime', '>=', startTimeBoundary)
        .where('status', '!=', 'cancelled')
        .get();

      if (!recentBookings.empty) {
        throw new HttpsError(
          'failed-precondition',
          `You are only allowed to book this facility once every ${cooldownValue} ${cooldownUnit}.`
        );
      }
    }

    // 2. Clashes validation (Capacity & Quantity check)
    const quantity = facData.quantity || 1;
    const clashes = await admin.firestore().collection('bookings')
      .where('facilityId', '==', facilityId)
      .where('status', '!=', 'cancelled')
      .get();

    const events = [];
    for (const doc of clashes.docs) {
      const b = doc.data();
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
      facilityId,
      userUid: uid,
      startTime,
      endTime,
      status: 'pending review',
      timestamp: Date.now()
    };

    await bookingRef.set(bookingData);

    return { success: true, booking: bookingData };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', error.message);
  }
});

exports.cancelBooking = onCall({ enforceAppCheck: true }, async (request) => {
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

exports.approvePayment = onCall({ enforceAppCheck: true }, async (request) => {
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

    const userDoc = await admin.firestore().collection('users').doc(residentUid).get();
    if (userDoc.exists) {
      const addressRef = userDoc.data().addressRef;
      if (addressRef) {
        const addressDoc = await addressRef.get();
        const addressData = addressDoc.data();
        const deliveryTimestamp = addressData ? addressData.deliveryDate : null;

        let newStatus = 'paid';
        if (deliveryTimestamp) {
          const deliveryDate = deliveryTimestamp.toDate();
          const requiredPeriods = [];
          const now = new Date();
          let current = new Date(deliveryDate.getFullYear(), deliveryDate.getMonth(), 1);
          const target = new Date(now.getFullYear(), now.getMonth(), 1);

          while (current <= target) {
            const yyyy = current.getFullYear();
            const mm = String(current.getMonth() + 1).padStart(2, '0');
            requiredPeriods.push(`${yyyy}-${mm}`);
            current.setMonth(current.getMonth() + 1);
          }

          const paymentsQuery = await admin.firestore().collection('payments')
            .where('addressRef', '==', addressRef)
            .get();

          const paymentsMap = {};
          paymentsQuery.forEach((doc) => {
            const pData = doc.data();
            const period = pData.period;
            const status = pData.status;
            if (period && status) {
              const existing = paymentsMap[period];
              if (!existing || status === 'approved' || (status === 'pending' && existing === 'rejected')) {
                paymentsMap[period] = status;
              }
            }
          });

          let hasPending = false;
          let hasUnpaid = false;

          for (const period of requiredPeriods) {
            const status = paymentsMap[period];
            if (!status || status === 'rejected') {
              hasUnpaid = true;
            } else if (status === 'pending') {
              hasPending = true;
            }
          }

          if (hasUnpaid) {
            newStatus = 'restricted';
          } else if (hasPending) {
            newStatus = 'reviewing';
          } else {
            newStatus = 'paid';
          }
        }

        await addressRef.update({
          paymentStatus: newStatus,
          lastPaymentApproval: Date.now()
        });
      }
    }

    return { success: true };
  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

exports.addRoommate = onCall({ enforceAppCheck: true }, async (request) => {
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

exports.adminUpdatePassword = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { uid, newPassword } = request.data;
  if (!uid || !newPassword) {
    throw new HttpsError('invalid-argument', 'Missing uid or newPassword.');
  }

  try {
    await admin.auth().updateUser(uid, { password: newPassword });
    return { success: true };
  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

exports.adminCreateUser = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { name, email, password, role, streetName, number, addressId } = request.data;
  if (!name || !email || !password || !role) {
    throw new HttpsError('invalid-argument', 'Missing name, email, password, or role.');
  }

  const cleanName = name.toString().trim();
  const cleanEmail = email.toString().trim().toLowerCase();
  const cleanPassword = password.toString().trim();
  const cleanRole = role.toString().trim().toLowerCase();

  if (cleanPassword.length < 6) {
    throw new HttpsError('invalid-argument', 'Password must be at least 6 characters long.');
  }

  if (!['resident', 'guard', 'admin'].includes(cleanRole)) {
    throw new HttpsError('invalid-argument', `Invalid role: ${cleanRole}. Must be resident, guard, or admin.`);
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

    // 4. Update address if resident (claim address and mark paymentStatus: 'paid')
    if (cleanRole === 'resident' && addressRef) {
      await addressRef.update({
        residentUid: userRecord.uid,
        paymentStatus: 'paid',
      });
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
        appName: 'Suburban Life',
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

exports.adminProvisionGuard = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { name, email, password } = request.data;
  if (!name || !email || !password) {
    throw new HttpsError('invalid-argument', 'Missing name, email, or password.');
  }

  try {
    const userRecord = await admin.auth().createUser({
      email,
      password,
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
        appName: 'Suburban Life',
      }).catch(err => console.error('Error sending guard welcome email:', err));
    }

    return { success: true, uid: userRecord.uid };
  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

exports.adminTestSmtpConnection = onCall({ enforceAppCheck: true }, async (request) => {
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
      ? `"${config.senderName || 'Suburban Life'}" <${config.senderEmail}>`
      : `"${config.senderName || 'Suburban Life'}" <${config.user}>`;

    const sampleData = {
      name: 'Usuario de Prueba',
      email: testRecipient.toString().trim(),
      password: 'SamplePass#2026',
      address: 'Calle Ejemplo #101',
      role: 'Residente',
      appName: config.senderName || 'Suburban Life',
    };

    let subject = 'Suburban Life - Test de Configuración SMTP';
    if (config.customSubject && config.customSubject.trim().length > 0) {
      subject = `[Test] ${replacePlaceholders(config.customSubject, sampleData)}`;
    }

    let textBody = 'Este es un correo de prueba enviado desde la configuración de administración de Suburban Life para verificar el servicio SMTP.';
    let htmlBody = `
      <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 24px; background-color: #f8f9fa; border-radius: 12px;">
        <div style="background-color: #25d366; padding: 20px; border-radius: 8px 8px 0 0; text-align: center;">
          <h2 style="color: #ffffff; margin: 0; font-size: 22px;">¡Conexión SMTP Exitosa!</h2>
        </div>
        <div style="background-color: #ffffff; padding: 24px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.05);">
          <p style="font-size: 15px; color: #1f2937;">Tu servidor SMTP ha sido verificado correctamente.</p>
          <p style="font-size: 14px; color: #4b5563; line-height: 1.6;">
            Los correos automáticos de bienvenida con credenciales para nuevos residentes y guardias están listos para ser enviados.
          </p>
          <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 20px 0;" />
          <p style="font-size: 12px; color: #9ca3af; text-align: center; margin: 0;">
            Suburban Life Administration System
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
        <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 24px; background-color: #f8f9fa; border-radius: 12px;">
          <div style="background-color: #25d366; padding: 16px 20px; border-radius: 8px 8px 0 0; text-align: center;">
            <h2 style="color: #ffffff; margin: 0; font-size: 20px;">¡Conexión SMTP Exitosa & Vista Previa!</h2>
          </div>
          <div style="background-color: #ffffff; padding: 24px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.05); color: #1f2937; line-height: 1.6; font-size: 14px;">
            <p style="font-size: 13px; color: #059669; font-weight: bold; margin-top: 0;">
              ✓ Tu mensaje personalizado se visualiza así con datos de muestra:
            </p>
            <div style="background-color: #f9fafb; border: 1px dashed #d1d5db; border-radius: 6px; padding: 16px; margin: 16px 0;">
              ${escapedBody}
            </div>
            <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 20px 0;" />
            <p style="font-size: 12px; color: #9ca3af; text-align: center; margin: 0;">
              Suburban Life Administration System
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

exports.adminDeleteUser = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('failed-precondition', 'Function must be called by an authenticated admin.');
  }

  const { uid } = request.data;
  if (!uid) {
    throw new HttpsError('invalid-argument', 'Missing uid.');
  }

  try {
    await admin.auth().deleteUser(uid);
    await admin.firestore().collection('users').doc(uid).delete();
    return { success: true };
  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

exports.unbindAddress = onCall({ enforceAppCheck: true }, async (request) => {
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

    // 3. Clear addressRef on roommates (familyMembers)
    const familyMembers = userData.familyMembers || [];
    for (const roommateUid of familyMembers) {
      const roommateRef = db.collection('users').doc(roommateUid);
      batch.update(roommateRef, {
        addressRef: null
      });
      await admin.auth().setCustomUserClaims(roommateUid, {});
    }

    await batch.commit();
    return { success: true, message: 'Address unlinked successfully.' };
  } catch (error) {
    throw new HttpsError('internal', error.message);
  }
});

exports.deleteOwnAccount = onCall({ enforceAppCheck: true }, async (request) => {
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

exports.removeRoommate = onCall({ enforceAppCheck: true }, async (request) => {
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

    if (residentQuery.empty) {
      throw new HttpsError('failed-precondition', 'Roommate is not associated with any family group.');
    }

    const residentDoc = residentQuery.docs[0];
    const residentUid = residentDoc.id;

    // Enforce authorization: must be admin OR the primary resident of that family group
    if (callerUid !== residentUid && !isAdmin) {
      throw new HttpsError('permission-denied', 'You do not have permission to remove this roommate.');
    }

    const batch = db.batch();

    // 1. Remove roommateUid from resident's familyMembers list
    batch.update(residentDoc.ref, {
      familyMembers: FieldValue.arrayRemove(roommateUid)
    });

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

exports.adminBulkImportResidents = onCall({ enforceAppCheck: true }, async (request) => {
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

    // Determine password: if not specified or < 8 chars, generate a cryptographically secure random password
    let password = rawPassword;
    let isAutoGenerated = false;
    if (!password || password.length < 8) {
      password = generateSecurePassword(12);
      isAutoGenerated = true;
    }

    try {
      const db = admin.firestore();
      let addressRef = null;
      let addressMatched = false;

      // 1. Verify address existence if streetName and number are provided (do NOT create new addresses!)
      if (streetName && numberStr) {
        const numVal = isNaN(Number(numberStr)) ? numberStr : Number(numberStr);

        let addressQuery = await db.collection('addresses')
          .where('streetName', '==', streetName)
          .where('number', '==', numVal)
          .get();

        if (addressQuery.empty && typeof numVal === 'number') {
          addressQuery = await db.collection('addresses')
            .where('streetName', '==', streetName)
            .where('number', '==', numberStr)
            .get();
        }

        // Case-insensitive & trimmed fallback lookup if direct query yields no results
        if (addressQuery.empty) {
          const allAddressesSnap = await db.collection('addresses').get();
          const matchedDoc = allAddressesSnap.docs.find(doc => {
            const d = doc.data();
            const sName = (d.streetName || '').toString().trim().toLowerCase();
            const sNum = (d.number !== undefined && d.number !== null) ? d.number.toString().trim() : '';
            return sName === streetName.toLowerCase() && sNum === numberStr;
          });

          if (matchedDoc) {
            addressQuery = { empty: false, docs: [matchedDoc] };
          }
        }

        if (addressQuery.empty) {
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

        const existingDoc = addressQuery.docs[0];
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
          appName: 'Suburban Life',
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

exports.adminBulkImportAddresses = onCall({ enforceAppCheck: true }, async (request) => {
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
exports.validateAndRegisterQrAccess = onCall({ enforceAppCheck: true }, async (request) => {
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
          creatorUid: qrData.creatorUid || 'unknown',
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
          visitorName: qrData.visitorName || '',
          vehiclePlate: qrData.vehiclePlate || '',
          type: qrData.type || 'temporary',
          creatorUid: qrData.creatorUid || '',
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
            creatorUid: qrData.creatorUid || 'unknown',
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
            visitorName: qrData.visitorName || '',
            vehiclePlate: qrData.vehiclePlate || '',
            type: qrData.type || 'temporary',
            creatorUid: qrData.creatorUid || '',
          },
        };
      }
    }

    // 3. Verify creator resident address payment standing
    if (qrData.creatorUid) {
      const userRef = db.collection('users').doc(qrData.creatorUid);
      const userSnap = await transaction.get(userRef);
      if (userSnap.exists) {
        const userData = userSnap.data();
        if (userData.addressRef) {
          const addrRef = typeof userData.addressRef === 'string'
            ? db.doc(userData.addressRef)
            : userData.addressRef;
          const addrSnap = await transaction.get(addrRef);
          if (addrSnap.exists) {
            const addrData = addrSnap.data();
            if (addrData.paymentStatus && addrData.paymentStatus !== 'paid') {
              if (mode === 'validate_and_register') {
                const logRef = db.collection('access_logs').doc();
                transaction.set(logRef, {
                  qrCodeId: qrId,
                  guardUid: guardUid,
                  creatorUid: qrData.creatorUid,
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
                  visitorName: qrData.visitorName || '',
                  vehiclePlate: qrData.vehiclePlate || '',
                  type: qrData.type || 'temporary',
                  creatorUid: qrData.creatorUid || '',
                },
              };
            }
          }
        }
      }
    }

    // 4. If mode is validate_only, return validity preview without registering
    if (mode === 'validate_only') {
      return {
        success: true,
        granted: true,
        reason: 'Access granted.',
        qrData: {
          id: qrId,
          visitorName: qrData.visitorName || '',
          vehiclePlate: qrData.vehiclePlate || '',
          type: qrData.type || 'temporary',
          creatorUid: qrData.creatorUid || '',
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
      creatorUid: qrData.creatorUid || 'unknown',
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
        visitorName: qrData.visitorName || '',
        vehiclePlate: qrData.vehiclePlate || '',
        type: qrData.type || 'temporary',
        creatorUid: qrData.creatorUid || '',
      },
    };
  });
});



