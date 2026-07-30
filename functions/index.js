const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { GoogleGenAI } = require('@google/genai');
admin.initializeApp();

const projectId = process.env.GCLOUD_PROJECT || 'suburban-life';
const ai = new GoogleGenAI({
  vertexai: true,
  project: projectId,
  location: 'us-central1',
});

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
      familyMembers: admin.firestore.FieldValue.arrayUnion(targetUid)
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

    return { success: true, uid: userRecord.uid };
  } catch (error) {
    throw new HttpsError('internal', error.message);
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
      familyMembers: admin.firestore.FieldValue.delete()
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
      familyMembers: admin.firestore.FieldValue.arrayRemove(roommateUid)
    });

    // 2. Clear addressRef and role on roommate's user document
    batch.update(roommateDoc.ref, {
      addressRef: null,
      role: admin.firestore.FieldValue.delete()
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
        error: 'Invalid name or email address.',
      });
      failureCount++;
      continue;
    }

    // Determine password: if not specified or < 6 chars, generate deterministic temp password
    let password = rawPassword;
    let isDeterministic = false;
    if (!password || password.length < 6) {
      const localPart = email.split('@')[0].replace(/[^a-zA-Z0-9._-]/g, '');
      password = `Suburban#${localPart}2026`;
      isDeterministic = true;
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

      results.push({
        name,
        email,
        password: rawPassword,
        streetName,
        number: numberStr,
        status: 'ok',
        assignedPassword: password,
        isDeterministicPassword: isDeterministic,
        addressLinked: addressMatched ? `${streetName} #${numberStr}` : null,
        uid: userRecord.uid,
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
        streetName: streetName,
        number: num,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
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



