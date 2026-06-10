const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Load service account credentials
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function run() {
  const csvPath = path.join(__dirname, '../addresses_import.csv');
  if (!fs.existsSync(csvPath)) {
    console.error('addresses_import.csv not found in the root directory.');
    process.exit(1);
  }

  const csvData = fs.readFileSync(csvPath, 'utf8');
  const lines = csvData.split('\n');

  // Skip header line
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    // Match CSV values handling quoted strings
    const match = line.match(/(".*?"|[^",\s]+)(?=\s*,|\s*$)/g);
    if (!match || match.length < 3) {
      console.warn(`Skipping invalid line: ${line}`);
      continue;
    }

    const streetName = match[0].replace(/"/g, '');
    const initialNumber = parseInt(match[1], 10);
    const finalNumber = parseInt(match[2], 10);
    
    const exclusionsString = match[3] ? match[3].replace(/"/g, '') : '';
    const exclusions = exclusionsString ? exclusionsString.split(',').map(n => parseInt(n.trim(), 10)) : [];

    console.log(`Processing ${streetName} from ${initialNumber} to ${finalNumber}...`);

    const batch = db.batch();
    let operationCount = 0;

    for (let number = initialNumber; number <= finalNumber; number++) {
      if (exclusions.includes(number)) {
        continue;
      }

      const addressRef = db.collection('addresses').doc();
      batch.set(addressRef, {
        streetName: streetName,
        number: number,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });

      operationCount++;

      if (operationCount === 500) {
        await batch.commit();
        console.log(`Committed 500 addresses for ${streetName}`);
        operationCount = 0;
      }
    }

    if (operationCount > 0) {
      await batch.commit();
    }
    console.log(`Successfully added addresses for street: ${streetName}`);
  }

  console.log('Address population completed successfully.');
  process.exit(0);
}

run().catch(error => {
  console.error('Error populating addresses:', error);
  process.exit(1);
});
