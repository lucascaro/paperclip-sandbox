const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, HeadingLevel, BorderStyle, WidthType,
  ShadingType, PageNumber, PageBreak, LevelFormat, ExternalHyperlink,
} = require("docx");

// --- Colors ---
const BRAND_DARK = "1B2A4A";
const BRAND_ACCENT = "2E75B6";
const RED_HIGH = "C0392B";
const ORANGE_MED = "E67E22";
const GREEN_OK = "27AE60";
const GRAY_LIGHT = "F2F4F7";
const GRAY_MID = "D5D8DC";
const WHITE = "FFFFFF";

// --- Borders ---
const noBorder = { style: BorderStyle.NONE, size: 0 };
const noBorders = { top: noBorder, bottom: noBorder, left: noBorder, right: noBorder };
const thinBorder = { style: BorderStyle.SINGLE, size: 1, color: GRAY_MID };
const thinBorders = { top: thinBorder, bottom: thinBorder, left: thinBorder, right: thinBorder };

// --- Page dimensions (US Letter, 1" margins) ---
const PAGE_W = 12240;
const PAGE_H = 15840;
const MARGIN = 1440;
const CONTENT_W = PAGE_W - 2 * MARGIN; // 9360

// --- Numbering ---
const numbering = {
  config: [
    {
      reference: "bullets",
      levels: [
        { level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } } },
        { level: 1, format: LevelFormat.BULLET, text: "\u2013", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 1440, hanging: 360 } } } },
      ],
    },
    {
      reference: "numbered",
      levels: [
        { level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } } },
      ],
    },
    {
      reference: "gates",
      levels: [
        { level: 0, format: LevelFormat.DECIMAL, text: "Gate %1:", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 720 } } } },
      ],
    },
  ],
};

// --- Helper functions ---
function heading1(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    spacing: { before: 360, after: 200 },
    children: [new TextRun({ text, bold: true, size: 32, font: "Arial", color: BRAND_DARK })],
  });
}

function heading2(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 280, after: 160 },
    children: [new TextRun({ text, bold: true, size: 26, font: "Arial", color: BRAND_ACCENT })],
  });
}

function heading3(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_3,
    spacing: { before: 200, after: 120 },
    children: [new TextRun({ text, bold: true, size: 22, font: "Arial", color: BRAND_DARK })],
  });
}

function para(runs, opts = {}) {
  const children = typeof runs === "string"
    ? [new TextRun({ text: runs, size: 21, font: "Arial", color: "333333" })]
    : runs;
  return new Paragraph({ spacing: { after: 120 }, ...opts, children });
}

function bullet(text, level = 0) {
  return new Paragraph({
    numbering: { reference: "bullets", level },
    spacing: { after: 80 },
    children: [new TextRun({ text, size: 21, font: "Arial", color: "333333" })],
  });
}

function bulletRuns(runs, level = 0) {
  return new Paragraph({
    numbering: { reference: "bullets", level },
    spacing: { after: 80 },
    children: runs,
  });
}

function bold(text) {
  return new TextRun({ text, bold: true, size: 21, font: "Arial", color: "333333" });
}

function normal(text) {
  return new TextRun({ text, size: 21, font: "Arial", color: "333333" });
}

function mono(text) {
  return new TextRun({ text, size: 19, font: "Courier New", color: "333333" });
}

function colorText(text, color) {
  return new TextRun({ text, bold: true, size: 21, font: "Arial", color });
}

