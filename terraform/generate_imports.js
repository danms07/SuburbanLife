#!/usr/bin/env node
'use strict';

/**
 * Generates Terraform 1.5+ `import {}` blocks in `terraform/imports.tf` by
 * inspecting an existing Firebase / Google Cloud project via read-only REST
 * endpoints, matching live Firestore composite indexes and overrides against
 * `../firestore.indexes.json`, and reporting suggested `terraform.tfvars`
 * values so the first `terraform plan` aligns cleanly with existing resources.
 *
 * Authentication uses `GOOGLE_OAUTH_ACCESS_TOKEN` (or `--token-env`) with a
 * read-only fallback to `gcloud auth print-access-token`. No secrets are ever
 * written to disk or printed to output.
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const PROJECT_ID_REGEX = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
const RESOURCE_SEGMENT_REGEX = /^[A-Za-z0-9._~()+:@-]+$/;

const PROTECTED_APP_CHECK_SERVICES = Object.freeze([
  'firestore.googleapis.com',
  'firebasestorage.googleapis.com',
  'firebasedatabase.googleapis.com',
  'identitytoolkit.googleapis.com',
]);

const DEFAULT_OPTIONS = Object.freeze({
  project: null,
  tfvars: path.join(__dirname, 'terraform.tfvars'),
  out: path.join(__dirname, 'imports.tf'),
  indexesFile: path.resolve(__dirname, '..', 'firestore.indexes.json'),
  webAppId: null,
  androidPackage: null,
  iosBundle: null,
  hostingSite: null,
  rtdbInstance: null,
  recaptchaSiteKey: null,
  functionsSaId: null,
  docsPublisherSaId: null,
  noDocsPublisher: false,
  githubRepo: null,
  wifPool: null,
  wifProvider: null,
  token: null,
  tokenEnv: 'GOOGLE_OAUTH_ACCESS_TOKEN',
  dryRun: false,
  help: false,
});

function printHelp() {
  const helpText = `
Usage: node ./generate_imports.js [options]

Inspects an existing Firebase/GCP project via read-only REST APIs and writes
Terraform import blocks to terraform/imports.tf (or --out <path>).

Options:
  -p, --project <id>             GCP/Firebase project ID (defaults to project_id in terraform.tfvars)
      --tfvars <path>            Path to terraform.tfvars for input hints (default: ./terraform.tfvars)
  -o, --out <path>               Output file path (default: ./imports.tf)
      --indexes-file <path>      Path to firestore.indexes.json (default: ../firestore.indexes.json)
      --web-app-id <id>          Specific Firebase Web App ID when multiple Web Apps exist
      --android-package <pkg>    Android package name (default: tfvars or com.example.suburban_life)
      --ios-bundle <id>          Apple bundle ID (default: tfvars or com.example.suburbanLife)
      --hosting-site <id>        Firebase Hosting site ID (default: tfvars or <project_id>)
      --rtdb-instance <id>       Firebase RTDB instance ID (default: auto-detect DEFAULT_DATABASE)
      --recaptcha-site-key <id>  Specific reCAPTCHA Enterprise key ID when multiple exist
      --functions-sa-id <id>     Functions runtime SA ID (default: suburban-life-functions)
      --docs-publisher-sa-id <id> Docs publisher SA ID (default: suburban-life-docs-publisher)
      --no-docs-publisher        Skip docs_publisher[0] SA import discovery
      --github-repo <owner/repo> GitHub repo slug for Workload Identity Federation discovery
      --wif-pool <id>            WIF Pool ID (default: github-actions-pool)
      --wif-provider <id>        WIF Provider ID (default: github-actions-oidc)
      --token-env <VAR>          Env var containing OAuth token (default: GOOGLE_OAUTH_ACCESS_TOKEN)
      --token <token>            Explicit OAuth bearer token (prefer --token-env or gcloud ADC)
      --dry-run                  Print generated imports.tf and summary without writing to disk
  -h, --help                     Show this help message

Examples:
  node ./generate_imports.js --project my-suburban-life-prod
  node ./generate_imports.js --dry-run
  GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)" node ./generate_imports.js
`.trimStart();
  process.stdout.write(helpText);
}

/**
 * Parses CLI arguments into an options object. Throws on unknown flags or missing values.
 *
 * @param {string[]} argv
 * @returns {object}
 */
function parseArgs(argv) {
  const options = { ...DEFAULT_OPTIONS };

  const valueFlags = new Map([
    ['-p', 'project'],
    ['--project', 'project'],
    ['--tfvars', 'tfvars'],
    ['-o', 'out'],
    ['--out', 'out'],
    ['--indexes-file', 'indexesFile'],
    ['--web-app-id', 'webAppId'],
    ['--android-package', 'androidPackage'],
    ['--ios-bundle', 'iosBundle'],
    ['--hosting-site', 'hostingSite'],
    ['--rtdb-instance', 'rtdbInstance'],
    ['--recaptcha-site-key', 'recaptchaSiteKey'],
    ['--functions-sa-id', 'functionsSaId'],
    ['--docs-publisher-sa-id', 'docsPublisherSaId'],
    ['--github-repo', 'githubRepo'],
    ['--wif-pool', 'wifPool'],
    ['--wif-provider', 'wifProvider'],
    ['--token-env', 'tokenEnv'],
    ['--token', 'token'],
  ]);

  const booleanFlags = new Map([
    ['--no-docs-publisher', 'noDocsPublisher'],
    ['--dry-run', 'dryRun'],
    ['-h', 'help'],
    ['--help', 'help'],
  ]);

  for (let i = 0; i < argv.length; i += 1) {
    const rawArg = argv[i];
    if (!rawArg.startsWith('-')) {
      throw new Error(`Unexpected positional argument "${rawArg}". Use --help to see options.`);
    }

    const eqIdx = rawArg.indexOf('=');
    const flag = eqIdx >= 0 ? rawArg.slice(0, eqIdx) : rawArg;
    const inlineValue = eqIdx >= 0 ? rawArg.slice(eqIdx + 1) : null;

    if (booleanFlags.has(flag)) {
      if (inlineValue !== null) {
        throw new Error(`Flag "${flag}" does not accept a value.`);
      }
      options[booleanFlags.get(flag)] = true;
      continue;
    }

    if (valueFlags.has(flag)) {
      let value = inlineValue;
      if (value === null) {
        if (i + 1 >= argv.length || argv[i + 1].startsWith('-')) {
          throw new Error(`Flag "${flag}" requires a value.`);
        }
        value = argv[i + 1];
        i += 1;
      }
      options[valueFlags.get(flag)] = value;
      continue;
    }

    throw new Error(`Unknown option "${flag}". Use --help to see supported flags.`);
  }

  return options;
}

/**
 * Validates GCP/Firebase project ID syntax to prevent malformed URLs or path traversal.
 *
 * @param {string} projectId
 * @returns {boolean}
 */
function isValidProjectId(projectId) {
  return typeof projectId === 'string' && PROJECT_ID_REGEX.test(projectId);
}

/**
 * Validates a single REST path segment before embedding it in a URL.
 *
 * @param {string} segment
 * @param {string} label
 * @returns {string}
 */
function assertSafeSegment(segment, label) {
  if (
    typeof segment !== 'string' ||
    segment.length === 0 ||
    segment.includes('..') ||
    segment.includes('/') ||
    segment.includes('\\') ||
    !RESOURCE_SEGMENT_REGEX.test(segment)
  ) {
    throw new Error(`Invalid ${label} identifier received from input or API response.`);
  }
  return segment;
}

/**
 * Extracts the final non-empty segment from a GCP slash-delimited resource name.
 *
 * @param {string | undefined | null} resourceName
 * @returns {string | null}
 */
function extractLastPathSegment(resourceName) {
  if (typeof resourceName !== 'string' || resourceName.trim() === '') {
    return null;
  }
  const parts = resourceName.trim().split('/').filter(Boolean);
  return parts.length > 0 ? parts[parts.length - 1] : null;
}

