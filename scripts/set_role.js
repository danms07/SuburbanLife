const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const identifier = process.argv[2];
const role = process.argv[3];

const supportedRoles = ['admin', 'resident', 'guard', 'roommate'];

if (!identifier || !role) {
  console.error('Please provide user UID/Email and role as arguments.');
  console.error('Usage: node create_admin.js <user_uid_or_email> <role>');
  console.error('Supported Roles: admin, resident, guard, roommate');
  process.exit(1);
}

if (!supportedRoles.includes(role)) {
  console.error(`Error: "${role}" is not a supported role.`);
  console.error('Supported Roles: admin, resident, guard, roommate');
  process.exit(1);
}

async function run() {
  try {
    let uid = identifier;
    
    if (identifier.includes('@')) {
      const userRecord = await admin.auth().getUserByEmail(identifier);
      uid = userRecord.uid;
    }

    const user = await admin.auth().getUser(uid);
    const existingClaims = user.customClaims || {};
    
    const claims = { ...existingClaims };
    claims[role] = true;

    await admin.auth().setCustomUserClaims(uid, claims);
    console.log(`Successfully set ${role} claim for user: ${uid} (${identifier})`);
    console.log('Current claims:', claims);
    process.exit(0);
  } catch (error) {
    console.error('Error setting custom claims:', error);
    process.exit(1);
  }
}

run();
