const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, HeadingLevel, BorderStyle, WidthType,
  ShadingType, PageNumber, PageBreak, LevelFormat,
} = require("docx");

// --- Colors ---
const BRAND_DARK = "1B2A4A";
const BRAND_ACCENT = "2E75B6";
const RED = "C0392B";
const GREEN = "27AE60";
const ORANGE = "E67E22";
const GRAY_LIGHT = "F2F4F7";
const GRAY_MID = "D5D8DC";
const WHITE = "FFFFFF";

// --- Page ---
const PAGE_W = 12240;
const PAGE_H = 15840;
const MARGIN = 1440;
const CONTENT_W = PAGE_W - 2 * MARGIN;

// --- Borders ---
const noBorder = { style: BorderStyle.NONE, size: 0 };
const thinBorder = { style: BorderStyle.SINGLE, size: 1, color: GRAY_MID };
const thinBorders = { top: thinBorder, bottom: thinBorder, left: thinBorder, right: thinBorder };

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
      reference: "numbered2",
      levels: [
        { level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } } },
      ],
    },
    {
      reference: "numbered3",
      levels: [
        { level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } } },
      ],
    },
    {
      reference: "numbered4",
      levels: [
        { level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } } },
      ],
    },
  ],
};

// --- Helpers ---
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
function numbered(text, ref = "numbered") {
  return new Paragraph({
    numbering: { reference: ref, level: 0 },
    spacing: { after: 80 },
    children: [new TextRun({ text, size: 21, font: "Arial", color: "333333" })],
  });
}
function numberedRuns(runs, ref = "numbered") {
  return new Paragraph({
    numbering: { reference: ref, level: 0 },
    spacing: { after: 80 },
    children: runs,
  });
}
function bold(text) { return new TextRun({ text, bold: true, size: 21, font: "Arial", color: "333333" }); }
function normal(text) { return new TextRun({ text, size: 21, font: "Arial", color: "333333" }); }
function mono(text) { return new TextRun({ text, size: 19, font: "Courier New", color: BRAND_DARK }); }
function spacer(h = 120) { return new Paragraph({ spacing: { after: h }, children: [] }); }

function codeBlock(lines) {
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA },
    columnWidths: [CONTENT_W],
    rows: [new TableRow({
      children: [new TableCell({
        width: { size: CONTENT_W, type: WidthType.DXA },
        borders: { top: thinBorder, bottom: thinBorder, left: thinBorder, right: thinBorder },
        margins: { top: 100, bottom: 100, left: 200, right: 200 },
        shading: { fill: "F5F5F5", type: ShadingType.CLEAR },
        children: lines.map(l => new Paragraph({
          spacing: { after: 40 },
          children: [new TextRun({ text: l, size: 18, font: "Courier New", color: "333333" })],
        })),
      })],
    })],
  });
}

function calloutBox(title, bodyText, fillColor = "FFF3CD", borderColor = "FFCC02") {
  const border = { style: BorderStyle.SINGLE, size: 2, color: borderColor };
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA },
    columnWidths: [CONTENT_W],
    rows: [new TableRow({
      children: [new TableCell({
        width: { size: CONTENT_W, type: WidthType.DXA },
        borders: { top: border, bottom: border, left: border, right: border },
        margins: { top: 120, bottom: 120, left: 200, right: 200 },
        shading: { fill: fillColor, type: ShadingType.CLEAR },
        children: [
          new Paragraph({ spacing: { after: 60 }, children: [bold(title)] }),
          new Paragraph({ children: [new TextRun({ text: bodyText, size: 20, font: "Arial", color: "555555" })] }),
        ],
      })],
    })],
  });
}

function stepRow(step, action, isHeader = false) {
  const bg = isHeader ? BRAND_DARK : WHITE;
  const fg = isHeader ? WHITE : "333333";
  const m = { top: 60, bottom: 60, left: 100, right: 100 };
  return new TableRow({ children: [
    new TableCell({ width: { size: 1400, type: WidthType.DXA }, borders: thinBorders, margins: m,
      shading: { fill: bg, type: ShadingType.CLEAR },
      children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: step, bold: true, size: 19, font: "Arial", color: fg })] })] }),
    new TableCell({ width: { size: 7960, type: WidthType.DXA }, borders: thinBorders, margins: m,
      shading: { fill: bg, type: ShadingType.CLEAR },
      children: [new Paragraph({ children: [new TextRun({ text: action, size: 19, font: "Arial", color: fg })] })] }),
  ]});
}