/**
 * Escapes backslashes, double quotes, control characters, and HCL `${` / `%{`
 * interpolation markers so values emitted inside HCL double-quoted strings are safe.
 *
 * @param {string} value
 * @returns {string}
 */
function escapeHclString(value) {
  return String(value)
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\r/g, '\\r')
    .replace(/\n/g, '\\n')
    .replace(/\t/g, '\\t')
    .replace(/\$\{/g, () => '$${')
    .replace(/%\{/g, () => '%%{');
}

/**
 * Strips `#`, `//`, and block HCL comments outside of double-quoted strings.
 *
 * @param {string} source
 * @returns {string}
 */
function stripHclComments(source) {
  let out = '';
  let inString = false;
  let escaped = false;
  let inLineComment = false;
  let inBlockComment = false;

  for (let i = 0; i < source.length; i += 1) {
    const ch = source[i];
    const next = source[i + 1];

    if (inLineComment) {
      if (ch === '\n') {
        inLineComment = false;
        out += ch;
      }
      continue;
    }

    if (inBlockComment) {
      if (ch === '*' && next === '/') {
        inBlockComment = false;
        i += 1;
      } else if (ch === '\n') {
        out += '\n';
      }
      continue;
    }

    if (inString) {
      out += ch;
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }

    if (ch === '"') {
      inString = true;
      out += ch;
      continue;
    }

    if (ch === '#') {
      inLineComment = true;
      continue;
    }

    if (ch === '/' && next === '/') {
      inLineComment = true;
      i += 1;
      continue;
    }

    if (ch === '/' && next === '*') {
      inBlockComment = true;
      i += 1;
      continue;
    }

    out += ch;
  }

  return out;
}

/**
 * Reads top-level scalar and list-of-strings values from a `terraform.tfvars` file
 * without executing HCL or evaluating external expressions.
 *
 * @param {string} tfvarsPath
 * @returns {Record<string, unknown>}
 */
function readTfvarsHints(tfvarsPath) {
  if (!tfvarsPath || !fs.existsSync(tfvarsPath)) {
    return {};
  }

  const raw = fs.readFileSync(tfvarsPath, 'utf8');
  const clean = stripHclComments(raw);
  const result = {};

  // Match simple top-level assignments: key = "str" | true | false | null | [ ... ]
  const assignRegex = /^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|(true|false|null)|\[([\s\S]*?)\])/gm;
  let match;
  while ((match = assignRegex.exec(clean)) !== null) {
    const key = match[1];
    if (match[2] !== undefined) {
      result[key] = match[2].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
    } else if (match[3] !== undefined) {
      if (match[3] === 'true') result[key] = true;
      else if (match[3] === 'false') result[key] = false;
      else result[key] = null;
    } else if (match[4] !== undefined) {
      const items = [];
      const itemRegex = /"((?:[^"\\]|\\.)*)"/g;
      let itemMatch;
      while ((itemMatch = itemRegex.exec(match[4])) !== null) {
        items.push(itemMatch[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\'));
      }
      result[key] = items;
    }
  }

  return result;
}

/**
 * Normalizes a SHA-1 or SHA-256 fingerprint to lowercase hex without colons,
 * matching `local.normalized_android_sha*` in `terraform/project.tf`.
 *
 * @param {string} hash
 * @returns {string}
 */
function normalizeShaFingerprint(hash) {
  return String(hash || '')
    .replace(/:/g, '')
    .trim()
    .toLowerCase();
}

/**
 * Computes the exact `for_each` map key used by `google_firestore_index.indexes`
 * in `terraform/firestore.tf`.
 *
 * @param {{ collectionGroup: string, queryScope?: string, fields: Array<{ fieldPath: string, order?: string | null, arrayConfig?: string | null }> }} idx
 * @returns {string}
 */
function buildFirestoreIndexKey(idx) {
  const scope = idx.queryScope || 'COLLECTION';
  const fieldsPart = (idx.fields || [])
    .map((f) => `${f.fieldPath}=${f.order || f.arrayConfig || 'NONE'}`)
    .join(',');
  return `${idx.collectionGroup}:${scope}:${fieldsPart}`;
}

/**
 * Parses a Firestore index resource name into its constituent segments.
 *
 * @param {string} name
 * @returns {{ project: string, database: string, collectionGroup: string, indexId: string } | null}
 */
function parseFirestoreIndexName(name) {
  if (typeof name !== 'string') return null;
  const match = /^projects\/([^/]+)\/databases\/([^/]+)\/collectionGroups\/([^/]+)\/indexes\/([^/]+)$/.exec(
    name.trim()
  );
  if (!match) return null;
  return {
    project: match[1],
    database: match[2],
    collectionGroup: match[3],
    indexId: match[4],
  };
}

/**
 * Matches live Firestore composite indexes returned by Firestore REST API
 * (`collectionGroups/-/indexes`) against `firestore.indexes.json` definitions.
 * Handles Firestore's automatically appended trailing `__name__` field.
 *
 * @param {Array<object>} localIndexes
 * @param {Array<object>} liveIndexes
 * @param {string} projectId
 * @returns {{ matched: Array<{ key: string, id: string, state: string | null }>, unmatchedLocalKeys: string[], unmatchedLive: Array<{ name: string, collectionGroup: string, queryScope: string, fields: Array<object> }> }}
 */
function matchFirestoreCompositeIndexes(localIndexes, liveIndexes, projectId) {
  const localByKey = new Map();
  for (const idx of localIndexes || []) {
    localByKey.set(buildFirestoreIndexKey(idx), idx);
  }

  const matchedByKey = new Map();
  const unmatchedLive = [];

  for (const liveIdx of liveIndexes || []) {
    // Only consider active Native / Firestore-compatible indexes in (default) database.
    if (liveIdx.apiScope && liveIdx.apiScope !== 'ANY_API') {
      continue;
    }
    if (liveIdx.state === 'DELETING' || liveIdx.state === 'DELETED') {
      continue;
    }

    const parsed = parseFirestoreIndexName(liveIdx.name);
    if (!parsed || parsed.database !== '(default)') {
      continue;
    }

    const liveFields = Array.isArray(liveIdx.fields) ? liveIdx.fields : [];
    if (liveFields.length === 0) {
      continue;
    }

    const queryScope = liveIdx.queryScope || 'COLLECTION';
    const exactKey = buildFirestoreIndexKey({
      collectionGroup: parsed.collectionGroup,
      queryScope,
      fields: liveFields,
    });

    let matchedKey = null;
    if (localByKey.has(exactKey)) {
      matchedKey = exactKey;
    } else if (
      liveFields.length > 1 &&
      liveFields[liveFields.length - 1].fieldPath === '__name__'
    ) {
      const trimmedKey = buildFirestoreIndexKey({
        collectionGroup: parsed.collectionGroup,
        queryScope,
        fields: liveFields.slice(0, -1),
      });
      if (localByKey.has(trimmedKey)) {
        matchedKey = trimmedKey;
      }
    }

    if (matchedKey) {
      if (!matchedByKey.has(matchedKey)) {
        const importId = `projects/${assertSafeSegment(projectId, 'projectId')}/databases/(default)/collectionGroups/${assertSafeSegment(parsed.collectionGroup, 'collectionGroup')}/indexes/${assertSafeSegment(parsed.indexId, 'indexId')}`;
        matchedByKey.set(matchedKey, {
          key: matchedKey,
          id: importId,
          state: liveIdx.state || null,
        });
      }
    } else {
      unmatchedLive.push({
        name: liveIdx.name,
        collectionGroup: parsed.collectionGroup,
        queryScope,
        fields: liveFields,
      });
    }
  }

  // Emit matched indexes in deterministic firestore.indexes.json order.
  const matched = [];
  const unmatchedLocalKeys = [];
  for (const key of localByKey.keys()) {
    if (matchedByKey.has(key)) {
      matched.push(matchedByKey.get(key));
    } else {
      unmatchedLocalKeys.push(key);
    }
  }

  return { matched, unmatchedLocalKeys, unmatchedLive };
}

