/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBLnJaRuctGLDcJncKdElMFtxa2PVKLZJg',
  authDomain: 'privadacatania-3a7b8.firebaseapp.com',
  projectId: 'privadacatania-3a7b8',
  storageBucket: 'privadacatania-3a7b8.firebasestorage.app',
  messagingSenderId: '587395279768',
  appId: '1:587395279768:web:b3edd7a46d0f68f45999ed',
});

const messaging = firebase.messaging();

const ALLOWED_TARGET_ROUTES = new Set([
  'home',
  'notifications',
  'payments',
  'bookings',
  'sanctions',
  'transparency',
  'qr_codes',
  'roommates',
  'announcements',
  'admin_payments',
  'admin_claims',
  'admin_bookings',
]);

messaging.onBackgroundMessage((payload) => {
  // Firebase SDK renders notification payloads automatically when `payload.notification` is present.
  // Only synthesize a Web notification when receiving a pure data-only background message.
  if (payload && !payload.notification && payload.data) {
    const title = String(payload.data.title || 'Suburban Life').slice(0, 120);
    const body = String(payload.data.body || '').slice(0, 300);
    const rawRoute = String(payload.data.targetRoute || 'notifications');
    const safeRoute = ALLOWED_TARGET_ROUTES.has(rawRoute) ? rawRoute : 'notifications';
    return self.registration.showNotification(title, {
      body,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      data: {
        targetRoute: safeRoute,
        entityId: String(payload.data.entityId || '').slice(0, 128),
      },
    });
  }
  return Promise.resolve();
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const payloadData = (event.notification && event.notification.data) || {};
  const rawRoute = String(
    payloadData.targetRoute ||
      (payloadData.FCM_MSG && payloadData.FCM_MSG.data && payloadData.FCM_MSG.data.targetRoute) ||
      'notifications'
  );
  const safeRoute = ALLOWED_TARGET_ROUTES.has(rawRoute) ? rawRoute : 'notifications';
  const targetUrl = new URL(`/?notificationRoute=${encodeURIComponent(safeRoute)}`, self.location.origin).href;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        let sameOrigin = false;
        try {
          sameOrigin = new URL(client.url).origin === self.location.origin;
        } catch (_) {
          sameOrigin = false;
        }
        if (sameOrigin && 'focus' in client) {
          client.postMessage({
            type: 'NOTIFICATION_CLICK',
            targetRoute: safeRoute,
          });
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
      return undefined;
    })
  );
});
