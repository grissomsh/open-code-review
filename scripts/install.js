#!/usr/bin/env node
"use strict";

/**
 * postinstall script for @ali/open-code-review
 * Downloads the pre-built Go binary matching the current platform.
 */

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
const https = require("https");
const crypto = require("crypto");

// ── Configuration ────────────────────────────────────────────────────────────
const REPO_BASE = "https://code.alibaba-inc.com/open-code-review/internal-release/raw/master";
const BINARY_NAME = "opencodereview";

// Resolve paths relative to package root (parent of scripts/)
const binDir = path.join(__dirname, "..", "bin");
const binaryDest = path.join(binDir, BINARY_NAME);

// ── Logging ──────────────────────────────────────────────────────────────────
function info(msg) {
  console.log(`[INFO]  ${msg}`);
}

function warn(msg) {
  console.warn(`[WARN]  ${msg}`);
}

function error(msg) {
  console.error(`[ERROR] ${msg}`);
}

// ── Detect OS & Arch ─────────────────────────────────────────────────────────
function detectPlatform() {
  const os = process.platform;
  let arch = process.arch;

  // Map Node.js arch to Go arch naming used in release artifacts
  switch (arch) {
    case "x64":
      arch = "amd64";
      break;
    case "arm64":
      arch = "arm64";
      break;
    default:
      throw new Error(
        `Unsupported architecture: ${arch}. Supported: amd64 (x64), arm64`
      );
  }

  if (os !== "linux" && os !== "darwin") {
    throw new Error(
      `Unsupported operating system: ${os}. Supported: linux, darwin`
    );
  }

  return { os, arch };
}

// ── Resolve version ──────────────────────────────────────────────────────────
async function resolveVersion() {
  const envVersion = process.env.OCR_VERSION;
  if (envVersion) {
    const v = envVersion.startsWith("v") ? envVersion : `v${envVersion}`;
    info(`Using pinned version from OCR_VERSION: ${v}`);
    return v;
  }

  try {
    info("Fetching latest version...");
    const body = await downloadText(`${REPO_BASE}/VERSION`);
    const lines = body.trim().split("\n").map(l => l.trim()).filter(Boolean);
    if (lines.length > 0) {
      const version = lines[lines.length - 1];
      info(`Latest version: ${version}`);
      return version;
    }
  } catch (e) {
    warn(`Failed to fetch VERSION endpoint: ${e.message}`);
  }

  throw new Error(
    "Cannot determine version. Set OCR_VERSION env variable to pin a specific version."
  );
}

// ── HTTP helpers ─────────────────────────────────────────────────────────────
function downloadText(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        // Follow redirect manually
        downloadText(res.headers.location).then(resolve).catch(reject);
        return;
      }
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode} fetching ${url}`));
        return;
      }
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => resolve(data));
    }).on("error", reject);
  });
}

function downloadBinary(url, destPath) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        downloadBinary(res.headers.location, destPath).then(resolve).catch(reject);
        return;
      }
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode} downloading ${url}`));
        return;
      }

      const fileStream = fs.createWriteStream(destPath);
      let downloadedBytes = 0;

      res.on("data", (chunk) => {
        downloadedBytes += chunk.length;
      });

      res.pipe(fileStream);

      fileStream.on("finish", () => {
        fileStream.close(() => resolve());
      });

      fileStream.on("error", (err) => {
        fs.unlink(destPath, () => {}); // clean up partial download
        reject(err);
      });
    }).on("error", reject);
  });
}

// ── Checksum verification ────────────────────────────────────────────────────
async function verifyChecksum(binaryFilePath, expectedSha) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(binaryFilePath);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
    stream.on("error", reject);
  });
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  info("OpenCodeReview Installer");
  info("=========================");

  const { os, arch } = detectPlatform();
  info(`Detected platform: ${os}/${arch}`);

  const version = await resolveVersion();

  // Ensure bin directory exists
  if (!fs.existsSync(binDir)) {
    fs.mkdirSync(binDir, { recursive: true });
  }

  // Ensure the JS wrapper has execute permission (needed on some Linux setups)
  const jsWrapper = path.join(binDir, "ocr.js");
  if (fs.existsSync(jsWrapper)) {
    try {
      fs.chmodSync(jsWrapper, 0o755);
      info("Made ocr.js executable.");
    } catch (e) {
      warn(`Could not make ocr.js executable: ${e.message}`);
    }
  }

  // Download URL: bin/{VERSION}/{NAME}-{OS}-{ARCH}
  const versionNum = version.replace(/^v/, "");
  const remoteFileName = `${BINARY_NAME}-${os}-${arch}`;
  const downloadUrl = `${REPO_BASE}/bin/v${versionNum}/${remoteFileName}`;
  info(`Downloading ${downloadUrl} ...`);

  await downloadBinary(downloadUrl, binaryDest);
  fs.chmodSync(binaryDest, 0o755);

  // Try to verify checksum
  try {
    info("Fetching checksum file...");
    const shaContent = await downloadText(`${REPO_BASE}/bin/v${versionNum}/sha256sum.txt`);
    for (const line of shaContent.split("\n")) {
      const trimmed = line.trim();
      // Match by OS+arch since local name lacks version prefix
      if (trimmed.endsWith(`-${os}-${arch}`)) {
        const expectedSha = trimmed.split(/\s+/)[0];
        if (expectedSha) {
          const actualSha = await verifyChecksum(binaryDest, expectedSha);
          if (actualSha !== expectedSha.toLowerCase()) {
            throw new Error(
              `Checksum mismatch! Expected: ${expectedSha}, Got: ${actualSha}`
            );
          }
          info("Checksum verified.");
          break;
        }
      }
    }
  } catch (e) {
    if (e.message.includes("HTTP 404") || e.message.includes("checksum")) {
      warn("Checksum file not found; skipping integrity check.");
    } else if (e.message.includes("Mismatch")) {
      throw e;
    } else {
      warn(`Could not verify checksum: ${e.message}`);
    }
  }

  info(`Installed: ${binaryDest}`);
  info("");
  info("OpenCodeReview is ready!");
  info("");
  info("Quick start:");
  info("  ocr version             Show version info");
  info("  ocr config set          Configure your LLM provider");
  info("  ocr review              Start a code review");
}

main().catch((err) => {
  error(err.message);
  process.exit(1);
});
