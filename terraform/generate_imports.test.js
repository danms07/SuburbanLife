'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const {
  assertSafeSegment,
  buildFirestoreIndexKey,
  buildTfvarsSuggestions,
  createGcpApiClient,
  discoverResources,
  escapeHclString,
  formatCliSummary,
  isValidProjectId,
  loadFirestoreIndexesConfig,
  matchFirestoreCompositeIndexes,
  normalizeShaFingerprint,
  parseArgs,
  readTfvarsHints,
  renderImportsTf,
  resolveAccessToken,
  stripHclComments,
} = require('./generate_imports.js');

const REPO_INDEXES_PATH = path.resolve(__dirname, '..', 'firestore.indexes.json');

test('parseArgs handles flags, inline equals, booleans, and invalid input', () => {
  const opts = parseArgs([
    '-p',
    'suburban-prod-01',
    '--hosting-site=custom-site',
    '--github-repo',
    'acme/suburban-life',
    '--no-docs-publisher',
    '--dry-run',
  ]);
  assert.equal(opts.project, 'suburban-prod-01');
  assert.equal(opts.hostingSite, 'custom-site');
  assert.equal(opts.githubRepo, 'acme/suburban-life');
  assert.equal(opts.noDocsPublisher, true);
  assert.equal(opts.dryRun, true);
  assert.equal(opts.help, false);

  assert.throws(() => parseArgs(['positional']), /Unexpected positional argument/);
  assert.throws(() => parseArgs(['--unknown']), /Unknown option/);
  assert.throws(() => parseArgs(['--project']), /requires a value/);
  assert.throws(() => parseArgs(['--dry-run=yes']), /does not accept a value/);
});

test('isValidProjectId and assertSafeSegment reject unsafe identifiers', () => {
  assert.equal(isValidProjectId('suburban-life-01'), true);
  assert.equal(isValidProjectId('abcde'), false);
  assert.equal(isValidProjectId('SuburbanLife'), false);
  assert.equal(isValidProjectId('123456'), false);
  assert.equal(isValidProjectId('suburban-life-'), false);

  assert.equal(assertSafeSegment('1:123:web:abc', 'appId'), '1:123:web:abc');
  assert.equal(
    assertSafeSegment('sa-name@proj.iam.gserviceaccount.com', 'email'),
    'sa-name@proj.iam.gserviceaccount.com'
  );
  assert.throws(() => assertSafeSegment('../secrets', 'segment'), /Invalid segment/);
  assert.throws(() => assertSafeSegment('foo/bar', 'segment'), /Invalid segment/);
  assert.throws(() => assertSafeSegment('', 'segment'), /Invalid segment/);
});

test('escapeHclString escapes quotes, slashes, control chars, and interpolations', () => {
  assert.equal(escapeHclString('a\\b"c'), 'a\\\\b\\"c');
  assert.equal(escapeHclString('line1\nline2\t${var.x}%{if}'), 'line1\\nline2\\t$${var.x}%%{if}');
});

