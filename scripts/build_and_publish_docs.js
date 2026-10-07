const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

let marked;
try {
  ({ marked } = require('marked'));
} catch {
  const vm = require('vm');
  const umdPath = path.join(path.dirname(require.resolve('marked/package.json')), 'lib/marked.umd.js');
  const sandbox = { exports: {}, module: { exports: {} } };
  vm.runInNewContext(fs.readFileSync(umdPath, 'utf8'), sandbox);
  marked = sandbox.module.exports.marked || sandbox.exports.marked || sandbox.module.exports;
}

const ALLOWED_VISIBILITIES = ['all', 'admin'];
const BOX_DRAWING_REGEX = /[┌┐└┘├┤┬┴┼─│▼▲►◄]/;

/**
 * Escapes untrusted or dynamic strings for safe HTML interpolation.
 */
function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Resolves and validates that a target path stays strictly inside an allowed base directory.
 */
function resolveSafePath(baseDir, relativeTarget) {
  const resolvedBase = path.resolve(baseDir);
  const resolvedTarget = path.resolve(resolvedBase, relativeTarget);
  if (!resolvedTarget.startsWith(resolvedBase + path.sep) && resolvedTarget !== resolvedBase) {
    throw new Error(`Path traversal blocked: "${relativeTarget}" resolves outside "${resolvedBase}"`);
  }
  return resolvedTarget;
}

/**
 * Filters and validates the documents from docs_pipeline.json that should be parsed.
 * Supports optional CLI filter (e.g., --only=admin_user_manual_es,technical_overview_es or --all).
 */
function selectDocumentsToParse(pipelineConfig, options = {}) {
  if (!pipelineConfig || !Array.isArray(pipelineConfig.documents)) {
    throw new Error('Invalid pipeline configuration: "documents" array is required.');
  }

  const onlyIds = options.only
    ? options.only
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean)
    : null;
  const parseAll = options.all === true;

  return pipelineConfig.documents
    .filter((doc) => {
      if (onlyIds && onlyIds.length > 0) {
        return onlyIds.includes(doc.id);
      }
      if (parseAll) {
        return true;
      }
      return doc.parse === true;
    })
    .map((doc) => {
      const id = String(doc.id || '').trim().replace(/[^a-zA-Z0-9_-]/g, '_');
      if (!id) {
        throw new Error('Every document entry in docs_pipeline.json must have a valid "id".');
      }
      const visibility = String(doc.visibility || 'all').trim().toLowerCase();
      if (!ALLOWED_VISIBILITIES.includes(visibility)) {
        throw new Error(
          `Invalid visibility "${visibility}" for document "${id}". Allowed: ${ALLOWED_VISIBILITIES.join(', ')}`
        );
      }
      const outputFileName = path.basename(String(doc.outputFileName || `${id}.pdf`).trim());
      if (!outputFileName.toLowerCase().endsWith('.pdf')) {
        throw new Error(`Output file name for "${id}" must end with .pdf (got "${outputFileName}").`);
      }

      return {
        id,
        source: String(doc.source || '').trim(),
        outputFileName,
        title: String(doc.title || id).trim(),
        category: String(doc.category || (pipelineConfig.defaultCategory && pipelineConfig.defaultCategory.id) || 'manuals')
          .trim()
          .toLowerCase(),
        folderId: String(doc.folderId || (pipelineConfig.defaultFolder && pipelineConfig.defaultFolder.id) || 'root').trim(),
        visibility,
        parse: Boolean(doc.parse),
      };
    });
}

/**
 * Extracts Mermaid code blocks and ASCII box-drawing diagram code blocks from Markdown,
 * replacing them with placeholders so they can be pre-rendered into PNG images before PDF generation.
 */
function extractDiagramsFromMarkdown(markdown) {
  const diagrams = [];
  const fenceRegex = /```([a-zA-Z0-9_-]*)\r?\n([\s\S]*?)```/g;

  const transformedMarkdown = markdown.replace(fenceRegex, (fullMatch, lang, code) => {
    const normalizedLang = (lang || '').trim().toLowerCase();
    const trimmedCode = code.replace(/\s+$/, '');

    if (normalizedLang === 'mermaid') {
      const index = diagrams.length;
      diagrams.push({
        index,
        type: 'mermaid',
        code: trimmedCode,
      });
      return `\n\n@@DIAGRAM_PLACEHOLDER_${index}@@\n\n`;
    }

    if ((normalizedLang === '' || normalizedLang === 'text' || normalizedLang === 'ascii') && BOX_DRAWING_REGEX.test(trimmedCode)) {
      const index = diagrams.length;
      diagrams.push({
        index,
        type: 'ascii',
        code: trimmedCode,
      });
      return `\n\n@@DIAGRAM_PLACEHOLDER_${index}@@\n\n`;
    }

    return fullMatch;
  });

  return {
    transformedMarkdown,
    diagrams,
  };
}