// Risk table row
function riskRow(risk, severity, detail, isHeader = false) {
  const sevColor = severity === "HIGH" ? RED_HIGH : severity === "MEDIUM" ? ORANGE_MED : GREEN_OK;
  const bgColor = isHeader ? BRAND_DARK : WHITE;
  const textColor = isHeader ? WHITE : "333333";
  const cellMargins = { top: 60, bottom: 60, left: 100, right: 100 };

  return new TableRow({
    children: [
      new TableCell({
        width: { size: 2400, type: WidthType.DXA },
        borders: thinBorders,
        margins: cellMargins,
        shading: { fill: bgColor, type: ShadingType.CLEAR },
        children: [new Paragraph({ children: [new TextRun({ text: risk, bold: isHeader, size: 19, font: "Arial", color: textColor })] })],
      }),
      new TableCell({
        width: { size: 1200, type: WidthType.DXA },
        borders: thinBorders,
        margins: cellMargins,
        shading: { fill: isHeader ? BRAND_DARK : WHITE, type: ShadingType.CLEAR },
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [new TextRun({ text: severity, bold: true, size: 19, font: "Arial", color: isHeader ? WHITE : sevColor })],
        })],
      }),
      new TableCell({
        width: { size: 5760, type: WidthType.DXA },
        borders: thinBorders,
        margins: cellMargins,
        shading: { fill: bgColor, type: ShadingType.CLEAR },
        children: [new Paragraph({ children: [new TextRun({ text: detail, size: 19, font: "Arial", color: textColor })] })],
      }),
    ],
  });
}

// Scan finding row
function scanRow(finding, verdict, isHeader = false) {
  const bgColor = isHeader ? BRAND_DARK : WHITE;
  const textColor = isHeader ? WHITE : "333333";
  const cellMargins = { top: 60, bottom: 60, left: 100, right: 100 };

  return new TableRow({
    children: [
      new TableCell({
        width: { size: 4680, type: WidthType.DXA },
        borders: thinBorders,
        margins: cellMargins,
        shading: { fill: bgColor, type: ShadingType.CLEAR },
        children: [new Paragraph({ children: [new TextRun({ text: finding, bold: isHeader, size: 19, font: "Arial", color: textColor })] })],
      }),
      new TableCell({
        width: { size: 4680, type: WidthType.DXA },
        borders: thinBorders,
        margins: cellMargins,
        shading: { fill: bgColor, type: ShadingType.CLEAR },
        children: [new Paragraph({ children: [new TextRun({ text: verdict, bold: isHeader, size: 19, font: "Arial", color: textColor })] })],
      }),
    ],
  });
}

// Gate row
function gateRow(gate, action, criteria, isHeader = false) {
  const bgColor = isHeader ? BRAND_DARK : WHITE;
  const textColor = isHeader ? WHITE : "333333";
  const cellMargins = { top: 60, bottom: 60, left: 100, right: 100 };

  return new TableRow({
    children: [
      new TableCell({
        width: { size: 1200, type: WidthType.DXA },
        borders: thinBorders,
        margins: cellMargins,
        shading: { fill: bgColor, type: ShadingType.CLEAR },
        children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: gate, bold: true, size: 19, font: "Arial", color: textColor })] })],
      }),
      new TableCell({
        width: { size: 3580, type: WidthType.DXA },
        borders: thinBorders,
        margins: cellMargins,
        shading: { fill: bgColor, type: ShadingType.CLEAR },
        children: [new Paragraph({ children: [new TextRun({ text: action, size: 19, font: "Arial", color: textColor })] })],
      }),
      new TableCell({
        width: { size: 4580, type: WidthType.DXA },
        borders: thinBorders,
        margins: cellMargins,
        shading: { fill: bgColor, type: ShadingType.CLEAR },
        children: [new Paragraph({ children: [new TextRun({ text: criteria, size: 19, font: "Arial", color: textColor })] })],
      }),
    ],
  });
}

// Callout box
function calloutBox(title, bodyText, fillColor = "FFF3CD", borderColor = "FFCC02") {
  const border = { style: BorderStyle.SINGLE, size: 2, color: borderColor };
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA },
    columnWidths: [CONTENT_W],
    rows: [
      new TableRow({
        children: [
          new TableCell({
            width: { size: CONTENT_W, type: WidthType.DXA },
            borders: { top: border, bottom: border, left: border, right: border },
            margins: { top: 120, bottom: 120, left: 200, right: 200 },
            shading: { fill: fillColor, type: ShadingType.CLEAR },
            children: [
              new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: title, bold: true, size: 21, font: "Arial", color: "333333" })] }),
              new Paragraph({ children: [new TextRun({ text: bodyText, size: 20, font: "Arial", color: "555555" })] }),
            ],
          }),
        ],
      }),
    ],
  });
}