/**
 * Loads `indexes` and `fieldOverrides` from `firestore.indexes.json`.
 *
 * @param {string} indexesFilePath
 * @returns {{ indexes: Array<object>, fieldOverrides: Array<object> }}
 */
function loadFirestoreIndexesConfig(indexesFilePath) {
  if (!fs.existsSync(indexesFilePath)) {
    throw new Error(`Could not find firestore.indexes.json at "${indexesFilePath}".`);
  }
  const parsed = JSON.parse(fs.readFileSync(indexesFilePath, 'utf8'));
  return {
    indexes: Array.isArray(parsed.indexes) ? parsed.indexes : [],
    fieldOverrides: Array.isArray(parsed.fieldOverrides) ? parsed.fieldOverrides : [],
  };
}

/**
 * Resolves a GCP OAuth2 access token from `--token`, `--token-env` env var, or
 * `gcloud auth print-access-token` using `execFileSync` (no shell interpolation).
 *
 * @param {{ token: string | null, tokenEnv: string, execFileSyncImpl?: Function, env?: NodeJS.ProcessEnv }} params
 * @returns {string}
 */
function resolveAccessToken({
  token,
  tokenEnv,
  execFileSyncImpl = execFileSync,
  env = process.env,
}) {
  if (token && token.trim() !== '') {
    return token.trim();
  }

  if (tokenEnv && env[tokenEnv] && String(env[tokenEnv]).trim() !== '') {
    return String(env[tokenEnv]).trim();
  }

  try {
    const output = execFileSyncImpl('gcloud', ['auth', 'print-access-token'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 15000,
    });
    const resolved = String(output || '').trim();
    if (!resolved) {
      throw new Error('gcloud returned an empty access token.');
    }
    return resolved;
  } catch (err) {
    throw new Error(
      `Failed to obtain a GCP OAuth access token (${err.message}). Run "gcloud auth login" or set ${tokenEnv || 'GOOGLE_OAUTH_ACCESS_TOKEN'}.`
    );
  }
}

/**
 * Builds a strict read-only Google Cloud / Firebase REST client that only
 * transmits credentials over HTTPS to `*.googleapis.com` with redirects disabled.
 *
 * @param {{ accessToken: string, projectId: string, fetchImpl?: Function }} params
 */
function createGcpApiClient({ accessToken, projectId, fetchImpl = fetch }) {
  assertSafeSegment(projectId, 'projectId');

  async function requestJson(url, { allowMissing = false } = {}) {
    const parsedUrl = new URL(url);
    if (
      parsedUrl.protocol !== 'https:' ||
      parsedUrl.username ||
      parsedUrl.password ||
      !parsedUrl.hostname.endsWith('.googleapis.com')
    ) {
      throw new Error(`Refusing to send credentials to non-googleapis endpoint "${parsedUrl.origin}".`);
    }

    const response = await fetchImpl(parsedUrl.toString(), {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: 'application/json',
        'x-goog-user-project': projectId,
      },
      redirect: 'error',
      signal: AbortSignal.timeout(20000),
    });

    if (response.ok) {
      const text = typeof response.text === 'function' ? await response.text() : null;
      if (text !== null) {
        return { ok: true, status: response.status, data: text ? JSON.parse(text) : {} };
      }
      return { ok: true, status: response.status, data: await response.json() };
    }

    let apiMessage = response.statusText || `HTTP ${response.status}`;
    try {
      const errBody = await response.json();
      if (errBody && errBody.error && errBody.error.message) {
        apiMessage = errBody.error.message;
      }
    } catch {
      // Ignore non-JSON error body.
    }

    if (allowMissing && (response.status === 404 || response.status === 403 || response.status === 400)) {
      return { ok: false, status: response.status, error: apiMessage, data: null };
    }

    throw new Error(`GET ${parsedUrl.pathname} failed (${response.status}): ${apiMessage}`);
  }

  async function listPaginated(baseUrl, itemsKey, options = {}) {
    const items = [];
    let pageToken = null;
    const separator = baseUrl.includes('?') ? '&' : '?';

    do {
      const pageUrl = pageToken
        ? `${baseUrl}${separator}pageToken=${encodeURIComponent(pageToken)}`
        : baseUrl;
      const res = await requestJson(pageUrl, options);
      if (!res.ok) {
        return { ok: false, status: res.status, error: res.error, items: [] };
      }
      if (Array.isArray(res.data && res.data[itemsKey])) {
        items.push(...res.data[itemsKey]);
      }
      pageToken = (res.data && res.data.nextPageToken) || null;
    } while (pageToken);

    return { ok: true, status: 200, items };
  }

  return { requestJson, listPaginated };
}

/**
 * Selects the best matching Firebase Android or Apple app from a list, preferring
 * an exact bundle/package ID match and falling back when only one active app exists.
 *
 * @param {Array<object>} apps
 * @param {string} idField
 * @param {string} expectedValue
 * @returns {{ app: object | null, exactMatch: boolean, multipleWithoutMatch: boolean }}
 */
function selectPlatformApp(apps, idField, expectedValue) {
  const activeApps = (apps || []).filter((a) => a.state !== 'DELETED');
  const exact = activeApps.find((a) => a[idField] === expectedValue);
  if (exact) {
    return { app: exact, exactMatch: true, multipleWithoutMatch: false };
  }
  if (activeApps.length === 1) {
    return { app: activeApps[0], exactMatch: false, multipleWithoutMatch: false };
  }
  return {
    app: null,
    exactMatch: false,
    multipleWithoutMatch: activeApps.length > 1,
  };
}

/**
 * Discovers live GCP/Firebase resources matching SuburbanLife's Terraform schema.
 *
 * @param {{ projectId: string, options: object, tfvarsHints: object, localIndexesConfig: { indexes: Array<object>, fieldOverrides: Array<object> }, apiClient: ReturnType<typeof createGcpApiClient> }} params
 */
