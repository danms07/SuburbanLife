const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const {
  escapeHtml,
  resolveSafePath,
  selectDocumentsToParse,
  extractDiagramsFromMarkdown,
  preprocessMarkdownSyntax,
  buildPdfDocumentHtml,
} = require('../build_and_publish_docs');

test('selectDocumentsToParse filters by parse:true and validates visibility', () => {
  const sampleConfig = {
    defaultFolder: { id: 'official_manuals', name: 'Manuals' },
    defaultCategory: { id: 'manuals', name: 'Manuals' },
    documents: [
      {
        id: 'admin_user_manual_es',
        source: 'docs/admin_user_manual_es.md',
        outputFileName: 'Manual_Admin_ES.pdf',
        title: 'Manual Admin ES',
        visibility: 'admin',
        parse: true,
      },
      {
        id: 'admin_user_manual_en',
        source: 'docs/admin_user_manual.md',
        outputFileName: 'Manual_Admin_EN.pdf',
        title: 'Manual Admin EN',
        visibility: 'admin',
        parse: false,
      },
      {
        id: 'technical_overview_es',
        source: 'docs/technical_overview_es.md',
        outputFileName: 'Tech_ES.pdf',
        title: 'Tech Overview ES',
        visibility: 'all',
        parse: true,
      },
    ],
  };

  const defaultSelected = selectDocumentsToParse(sampleConfig);
  assert.equal(defaultSelected.length, 2);
  assert.deepEqual(
    defaultSelected.map((d) => d.id),
    ['admin_user_manual_es', 'technical_overview_es']
  );
  assert.equal(defaultSelected[0].visibility, 'admin');
  assert.equal(defaultSelected[1].visibility, 'all');

  // Filter with --only
  const onlyAdminEn = selectDocumentsToParse(sampleConfig, { only: 'admin_user_manual_en' });
  assert.equal(onlyAdminEn.length, 1);
  assert.equal(onlyAdminEn[0].id, 'admin_user_manual_en');

  // Invalid visibility throws
  assert.throws(() => {
    selectDocumentsToParse({
      documents: [
        {
          id: 'bad_doc',
          source: 'docs/test.md',
          outputFileName: 'test.pdf',
          visibility: 'public_internet',
          parse: true,
        },
      ],
    });
  }, /Invalid visibility/);
});

test('resolveSafePath blocks directory traversal outside baseDir', () => {
  const baseDir = path.resolve(__dirname, '../../docs');
  const safeResolved = resolveSafePath(baseDir, 'admin_user_manual_es.md');
  assert.ok(safeResolved.endsWith('admin_user_manual_es.md'));

  assert.throws(() => {
    resolveSafePath(baseDir, '../scripts/serviceAccountKey.json');
  }, /Path traversal blocked/);
});

test('extractDiagramsFromMarkdown extracts mermaid and ASCII box diagrams', () => {
  const md = `# Title

\`\`\`mermaid
flowchart TD
  A --> B
\`\`\`

Regular CSV block:
\`\`\`csv
name,email
John,john@example.com
\`\`\`

ASCII diagram:
\`\`\`
┌─────────┐
│  Box 1  │
└────┬────┘
     ▼
┌─────────┐
│  Box 2  │
└─────────┘
\`\`\`
`;

  const { transformedMarkdown, diagrams } = extractDiagramsFromMarkdown(md);
  assert.equal(diagrams.length, 2);
  assert.equal(diagrams[0].type, 'mermaid');
  assert.ok(diagrams[0].code.includes('A --> B'));
  assert.equal(diagrams[1].type, 'ascii');
  assert.ok(diagrams[1].code.includes('Box 1'));

  assert.ok(transformedMarkdown.includes('@@DIAGRAM_PLACEHOLDER_0@@'));
  assert.ok(transformedMarkdown.includes('@@DIAGRAM_PLACEHOLDER_1@@'));
  assert.ok(transformedMarkdown.includes('name,email'));
});

test('preprocessMarkdownSyntax converts LaTeX arrows and GitHub alerts', () => {
  const input = `Navigate: Panel $\\rightarrow$ Settings $\\uparrow$

> [!NOTE]
> Important note content here.
`;
  const processed = preprocessMarkdownSyntax(input);
  assert.ok(processed.includes('Panel → Settings ↑'));
  assert.ok(processed.includes('alert-box alert-note'));
  assert.ok(processed.includes('Important note content here.'));
});

test('escapeHtml and buildPdfDocumentHtml encode untrusted characters safely', () => {
  assert.equal(escapeHtml('<script>alert("x")</script>'), '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;');

  const html = buildPdfDocumentHtml({
    title: 'Manual <Admin>',
    visibility: 'admin',
    bodyHtml: '<p>Body</p>',
  });
  assert.ok(html.includes('<title>Manual &lt;Admin&gt;</title>'));
  assert.ok(html.includes('VISIBILIDAD: SOLO ADMINISTRADORES'));
});