/**
 * Pre-processes Markdown features such as inline LaTeX arrows ($\rightarrow$, $\uparrow$),
 * LaTeX display math blocks ($$...$$), and GitHub Alerts (> [!NOTE]).
 */
function preprocessMarkdownSyntax(markdown) {
  let processed = markdown;

  // Replace inline LaTeX arrows
  processed = processed.replace(/\$\\rightarrow\$/g, '→');
  processed = processed.replace(/\$\\uparrow\$/g, '↑');
  processed = processed.replace(/\$\\leftarrow\$/g, '←');

  // Replace display math blocks $$...$$ with clean code/formula callouts
  processed = processed.replace(/\$\$([\s\S]*?)\$\$/g, (_, formula) => {
    const cleaned = formula
      .replace(/\\text\{([^}]*)\}/g, '$1')
      .replace(/\\#/g, '#')
      .trim();
    return `\n<div class="math-formula"><code>${escapeHtml(cleaned)}</code></div>\n`;
  });

  // Transform GitHub-style alerts: > [!NOTE], > [!IMPORTANT], > [!WARNING], > [!TIP], > [!CAUTION]
  processed = processed.replace(
    /^>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*\r?\n((?:>.*(?:\r?\n|$))+)/gm,
    (_, alertType, bodyLines) => {
      const cleanBody = bodyLines
        .split(/\r?\n/)
        .map((line) => line.replace(/^>\s?/, ''))
        .join('\n')
        .trim();
      const parsedBody = marked.parse(cleanBody);
      const lowerType = alertType.toLowerCase();
      return `\n<div class="alert-box alert-${escapeHtml(lowerType)}"><div class="alert-title">${escapeHtml(alertType)}</div><div class="alert-content">${parsedBody}</div></div>\n`;
    }
  );

  return processed;
}

/**
 * Renders a single extracted diagram (Mermaid or ASCII box-drawing) into a high-DPI PNG file
 * using Puppeteer.
 */
async function renderDiagramToPng(browser, diagram, outputPngPath, mermaidScriptPath) {
  const page = await browser.newPage();
  try {
    await page.setViewport({ width: 1200, height: 900, deviceScaleFactor: 2 });

    if (diagram.type === 'mermaid') {
      const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    body {
      margin: 0;
      padding: 24px;
      background: #ffffff;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      display: inline-block;
    }
    #diagram-wrapper {
      display: inline-block;
      padding: 20px 28px;
      background: #F8F9FE;
      border: 1.5px solid #D8E0F5;
      border-radius: 12px;
    }
  </style>
</head>
<body>
  <div id="diagram-wrapper">
    <pre class="mermaid">${escapeHtml(diagram.code)}</pre>
  </div>
</body>
</html>`;

      await page.setContent(html, { waitUntil: 'load' });
      await page.addScriptTag({ path: mermaidScriptPath });
      await page.evaluate(async () => {
        window.mermaid.initialize({
          startOnLoad: false,
          theme: 'base',
          flowchart: {
            useMaxWidth: false,
            htmlLabels: true,
            curve: 'basis',
          },
          themeVariables: {
            primaryColor: '#EDE8F5',
            primaryTextColor: '#1F2937',
            primaryBorderColor: '#3D52A0',
            lineColor: '#3D52A0',
            secondaryColor: '#F3F4F6',
            tertiaryColor: '#FFFFFF',
            fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
          },
        });
        await window.mermaid.run({ querySelector: '.mermaid' });
      });

      const wrapper = await page.$('#diagram-wrapper');
      await wrapper.screenshot({ path: outputPngPath, type: 'png' });
    } else {
      // Render ASCII box-drawing diagram into a crisp styled graphic PNG
      const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    body {
      margin: 0;
      padding: 24px;
      background: #ffffff;
      display: inline-block;
    }
    #diagram-wrapper {
      display: inline-block;
      padding: 22px 28px;
      background: linear-gradient(180deg, #F8F9FE 0%, #EEF1FA 100%);
      border: 2px solid #3D52A0;
      border-radius: 12px;
      box-shadow: 0 4px 12px rgba(61, 82, 160, 0.08);
    }
    pre {
      margin: 0;
      font-family: "SFMono-Regular", Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      font-size: 14px;
      line-height: 1.35;
      color: #1E293B;
      font-weight: 600;
      white-space: pre;
    }
  </style>
</head>
<body>
  <div id="diagram-wrapper">
    <pre>${escapeHtml(diagram.code)}</pre>
  </div>
</body>
</html>`;

      await page.setContent(html, { waitUntil: 'load' });
      const wrapper = await page.$('#diagram-wrapper');
      await wrapper.screenshot({ path: outputPngPath, type: 'png' });
    }
  } finally {
    await page.close();
  }
}