async function discoverResources({
  projectId,
  options,
  tfvarsHints,
  localIndexesConfig,
  apiClient,
}) {
  assertSafeSegment(projectId, 'projectId');

  const imports = [];
  const commentedImports = [];
  const warnings = [];
  const discovered = {
    projectId,
    firestore: {},
    rtdb: {},
    storage: {},
    apps: {},
    hosting: {},
    auth: {},
    appCheck: { services: {} },
    iam: {},
  };

  const androidPackage =
    options.androidPackage || tfvarsHints.android_package_name || 'com.example.suburban_life';
  const iosBundle =
    options.iosBundle || tfvarsHints.ios_bundle_id || 'com.example.suburbanLife';
  const hostingSiteId =
    options.hostingSite || tfvarsHints.hosting_site_id || projectId;
  const rtdbInstanceOverride =
    options.rtdbInstance || tfvarsHints.rtdb_instance_id || null;
  const functionsSaId =
    options.functionsSaId || tfvarsHints.functions_service_account_id || 'suburban-life-functions';
  const docsPublisherSaId =
    options.docsPublisherSaId ||
    tfvarsHints.docs_publisher_service_account_id ||
    'suburban-life-docs-publisher';
  const createDocsPublisherSa = options.noDocsPublisher
    ? false
    : tfvarsHints.create_docs_publisher_service_account !== false;
  const githubRepository = options.githubRepo || tfvarsHints.github_repository || null;
  const wifPoolId = options.wifPool || tfvarsHints.github_wif_pool_id || 'github-actions-pool';
  const wifProviderId =
    options.wifProvider || tfvarsHints.github_wif_provider_id || 'github-actions-oidc';

  // 1. Check enabled GCP APIs (if Service Usage is accessible) to avoid noisy disabled-API probes.
  let enabledServices = null;
  const svcList = await apiClient.listPaginated(
    `https://serviceusage.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/services?filter=${encodeURIComponent('state:ENABLED')}&pageSize=200`,
    'services',
    { allowMissing: true }
  );
  if (svcList.ok) {
    enabledServices = new Set(
      svcList.items
        .map((item) => (item && item.config && item.config.name) || extractLastPathSegment(item && item.name))
        .filter(Boolean)
    );
  } else {
    warnings.push(
      `Could not list enabled APIs via Service Usage (${svcList.status}: ${svcList.error}); probing endpoints directly.`
    );
  }

  const isApiEnabled = (serviceName) =>
    enabledServices === null || enabledServices.has(serviceName);

  // 2. Firebase Project & Apps
  let webAppId = options.webAppId || null;
  let androidAppId = null;
  let appleAppId = null;
  let androidSha256 = Array.isArray(tfvarsHints.android_sha256_hashes)
    ? tfvarsHints.android_sha256_hashes.map(normalizeShaFingerprint).filter(Boolean)
    : [];
  let iosTeamId = tfvarsHints.ios_team_id || null;

  if (isApiEnabled('firebase.googleapis.com')) {
    const fbProject = await apiClient.requestJson(
      `https://firebase.googleapis.com/v1beta1/projects/${encodeURIComponent(projectId)}`,
      { allowMissing: true }
    );
    if (fbProject.ok) {
      imports.push({
        category: 'Firebase Project',
        to: 'google_firebase_project.default',
        id: `projects/${projectId}`,
      });
    } else if (fbProject.status !== 404) {
      warnings.push(`Firebase project lookup skipped (${fbProject.status}: ${fbProject.error}).`);
    }

    // Web App
    const webAppsRes = await apiClient.listPaginated(
      `https://firebase.googleapis.com/v1beta1/projects/${encodeURIComponent(projectId)}/webApps?pageSize=100`,
      'apps',
      { allowMissing: true }
    );
    if (webAppsRes.ok) {
      const activeWebApps = webAppsRes.items.filter((a) => a.state !== 'DELETED');
      let selectedWeb = null;
      if (webAppId) {
        selectedWeb = activeWebApps.find((a) => a.appId === webAppId) || null;
        if (!selectedWeb) {
          warnings.push(`Specified --web-app-id "${webAppId}" was not found on project "${projectId}".`);
        }
      } else if (activeWebApps.length === 1) {
        selectedWeb = activeWebApps[0];
      } else if (activeWebApps.length > 1) {
        const targetDisplay = tfvarsHints.web_app_display_name || 'Suburban Life Web';
        selectedWeb =
          activeWebApps.find((a) => a.displayName === targetDisplay) || activeWebApps[0];
        warnings.push(
          `Multiple Firebase Web Apps found (${activeWebApps.map((a) => a.appId).join(', ')}); selected "${selectedWeb.appId}". Pass --web-app-id to override.`
        );
      }

      if (selectedWeb) {
        webAppId = assertSafeSegment(selectedWeb.appId, 'webAppId');
        discovered.apps.webAppId = webAppId;
        discovered.apps.webDisplayName = selectedWeb.displayName || null;
        imports.push({
          category: 'Firebase Apps & Hosting',
          to: 'google_firebase_web_app.default',
          id: `projects/${projectId}/webApps/${webAppId}`,
        });
      }
    }

    // Android App + SHA fingerprints
    const androidAppsRes = await apiClient.listPaginated(
      `https://firebase.googleapis.com/v1beta1/projects/${encodeURIComponent(projectId)}/androidApps?pageSize=100`,
      'apps',
      { allowMissing: true }
    );
    if (androidAppsRes.ok) {
      const picked = selectPlatformApp(androidAppsRes.items, 'packageName', androidPackage);
      if (picked.app) {
        androidAppId = assertSafeSegment(picked.app.appId, 'androidAppId');
        discovered.apps.androidAppId = androidAppId;
        discovered.apps.androidPackageName = picked.app.packageName;
        discovered.apps.androidDisplayName = picked.app.displayName || null;
        if (!picked.exactMatch) {
          warnings.push(
            `Live Android app packageName "${picked.app.packageName}" differs from expected "${androidPackage}". Update android_package_name in terraform.tfvars.`
          );
        }
        imports.push({
          category: 'Firebase Apps & Hosting',
          to: 'google_firebase_android_app.default',
          id: `projects/${projectId}/androidApps/${androidAppId}`,
        });

        const shaRes = await apiClient.requestJson(
          `https://firebase.googleapis.com/v1beta1/projects/${encodeURIComponent(projectId)}/androidApps/${encodeURIComponent(androidAppId)}/sha`,
          { allowMissing: true }
        );
        if (shaRes.ok && Array.isArray(shaRes.data && shaRes.data.certificates)) {
          const sha1 = [];
          const sha256 = [];
          for (const cert of shaRes.data.certificates) {
            const norm = normalizeShaFingerprint(cert.shaHash);
            if (!norm) continue;
            if (cert.certType === 'SHA_1') sha1.push(norm);
            else if (cert.certType === 'SHA_256') sha256.push(norm);
          }
          discovered.apps.androidSha1Hashes = sha1;
          discovered.apps.androidSha256Hashes = sha256;
          if (sha256.length > 0) {
            androidSha256 = Array.from(new Set([...androidSha256, ...sha256]));
          }
        }
      } else if (picked.multipleWithoutMatch) {
        warnings.push(
          `Multiple Android apps exist and none matches packageName "${androidPackage}". Pass --android-package to select one.`
        );
      }
    }

    // Apple App
    const iosAppsRes = await apiClient.listPaginated(
      `https://firebase.googleapis.com/v1beta1/projects/${encodeURIComponent(projectId)}/iosApps?pageSize=100`,
      'apps',
      { allowMissing: true }
    );
    if (iosAppsRes.ok) {
      const picked = selectPlatformApp(iosAppsRes.items, 'bundleId', iosBundle);
      if (picked.app) {
        appleAppId = assertSafeSegment(picked.app.appId, 'appleAppId');
        discovered.apps.appleAppId = appleAppId;
        discovered.apps.iosBundleId = picked.app.bundleId;
        discovered.apps.iosDisplayName = picked.app.displayName || null;
        discovered.apps.iosTeamId = picked.app.teamId || null;
        discovered.apps.iosAppStoreId = picked.app.appStoreId || null;
        if (picked.app.teamId) {
          iosTeamId = picked.app.teamId;
        }
        if (!picked.exactMatch) {
          warnings.push(
            `Live Apple app bundleId "${picked.app.bundleId}" differs from expected "${iosBundle}". Update ios_bundle_id in terraform.tfvars.`
          );
        }
        imports.push({
          category: 'Firebase Apps & Hosting',
          to: 'google_firebase_apple_app.default',
          id: `projects/${projectId}/iosApps/${appleAppId}`,
        });
      } else if (picked.multipleWithoutMatch) {
        warnings.push(
          `Multiple Apple apps exist and none matches bundleId "${iosBundle}". Pass --ios-bundle to select one.`
        );
      }
    }
  }

  // 3. Firebase Hosting Site
  if (isApiEnabled('firebasehosting.googleapis.com')) {
    const safeSiteId = assertSafeSegment(hostingSiteId, 'hostingSiteId');
    let siteRes = await apiClient.requestJson(
      `https://firebasehosting.googleapis.com/v1beta1/projects/${encodeURIComponent(projectId)}/sites/${encodeURIComponent(safeSiteId)}`,
      { allowMissing: true }
    );
    let resolvedSiteId = safeSiteId;

    if (!siteRes.ok && !options.hostingSite && !tfvarsHints.hosting_site_id) {
      const sitesList = await apiClient.listPaginated(
        `https://firebasehosting.googleapis.com/v1beta1/projects/${encodeURIComponent(projectId)}/sites?pageSize=100`,
        'sites',
        { allowMissing: true }
      );
      if (sitesList.ok && sitesList.items.length > 0) {
        const defaultSite =
          sitesList.items.find((s) => s.type === 'DEFAULT_SITE') || sitesList.items[0];
        const seg = extractLastPathSegment(defaultSite.name);
        if (seg) {
          resolvedSiteId = assertSafeSegment(seg, 'hostingSiteId');
          siteRes = { ok: true, status: 200, data: defaultSite };
        }
      }
    }

    if (siteRes.ok) {
      discovered.hosting.siteId = resolvedSiteId;
      imports.push({
        category: 'Firebase Apps & Hosting',
        to: 'google_firebase_hosting_site.default',
        id: `projects/${projectId}/sites/${resolvedSiteId}`,
      });
    }
  }

  // 4. Identity Platform / Firebase Auth
  if (isApiEnabled('identitytoolkit.googleapis.com')) {
    const authRes = await apiClient.requestJson(
      `https://identitytoolkit.googleapis.com/v2/projects/${encodeURIComponent(projectId)}/config`,
      { allowMissing: true }
    );
    if (authRes.ok && authRes.data) {
      discovered.auth.allowDuplicateEmails = Boolean(
        authRes.data.signIn && authRes.data.signIn.allowDuplicateEmails
      );
      discovered.auth.authorizedDomains = Array.isArray(authRes.data.authorizedDomains)
        ? authRes.data.authorizedDomains
        : [];
      imports.push({
        category: 'Authentication (Identity Platform)',
        to: 'google_identity_platform_config.default',
        id: `projects/${projectId}/config`,
      });
    }
  }

  // 5. Cloud Firestore DB, Composite Indexes, and Field Overrides
  let firestoreDbExists = false;
  if (isApiEnabled('firestore.googleapis.com')) {
    const dbRes = await apiClient.requestJson(
      `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/databases/(default)`,
      { allowMissing: true }
    );
    if (dbRes.ok && dbRes.data) {
      firestoreDbExists = true;
      discovered.firestore.locationId = dbRes.data.locationId || null;
      discovered.firestore.deleteProtectionEnabled =
        dbRes.data.deleteProtectionState === 'DELETE_PROTECTION_ENABLED';
      discovered.firestore.pitrEnabled =
        dbRes.data.pointInTimeRecoveryEnablement === 'POINT_IN_TIME_RECOVERY_ENABLED';
      if (dbRes.data.type && dbRes.data.type !== 'FIRESTORE_NATIVE') {
        warnings.push(
          `Existing Firestore (default) database type is "${dbRes.data.type}", expected "FIRESTORE_NATIVE".`
        );
      }

      imports.push({
        category: 'Cloud Firestore',
        to: 'google_firestore_database.default',
        id: `projects/${projectId}/databases/(default)`,
      });

      // Composite Indexes
      const liveIndexesRes = await apiClient.listPaginated(
        `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/databases/(default)/collectionGroups/-/indexes?pageSize=200`,
        'indexes',
        { allowMissing: true }
      );

      if (liveIndexesRes.ok) {
        const indexMatch = matchFirestoreCompositeIndexes(
          localIndexesConfig.indexes,
          liveIndexesRes.items,
          projectId
        );
        discovered.firestore.totalLocalIndexes = localIndexesConfig.indexes.length;
        discovered.firestore.matchedIndexesCount = indexMatch.matched.length;
        discovered.firestore.unmatchedLocalIndexesCount = indexMatch.unmatchedLocalKeys.length;
        discovered.firestore.unmatchedLiveIndexes = indexMatch.unmatchedLive;

        for (const item of indexMatch.matched) {
          imports.push({
            category: 'Cloud Firestore Composite Indexes',
            to: `google_firestore_index.indexes["${escapeHclString(item.key)}"]`,
            id: item.id,
          });
        }
      } else {
        warnings.push(
          `Could not list Firestore composite indexes (${liveIndexesRes.status}: ${liveIndexesRes.error}).`
        );
      }

      // Single-field overrides & TTL policies
      const fieldStatuses = {};
      for (const fo of localIndexesConfig.fieldOverrides) {
        const col = assertSafeSegment(fo.collectionGroup, 'collectionGroup');
        const field = assertSafeSegment(fo.fieldPath, 'fieldPath');
        const fieldRes = await apiClient.requestJson(
          `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/databases/(default)/collectionGroups/${encodeURIComponent(col)}/fields/${encodeURIComponent(field)}`,
          { allowMissing: true }
        );
        if (fieldRes.ok && fieldRes.data) {
          const mapKey = `${col}.${field}`;
          fieldStatuses[mapKey] = {
            usesAncestorConfig: Boolean(fieldRes.data.indexConfig && fieldRes.data.indexConfig.usesAncestorConfig),
            ttlState: (fieldRes.data.ttlConfig && fieldRes.data.ttlConfig.state) || null,
          };
          imports.push({
            category: 'Cloud Firestore Field Overrides & TTL',
            to: `google_firestore_field.overrides["${escapeHclString(mapKey)}"]`,
            id: `projects/${projectId}/databases/(default)/collectionGroups/${col}/fields/${field}`,
          });
        }
      }
      discovered.firestore.fieldStatuses = fieldStatuses;
    }
  }

  // 6. Firebase Realtime Database
  if (isApiEnabled('firebasedatabase.googleapis.com')) {
    const rtdbRes = await apiClient.listPaginated(
      `https://firebasedatabase.googleapis.com/v1beta/projects/${encodeURIComponent(projectId)}/locations/-/instances?pageSize=100`,
      'instances',
      { allowMissing: true }
    );
    if (rtdbRes.ok) {
      const activeInstances = rtdbRes.items.filter((i) => i.state !== 'DELETED');
      let selectedInst = null;
      if (rtdbInstanceOverride) {
        selectedInst = activeInstances.find(
          (i) => extractLastPathSegment(i.name) === rtdbInstanceOverride
        );
      } else {
        selectedInst =
          activeInstances.find((i) => i.type === 'DEFAULT_DATABASE') ||
          activeInstances.find((i) => extractLastPathSegment(i.name) === `${projectId}-default-rtdb`) ||
          (activeInstances.length === 1 ? activeInstances[0] : null);
      }

      if (selectedInst) {
        const instMatch = /^projects\/([^/]+)\/locations\/([^/]+)\/instances\/([^/]+)$/.exec(
          selectedInst.name || ''
        );
        if (instMatch) {
          const region = assertSafeSegment(instMatch[2], 'rtdbRegion');
          const instanceId = assertSafeSegment(instMatch[3], 'rtdbInstanceId');
          discovered.rtdb.region = region;
          discovered.rtdb.instanceId = instanceId;
          imports.push({
            category: 'Firebase Realtime Database',
            to: 'google_firebase_database_instance.default',
            id: `projects/${projectId}/locations/${region}/instances/${instanceId}`,
          });
        }
      }
    }
  }

  // 7. Firebase Default Storage Bucket
  let storageBucketId = null;
  if (isApiEnabled('firebasestorage.googleapis.com')) {
    const bucketRes = await apiClient.requestJson(
      `https://firebasestorage.googleapis.com/v1beta/projects/${encodeURIComponent(projectId)}/defaultBucket`,
      { allowMissing: true }
    );
    if (bucketRes.ok && bucketRes.data && bucketRes.data.bucket && bucketRes.data.bucket.name) {
      const extractedBucket = extractLastPathSegment(bucketRes.data.bucket.name);
      if (extractedBucket) {
        storageBucketId = assertSafeSegment(extractedBucket, 'storageBucketId');
        discovered.storage.bucketId = storageBucketId;
        discovered.storage.location = bucketRes.data.location || null;
        imports.push({
          category: 'Cloud Storage for Firebase',
          to: 'google_firebase_storage_default_bucket.default',
          id: `projects/${projectId}/defaultBucket`,
        });
      }
    }
  }

  // 8. Firebase Security Rules Releases
  if (isApiEnabled('firebaserules.googleapis.com')) {
    const releasesRes = await apiClient.listPaginated(
      `https://firebaserules.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/releases?pageSize=100`,
      'releases',
      { allowMissing: true }
    );
    if (releasesRes.ok) {
      const firestoreRelease = releasesRes.items.find(
        (r) => typeof r.name === 'string' && r.name.endsWith('/releases/cloud.firestore')
      );
      if (firestoreRelease && firestoreDbExists) {
        imports.push({
          category: 'Security Rules Releases',
          to: 'google_firebaserules_release.firestore',
          id: `projects/${projectId}/releases/cloud.firestore`,
        });
      }

      if (storageBucketId) {
        const expectedSuffix = `/releases/firebase.storage/${storageBucketId}`;
        const storageRelease = releasesRes.items.find(
          (r) => typeof r.name === 'string' && r.name.endsWith(expectedSuffix)
        );
        if (storageRelease) {
          imports.push({
            category: 'Security Rules Releases',
            to: 'google_firebaserules_release.storage',
            id: `projects/${projectId}/releases/firebase.storage/${storageBucketId}`,
          });
        }
      }
    }
  }

  // 9. Firebase App Check & reCAPTCHA Enterprise
  let linkedRecaptchaKeyId = options.recaptchaSiteKey || null;
  if (isApiEnabled('firebaseappcheck.googleapis.com')) {
    if (webAppId) {
      const webAppCheck = await apiClient.requestJson(
        `https://firebaseappcheck.googleapis.com/v1beta/projects/${encodeURIComponent(projectId)}/apps/${encodeURIComponent(webAppId)}/recaptchaEnterpriseConfig`,
        { allowMissing: true }
      );
      if (webAppCheck.ok && webAppCheck.data) {
        const keySeg = extractLastPathSegment(webAppCheck.data.siteKey);
        if (!linkedRecaptchaKeyId && keySeg) {
          linkedRecaptchaKeyId = keySeg;
        }
        if (webAppCheck.data.tokenTtl) {
          discovered.appCheck.tokenTtl = webAppCheck.data.tokenTtl;
        }
        imports.push({
          category: 'Firebase App Check & reCAPTCHA Enterprise',
          to: 'google_firebase_app_check_recaptcha_enterprise_config.web',
          id: `projects/${projectId}/apps/${webAppId}/recaptchaEnterpriseConfig`,
        });
      }
    }

    if (androidAppId) {
      const playConfig = await apiClient.requestJson(
        `https://firebaseappcheck.googleapis.com/v1beta/projects/${encodeURIComponent(projectId)}/apps/${encodeURIComponent(androidAppId)}/playIntegrityConfig`,
        { allowMissing: true }
      );
      if (playConfig.ok && playConfig.data) {
        const targetId = `projects/${projectId}/apps/${androidAppId}/playIntegrityConfig`;
        if (androidSha256.length > 0) {
          imports.push({
            category: 'Firebase App Check & reCAPTCHA Enterprise',
            to: 'google_firebase_app_check_play_integrity_config.android[0]',
            id: targetId,
          });
        } else {
          commentedImports.push({
            category: 'Firebase App Check & reCAPTCHA Enterprise',
            to: 'google_firebase_app_check_play_integrity_config.android[0]',
            id: targetId,
            reason:
              'Play Integrity config exists remotely, but no android_sha256_hashes were found in tfvars or /sha; add android_sha256_hashes to terraform.tfvars and uncomment.',
          });
        }
      }
    }

    if (appleAppId) {
      const attestConfig = await apiClient.requestJson(
        `https://firebaseappcheck.googleapis.com/v1beta/projects/${encodeURIComponent(projectId)}/apps/${encodeURIComponent(appleAppId)}/appAttestConfig`,
        { allowMissing: true }
      );
      if (attestConfig.ok && attestConfig.data) {
        const targetId = `projects/${projectId}/apps/${appleAppId}/appAttestConfig`;
        if (iosTeamId && String(iosTeamId).trim() !== '') {
          imports.push({
            category: 'Firebase App Check & reCAPTCHA Enterprise',
            to: 'google_firebase_app_check_app_attest_config.apple[0]',
            id: targetId,
          });
        } else {
          commentedImports.push({
            category: 'Firebase App Check & reCAPTCHA Enterprise',
            to: 'google_firebase_app_check_app_attest_config.apple[0]',
            id: targetId,
            reason:
              'Apple App Attest config exists remotely, but ios_team_id is unset; set ios_team_id in terraform.tfvars and uncomment.',
          });
        }
      }
    }

    for (const svc of PROTECTED_APP_CHECK_SERVICES) {
      const svcCfg = await apiClient.requestJson(
        `https://firebaseappcheck.googleapis.com/v1beta/projects/${encodeURIComponent(projectId)}/services/${encodeURIComponent(svc)}`,
        { allowMissing: true }
      );
      if (svcCfg.ok && svcCfg.data && svcCfg.data.enforcementMode) {
        const mode = svcCfg.data.enforcementMode;
        discovered.appCheck.services[svc] = mode;
        if (mode === 'UNENFORCED' || mode === 'ENFORCED') {
          imports.push({
            category: 'Firebase App Check & reCAPTCHA Enterprise',
            to: `google_firebase_app_check_service_config.services["${escapeHclString(svc)}"]`,
            id: `projects/${projectId}/services/${svc}`,
          });
        }
      }
    }
  }

  if (isApiEnabled('recaptchaenterprise.googleapis.com')) {
    const keysRes = await apiClient.listPaginated(
      `https://recaptchaenterprise.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/keys?pageSize=100`,
      'keys',
      { allowMissing: true }
    );
    let selectedKey = null;

    if (keysRes.ok && keysRes.items.length > 0) {
      if (linkedRecaptchaKeyId) {
        selectedKey = keysRes.items.find(
          (k) => extractLastPathSegment(k.name) === linkedRecaptchaKeyId
        );
      }
      if (!selectedKey && !options.recaptchaSiteKey) {
        const webKeys = keysRes.items.filter((k) => Boolean(k.webSettings));
        if (webKeys.length === 1) {
          selectedKey = webKeys[0];
        } else if (webKeys.length > 1) {
          selectedKey =
            webKeys.find((k) => k.displayName === 'Suburban Life Web App Check') || null;
          if (!selectedKey) {
            warnings.push(
              `Multiple reCAPTCHA Enterprise web keys found (${webKeys.map((k) => extractLastPathSegment(k.name)).join(', ')}); pass --recaptcha-site-key to import a specific one.`
            );
          }
        }
      }
    } else if (linkedRecaptchaKeyId) {
      const directKeyRes = await apiClient.requestJson(
        `https://recaptchaenterprise.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/keys/${encodeURIComponent(assertSafeSegment(linkedRecaptchaKeyId, 'recaptchaSiteKey'))}`,
        { allowMissing: true }
      );
      if (directKeyRes.ok && directKeyRes.data) {
        selectedKey = directKeyRes.data;
      }
    }

    if (selectedKey) {
      const keyId = assertSafeSegment(
        extractLastPathSegment(selectedKey.name),
        'recaptchaKeyId'
      );
      discovered.appCheck.recaptchaKeyId = keyId;
      discovered.appCheck.recaptchaDisplayName = selectedKey.displayName || null;
      discovered.appCheck.recaptchaAllowedDomains =
        (selectedKey.webSettings && selectedKey.webSettings.allowedDomains) || [];
      imports.push({
        category: 'Firebase App Check & reCAPTCHA Enterprise',
        to: 'google_recaptcha_enterprise_key.web',
        id: `projects/${projectId}/keys/${keyId}`,
      });
    }
  }

  // 10. IAM Service Accounts & Workload Identity Federation
  if (isApiEnabled('iam.googleapis.com')) {
    const safeFunctionsSaId = assertSafeSegment(functionsSaId, 'functionsSaId');
    const fnSaEmail = `${safeFunctionsSaId}@${projectId}.iam.gserviceaccount.com`;
    const fnSaRes = await apiClient.requestJson(
      `https://iam.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/serviceAccounts/${encodeURIComponent(fnSaEmail)}`,
      { allowMissing: true }
    );
    if (fnSaRes.ok) {
      imports.push({
        category: 'IAM & Workload Identity Federation',
        to: 'google_service_account.functions_runtime',
        id: `projects/${projectId}/serviceAccounts/${fnSaEmail}`,
      });
    }

    if (createDocsPublisherSa) {
      const safeDocsSaId = assertSafeSegment(docsPublisherSaId, 'docsPublisherSaId');
      const docsSaEmail = `${safeDocsSaId}@${projectId}.iam.gserviceaccount.com`;
      const docsSaRes = await apiClient.requestJson(
        `https://iam.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/serviceAccounts/${encodeURIComponent(docsSaEmail)}`,
        { allowMissing: true }
      );
      if (docsSaRes.ok) {
        imports.push({
          category: 'IAM & Workload Identity Federation',
          to: 'google_service_account.docs_publisher[0]',
          id: `projects/${projectId}/serviceAccounts/${docsSaEmail}`,
        });
      }
    }

    const safePoolId = assertSafeSegment(wifPoolId, 'wifPoolId');
    const safeProviderId = assertSafeSegment(wifProviderId, 'wifProviderId');
    const poolRes = await apiClient.requestJson(
      `https://iam.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/locations/global/workloadIdentityPools/${encodeURIComponent(safePoolId)}`,
      { allowMissing: true }
    );
    if (poolRes.ok && poolRes.data && poolRes.data.state !== 'DELETED') {
      const poolImportId = `projects/${projectId}/locations/global/workloadIdentityPools/${safePoolId}`;
      const provRes = await apiClient.requestJson(
        `https://iam.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/locations/global/workloadIdentityPools/${encodeURIComponent(safePoolId)}/providers/${encodeURIComponent(safeProviderId)}`,
        { allowMissing: true }
      );
      const providerImportId = `${poolImportId}/providers/${safeProviderId}`;

      if (githubRepository) {
        imports.push({
          category: 'IAM & Workload Identity Federation',
          to: 'google_iam_workload_identity_pool.github_actions[0]',
          id: poolImportId,
        });
        if (provRes.ok && provRes.data && provRes.data.state !== 'DELETED') {
          imports.push({
            category: 'IAM & Workload Identity Federation',
            to: 'google_iam_workload_identity_pool_provider.github_actions[0]',
            id: providerImportId,
          });
        }
      } else {
        commentedImports.push({
          category: 'IAM & Workload Identity Federation',
          to: 'google_iam_workload_identity_pool.github_actions[0]',
          id: poolImportId,
          reason:
            'WIF pool exists remotely, but github_repository is null; set github_repository in terraform.tfvars and pass --github-repo to import.',
        });
        if (provRes.ok && provRes.data && provRes.data.state !== 'DELETED') {
          commentedImports.push({
            category: 'IAM & Workload Identity Federation',
            to: 'google_iam_workload_identity_pool_provider.github_actions[0]',
            id: providerImportId,
            reason:
              'WIF provider exists remotely, but github_repository is null; set github_repository in terraform.tfvars and pass --github-repo to import.',
          });
        }
      }
    }
  }

  return { imports, commentedImports, warnings, discovered };
}