test('stripHclComments and readTfvarsHints parse strings, booleans, null, and lists safely', () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'suburban-tfvars-test-'));
  try {
    const tfvarsPath = path.join(tmpDir, 'terraform.tfvars');
    fs.writeFileSync(
      tfvarsPath,
      [
        '# Top comment with project_id = "ignored"',
        'project_id = "suburban-prod" // trailing comment',
        '  create_docs_publisher_service_account = false',
        'ios_team_id = null',
        'custom_domains = [',
        '  "portal.example.com", # inline comment',
        '  "https://url-with-#-hash.example.com",',
        ']',
        '/* block comment',
        'hosting_site_id = "ignored-in-block"',
        '*/',
        'rtdb_instance_id = "suburban-custom-rtdb"',
      ].join('\n'),
      'utf8'
    );

    const stripped = stripHclComments('a = "x#y//z" # comment');
    assert.equal(stripped.trim(), 'a = "x#y//z"');

    const hints = readTfvarsHints(tfvarsPath);
    assert.equal(hints.project_id, 'suburban-prod');
    assert.equal(hints.create_docs_publisher_service_account, false);
    assert.equal(hints.ios_team_id, null);
    assert.deepEqual(hints.custom_domains, [
      'portal.example.com',
      'https://url-with-#-hash.example.com',
    ]);
    assert.equal(hints.hosting_site_id, undefined);
    assert.equal(hints.rtdb_instance_id, 'suburban-custom-rtdb');
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test('matchFirestoreCompositeIndexes matches all 33 real firestore.indexes.json entries including trailing __name__', () => {
  const config = loadFirestoreIndexesConfig(REPO_INDEXES_PATH);
  assert.equal(config.indexes.length, 33);
  assert.equal(config.fieldOverrides.length, 3);

  // Simulate Firestore REST API returning project number + auto-appended __name__ field.
  const simulatedLive = config.indexes.map((idx, i) => ({
    name: `projects/987654321/databases/(default)/collectionGroups/${idx.collectionGroup}/indexes/CICAgNj${i}`,
    queryScope: idx.queryScope || 'COLLECTION',
    apiScope: 'ANY_API',
    state: 'READY',
    fields: [
      ...idx.fields,
      {
        fieldPath: '__name__',
        order: idx.fields[idx.fields.length - 1].order || 'ASCENDING',
      },
    ],
  }));

  // Inject noise that must be ignored or reported as unmatched live:
  simulatedLive.push(
    {
      name: 'projects/987654321/databases/(default)/collectionGroups/bookings/indexes/IGNORED_DS',
      apiScope: 'DATASTORE_MODE_API',
      state: 'READY',
      fields: [{ fieldPath: 'foo', order: 'ASCENDING' }],
    },
    {
      name: 'projects/987654321/databases/(default)/collectionGroups/bookings/indexes/IGNORED_DEL',
      apiScope: 'ANY_API',
      state: 'DELETING',
      fields: [{ fieldPath: 'bar', order: 'ASCENDING' }],
    },
    {
      name: 'projects/987654321/databases/(default)/collectionGroups/custom_col/indexes/EXTRA_LIVE',
      apiScope: 'ANY_API',
      state: 'READY',
      fields: [
        { fieldPath: 'tags', arrayConfig: 'CONTAINS' },
        { fieldPath: 'createdAt', order: 'DESCENDING' },
        { fieldPath: '__name__', order: 'DESCENDING' },
      ],
    }
  );

  const matchResult = matchFirestoreCompositeIndexes(
    config.indexes,
    simulatedLive,
    'suburban-prod-01'
  );

  assert.equal(matchResult.matched.length, 33);
  assert.equal(matchResult.unmatchedLocalKeys.length, 0);
  assert.equal(matchResult.unmatchedLive.length, 1);
  assert.equal(matchResult.unmatchedLive[0].collectionGroup, 'custom_col');

  // Verify import ID normalizes project number -> project_id and preserves exact Terraform key format.
  assert.equal(
    matchResult.matched[0].key,
    'bookings:COLLECTION:facilityId=ASCENDING,addressId=ASCENDING,startTime=ASCENDING'
  );
  assert.equal(
    matchResult.matched[0].id,
    'projects/suburban-prod-01/databases/(default)/collectionGroups/bookings/indexes/CICAgNj0'
  );
});

test('matchFirestoreCompositeIndexes handles arrayConfig and explicit __name__ fields cleanly', () => {
  const localIndexes = [
    {
      collectionGroup: 'posts',
      fields: [
        { fieldPath: 'tags', arrayConfig: 'CONTAINS' },
        { fieldPath: '__name__', order: 'ASCENDING' },
      ],
    },
    {
      collectionGroup: 'audit',
      queryScope: 'COLLECTION_GROUP',
      fields: [{ fieldPath: 'createdAt', order: 'DESCENDING' }],
    },
  ];

  const liveIndexes = [
    {
      name: 'projects/p/databases/(default)/collectionGroups/posts/indexes/idx1',
      queryScope: 'COLLECTION',
      state: 'READY',
      fields: [
        { fieldPath: 'tags', arrayConfig: 'CONTAINS' },
        { fieldPath: '__name__', order: 'ASCENDING' },
      ],
    },
  ];

  const res = matchFirestoreCompositeIndexes(localIndexes, liveIndexes, 'my-proj');
  assert.equal(res.matched.length, 1);
  assert.equal(res.matched[0].key, 'posts:COLLECTION:tags=CONTAINS,__name__=ASCENDING');
  assert.deepEqual(res.unmatchedLocalKeys, ['audit:COLLECTION_GROUP:createdAt=DESCENDING']);
});

test('resolveAccessToken respects precedence and avoids leaking commands', () => {
  assert.equal(
    resolveAccessToken({
      token: '  direct-tok  ',
      tokenEnv: 'MY_TOK',
      env: { MY_TOK: 'env-tok' },
      execFileSyncImpl: () => {
        throw new Error('should not run gcloud');
      },
    }),
    'direct-tok'
  );

  assert.equal(
    resolveAccessToken({
      token: null,
      tokenEnv: 'MY_TOK',
      env: { MY_TOK: '  env-tok  ' },
      execFileSyncImpl: () => {
        throw new Error('should not run gcloud');
      },
    }),
    'env-tok'
  );

  let calledWith = null;
  const fromGcloud = resolveAccessToken({
    token: null,
    tokenEnv: 'GOOGLE_OAUTH_ACCESS_TOKEN',
    env: {},
    execFileSyncImpl: (cmd, args) => {
      calledWith = [cmd, args];
      return 'gcloud-tok\n';
    },
  });
  assert.equal(fromGcloud, 'gcloud-tok');
  assert.deepEqual(calledWith, ['gcloud', ['auth', 'print-access-token']]);

  assert.throws(
    () =>
      resolveAccessToken({
        token: null,
        tokenEnv: 'GOOGLE_OAUTH_ACCESS_TOKEN',
        env: {},
        execFileSyncImpl: () => {
          throw new Error('not logged in');
        },
      }),
    /Failed to obtain a GCP OAuth access token/
  );
});

test('createGcpApiClient enforces googleapis HTTPS origin, disables redirects, and paginates', async () => {
  const calls = [];
  const client = createGcpApiClient({
    accessToken: 'secret-token-value',
    projectId: 'suburban-prod-01',
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      if (url.includes('pageToken=page2')) {
        return {
          ok: true,
          status: 200,
          text: async () => JSON.stringify({ items: [{ id: 2 }] }),
        };
      }
      if (url.includes('/missing')) {
        return {
          ok: false,
          status: 404,
          statusText: 'Not Found',
          json: async () => ({ error: { message: 'nope' } }),
        };
      }
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({ items: [{ id: 1 }], nextPageToken: 'page2' }),
      };
    },
  });

  await assert.rejects(
    () => client.requestJson('https://evil.example.com/v1/projects/foo'),
    /Refusing to send credentials/
  );
  await assert.rejects(
    () => client.requestJson('http://firebase.googleapis.com/v1beta1/projects/foo'),
    /Refusing to send credentials/
  );

  const missing = await client.requestJson('https://firebase.googleapis.com/v1/missing', {
    allowMissing: true,
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.status, 404);

  const listed = await client.listPaginated(
    'https://firebase.googleapis.com/v1beta1/projects/suburban-prod-01/webApps',
    'items'
  );
  assert.equal(listed.ok, true);
  assert.deepEqual(listed.items, [{ id: 1 }, { id: 2 }]);
  assert.equal(calls[1].init.redirect, 'error');
  assert.equal(calls[1].init.headers['x-goog-user-project'], 'suburban-prod-01');
  assert.equal(calls[1].init.headers.Authorization, 'Bearer secret-token-value');
});