/**
 * Builds the complete styled HTML document with embedded PNG diagram images.
 */
function buildPdfDocumentHtml({ title, visibility, bodyHtml }) {
  const visibilityBadge =
    visibility === 'admin'
      ? '<span class="badge badge-admin">VISIBILIDAD: SOLO ADMINISTRADORES</span>'
      : '<span class="badge badge-all">VISIBILIDAD: COMUNIDAD GENERAL</span>';

  return `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8" />
  <title>${escapeHtml(title)}</title>
  <style>
    @page {
      size: A4;
      margin: 22mm 18mm 22mm 18mm;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      color: #1F2937;
      line-height: 1.6;
      font-size: 11pt;
      margin: 0;
      padding: 0;
    }
    .doc-banner {
      background: linear-gradient(135deg, #3D52A0 0%, #7091E6 100%);
      color: #FFFFFF;
      padding: 20px 24px;
      border-radius: 10px;
      margin-bottom: 24px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .doc-banner-brand {
      font-size: 10pt;
      text-transform: uppercase;
      letter-spacing: 1.2px;
      opacity: 0.9;
      font-weight: 700;
    }
    .badge {
      display: inline-block;
      padding: 4px 10px;
      border-radius: 6px;
      font-size: 8.5pt;
      font-weight: 700;
      letter-spacing: 0.5px;
    }
    .badge-admin {
      background-color: #FEF2F2;
      color: #B91C1C;
      border: 1px solid #FECACA;
    }
    .badge-all {
      background-color: #ECFDF5;
      color: #047857;
      border: 1px solid #A7F3D0;
    }
    h1 {
      color: #3D52A0;
      font-size: 20pt;
      margin-top: 0;
      margin-bottom: 12px;
      border-bottom: 2px solid #EDE8F5;
      padding-bottom: 8px;
    }
    h2 {
      color: #3D52A0;
      font-size: 14.5pt;
      margin-top: 24px;
      margin-bottom: 10px;
      border-bottom: 1px solid #E5E7EB;
      padding-bottom: 4px;
      page-break-after: avoid;
    }
    h3 {
      color: #2E3A59;
      font-size: 12pt;
      margin-top: 18px;
      margin-bottom: 6px;
      page-break-after: avoid;
    }
    h4 {
      color: #374151;
      font-size: 11pt;
      margin-top: 14px;
      margin-bottom: 4px;
      page-break-after: avoid;
    }
    p, li {
      font-size: 10.5pt;
      color: #374151;
    }
    ul, ol {
      padding-left: 22px;
      margin-top: 6px;
      margin-bottom: 12px;
    }
    li {
      margin-bottom: 4px;
    }
    a {
      color: #3D52A0;
      text-decoration: none;
    }
    hr {
      border: none;
      border-top: 1px solid #E5E7EB;
      margin: 22px 0;
    }
    code {
      font-family: "SFMono-Regular", Menlo, Monaco, Consolas, monospace;
      background-color: #F3F4F6;
      color: #3D52A0;
      padding: 2px 5px;
      border-radius: 4px;
      font-size: 9.5pt;
    }
    pre {
      background-color: #F8FAFC;
      border: 1px solid #E2E8F0;
      border-radius: 8px;
      padding: 12px 16px;
      overflow-x: auto;
      page-break-inside: avoid;
    }
    pre code {
      background: none;
      color: #1E293B;
      padding: 0;
      font-size: 9pt;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin: 16px 0;
      font-size: 9.5pt;
      page-break-inside: avoid;
    }
    th {
      background-color: #3D52A0;
      color: #FFFFFF;
      text-align: left;
      padding: 8px 12px;
      font-weight: 600;
    }
    td {
      padding: 8px 12px;
      border-bottom: 1px solid #E5E7EB;
      vertical-align: top;
    }
    tr:nth-child(even) td {
      background-color: #F9FAFB;
    }
    .diagram-container {
      text-align: center;
      margin: 18px 0;
      page-break-inside: avoid;
    }
    .diagram-image {
      max-width: 100%;
      height: auto;
      border-radius: 8px;
    }
    .alert-box {
      border-left: 4px solid #3D52A0;
      background-color: #F8F9FE;
      padding: 12px 16px;
      border-radius: 0 8px 8px 0;
      margin: 16px 0;
      page-break-inside: avoid;
    }
    .alert-title {
      font-weight: 700;
      font-size: 9.5pt;
      color: #3D52A0;
      margin-bottom: 4px;
      letter-spacing: 0.5px;
    }
    .math-formula {
      background-color: #F8F9FE;
      border: 1px solid #D8E0F5;
      border-radius: 8px;
      padding: 10px 14px;
      text-align: center;
      margin: 12px 0;
    }
  </style>
</head>
<body>
  <div class="doc-banner">
    <span class="doc-banner-brand">Suburban Life — Documentación Oficial</span>
    ${visibilityBadge}
  </div>
  ${bodyHtml}
</body>
</html>`;
}