/**
 * Renders Terraform 1.5+ `import {}` blocks grouped cleanly by subsystem.
 *
 * @param {{ projectId: string, generatedAt: string, imports: Array<object>, commentedImports: Array<object>, warnings: Array<string> }} params
 * @returns {string}
 */
function renderImportsTf({
  projectId,
  generatedAt,
  imports,
  commentedImports,
  warnings,
}) {
  const lines = [
    '# ==============================================================================',
    `# Auto-generated Terraform import blocks for project "${escapeHclString(projectId)}"`,
    `# Generated at: ${generatedAt}`,
    '# Regenerate with: node ./generate_imports.js',
    '# Review `terraform plan` carefully and remove this file once `terraform apply` succeeds.',
    '# ==============================================================================',
    '',
  ];

  if (warnings.length > 0) {
    lines.push('# Warnings during discovery:');
    for (const warn of warnings) {
      lines.push(`#   - ${warn.replace(/\r?\n/g, ' ')}`);
    }
    lines.push('');
  }

  if (imports.length === 0 && commentedImports.length === 0) {
    lines.push('# No existing adoptable Firebase/GCP resources were discovered for this project.');
    lines.push('# Set `create_project = false` and run `terraform apply` to provision them cleanly.');
    lines.push('');
    return lines.join('\n');
  }

  let currentCategory = null;
  for (const item of imports) {
    if (item.category !== currentCategory) {
      if (currentCategory !== null) lines.push('');
      currentCategory = item.category;
      lines.push(`# ------------------------------------------------------------------------------`);
      lines.push(`# ${currentCategory}`);
      lines.push(`# ------------------------------------------------------------------------------`);
    }
    lines.push('import {');
    lines.push(`  to = ${item.to}`);
    lines.push(`  id = "${escapeHclString(item.id)}"`);
    lines.push('}');
    lines.push('');
  }

  if (commentedImports.length > 0) {
    lines.push('# ------------------------------------------------------------------------------');
    lines.push('# Conditional Imports (uncomment after updating corresponding terraform.tfvars vars)');
    lines.push('# ------------------------------------------------------------------------------');
    for (const item of commentedImports) {
      lines.push(`# ${item.reason.replace(/\r?\n/g, ' ')}`);
      lines.push('# import {');
      lines.push(`#   to = ${item.to}`);
      lines.push(`#   id = "${escapeHclString(item.id)}"`);
      lines.push('# }');
      lines.push('');
    }
  }

  return `${lines.join('\n').trimEnd()}\n`;
}