test('discoverResources, renderImportsTf, and buildTfvarsSuggestions wire all Terraform resources', async () => {
  const localIndexesConfig = loadFirestoreIndexesConfig(REPO_INDEXES_PATH);
  const projectId = 'suburban-live-01';

  const mockResponses = new Map([
    [
      `https://serviceusage.googleapis.com/v1/projects/${projectId}/services`,
      {
        services: [
          { config: { name: 'firebase.googleapis.com' } },
          { config: { name: 'firebasehosting.googleapis.com' } },
          { config: { name: 'identitytoolkit.googleapis.com' } },
          { config: { name: 'firestore.googleapis.com' } },
          { config: { name: 'firebasedatabase.googleapis.com' } },
          { config: { name: 'firebasestorage.googleapis.com' } },
          { config: { name: 'firebaserules.googleapis.com' } },
          { config: { name: 'firebaseappcheck.googleapis.com' } },
          { config: { name: 'recaptchaenterprise.googleapis.com' } },
          { config: { name: 'iam.googleapis.com' } },
        ],
      },
    ],
    [`https://firebase.googleapis.com/v1beta1/projects/${projectId}`, { projectId }],
    [
      `https://firebase.googleapis.com/v1beta1/projects/${projectId}/webApps`,
      { apps: [{ appId: '1:99:web:aaa', displayName: 'Suburban Portal Web' }] },
    ],
    [
      `https://firebase.googleapis.com/v1beta1/projects/${projectId}/androidApps`,
      {
        apps: [
          {
            appId: '1:99:android:bbb',
            packageName: 'com.example.suburban_life',
            displayName: 'Suburban Life Android',
          },
        ],
      },
    ],
    [
      `https://firebase.googleapis.com/v1beta1/projects/${projectId}/androidApps/1%3A99%3Aandroid%3Abbb/sha`,
      {
        certificates: [
          { certType: 'SHA_1', shaHash: 'AA:BB:CC:DD'.repeat(5) },
          { certType: 'SHA_256', shaHash: '11:22:33:44'.repeat(8) },
        ],
      },
    ],
    [
      `https://firebase.googleapis.com/v1beta1/projects/${projectId}/iosApps`,
      {
        apps: [
          {
            appId: '1:99:ios:ccc',
            bundleId: 'com.example.suburbanLife',
            displayName: 'Suburban Life iOS',
            teamId: 'AB12CD34EF',
            appStoreId: '6440001234',
          },
        ],
      },
    ],
    [
      `https://firebasehosting.googleapis.com/v1beta1/projects/${projectId}/sites/${projectId}`,
      { name: `projects/${projectId}/sites/${projectId}`, type: 'DEFAULT_SITE' },
    ],
    [
      `https://identitytoolkit.googleapis.com/v2/projects/${projectId}/config`,
      {
        signIn: { allowDuplicateEmails: false },
        authorizedDomains: [
          'localhost',
          `${projectId}.firebaseapp.com`,
          `${projectId}.web.app`,
          'portal.example.org',
        ],
      },
    ],
    [
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)`,
      {
        locationId: 'nam5',
        type: 'FIRESTORE_NATIVE',
        deleteProtectionState: 'DELETE_PROTECTION_ENABLED',
        pointInTimeRecoveryEnablement: 'POINT_IN_TIME_RECOVERY_DISABLED',
      },
    ],
    [
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/collectionGroups/-/indexes`,
      {
        indexes: localIndexesConfig.indexes.slice(0, 2).map((idx, i) => ({
          name: `projects/99/databases/(default)/collectionGroups/${idx.collectionGroup}/indexes/IDX_${i}`,
          queryScope: idx.queryScope || 'COLLECTION',
          apiScope: 'ANY_API',
          state: 'READY',
          fields: [...idx.fields, { fieldPath: '__name__', order: 'ASCENDING' }],
        })),
      },
    ],
    [
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/collectionGroups/access_logs/fields/expireAt`,
      { indexConfig: { indexes: [] }, ttlConfig: { state: 'ACTIVE' } },
    ],
    [
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/collectionGroups/qr_codes/fields/expireAt`,
      { indexConfig: { indexes: [] }, ttlConfig: { state: 'ACTIVE' } },
    ],
    [
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/collectionGroups/booking_attachments/fields/expireAt`,
      { indexConfig: { indexes: [] }, ttlConfig: { state: 'ACTIVE' } },
    ],
    [
      `https://firebasedatabase.googleapis.com/v1beta/projects/${projectId}/locations/-/instances`,
      {
        instances: [
          {
            name: `projects/99/locations/europe-west1/instances/${projectId}-default-rtdb`,
            type: 'DEFAULT_DATABASE',
            state: 'ACTIVE',
          },
        ],
      },
    ],
    [
      `https://firebasestorage.googleapis.com/v1beta/projects/${projectId}/defaultBucket`,
      {
        name: `projects/99/defaultBucket`,
        bucket: { name: `projects/99/buckets/${projectId}.firebasestorage.app` },
        location: 'US',
      },
    ],
    [
      `https://firebaserules.googleapis.com/v1/projects/${projectId}/releases`,
      {
        releases: [
          { name: `projects/${projectId}/releases/cloud.firestore` },
          {
            name: `projects/${projectId}/releases/firebase.storage/${projectId}.firebasestorage.app`,
          },
        ],
      },
    ],
    [
      `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}/apps/1%3A99%3Aweb%3Aaaa/recaptchaEnterpriseConfig`,
      {
        name: `projects/${projectId}/apps/1:99:web:aaa/recaptchaEnterpriseConfig`,
        siteKey: `projects/99/keys/6LeTestKey123`,
        tokenTtl: '7200s',
      },
    ],
    [
      `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}/apps/1%3A99%3Aandroid%3Abbb/playIntegrityConfig`,
      { tokenTtl: '7200s' },
    ],
    [
      `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}/apps/1%3A99%3Aios%3Accc/appAttestConfig`,
      { tokenTtl: '7200s' },
    ],
    [
      `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}/services/firestore.googleapis.com`,
      { enforcementMode: 'ENFORCED' },
    ],
    [
      `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}/services/firebasestorage.googleapis.com`,
      { enforcementMode: 'ENFORCED' },
    ],
    [
      `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}/services/firebasedatabase.googleapis.com`,
      { enforcementMode: 'ENFORCED' },
    ],
    [
      `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}/services/identitytoolkit.googleapis.com`,
      { enforcementMode: 'OFF' },
    ],
    [
      `https://recaptchaenterprise.googleapis.com/v1/projects/${projectId}/keys`,
      {
        keys: [
          {
            name: `projects/${projectId}/keys/6LeTestKey123`,
            displayName: 'Suburban Life Web App Check',
            webSettings: {
              allowedDomains: [
                `${projectId}.web.app`,
                `${projectId}.firebaseapp.com`,
                'portal.example.org',
              ],
            },
          },
        ],
      },
    ],
    [
      `https://iam.googleapis.com/v1/projects/${projectId}/serviceAccounts/${encodeURIComponent(`suburban-life-functions@${projectId}.iam.gserviceaccount.com`)}`,
      { email: `suburban-life-functions@${projectId}.iam.gserviceaccount.com` },
    ],
    [
      `https://iam.googleapis.com/v1/projects/${projectId}/serviceAccounts/${encodeURIComponent(`suburban-life-docs-publisher@${projectId}.iam.gserviceaccount.com`)}`,
      { email: `suburban-life-docs-publisher@${projectId}.iam.gserviceaccount.com` },
    ],
    [
      `https://iam.googleapis.com/v1/projects/${projectId}/locations/global/workloadIdentityPools/github-actions-pool`,
      { state: 'ACTIVE' },
    ],
    [
      `https://iam.googleapis.com/v1/projects/${projectId}/locations/global/workloadIdentityPools/github-actions-pool/providers/github-actions-oidc`,
      { state: 'ACTIVE' },
    ],
  ]);

  const apiClient = {
    async requestJson(url) {
      const base = url.split('?')[0];
      if (mockResponses.has(base)) {
        return { ok: true, status: 200, data: mockResponses.get(base) };
      }
      return { ok: false, status: 404, error: 'not found', data: null };
    },
    async listPaginated(url, key) {
      const res = await this.requestJson(url);
      if (!res.ok) return { ok: false, status: res.status, error: res.error, items: [] };
      return { ok: true, status: 200, items: res.data[key] || [] };
    },
  };

  const result = await discoverResources({
    projectId,
    options: parseArgs(['--project', projectId]),
    tfvarsHints: {},
    localIndexesConfig,
    apiClient,
  });

  const importedTargets = new Set(result.imports.map((i) => i.to));
  assert.equal(importedTargets.has('google_firebase_project.default'), true);
  assert.equal(importedTargets.has('google_firebase_web_app.default'), true);
  assert.equal(importedTargets.has('google_firebase_android_app.default'), true);
  assert.equal(importedTargets.has('google_firebase_apple_app.default'), true);
  assert.equal(importedTargets.has('google_firebase_hosting_site.default'), true);
  assert.equal(importedTargets.has('google_identity_platform_config.default'), true);
  assert.equal(importedTargets.has('google_firestore_database.default'), true);
  assert.equal(importedTargets.has('google_firebaserules_release.firestore'), true);
  assert.equal(importedTargets.has('google_firebaserules_release.storage'), true);
  assert.equal(importedTargets.has('google_firebase_database_instance.default'), true);
  assert.equal(importedTargets.has('google_firebase_storage_default_bucket.default'), true);
  assert.equal(importedTargets.has('google_recaptcha_enterprise_key.web'), true);
  assert.equal(
    importedTargets.has('google_firebase_app_check_recaptcha_enterprise_config.web'),
    true
  );
  assert.equal(
    importedTargets.has('google_firebase_app_check_play_integrity_config.android[0]'),
    true
  );
  assert.equal(importedTargets.has('google_firebase_app_check_app_attest_config.apple[0]'), true);
  assert.equal(
    importedTargets.has('google_firebase_app_check_service_config.services["firestore.googleapis.com"]'),
    true
  );
  assert.equal(
    importedTargets.has('google_firebase_app_check_service_config.services["identitytoolkit.googleapis.com"]'),
    false,
    'OFF enforcement services do not need explicit import'
  );
  assert.equal(importedTargets.has('google_service_account.functions_runtime'), true);
  assert.equal(importedTargets.has('google_service_account.docs_publisher[0]'), true);

  // WIF pool/provider discovered when github_repository is unset -> placed into commentedImports
  assert.deepEqual(
    result.commentedImports.map((c) => c.to),
    [
      'google_iam_workload_identity_pool.github_actions[0]',
      'google_iam_workload_identity_pool_provider.github_actions[0]',
    ]
  );

  // Verify composite index count & field overrides count
  assert.equal(result.discovered.firestore.matchedIndexesCount, 2);
  assert.equal(result.discovered.firestore.unmatchedLocalIndexesCount, 31);
  assert.equal(importedTargets.has('google_firestore_field.overrides["access_logs.expireAt"]'), true);

  const rendered = renderImportsTf({
    projectId,
    generatedAt: '2026-11-19T00:00:00.000Z',
    imports: result.imports,
    commentedImports: result.commentedImports,
    warnings: result.warnings,
  });
  assert.match(rendered, /to = google_firebase_project\.default/);
  assert.match(rendered, /id = "projects\/suburban-live-01\/locations\/europe-west1\/instances\/suburban-live-01-default-rtdb"/);
  assert.match(rendered, /# import \{/);

  const tfvarsSuggestions = buildTfvarsSuggestions({
    projectId,
    discovered: result.discovered,
  });
  assert.equal(
    tfvarsSuggestions.suggestions.some((s) => s.includes('rtdb_region      = "europe-west1"')),
    true
  );
  assert.equal(
    tfvarsSuggestions.suggestions.some((s) => s.includes('ios_team_id = "AB12CD34EF"')),
    true
  );
  assert.equal(
    tfvarsSuggestions.suggestions.some((s) => s.includes('app_check_enforcement_mode = "ENFORCED"')),
    true
  );
  assert.equal(
    tfvarsSuggestions.notes.some((n) => n.includes('portal.example.org')),
    true
  );

  const summary = formatCliSummary({
    projectId,
    outPath: '/repo/terraform/imports.tf',
    dryRun: false,
    result,
    suggestions: tfvarsSuggestions,
  });
  assert.match(summary, /Firestore composite indexes: 2\/33 matched/);
});