/**
 * Initializes Firebase Admin SDK using environment credentials (CI) or local serviceAccountKey.json.
 */
function initFirebaseAdmin(options = {}) {
  const admin = require('firebase-admin');
  if (admin.apps.length > 0) {
    return admin.app();
  }

  const defaultProjectId = process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID || 'suburban-life-a67ab';
  const storageBucket = process.env.FIREBASE_STORAGE_BUCKET || `${defaultProjectId}.firebasestorage.app`;

  if (options.emulator) {
    process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
    process.env.FIREBASE_STORAGE_EMULATOR_HOST = process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:9199';
    return admin.initializeApp({
      projectId: defaultProjectId,
      storageBucket,
    });
  }

  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    const projectId = serviceAccount.project_id || defaultProjectId;
    return admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId,
      storageBucket: process.env.FIREBASE_STORAGE_BUCKET || `${projectId}.firebasestorage.app`,
    });
  }

  const localKeyPath = path.resolve(__dirname, 'serviceAccountKey.json');
  if (fs.existsSync(localKeyPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(localKeyPath, 'utf8'));
    const projectId = serviceAccount.project_id || defaultProjectId;
    return admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId,
      storageBucket: process.env.FIREBASE_STORAGE_BUCKET || `${projectId}.firebasestorage.app`,
    });
  }

  throw new Error(
    'Firebase credentials not found. Set FIREBASE_SERVICE_ACCOUNT env var (in GitHub Actions) or place serviceAccountKey.json in scripts/.'
  );
}

/**
 * Publishes a generated PDF to Firebase Storage and populates/updates its record in the
 * Transparency section (`documents` collection) with its configured `visibility` ('admin' or 'all').
 */
