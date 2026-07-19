import { spawnSync } from "node:child_process";
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, readdirSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { publishFromFeishu } from "./publish-from-feishu.mjs";
import { processWorldWorkshop } from "./world-workshop.mjs";
import { publishReviewAssignments } from "./review-assignments.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const engineRoot = resolve(scriptDir, "..");
const projectRoot = resolve(engineRoot, "..");
const config = JSON.parse(readFileSync(join(engineRoot, "feishu", "publish-config.json"), "utf8"));
const outboxDir = join(projectRoot, "xiao-hetao-ai-server", "data", "feishu-outbox");
const syncScript = join(projectRoot, "xiao-hetao-ai-server", "sync-feishu-session.ps1");
const stateDir = join(engineRoot, ".state");
const syncStatePath = join(stateDir, "synced-feishu-sessions.json");
const watcherLockPath = join(stateDir, "watch-feishu-publish.lock");
let busy = false;

function pidIsAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export function acquireWatcherLock() {
  mkdirSync(stateDir, { recursive: true });
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const fd = openSync(watcherLockPath, "wx");
      writeFileSync(fd, `${JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() })}\n`, "utf8");
      closeSync(fd);

      let released = false;
      const release = () => {
        if (released) return;
        released = true;
        try {
          const lock = JSON.parse(readFileSync(watcherLockPath, "utf8"));
          if (Number(lock.pid) === process.pid) unlinkSync(watcherLockPath);
        } catch {
          // A stale or already-replaced lock is safe to leave for the next start.
        }
      };
      process.once("exit", release);
      return { acquired: true, release };
    } catch (error) {
      if (error?.code !== "EEXIST") throw error;
      let existingPid = 0;
      try {
        existingPid = Number(JSON.parse(readFileSync(watcherLockPath, "utf8")).pid);
      } catch {
        // Invalid lock files are treated as stale.
      }
      if (pidIsAlive(existingPid)) return { acquired: false, pid: existingPid };
      try { unlinkSync(watcherLockPath); } catch { /* retried below */ }
    }
  }
  return { acquired: false, pid: 0 };
}

function readSyncState() {
  if (!existsSync(syncStatePath)) return { files: {} };
  try {
    return JSON.parse(readFileSync(syncStatePath, "utf8"));
  } catch {
    return { files: {} };
  }
}

function writeSyncState(state) {
  mkdirSync(stateDir, { recursive: true });
  writeFileSync(syncStatePath, `${JSON.stringify(state, null, 2)}\n`, "utf8");
}

export function syncEvidenceOutbox() {
  if (!existsSync(outboxDir)) return;
  const state = readSyncState();
  for (const name of readdirSync(outboxDir).filter((file) => file.endsWith(".json")).sort()) {
    if (state.files[name]) continue;
    const outboxPath = join(outboxDir, name);
    JSON.parse(readFileSync(outboxPath, "utf8"));
    const result = spawnSync("powershell.exe", [
      "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
      "-File", syncScript,
      "-OutboxPath", outboxPath,
      "-BaseToken", config.base_token,
      "-TableId", config.tables.classroom_evidence,
    ], { cwd: projectRoot, encoding: "utf8", windowsHide: true });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(result.stderr?.trim() || result.stdout?.trim() || `课堂证据同步退出码 ${result.status}`);
    state.files[name] = new Date().toISOString();
    writeSyncState(state);
    console.log(`[content-engine] 课堂证据已回写：${name}`);
  }
}

export async function tick() {
  if (busy) return;
  busy = true;
  try {
    const workshopResults = await processWorldWorkshop(config, engineRoot);
    for (const item of workshopResults) {
      console.log(item.status === "generated"
        ? `[content-engine] 世界候选已生成：${item.unit.world.theme}@${item.unit.version}`
        : `[content-engine] 世界候选生成失败：${item.error}`);
    }
    const result = publishFromFeishu();
    if (result.status === "published") {
      console.log(`[content-engine] 已发布 ${result.unit.unit_id}@${result.unit.version}（主任务 ${result.unit.world.main_target}，迁移 ${result.unit.world.transfer_target}）`);
    }
    syncEvidenceOutbox();
    const assignments = publishReviewAssignments(config, engineRoot);
    for (const assignment of assignments) console.log(`[content-engine] 回访任务已发布：${assignment.variant_id} → ${assignment.student_hash}`);
  } catch (error) {
    console.error(`[content-engine] ${error instanceof Error ? error.message : String(error)}`);
  } finally {
    busy = false;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const runOnce = process.argv.includes("--once");
  const lock = acquireWatcherLock();
  if (!lock.acquired) {
    console.log(`[content-engine] 已有飞书发布器运行（PID ${lock.pid || "未知"}），本进程退出`);
  } else {
    console.log(runOnce
      ? "[content-engine] 执行一次发布与课堂证据同步"
      : `[content-engine] 飞书发布器已启动，每 ${config.poll_interval_ms / 1000} 秒检查一次“发布请求”`);
    await tick();
    if (runOnce) lock.release();
    else setInterval(tick, config.poll_interval_ms);
  }
}