/**
 * Computes suggested `terraform.tfvars` snippets from live GCP metadata so
 * `terraform plan` matches existing regions, domains, fingerprints, and App Check modes.
 *
 * @param {{ projectId: string, discovered: object }} params
 * @returns {{ suggestions: string[], notes: string[] }}
 */
function buildTfvarsSuggestions({ projectId, discovered }) {
  const hclQuote = (v) => `"${escapeHclString(v)}"`;
  const suggestions = [`create_project = false`, `project_id     = ${hclQuote(projectId)}`];
  const notes = [];

  if (discovered.firestore.locationId) {
    suggestions.push(`firestore_location                       = ${hclQuote(discovered.firestore.locationId)}`);
    suggestions.push(
      `firestore_delete_protection_enabled      = ${Boolean(discovered.firestore.deleteProtectionEnabled)}`
    );
    suggestions.push(
      `firestore_point_in_time_recovery_enabled = ${Boolean(discovered.firestore.pitrEnabled)}`
    );
  }

  if (discovered.rtdb.region) {
    suggestions.push(`rtdb_region      = ${hclQuote(discovered.rtdb.region)}`);
    if (discovered.rtdb.instanceId !== `${projectId}-default-rtdb`) {
      suggestions.push(`rtdb_instance_id = ${hclQuote(discovered.rtdb.instanceId)}`);
    }
  }

  if (discovered.storage.location) {
    suggestions.push(`storage_location = ${hclQuote(discovered.storage.location)}`);
  }

  const effectiveSiteId = discovered.hosting.siteId || projectId;
  if (discovered.hosting.siteId && discovered.hosting.siteId !== projectId) {
    suggestions.push(`hosting_site_id = ${hclQuote(discovered.hosting.siteId)}`);
  }

  if (discovered.apps.webDisplayName && discovered.apps.webDisplayName !== 'Suburban Life Web') {
    suggestions.push(`web_app_display_name = ${hclQuote(discovered.apps.webDisplayName)}`);
  }

  if (discovered.apps.androidPackageName) {
    if (discovered.apps.androidPackageName !== 'com.example.suburban_life') {
      suggestions.push(`android_package_name = ${hclQuote(discovered.apps.androidPackageName)}`);
    }
    if (
      discovered.apps.androidDisplayName &&
      discovered.apps.androidDisplayName !== 'Suburban Life Android'
    ) {
      suggestions.push(`android_app_display_name = ${hclQuote(discovered.apps.androidDisplayName)}`);
    }
    if (discovered.apps.androidSha1Hashes && discovered.apps.androidSha1Hashes.length > 0) {
      suggestions.push(
        `android_sha1_hashes   = [${discovered.apps.androidSha1Hashes.map(hclQuote).join(', ')}]`
      );
    }
    if (discovered.apps.androidSha256Hashes && discovered.apps.androidSha256Hashes.length > 0) {
      suggestions.push(
        `android_sha256_hashes = [${discovered.apps.androidSha256Hashes.map(hclQuote).join(', ')}]`
      );
    }
  }

  if (discovered.apps.iosBundleId) {
    if (discovered.apps.iosBundleId !== 'com.example.suburbanLife') {
      suggestions.push(`ios_bundle_id = ${hclQuote(discovered.apps.iosBundleId)}`);
    }
    if (
      discovered.apps.iosDisplayName &&
      discovered.apps.iosDisplayName !== 'Suburban Life iOS'
    ) {
      suggestions.push(`ios_app_display_name = ${hclQuote(discovered.apps.iosDisplayName)}`);
    }
    if (discovered.apps.iosTeamId) {
      suggestions.push(`ios_team_id = ${hclQuote(discovered.apps.iosTeamId)}`);
    }
    if (discovered.apps.iosAppStoreId) {
      suggestions.push(`ios_app_store_id = ${hclQuote(discovered.apps.iosAppStoreId)}`);
    }
  }

  if (discovered.auth.allowDuplicateEmails) {
    suggestions.push(`auth_allow_duplicate_emails = true`);
  }

  const defaultAuthDomains = new Set([
    'localhost',
    `${projectId}.firebaseapp.com`,
    `${projectId}.web.app`,
    `${effectiveSiteId}.firebaseapp.com`,
    `${effectiveSiteId}.web.app`,
  ]);
  const extraAuthDomains = (discovered.auth.authorizedDomains || []).filter(
    (d) => !defaultAuthDomains.has(d)
  );
  if (extraAuthDomains.length > 0) {
    notes.push(
      `Existing Auth authorizedDomains not in defaults: ${extraAuthDomains.join(', ')} -> add to custom_domains or auth_extra_authorized_domains.`
    );
  }

  const defaultRecaptchaDomains = new Set([
    `${effectiveSiteId}.web.app`,
    `${effectiveSiteId}.firebaseapp.com`,
  ]);
  const extraRecaptchaDomains = (discovered.appCheck.recaptchaAllowedDomains || []).filter(
    (d) => !defaultRecaptchaDomains.has(d)
  );
  if (extraRecaptchaDomains.length > 0) {
    notes.push(
      `Existing reCAPTCHA allowedDomains not in defaults: ${extraRecaptchaDomains.join(', ')} -> add to custom_domains or recaptcha_extra_allowed_domains.`
    );
  }

  if (
    discovered.appCheck.recaptchaDisplayName &&
    discovered.appCheck.recaptchaDisplayName !== 'Suburban Life Web App Check'
  ) {
    suggestions.push(`recaptcha_display_name = ${hclQuote(discovered.appCheck.recaptchaDisplayName)}`);
  }

  const modes = Object.values(discovered.appCheck.services || {}).filter(
    (m) => m === 'ENFORCED' || m === 'UNENFORCED'
  );
  if (modes.length > 0) {
    const uniqueModes = Array.from(new Set(modes));
    if (uniqueModes.length === 1) {
      suggestions.push(`app_check_enforcement_mode = ${hclQuote(uniqueModes[0])}`);
    } else {
      notes.push(
        `App Check service enforcement modes are mixed (${Object.entries(discovered.appCheck.services)
          .map(([k, v]) => `${k}=${v}`)
          .join(', ')}); Terraform manages all 4 services uniformly via app_check_enforcement_mode.`
      );
    }
  }

  if (discovered.appCheck.tokenTtl && discovered.appCheck.tokenTtl !== '3600s') {
    suggestions.push(`app_check_token_ttl = ${hclQuote(discovered.appCheck.tokenTtl)}`);
  }

  return { suggestions, notes };
}