async function publishDocumentToTransparency(docEntry, pdfFilePath, pipelineConfig, options = {}) {
  initFirebaseAdmin(options);
  const admin = require('firebase-admin');
  const { FieldValue } = require('firebase-admin/firestore');
  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  const fileBuffer = fs.readFileSync(pdfFilePath);
  const fileSize = fileBuffer.length;

  const prefix = docEntry.visibility === 'admin' ? 'documents/admin_only' : 'documents';
  const storagePath = `${prefix}/${docEntry.id}_${docEntry.outputFileName}`;
  const downloadToken = crypto.randomUUID();

  const fileRef = bucket.file(storagePath);
  await fileRef.save(fileBuffer, {
    resumable: false,
    metadata: {
      contentType: 'application/pdf',
      contentDisposition: `attachment; filename="${docEntry.outputFileName}"`,
      metadata: {
        firebaseStorageDownloadTokens: downloadToken,
        visibility: docEntry.visibility,
        uploaderUid: 'system_docs_pipeline',
      },
    },
  });

  const encodedPath = encodeURIComponent(storagePath);
  const isStorageEmulator = Boolean(process.env.FIREBASE_STORAGE_EMULATOR_HOST);
  const downloadUrl = isStorageEmulator
    ? `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${downloadToken}`
    : `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${downloadToken}`;

  // 1. Ensure category exists
  const defaultCat = pipelineConfig.defaultCategory || { id: 'manuals', name: 'Manuales / Manuals' };
  const catId = docEntry.category || defaultCat.id;
  const catRef = db.collection('document_categories').doc(catId);
  const catSnap = await catRef.get();
  if (!catSnap.exists) {
    await catRef.set({
      name: catId === defaultCat.id ? defaultCat.name : catId,
      createdAt: FieldValue.serverTimestamp(),
    });
  }

  // 2. Ensure virtual folder exists
  const defaultFolder = pipelineConfig.defaultFolder || {
    id: 'official_manuals',
    name: 'Manuales y Documentación Oficial',
    parentId: 'root',
  };
  if (docEntry.folderId && docEntry.folderId !== 'root') {
    const folderRef = db.collection('document_folders').doc(docEntry.folderId);
    const folderSnap = await folderRef.get();
    if (!folderSnap.exists) {
      await folderRef.set({
        name: docEntry.folderId === defaultFolder.id ? defaultFolder.name : docEntry.folderId,
        parentId: defaultFolder.parentId || 'root',
        createdAt: FieldValue.serverTimestamp(),
        createdBy: 'system_docs_pipeline',
      });
    }
  }

  // 3. Upsert document metadata in `documents` collection
  const docRef = db.collection('documents').doc(docEntry.id);
  const existingSnap = await docRef.get();
  const now = FieldValue.serverTimestamp();

  const payload = {
    title: docEntry.title,
    fileName: docEntry.outputFileName,
    fileType: 'pdf',
    fileSize,
    category: catId,
    folderId: docEntry.folderId || 'root',
    visibility: docEntry.visibility,
    url: downloadUrl,
    storagePath,
    publicationDate: now,
    updatedAt: now,
    uploaderUid: 'system_docs_pipeline',
  };

  if (!existingSnap.exists) {
    payload.uploadedAt = now;
  }

  await docRef.set(payload, { merge: true });

  // 4. Backfill `visibility: 'all'` on any legacy documents missing the `visibility` field
  const allDocsSnap = await db.collection('documents').get();
  const batch = db.batch();
  let backfilledCount = 0;
  for (const d of allDocsSnap.docs) {
    const data = d.data();
    if (!data.visibility) {
      batch.update(d.ref, { visibility: 'all' });
      backfilledCount++;
    }
  }
  if (backfilledCount > 0) {
    await batch.commit();
  }

  return {
    docId: docEntry.id,
    storagePath,
    url: downloadUrl,
    visibility: docEntry.visibility,
    fileSize,
  };
}

/**
 * Main pipeline execution function.
 */
