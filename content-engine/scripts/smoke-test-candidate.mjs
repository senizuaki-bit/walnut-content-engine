import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { compileContentUnit } from "./compile-content.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const engineRoot = resolve(scriptDir, "..");
const projectRoot = resolve(engineRoot, "..");

export function smokeTestCandidate(sourcePath, options = {}) {
  const projectDir = resolve(options.projectDir ?? join(projectRoot, "my_topdown_game-main"));
  const godotExe = resolve(options.godotExe ?? join(projectRoot, "tools", "godot-4.5.2", "Godot_v4.5.2-stable_win64_console.exe"));
  const stageRoot = mkdtempSync(join(tmpdir(), "walnut-candidate-smoke-"));
  try {
    const compiled = compileContentUnit(resolve(sourcePath), {
      projectDir,
      assetSourcePath: options.assetSourcePath,
      projectContentDir: join(stageRoot, "content"),
      godotDir: join(stageRoot, "generated", "godot"),
      aiDir: join(stageRoot, "generated", "ai"),
      generatedAt: options.generatedAt,
    });
    const result = spawnSync(godotExe, ["--headless", "--path", projectDir, "--", "--demo-test"], {
      cwd: projectDir,
      encoding: "utf8",
      windowsHide: true,
      env: { ...process.env, XIAO_HETAO_CONTENT_MANIFEST: compiled.paths.godotAliasPath },
      timeout: Number(options.timeoutMs ?? 120_000),
    });
    if (result.error) throw result.error;
    const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
    if (result.status !== 0 || !output.includes("DATA_GARDEN_SMOKE_OK")) {
      throw new Error(`候选包 Godot 冒烟失败：${output.replace(/\s+/gu, " ").trim().slice(0, 500)}`);
    }
    return { ok: true, contentHash: compiled.contentHash, output: "DATA_GARDEN_SMOKE_OK", assets: compiled.assets };
  } finally {
    if (!options.keepStage) rmSync(stageRoot, { recursive: true, force: true });
  }
}

function runCli() {
  const sourcePath = process.argv[2];
  if (!sourcePath) throw new Error("用法：node smoke-test-candidate.mjs <candidate.json>");
  const result = smokeTestCandidate(sourcePath, { keepStage: process.argv.includes("--keep-stage") });
  console.log(`CANDIDATE_SMOKE_OK ${result.contentHash.slice(0, 12)}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { runCli(); } catch (error) { console.error(`CANDIDATE_SMOKE_FAILED ${error instanceof Error ? error.message : String(error)}`); process.exitCode = 1; }
}