/**
 * Formats the terminal summary after discovery completes.
 *
 * @param {{ projectId: string, outPath: string, dryRun: boolean, result: object, suggestions: { suggestions: string[], notes: string[] } }} params
 * @returns {string}
 */
function formatCliSummary({ projectId, outPath, dryRun, result, suggestions }) {
  const lines = [];
  lines.push(`Project: ${projectId}`);
  lines.push(
    dryRun
      ? `Mode: dry-run (${outPath} was NOT modified)`
      : `Wrote ${result.imports.length} import block(s) to ${outPath}`
  );

  if (typeof result.discovered.firestore.totalLocalIndexes === 'number') {
    lines.push(
      `Firestore composite indexes: ${result.discovered.firestore.matchedIndexesCount}/${result.discovered.firestore.totalLocalIndexes} matched (${result.discovered.firestore.unmatchedLocalIndexesCount} missing remotely will be created on apply).`
    );
  }

  const unmatchedLive = result.discovered.firestore.unmatchedLiveIndexes || [];
  if (unmatchedLive.length > 0) {
    lines.push(
      `Unmatched live Firestore composite indexes (${unmatchedLive.length}, not in firestore.indexes.json — Terraform will leave them untouched):`
    );
    for (const idx of unmatchedLive) {
      lines.push(`  - ${buildFirestoreIndexKey(idx)}`);
    }
  }

  if (result.warnings.length > 0) {
    lines.push('');
    lines.push('Warnings:');
    for (const warn of result.warnings) {
      lines.push(`  ! ${warn}`);
    }
  }

  if (suggestions.suggestions.length > 0) {
    lines.push('');
    lines.push('Suggested terraform.tfvars values to match live state:');
    for (const line of suggestions.suggestions) {
      lines.push(`  ${line}`);
    }
  }

  if (suggestions.notes.length > 0) {
    lines.push('');
    lines.push('Additional configuration notes:');
    for (const note of suggestions.notes) {
      lines.push(`  - ${note}`);
    }
  }

  lines.push('');
  lines.push('Next steps:');
  lines.push('  1. Update terraform.tfvars with the suggested values above.');
  lines.push('  2. Run `terraform init && terraform plan` to review imported vs new/updated resources.');
  lines.push('  3. Run `terraform apply`, then remove imports.tf once state is committed.');

  return `${lines.join('\n')}\n`;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }

  const tfvarsPath = path.resolve(options.tfvars);
  const tfvarsHints = readTfvarsHints(tfvarsPath);

  const projectId = options.project || tfvarsHints.project_id;
  if (!projectId) {
    throw new Error(
      'Missing project ID. Pass --project <project_id> or set project_id in terraform.tfvars.'
    );
  }
  if (!isValidProjectId(projectId)) {
    throw new Error(
      `Invalid GCP project ID "${projectId}". Expected 6-30 lowercase letters, digits, or hyphens.`
    );
  }

  const indexesFilePath = path.resolve(options.indexesFile);
  const localIndexesConfig = loadFirestoreIndexesConfig(indexesFilePath);
  const outPath = path.resolve(options.out);

  const accessToken = resolveAccessToken({
    token: options.token,
    tokenEnv: options.tokenEnv,
  });

  const apiClient = createGcpApiClient({ accessToken, projectId });
  const result = await discoverResources({
    projectId,
    options,
    tfvarsHints,
    localIndexesConfig,
    apiClient,
  });

  const rendered = renderImportsTf({
    projectId,
    generatedAt: new Date().toISOString(),
    imports: result.imports,
    commentedImports: result.commentedImports,
    warnings: result.warnings,
  });

  if (options.dryRun) {
    process.stdout.write(`${rendered}\n`);
  } else {
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, rendered, 'utf8');
  }

  const suggestions = buildTfvarsSuggestions({ projectId, discovered: result.discovered });
  process.stdout.write(
    formatCliSummary({ projectId, outPath, dryRun: options.dryRun, result, suggestions })
  );
}

if (require.main === module) {
  main().catch((err) => {
    console.error(`Error: ${err.message}`);
    process.exitCode = 1;
  });
}

module.exports = {
  PROTECTED_APP_CHECK_SERVICES,
  assertSafeSegment,
  buildFirestoreIndexKey,
  buildTfvarsSuggestions,
  createGcpApiClient,
  discoverResources,
  escapeHclString,
  extractLastPathSegment,
  formatCliSummary,
  isValidProjectId,
  loadFirestoreIndexesConfig,
  matchFirestoreCompositeIndexes,
  normalizeShaFingerprint,
  parseArgs,
  parseFirestoreIndexName,
  readTfvarsHints,
  renderImportsTf,
  resolveAccessToken,
  selectPlatformApp,
  stripHclComments,
};