test('discoverResources handles default Hosting fallback, conditional App Check prerequisites, and mixed enforcement modes', async () => {
  const projectId = 'suburban-edge-01';
  const mockResponses = new Map([
    [
      `https://serviceusage.googleapis.com/v1/projects/${projectId}/services`,
      {
        services: [
          { config: { name: 'firebase.googleapis.com' } },
          { config: { name: 'firebasehosting.googleapis.com' } },
          { config: { name: 'firebaseappcheck.googleapis.com' } },
        ],
      },
    ],
    [`https://firebase.googleapis.com/v1beta1/projects/${projectId}`, { projectId }],
    [
      `https://firebase.googleapis.com/v1beta1/projects/${projectId}/androidApps`,
      { apps: [{ appId: '1:10:android:111', packageName: 'com.custom.app' }] },
    ],
    [
      `https://firebase.googleapis.com/v1beta1/projects/${projectId}/iosApps`,
      { apps: [{ appId: '1:10:ios:222', bundleId: 'com.example.suburbanLife' }] },
    ],
    [
      `https://firebasehosting.googleapis.com/v1beta1/projects/${projectId}/sites`,
      { sites: [{ name: `projects/${projectId}/sites/edge-default-site`, type: 'DEFAULT_SITE' }] },
    ],
    [
      `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}/apps/1%3A10%3Aandroid%3A111/playIntegrityConfig`,
      { tokenTtl: '3600s' },
    ],
    [
      `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}/apps/1%3A10%3Aios%3A222/appAttestConfig`,
      { tokenTtl: '3600s' },
    ],
    [
      `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}/services/firestore.googleapis.com`,
      { enforcementMode: 'ENFORCED' },
    ],
    [
      `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectId}/services/firebasestorage.googleapis.com`,
      { enforcementMode: 'UNENFORCED' },
    ],
  ]);

  const apiClient = {
    async requestJson(url) {
      const base = url.split('?')[0];
      if (mockResponses.has(base)) {
        return { ok: true, status: 200, data: mockResponses.get(base) };
      }
      return { ok: false, status: 404, error: 'not found', data: null };
    },
    async listPaginated(url, key) {
      const res = await this.requestJson(url);
      if (!res.ok) return { ok: false, status: res.status, error: res.error, items: [] };
      return { ok: true, status: 200, items: res.data[key] || [] };
    },
  };

  const result = await discoverResources({
    projectId,
    options: parseArgs(['--project', projectId]),
    tfvarsHints: {},
    localIndexesConfig: { indexes: [], fieldOverrides: [] },
    apiClient,
  });

  // Fallback DEFAULT_SITE selected cleanly.
  const hostingImport = result.imports.find((i) => i.to === 'google_firebase_hosting_site.default');
  assert.equal(hostingImport.id, `projects/${projectId}/sites/edge-default-site`);

  // Android package mismatch warning emitted.
  assert.equal(
    result.warnings.some((w) => w.includes('com.custom.app')),
    true
  );

  // Missing android_sha256_hashes & ios_team_id place count-gated App Check resources into commentedImports.
  assert.deepEqual(
    result.commentedImports.map((c) => c.to),
    [
      'google_firebase_app_check_play_integrity_config.android[0]',
      'google_firebase_app_check_app_attest_config.apple[0]',
    ]
  );

  const suggestions = buildTfvarsSuggestions({
    projectId,
    discovered: result.discovered,
  });
  assert.equal(
    suggestions.suggestions.some((s) => s.includes('hosting_site_id = "edge-default-site"')),
    true
  );
  assert.equal(
    suggestions.notes.some((n) => n.includes('App Check service enforcement modes are mixed')),
    true
  );
});

test('normalizeShaFingerprint strips colons and lowercases hex', () => {
  assert.equal(normalizeShaFingerprint('AA:BB:CC:00'), 'aabbcc00');
});