function spacer(height = 120) {
  return new Paragraph({ spacing: { after: height }, children: [] });
}

// --- Build Document ---
const doc = new Document({
  styles: {
    default: {
      document: { run: { font: "Arial", size: 21 } },
    },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 32, bold: true, font: "Arial", color: BRAND_DARK },
        paragraph: { spacing: { before: 360, after: 200 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 26, bold: true, font: "Arial", color: BRAND_ACCENT },
        paragraph: { spacing: { before: 280, after: 160 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 22, bold: true, font: "Arial", color: BRAND_DARK },
        paragraph: { spacing: { before: 200, after: 120 }, outlineLevel: 2 } },
    ],
  },
  numbering,
  sections: [
    // ===================== COVER PAGE =====================
    {
      properties: {
        page: {
          size: { width: PAGE_W, height: PAGE_H },
          margin: { top: MARGIN, right: MARGIN, bottom: MARGIN, left: MARGIN },
        },
      },
      children: [
        spacer(2400),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 80 },
          children: [new TextRun({ text: "SECURITY ANALYSIS REPORT", size: 44, bold: true, font: "Arial", color: BRAND_DARK })],
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 200 },
          border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: BRAND_ACCENT, space: 8 } },
          children: [new TextRun({ text: "paperclipai/companies.sh", size: 32, font: "Arial", color: BRAND_ACCENT })],
        }),
        spacer(400),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 80 },
          children: [new TextRun({ text: "npm package: companies.sh v2026.325.2", size: 22, font: "Arial", color: "666666" })],
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 80 },
          children: [new TextRun({ text: "npm package: paperclipai v2026.325.0", size: 22, font: "Arial", color: "666666" })],
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 80 },
          children: [new TextRun({ text: "npm package: @paperclipai/server (11MB, closed source)", size: 22, font: "Arial", color: "666666" })],
        }),
        spacer(600),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 80 },
          children: [new TextRun({ text: "Prepared: March 29, 2026", size: 22, font: "Arial", color: "888888" })],
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 80 },
          children: [new TextRun({ text: "Classification: Internal", size: 22, font: "Arial", color: "888888" })],
        }),
        spacer(1200),
        calloutBox(
          "OVERALL ASSESSMENT: PROCEED WITH EXTREME CAUTION",
          "This package installs a persistent background server, a local database, and has unauditable closed-source components. Static analysis found no direct credential theft, but dynamic import capabilities and S3 upload infrastructure mean runtime behavior cannot be fully predicted from code alone. Docker isolation and network monitoring are required before any execution.",
          "FCE4EC",
          RED_HIGH,
        ),
      ],
    },

    // ===================== BODY =====================
    {
      properties: {
        page: {
          size: { width: PAGE_W, height: PAGE_H },
          margin: { top: MARGIN, right: MARGIN, bottom: MARGIN, left: MARGIN },
        },
      },
      headers: {
        default: new Header({
          children: [new Paragraph({
            border: { bottom: { style: BorderStyle.SINGLE, size: 1, color: GRAY_MID, space: 4 } },
            children: [
              new TextRun({ text: "Security Analysis: paperclipai/companies.sh", size: 16, font: "Arial", color: "999999" }),
            ],
          })],
        }),
      },
      footers: {
        default: new Footer({
          children: [new Paragraph({
            alignment: AlignmentType.CENTER,
            border: { top: { style: BorderStyle.SINGLE, size: 1, color: GRAY_MID, space: 4 } },
            children: [
              new TextRun({ text: "Page ", size: 16, font: "Arial", color: "999999" }),
              new TextRun({ children: [PageNumber.CURRENT], size: 16, font: "Arial", color: "999999" }),
              new TextRun({ text: "  |  Internal  |  March 29, 2026", size: 16, font: "Arial", color: "999999" }),
            ],
          })],
        }),
      },
      children: [
        // --- 1. Executive Summary ---
        heading1("1. Executive Summary"),
        para("This report documents a security analysis of the paperclipai/companies.sh npm ecosystem, an AI agent orchestration framework. The analysis was conducted through static code inspection of downloaded (but never executed) packages."),
        spacer(80),
        heading3("Key Findings"),
        bulletRuns([bold("No direct credential theft detected"), normal(" \u2014 no reads of ~/.ssh, ~/.aws, ~/.gnupg, or keychain paths in either package")]),
        bulletRuns([bold("Persistent background server"), normal(" \u2014 the package silently starts a detached Node.js server on port 3100 that survives after the CLI exits")]),
        bulletRuns([bold("Closed-source core"), normal(" \u2014 @paperclipai/server (11MB, 744 files) has no public source code; runtime behavior is unauditable")]),
        bulletRuns([bold("Dynamic code loading"), normal(" \u2014 new Function() constructor enables arbitrary module imports at runtime, defeating static analysis")]),
        bulletRuns([bold("S3 upload infrastructure"), normal(" \u2014 full AWS S3 client with a default bucket named \"paperclip\"; data exfiltration capability exists")]),
        bulletRuns([bold("Young organization"), normal(" \u2014 the entire paperclipai GitHub org is < 5 weeks old with 38,000 stars in 27 days from a single maintainer")]),

        spacer(80),
        heading3("Recommendation"),
        calloutBox(
          "DO NOT RUN ON HOST WITHOUT ISOLATION",
          "Execute only inside a Docker container with network disabled (Gate 1), then with mitmproxy monitoring (Gate 2). Use scoped, rate-limited API keys with $5\u201310 spend caps. Follow the incremental trust gates detailed in Section 5.",
          "E8F5E9",
          GREEN_OK,
        ),

        // --- 2. What This Package Actually Does ---
        new Paragraph({ children: [new PageBreak()] }),
        heading1("2. Package Architecture"),

        para("The companies.sh ecosystem is a three-layer system, not a simple CLI tool:"),
        spacer(60),

        heading3("Layer 1: companies.sh (CLI Orchestrator)"),
        bullet("Thin TypeScript CLI that fetches agent configuration templates from GitHub"),
        bullet("Checks if the local Paperclip server is running on 127.0.0.1:3100"),
        bullet("If not running, silently launches it in the background as a detached process"),
        bullet("Downloads company template files and imports them via the server API"),
        bullet("Writes telemetry UUID to ~/.config/companies.sh/ and phones home to AWS Lambda"),

        spacer(60),
        heading3("Layer 2: paperclipai (Server Engine)"),
        bullet("Full Node.js server that installs and starts a local PostgreSQL database"),
        bullet("Starts a web server on port 3100 with HTTP and WebSocket endpoints"),
        bullet("Runs persistently in the background after first launch"),
        bullet("Contains adapters for Claude Code, Codex, Cursor, Gemini CLI, and others"),

        spacer(60),
        heading3("Layer 3: @paperclipai/server (Closed-Source Runtime)"),
        bullet("744 files, 11MB unpacked \u2014 the actual agent execution engine"),
        bullet("No publicly available source code"),
        bullet("Dependencies include @aws-sdk/client-s3, embedded-postgres, express, ws, sharp, chokidar, open, better-auth"),
        bullet("Manages agent filesystem access, memory, coordination, and execution"),

        // --- 3. Risk Assessment ---
        new Paragraph({ children: [new PageBreak()] }),
        heading1("3. Risk Assessment"),

        para("The following risks were identified through static analysis and dependency inspection:"),
        spacer(80),

        new Table({
          width: { size: CONTENT_W, type: WidthType.DXA },
          columnWidths: [2400, 1200, 5760],
          rows: [
            riskRow("Risk", "Severity", "Detail", true),
            riskRow("Persistent background server", "HIGH", "Running npx companies.sh add silently starts a detached Node.js server on port 3100 (detached: true, child.unref()). It survives after the CLI exits. No explicit \"install a server\" prompt is shown."),
            riskRow("Unauditable server core", "HIGH", "@paperclipai/server (11MB compiled JS) has no public source. You cannot verify what it does at runtime."),
            riskRow("Supply chain attack surface", "HIGH", "20+ dependencies including @aws-sdk/client-s3 (S3 uploads), embedded-postgres (database), open (browser launch), sharp (native binary), chokidar (filesystem watcher)."),
            riskRow("Dynamic code loading", "HIGH", "new Function(\"specifier\", \"return import(specifier)\") in paperclipai enables loading arbitrary modules at runtime, defeating static analysis."),
            riskRow("S3 upload capability", "HIGH", "Full S3 configuration with default bucket named \"paperclip\". Infrastructure for data exfiltration exists even if not currently active."),
            riskRow("Suspicious social proof", "MEDIUM", "Entire org created 2026-02-27. Main repo: 38k stars in 27 days, single maintainer (cryppadotta, protonmail). Star inflation at this velocity is a known social engineering pattern."),
            riskRow("Telemetry without consent", "MEDIUM", "Writes UUID to ~/.config/companies.sh/telemetry.json and POSTs to AWS Lambda on first run. Opt-out via env var, not opt-in."),
            riskRow("Agent filesystem access", "MEDIUM", "Agents get $AGENT_HOME with read/write. chokidar watches broadly. Scope depends on unauditable server sandbox."),
            riskRow("Template injection risk", "MEDIUM", "Community PRs to the template registry (46 forks, 6 open issues) could inject malicious agent configurations."),
            riskRow("Generic fetch(url)", "MEDIUM", "paperclipai contains fetch() calls with variable URLs \u2014 destinations determined at runtime, not just hardcoded API endpoints."),
          ],
        }),

        // --- 4. Static Scan Results ---
        new Paragraph({ children: [new PageBreak()] }),
        heading1("4. Static Scan Results"),

        para("Packages were downloaded as tarballs and unpacked without execution. The following patterns were searched via grep across all .js and .ts files."),

        spacer(80),
        heading2("4.1 companies.sh (CLI Layer)"),
        spacer(40),

        new Table({
          width: { size: CONTENT_W, type: WidthType.DXA },
          columnWidths: [4680, 4680],
          rows: [
            scanRow("Finding", "Verdict", true),
            scanRow("Sensitive path access (.ssh, .aws, .gnupg, keychain)", "CLEAN \u2014 none found"),
            scanRow("eval() / Function() constructor", "CLEAN \u2014 none found"),
            scanRow("Child process spawning", "EXPECTED \u2014 spawns the paperclip server process"),
            scanRow("Network requests", "KNOWN \u2014 health check to localhost:3100 + telemetry to AWS Lambda"),
            scanRow("Environment variable access", "REASONABLE \u2014 PAPERCLIPAI_CMD, PATH, CI detection flags"),
            scanRow("Filesystem writes outside cwd", "KNOWN \u2014 writes to ~/.config/companies.sh/ (telemetry state)"),
            scanRow("Telemetry endpoints", "CONFIRMED \u2014 rusqrrg391.execute-api.us-east-1.amazonaws.com/ingest"),
          ],
        }),

        spacer(200),
        heading2("4.2 paperclipai (Server Engine)"),
        spacer(40),

        new Table({
          width: { size: CONTENT_W, type: WidthType.DXA },
          columnWidths: [4680, 4680],
          rows: [
            scanRow("Finding", "Verdict", true),
            scanRow("Sensitive path access (.ssh, .aws, .gnupg, keychain)", "CLEAN \u2014 none found"),
            scanRow("eval() / Function() constructor", "CONCERN \u2014 new Function(\"specifier\", \"return import(specifier)\") enables dynamic imports"),
            scanRow("Network requests", "MIXED \u2014 api.anthropic.com and api.openai.com (expected), plus generic fetch(url) with variable destinations"),
            scanRow("Environment variable access", "HEAVY \u2014 20+ env vars including DATABASE_URL, auth secrets, master encryption keys"),
            scanRow("Filesystem writes", "EXTENSIVE \u2014 ~15 mkdirSync/writeFileSync calls; writes to PAPERCLIP_HOME, creates dirs and config files"),
            scanRow("Detached/background processes", "CONFIRMED \u2014 spawn with detached: true and child.unref(); server.unref() keeps server alive"),
            scanRow("S3/cloud upload capability", "CONFIRMED \u2014 full S3 config schema, bucket setup (default: \"paperclip\"), region config, @aws-sdk/client-s3"),
            scanRow("Database installation", "CONFIRMED \u2014 embedded-postgres installs and runs a local PostgreSQL instance"),
          ],
        }),

        spacer(200),
        heading3("What the Scan Cannot Tell You"),
        para("The presence of new Function() for dynamic imports means the package can load and execute arbitrary code at runtime that is not visible in the static scan. The generic fetch(url) calls with variable URLs mean network destinations are determined at runtime. Full behavioral analysis requires monitored execution (see Section 5, Gates 1\u20132)."),

        // --- 5. Mitigation Plan ---
        new Paragraph({ children: [new PageBreak()] }),
        heading1("5. Mitigation Plan: Incremental Trust Gates"),

        para("Each gate is a checkpoint. Do not proceed to the next unless the current one passes clean."),
        spacer(80),

        new Table({
          width: { size: CONTENT_W, type: WidthType.DXA },
          columnWidths: [1200, 3580, 4580],
          rows: [
            gateRow("Gate", "Action", "Pass Criteria", true),
            gateRow("0", "Static grep scan (no execution)", "No reads of sensitive paths, no calls to unknown endpoints, no eval with user input"),
            gateRow("1", "Docker container, network disabled", "Fails gracefully; only api.anthropic.com, api.openai.com, registry.npmjs.org in error logs"),
            gateRow("2", "Docker + mitmproxy HTTPS inspection", "All traffic to known-good endpoints; no env vars, filesystem content, or credentials in payloads"),
            gateRow("3", "Filesystem-sandboxed host run (sandbox-exec)", "No file access attempts outside the project directory"),
            gateRow("4", "Normal operation with monitoring", "Clean post-run audit; no new LaunchAgents, background processes, or listening ports"),
            gateRow("5", "Ongoing hygiene", "Version pinned; Gates 0\u20132 re-run before every upgrade"),
          ],
        }),

        spacer(200),
        heading2("5.1 Credential Safety (Pre-Requisite for All Gates)"),
        spacer(40),
        bullet("Anthropic: create a dedicated key named \"paperclip-sandbox\" with $5\u201310/month spend cap"),
        bullet("OpenAI: create a new Project with $10/month budget; key scoped to that Project only"),
        bullet("Other services: only add after trust gates pass; use test accounts with minimal permissions"),
        bullet("Never export API keys in shell profile \u2014 .env file only, never committed to git"),
        bullet("Monitor usage dashboards before and after every test run"),

        spacer(200),
        heading2("5.2 Docker Sandbox Configuration"),
        spacer(40),
        para("The provided Dockerfile.sandbox and run-sandboxed.sh script enforce:"),
        bullet("Read-only filesystem (--read-only)"),
        bullet("All Linux capabilities dropped (--cap-drop ALL)"),
        bullet("No privilege escalation (--security-opt no-new-privileges)"),
        bullet("512MB memory limit"),
        bullet("Network disabled by default (--network none)"),
        bullet("Telemetry disabled (DO_NOT_TRACK=1)"),
        bullet("Non-root user inside container"),

        spacer(200),
        heading2("5.3 Network Monitoring (Gate 2)"),
        spacer(40),
        para("mitmproxy intercepts all HTTPS traffic, allowing inspection of:"),
        bullet("Every destination host and endpoint path"),
        bullet("Request headers (including any leaked credentials)"),
        bullet("Request/response bodies (data being sent and received)"),
        bullet("Connection timing and frequency"),
        spacer(60),
        para("After the run, mitmweb provides a browser UI for reviewing all captured traffic. Look specifically for requests to endpoints other than api.anthropic.com, api.openai.com, and registry.npmjs.org."),

        spacer(200),
        heading2("5.4 Post-Run Audit Checklist"),
        spacer(40),
        bullet("Files modified outside project directory since the run marker timestamp"),
        bullet("New LaunchAgents installed in ~/Library/LaunchAgents/"),
        bullet("Background processes still running (paperclip, companies, embedded-postgres)"),
        bullet("Listening ports (node or postgres on any port, especially 3100)"),
        bullet("Telemetry artifacts at ~/.config/companies.sh/telemetry.json"),
        bullet("Docker containers still running from the sandbox image"),

        // --- 6. Mitigating Factors ---
        new Paragraph({ children: [new PageBreak()] }),
        heading1("6. Mitigating Factors"),

        para("For balanced assessment, the following positive signals were observed:"),
        spacer(60),
        bullet("The CLI layer (companies.sh) has clean, readable TypeScript source code"),
        bullet("Telemetry implementation respects DO_NOT_TRACK=1 and CI=true environment variables"),
        bullet("npm publishing uses GitHub Actions OIDC for provenance (not a personal token)"),
        bullet("Agent instruction templates include explicit \"never exfiltrate secrets\" clauses"),
        bullet("The main paperclip repo has active commit history and contributor community"),
        bullet("Telemetry UUIDs rotate every 30 days and only fire on successful install"),
        spacer(100),
        calloutBox(
          "Important Caveat",
          "Agent instruction clauses like \"never exfiltrate secrets\" are LLM prompts, not access controls. They can be overridden by prompt injection or ignored by the underlying tool framework. The actual security boundary is what the server code permits, and that code is closed-source.",
          "FFF3CD",
          "FFCC02",
        ),

        // --- 7. Conclusion ---
        spacer(200),
        heading1("7. Conclusion"),

        para("The paperclipai/companies.sh ecosystem presents a mixed security profile:"),
        spacer(60),
        bulletRuns([bold("No smoking gun: "), normal("Static analysis found no direct reads of sensitive credentials, SSH keys, or browser data.")]),
        bulletRuns([bold("Cannot be fully cleared: "), normal("Dynamic code loading (new Function), generic fetch with variable URLs, and a closed-source 11MB server core mean runtime behavior is unpredictable from static analysis alone.")]),
        bulletRuns([bold("Unusual trust signals: "), normal("A 5-week-old organization with 38k GitHub stars and a single anonymous maintainer warrants skepticism about the social proof.")]),
        spacer(100),
        para([
          normal("The incremental trust gate approach (Section 5) provides a structured path to evaluate the framework safely. "),
          bold("Gate 0 (static scan) is complete and passed with caveats. "),
          normal("Gates 1\u20132 (Docker isolation + network monitoring) are required before any execution with real API keys."),
        ]),

        spacer(200),
        new Paragraph({
          border: { top: { style: BorderStyle.SINGLE, size: 1, color: GRAY_MID, space: 8 } },
          spacing: { before: 200, after: 80 },
          children: [new TextRun({ text: "End of Report", italics: true, size: 20, font: "Arial", color: "999999" })],
        }),
        new Paragraph({
          children: [new TextRun({ text: "Prepared by automated security analysis. All findings based on static inspection of companies.sh v2026.325.2 and paperclipai v2026.325.0. No code was executed during this analysis.", italics: true, size: 18, font: "Arial", color: "999999" })],
        }),
      ],
    },
  ],
});

// --- Generate ---
const OUTPUT = require("path").join(__dirname, "Security-Analysis-paperclipai-companies-sh.docx");
Packer.toBuffer(doc).then((buffer) => {
  fs.writeFileSync(OUTPUT, buffer);
  console.log(`Report written to: ${OUTPUT}`);
});