async function runPipeline(cliOptions = {}) {
  const repoRoot = path.resolve(__dirname, '..');
  const docsDir = path.resolve(repoRoot, 'docs');
  const outputDir = path.resolve(docsDir, 'pdf');
  const diagramsDir = path.resolve(outputDir, 'diagrams');
  const configPath = resolveSafePath(docsDir, 'docs_pipeline.json');

  if (!fs.existsSync(configPath)) {
    throw new Error(`Pipeline configuration not found at ${configPath}`);
  }

  const pipelineConfig = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const docsToBuild = selectDocumentsToParse(pipelineConfig, cliOptions);

  if (docsToBuild.length === 0) {
    console.log('No documents matched for parsing. Check "parse: true" in docs/docs_pipeline.json.');
    return [];
  }

  fs.mkdirSync(outputDir, { recursive: true });
  fs.mkdirSync(diagramsDir, { recursive: true });

  const puppeteer = require('puppeteer');
  const mermaidScriptPath = require.resolve('mermaid/dist/mermaid.min.js');

  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });

  const results = [];

  try {
    for (const docEntry of docsToBuild) {
      const relativeFromDocs = docEntry.source.replace(/^docs[\\/]/, '');
      const sourcePath = resolveSafePath(docsDir, relativeFromDocs);
      const outputPdfPath = resolveSafePath(outputDir, docEntry.outputFileName);

      if (!fs.existsSync(sourcePath)) {
        throw new Error(`Source markdown file not found: ${sourcePath}`);
      }

      console.log(`\n[1/3] Parsing Markdown & extracting diagrams: ${docEntry.source}`);
      const rawMarkdown = fs.readFileSync(sourcePath, 'utf8');
      const { transformedMarkdown, diagrams } = extractDiagramsFromMarkdown(rawMarkdown);

      const diagramHtmlMap = new Map();
      if (diagrams.length > 0) {
        console.log(`[2/3] Rendering ${diagrams.length} diagram(s) to PNG images for "${docEntry.id}"...`);
        for (const diagram of diagrams) {
          const pngFileName = `${docEntry.id}_diagram_${diagram.index + 1}.png`;
          const pngPath = resolveSafePath(diagramsDir, pngFileName);
          await renderDiagramToPng(browser, diagram, pngPath, mermaidScriptPath);

          const pngBase64 = fs.readFileSync(pngPath).toString('base64');
          const imgHtml = `<div class="diagram-container"><img src="data:image/png;base64,${pngBase64}" alt="Diagram ${diagram.index + 1}" class="diagram-image" /></div>`;
          diagramHtmlMap.set(`@@DIAGRAM_PLACEHOLDER_${diagram.index}@@`, imgHtml);
          console.log(`  ✓ Saved diagram image: docs/pdf/diagrams/${pngFileName}`);
        }
      } else {
        console.log(`[2/3] No diagrams found in "${docEntry.id}".`);
      }

      const preprocessedMd = preprocessMarkdownSyntax(transformedMarkdown);
      let bodyHtml = marked.parse(preprocessedMd);

      for (const [placeholder, imgTag] of diagramHtmlMap.entries()) {
        bodyHtml = bodyHtml.replace(new RegExp(`<p>\\s*${placeholder}\\s*<\\/p>`, 'g'), imgTag);
        bodyHtml = bodyHtml.replace(new RegExp(placeholder, 'g'), imgTag);
      }

      const fullHtml = buildPdfDocumentHtml({
        title: docEntry.title,
        visibility: docEntry.visibility,
        bodyHtml,
      });

      console.log(`[3/3] Generating PDF: docs/pdf/${docEntry.outputFileName} (visibility: ${docEntry.visibility})`);
      const pdfPage = await browser.newPage();
      try {
        await pdfPage.setContent(fullHtml, { waitUntil: 'networkidle0' });
        await pdfPage.pdf({
          path: outputPdfPath,
          format: 'A4',
          printBackground: true,
          displayHeaderFooter: true,
          headerTemplate: `<div style="font-size: 8px; color: #6B7280; width: 100%; padding: 0 18mm; display: flex; justify-content: space-between; font-family: sans-serif;">
            <span>${escapeHtml(docEntry.title)}</span>
            <span>${docEntry.visibility === 'admin' ? 'CONFIDENCIAL — SOLO ADMIN' : 'SUBURBAN LIFE'}</span>
          </div>`,
          footerTemplate: `<div style="font-size: 8px; color: #6B7280; width: 100%; padding: 0 18mm; display: flex; justify-content: space-between; font-family: sans-serif;">
            <span>Suburban Life</span>
            <span>Página <span class="pageNumber"></span> de <span class="totalPages"></span></span>
          </div>`,
          margin: {
            top: '22mm',
            bottom: '22mm',
            left: '18mm',
            right: '18mm',
          },
        });
      } finally {
        await pdfPage.close();
      }

      const stat = fs.statSync(outputPdfPath);
      console.log(`  ✓ PDF generated (${(stat.size / 1024).toFixed(1)} KB)`);

      let publishedInfo = null;
      if (cliOptions.publish) {
        console.log(`  ↑ Publishing "${docEntry.title}" to Transparency section (visibility: ${docEntry.visibility})...`);
        publishedInfo = await publishDocumentToTransparency(docEntry, outputPdfPath, pipelineConfig, cliOptions);
        console.log(`  ✓ Published to Firestore documents/${publishedInfo.docId}`);
      }

      results.push({
        ...docEntry,
        outputPdfPath,
        diagramCount: diagrams.length,
        fileSize: stat.size,
        published: publishedInfo,
      });
    }
  } finally {
    await browser.close();
  }

  return results;
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const cliOptions = {
    publish: args.includes('--publish'),
    emulator: args.includes('--emulator'),
    all: args.includes('--all'),
    only: null,
  };

  for (const arg of args) {
    if (arg.startsWith('--only=')) {
      cliOptions.only = arg.slice('--only='.length);
    }
  }

  runPipeline(cliOptions)
    .then((results) => {
      console.log(`\nPipeline completed successfully. Processed ${results.length} document(s).`);
      process.exit(0);
    })
    .catch((err) => {
      console.error('\nPipeline failed:', err.message || err);
      process.exit(1);
    });
}

module.exports = {
  escapeHtml,
  resolveSafePath,
  selectDocumentsToParse,
  extractDiagramsFromMarkdown,
  preprocessMarkdownSyntax,
  buildPdfDocumentHtml,
  runPipeline,
};