// --- Build Document ---
const doc = new Document({
  styles: {
    default: { document: { run: { font: "Arial", size: 21 } } },
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
        page: { size: { width: PAGE_W, height: PAGE_H }, margin: { top: MARGIN, right: MARGIN, bottom: MARGIN, left: MARGIN } },
      },
      children: [
        spacer(2400),
        new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 80 },
          children: [new TextRun({ text: "GETTING STARTED SAFELY WITH", size: 28, font: "Arial", color: "666666" })] }),
        new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 200 },
          border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: BRAND_ACCENT, space: 8 } },
          children: [new TextRun({ text: "Paperclip AI (companies.sh)", size: 44, bold: true, font: "Arial", color: BRAND_DARK })] }),
        spacer(300),
        new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 80 },
          children: [new TextRun({ text: "A step-by-step guide to running paperclipai safely", size: 24, font: "Arial", color: "666666" })] }),
        new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 80 },
          children: [new TextRun({ text: "using Docker isolation, network monitoring, and scoped credentials", size: 22, font: "Arial", color: "888888" })] }),
        spacer(800),
        new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 80 },
          children: [new TextRun({ text: "March 2026", size: 22, font: "Arial", color: "888888" })] }),
        spacer(1200),
        calloutBox(
          "WHO THIS IS FOR",
          "Anyone evaluating paperclipai/companies.sh for the first time. This guide assumes you have Docker installed and basic command-line familiarity. No prior knowledge of Paperclip is needed.",
          "E3F2FD",
          BRAND_ACCENT,
        ),
      ],
    },

    // ===================== BODY =====================
    {
      properties: {
        page: { size: { width: PAGE_W, height: PAGE_H }, margin: { top: MARGIN, right: MARGIN, bottom: MARGIN, left: MARGIN } },
      },
      headers: {
        default: new Header({ children: [new Paragraph({
          border: { bottom: { style: BorderStyle.SINGLE, size: 1, color: GRAY_MID, space: 4 } },
          children: [new TextRun({ text: "Getting Started Safely with Paperclip AI", size: 16, font: "Arial", color: "999999" })],
        })] }),
      },
      footers: {
        default: new Footer({ children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          border: { top: { style: BorderStyle.SINGLE, size: 1, color: GRAY_MID, space: 4 } },
          children: [
            new TextRun({ text: "Page ", size: 16, font: "Arial", color: "999999" }),
            new TextRun({ children: [PageNumber.CURRENT], size: 16, font: "Arial", color: "999999" }),
          ],
        })] }),
      },
      children: [
        // --- What is Paperclip? ---
        heading1("1. What is Paperclip?"),
        para("Paperclip is an AI agent orchestration platform. It lets you create virtual \"companies\" made of AI agents — a CEO agent, engineers, QA testers, designers — that coordinate through a shared server to accomplish tasks."),
        spacer(40),
        para([bold("What it installs: "), normal("A Node.js server (port 3100) with an embedded PostgreSQL database, a React dashboard, and agent execution infrastructure.")]),
        para([bold("What companies.sh does: "), normal("A CLI companion that imports pre-built company templates from a catalog of 16+ templates with 440+ agents.")]),
        para([bold("What agents do: "), normal("Wake on scheduled \"heartbeats,\" check for assigned tasks, execute work (code, research, content), delegate subtasks, and report results.")]),

        spacer(80),
        calloutBox(
          "WHY CAUTION IS WARRANTED",
          "The core server runtime (@paperclipai/server, 11MB) is open source (https://github.com/paperclipai/paperclip), but the npm artifact is compiled JS that may diverge from the repository. The npm package installs a persistent background server and database. The GitHub organization is less than 5 weeks old. A full security analysis is available in the companion document. This guide focuses on how to run it safely despite these concerns.",
          "FCE4EC",
          RED,
        ),

        // --- Prerequisites ---
        spacer(200),
        heading1("2. Prerequisites"),
        spacer(40),

        new Table({
          width: { size: CONTENT_W, type: WidthType.DXA },
          columnWidths: [1400, 7960],
          rows: [
            stepRow("Tool", "Details", true),
            stepRow("Docker", "Docker Desktop installed and running. This is the primary isolation boundary."),
            stepRow("Git", "For cloning the paperclip-sandbox repository."),
            stepRow("Node.js", "v20+ (for running the static scan script only — not for running Paperclip itself)."),
            stepRow("API Keys", "Anthropic and/or OpenAI accounts for LLM access. You will create scoped, limited keys."),
          ],
        }),

        spacer(100),
        para([bold("Optional but recommended: "), normal("mitmproxy (brew install mitmproxy) for inspecting all HTTPS traffic during Gate 2.")]),

        // --- Step 1: Clone ---
        new Paragraph({ children: [new PageBreak()] }),
        heading1("3. Step-by-Step Setup"),

        heading2("Step 1: Clone the sandbox repository"),
        spacer(40),
        codeBlock([
          "git clone <repo-url> paperclip-sandbox",
          "cd paperclip-sandbox",
        ]),

        spacer(80),
        para("This repository contains Docker configuration, security scripts, and safe wrapper scripts. It does NOT contain Paperclip itself — Paperclip is installed inside the Docker container at build time."),

        // --- Step 2: API Keys ---
        spacer(200),
        heading2("Step 2: Create scoped API keys"),
        spacer(40),
        para("This is the single most important safety step. Never use your primary development API keys."),
        spacer(60),

        heading3("Anthropic"),
        numbered("Log in to console.anthropic.com", "numbered"),
        numbered("Create a new Workspace (or use an existing test workspace)", "numbered"),
        numbered("Create a new API key named \"paperclip-sandbox\"", "numbered"),
        numbered("Set a monthly spend limit of $5\u201310 on the workspace", "numbered"),

        spacer(60),
        heading3("OpenAI"),
        numbered("Log in to platform.openai.com", "numbered2"),
        numbered("Create a new Project named \"paperclip-sandbox\"", "numbered2"),
        numbered("Set a $10/month budget on the Project", "numbered2"),
        numbered("Create an API key scoped to that Project only", "numbered2"),

        spacer(60),
        heading3("Other services"),
        bullet("Other services: Only add if a specific company template requires them. Use test accounts with minimal permissions."),

        // --- Step 3: Configure ---
        spacer(200),
        heading2("Step 3: Configure environment"),
        spacer(40),
        codeBlock([
          "cp .env.example .env",
          "",
          "# Edit .env and add your scoped keys:",
          "# ANTHROPIC_API_KEY=sk-ant-...",
          "# OPENAI_API_KEY=sk-...",
        ]),

        spacer(80),
        calloutBox(
          "NEVER DO THIS",
          "Do not export API keys in your shell profile (e.g., export OPENAI_API_KEY=...). Keys should only exist in the .env file, which is gitignored and only passed to the Docker container. Do not commit .env to git.",
          "FCE4EC",
          RED,
        ),

        // --- Step 4: Static scan ---
        new Paragraph({ children: [new PageBreak()] }),
        heading2("Step 4: Run the static security scan (Gate 0)"),
        spacer(40),
        para("This downloads the npm packages without executing them and searches for dangerous patterns."),
        spacer(60),
        codeBlock(["./security/static-scan.sh"]),
        spacer(80),
        para("Review the output. You are looking for:"),
        bullet("Reads of sensitive paths (.ssh, .aws, .gnupg, keychains)"),
        bullet("eval() or Function() with dynamic, user-controlled input"),
        bullet("Network calls to unrecognized endpoints"),
        bullet("Detached background process creation"),
        bullet("S3 upload patterns or cloud exfiltration"),
        spacer(60),
        para([bold("If anything looks alarming, stop. "), normal("Share the output with someone who can review it. Do not proceed to the next step until you are comfortable with the scan results.")]),

        // --- Step 5: Gate 1 ---
        spacer(200),
        heading2("Step 5: First run — Docker with no network (Gate 1)"),
        spacer(40),
        para("This is the safest possible execution. The container has no internet access, so even if the code is malicious, it cannot exfiltrate data."),
        spacer(60),
        codeBlock(["./scripts/start.sh --isolated"]),
        spacer(80),
        para("What to expect:"),
        bullet("The container builds and starts Paperclip"),
        bullet("Onboarding runs automatically"),
        bullet("Network calls will fail (this is intentional)"),
        bullet("Check the logs for which endpoints it tried to reach"),
        spacer(60),
        para([bold("Pass criteria: "), normal("Only api.anthropic.com, api.openai.com, and registry.npmjs.org appear in error logs. No unexpected endpoints.")]),
        spacer(60),
        para("Stop the sandbox and run the audit:"),
        codeBlock([
          "./scripts/stop.sh",
          "./security/audit-run.sh /tmp/paperclip-sandbox-marker-XXXXX",
        ]),

        // --- Step 6: Gate 2 ---
        spacer(200),
        heading2("Step 6: Monitored run with mitmproxy (Gate 2)"),
        spacer(40),
        para("Now enable network access, but route all traffic through a proxy that logs every request."),
        spacer(60),
        codeBlock(["./scripts/start.sh --proxy"]),
        spacer(80),
        para("This starts two containers:"),
        bullet("Paperclip server (all traffic routed through the proxy)"),
        bullet("mitmproxy web UI at http://localhost:8081"),
        spacer(60),
        para("Open http://localhost:8081 in your browser. You will see every HTTPS request in real time — destination, headers, and full request/response bodies."),
        spacer(60),
        para([bold("What to verify:")]),
        bullet("All traffic goes to known-good endpoints (api.anthropic.com, api.openai.com, registry.npmjs.org, github.com)"),
        bullet("Request bodies contain only expected data (prompts, template downloads)"),
        bullet("No environment variables, file contents, or credentials appear in request payloads"),
        bullet("No requests to unknown AWS endpoints, S3 buckets, or third-party servers"),

        // --- Step 7: Normal use ---
        new Paragraph({ children: [new PageBreak()] }),
        heading2("Step 7: Normal operation"),
        spacer(40),
        para("After Gates 0\u20132 pass clean, you can run with network access:"),
        spacer(60),
        codeBlock(["./scripts/start.sh"]),
        spacer(80),
        para("The dashboard is at http://localhost:3100. From here you can:"),
        bullet("Create companies via the UI"),
        bullet("Add pre-built company templates from the catalog"),
        bullet("Hire agents, assign tasks, and monitor execution"),
        spacer(60),
        para("To add a company template:"),
        codeBlock(["./scripts/add-company.sh paperclipai/companies/default"]),
        spacer(60),
        para("To monitor resource usage and network connections:"),
        codeBlock(["./scripts/monitor.sh"]),

        // --- Safety Rules ---
        spacer(200),
        heading1("4. Ongoing Safety Rules"),
        spacer(40),

        heading3("Always"),
        bullet("Run inside Docker — never npx paperclipai or npx companies.sh directly on your host"),
        bullet("Use scoped API keys with spend caps — check provider dashboards after each session"),
        bullet("Run the post-run audit after stopping the sandbox"),
        bullet("Back up before upgrades: ./scripts/backup.sh"),
        spacer(60),

        heading3("Never"),
        bullet("Export API keys in your shell profile or .bashrc/.zshrc"),
        bullet("Run Paperclip outside of Docker on a machine with SSH keys, AWS credentials, or browser sessions"),
        bullet("Skip trust gates when upgrading to a new version"),
        bullet("Give Paperclip access to production API keys or real customer accounts"),
        spacer(60),

        heading3("When upgrading"),
        numbered("Stop the sandbox", "numbered3"),
        numbered("Back up: ./scripts/backup.sh", "numbered3"),
        numbered("Re-run Gate 0 (static scan) on the new version", "numbered3"),
        numbered("Re-run Gate 1 (isolated) to check for new endpoints", "numbered3"),
        numbered("Re-run Gate 2 (proxy) to inspect traffic changes", "numbered3"),
        numbered("Only then start normally", "numbered3"),

        // --- Quick Reference ---
        new Paragraph({ children: [new PageBreak()] }),
        heading1("5. Quick Reference"),
        spacer(40),

        new Table({
          width: { size: CONTENT_W, type: WidthType.DXA },
          columnWidths: [3500, 5860],
          rows: [
            stepRow("Command", "What it does", true),
            stepRow("./scripts/start.sh", "Start Paperclip in Docker with safety controls"),
            stepRow("./scripts/start.sh --isolated", "Start with NO network (Gate 1)"),
            stepRow("./scripts/start.sh --proxy", "Start with mitmproxy monitoring (Gate 2)"),
            stepRow("./scripts/stop.sh", "Stop all containers, check for escaped processes"),
            stepRow("./scripts/add-company.sh <template>", "Add a company template inside the running container"),
            stepRow("./scripts/monitor.sh", "Live resource and network monitoring"),
            stepRow("./scripts/backup.sh", "Snapshot data/ before upgrades"),
            stepRow("./security/static-scan.sh", "Download and grep packages (no execution)"),
            stepRow("./security/audit-run.sh <marker>", "Post-run file, process, and port audit"),
          ],
        }),

        spacer(200),
        heading2("Key URLs"),
        bullet("Paperclip Dashboard: http://localhost:3100"),
        bullet("mitmproxy UI (proxy mode): http://localhost:8081"),
        bullet("Health check: http://localhost:3100/api/health"),

        spacer(200),
        heading2("Key Files"),
        bullet(".env — your scoped API keys (gitignored, never committed)"),
        bullet("data/ — all Paperclip data: database, agent workspaces, backups (gitignored)"),
        bullet("docker/ — container configuration and compose files"),
        bullet("security/PLAYBOOK.md — full security analysis and trust gate details"),

        // --- Troubleshooting ---
        spacer(200),
        heading1("6. Troubleshooting"),
        spacer(40),

        heading3("Container fails to start"),
        bullet("Check Docker Desktop is running"),
        bullet("Check .env file exists and has at least one API key"),
        bullet("Check port 3100 is not in use: lsof -i :3100"),
        spacer(60),

        heading3("Agents are not executing"),
        bullet("Check the dashboard for error messages on agent cards"),
        bullet("Verify API keys are valid and have remaining budget"),
        bullet("Check container logs: docker logs paperclip-sandbox"),
        spacer(60),

        heading3("Proxy mode shows no traffic"),
        bullet("Ensure you used --proxy flag (not just --network)"),
        bullet("Check mitmproxy container is running: docker ps"),
        bullet("Open http://localhost:8081 — traffic appears in real time"),
        spacer(60),

        heading3("Need to start fresh"),
        codeBlock([
          "./scripts/stop.sh",
          "rm -rf data/*",
          "touch data/.gitkeep",
          "./scripts/start.sh",
        ]),

        spacer(200),
        new Paragraph({
          border: { top: { style: BorderStyle.SINGLE, size: 1, color: GRAY_MID, space: 8 } },
          spacing: { before: 200, after: 80 },
          children: [new TextRun({ text: "End of Guide", italics: true, size: 20, font: "Arial", color: "999999" })],
        }),
        new Paragraph({
          children: [new TextRun({ text: "For the full security analysis, see the companion document: Security Analysis Report — paperclipai/companies.sh", italics: true, size: 18, font: "Arial", color: "999999" })],
        }),
      ],
    },
  ],
});

// --- Generate ---
const OUTPUT = require("path").join(__dirname, "Getting-Started-Safely-with-Paperclip-AI.docx");
Packer.toBuffer(doc).then((buffer) => {
  fs.writeFileSync(OUTPUT, buffer);
  console.log(`Guide written to: ${OUTPUT}`);
});
