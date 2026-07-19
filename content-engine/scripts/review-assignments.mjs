import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { listRecords, updateRecord } from "./feishu-bridge.mjs";

export function publishReviewAssignments(config, engineRoot) {
  const tableId = config.tables.classroom_evidence;
  const rows = listRecords(config, tableId, engineRoot);
  const activeManifestPath = join(engineRoot, "..", "my_topdown_game-main", "content", "generated", `${config.unit_id}.json`);
  const sourceVersion = JSON.parse(readFileSync(join(engineRoot, "source", "data-garden-loop.json"), "utf8")).version;
  const versionedManifestPath = join(engineRoot, "generated", "godot", `${config.unit_id}.${sourceVersion}.json`);
  const manifestPath = existsSync(activeManifestPath) ? activeManifestPath : versionedManifestPath;
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const knownVariants = new Set((manifest.transfer_variants ?? []).map((variant) => variant.variant_id));
  const assignmentDir = join(engineRoot, "generated", "review-assignments");
  mkdirSync(assignmentDir, { recursive: true });
  const results = [];
  for (const row of rows.filter((candidate) => candidate.fields["回访发布"] === true)) {
    const studentHash = String(row.fields["学生哈希"] ?? "");
    const variantId = String(row.fields["推荐变式ID"] ?? "");
    if (!/^walnut_[a-f0-9]{24}$/u.test(studentHash) || !knownVariants.has(variantId)) {
      updateRecord(config, tableId, row.record_id, { "回访发布": false, "回访发布结果": "发布失败：学生哈希或推荐变式无效" }, { cwd: engineRoot, statePath: join(engineRoot, ".state", "review-assignment-error.json") });
      continue;
    }
    const assignmentId = `assignment_${createHash("sha256").update(`${row.record_id}:${variantId}:${manifest.version}`).digest("hex").slice(0, 20)}`;
    const assignment = {
      assignment_id: assignmentId,
      student_hash: studentHash,
      unit_id: manifest.unit_id,
      content_version: manifest.version,
      content_hash: manifest.content_hash,
      variant_id: variantId,
      source_session_id: String(row.fields["会话ID"] ?? ""),
      published_at: new Date().toISOString(),
    };
    writeFileSync(join(assignmentDir, `${studentHash}.json`), `${JSON.stringify(assignment, null, 2)}\n`, "utf8");
    updateRecord(config, tableId, row.record_id, {
      "回访发布": false,
      "回访任务ID": assignmentId,
      "回访发布结果": `已发布 ${variantId}｜${manifest.version}`,
    }, { cwd: engineRoot, statePath: join(engineRoot, ".state", "review-assignment-success.json") });
    results.push(assignment);
  }
  return results;
}
