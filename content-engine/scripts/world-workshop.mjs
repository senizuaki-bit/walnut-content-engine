import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { generateSkinCandidate } from "./generate-skin-candidate.mjs";
import { nextMinorVersion } from "./generation-common.mjs";
import { listRecords, updateRecord, uploadAttachment } from "./feishu-bridge.mjs";

function safeMessage(error) {
  return String(error instanceof Error ? error.message : error).replace(/\s+/gu, " ").trim().slice(0, 300);
}

const ASSET_LABELS = Object.freeze({
  background_before: "修复前背景",
  background_after: "修复后背景",
  target_entity: "目标实体",
  console: "控制台",
  npc: "NPC",
});

function heartbeatText() {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(new Date());
}

export function workshopProgressFields(event = {}) {
  const asset = ASSET_LABELS[event.asset_key] ?? String(event.asset_key ?? "素材");
  const index = Number(event.asset_index ?? 0);
  const total = Math.max(1, Number(event.asset_total ?? 5));
  const imageProgress = Math.min(68, 10 + Math.round((Math.max(0, index - (event.phase === "image_complete" || event.phase === "asset_resumed" ? 0 : 1)) / total) * 58));
  let progress = Number.isFinite(Number(event.progress)) ? Number(event.progress) : imageProgress;
  let status;
  switch (event.phase) {
    case "text_start": status = "文案生成/恢复中"; break;
    case "original_restore": status = "恢复官方原版花园｜不调用生图模型"; break;
    case "text_complete": status = event.resumed ? "文案检查点已恢复" : "文案已生成"; break;
    case "images_start": status = "准备生成 5 张世界素材"; break;
    case "image_request": status = `生图 ${index}/${total}｜${asset}｜请求中（第 ${event.attempt} 次，最长约 6 分钟）`; break;
    case "image_waiting": status = `生图 ${index}/${total}｜${asset}｜已等待 ${event.elapsed_seconds} 秒，连接仍在处理`; break;
    case "image_received": status = `生图 ${index}/${total}｜${asset}｜已返回，正在后处理`; break;
    case "image_complete": status = `生图 ${index}/${total}｜${asset}｜已完成`; break;
    case "asset_resumed": status = `生图 ${index}/${total}｜${asset}｜复用检查点`; break;
    case "asset_fixed_original": status = `${asset}｜固定使用原版，不参与生图`; break;
    case "images_complete": status = "5 张素材已完成，准备拼接预览"; break;
    case "preview": status = `正在拼接预览｜视觉轮次 ${Number(event.repair_round ?? 0) + 1}`; break;
    case "visual_qa": status = `豆包 Pro 视觉质检中｜轮次 ${Number(event.repair_round ?? 0) + 1}`; break;
    case "visual_result": status = event.status === "passed" ? "豆包 Pro 视觉质检通过" : `视觉质检待修复｜${String(event.summary ?? "").slice(0, 120)}`; break;
    case "visual_repair": status = `自动定向修复第 ${event.repair_round} 轮｜${(event.repair_keys ?? []).map((key) => ASSET_LABELS[key] ?? key).join("、")}`; break;
    case "candidate_validation": status = "素材与内容结构硬校验中"; break;
    case "smoke": status = "Godot 机器试玩中"; break;
    case "smoke_complete": status = event.smoke_ok ? "Godot 机器试玩通过" : "Godot 机器试玩已跳过"; break;
    case "complete": status = "候选已完成，等待教研审核"; break;
    default: status = String(event.phase ?? "生成处理中");
  }
  progress = Math.max(0, Math.min(100, Math.round(progress)));
  return { "图片生成状态": status, "图片生成进度": progress, "图片生成心跳": heartbeatText() };
}

export async function processWorldWorkshop(config, engineRoot) {
  const tableId = config.tables.content_units;
  const rows = listRecords(config, tableId, engineRoot);
  const requests = rows.filter((row) => row.fields["生成请求"] === true || row.fields["恢复原版"] === true);
  const results = [];
  for (const row of requests) {
    const restoreOriginal = row.fields["恢复原版"] === true;
    const theme = restoreOriginal ? "原版花园" : String(row.fields["主题"] ?? "").trim();
    let lastImageProgress = 0;
    try {
      if (!theme) throw new Error("请先选择主题再勾选生成请求");
      const currentVersion = String(row.fields["版本"] ?? "0.0.0");
      const version = nextMinorVersion(currentVersion);
      updateRecord(config, tableId, row.record_id, { "生成请求": false, "恢复原版": false, "候选结果": `生成中：${theme}｜${version}`, "候选审核通过": false, ...workshopProgressFields({ phase: restoreOriginal ? "original_restore" : "text_start", progress: 0 }) }, {
        cwd: engineRoot,
        statePath: join(engineRoot, ".state", "workshop-start-update.json"),
      });
      const candidate = await generateSkinCandidate({
        theme,
        version,
        restoreOriginal,
        onProgress: (event) => {
          const fields = workshopProgressFields(event);
          lastImageProgress = Number(fields["图片生成进度"] ?? lastImageProgress);
          updateRecord(config, tableId, row.record_id, fields, {
            cwd: engineRoot,
            statePath: join(engineRoot, ".state", "workshop-progress-update.json"),
          });
        },
      });
      const visualLabel = candidate.visualQuality.status === "passed"
        ? "豆包视觉质检通过"
        : "豆包视觉质检暂不可用（已保留硬校验与 Godot 冒烟）";
      updateRecord(config, tableId, row.record_id, {
        "候选路径": candidate.candidatePath,
        "候选版本": candidate.unit.version,
        "候选哈希": candidate.smoke.contentHash,
        "候选结果": `候选通过硬校验与 Godot 冒烟：${theme}｜${candidate.unit.version}｜${candidate.smoke.contentHash.slice(0, 12)}｜${visualLabel}${candidate.qualityWarnings.length > 0 ? `｜文案提示 ${candidate.qualityWarnings.length} 条` : ""}`,
        "自动测试通过": true,
        "发布状态": "教研审核",
        ...workshopProgressFields({ phase: "complete", progress: 100 }),
      }, { cwd: engineRoot, statePath: join(engineRoot, ".state", "workshop-success-update.json") });
      uploadAttachment(config, tableId, row.record_id, "候选预览", candidate.previewPath, engineRoot);
      results.push({ status: "generated", recordId: row.record_id, ...candidate });
    } catch (error) {
      const message = safeMessage(error);
      updateRecord(config, tableId, row.record_id, {
        "生成请求": false,
        "恢复原版": false,
        "候选结果": `生成失败：${message}`,
        "自动测试通过": false,
        "发布状态": "草稿",
        "图片生成状态": `失败｜${message}`,
        "图片生成进度": lastImageProgress,
        "图片生成心跳": heartbeatText(),
      }, { cwd: engineRoot, statePath: join(engineRoot, ".state", "workshop-failed-update.json") });
      results.push({ status: "failed", recordId: row.record_id, error: message });
    }
  }
  return results;
}

export function candidatePathFromFields(fields, engineRoot) {
  const value = String(fields["候选路径"] ?? "").trim();
  if (!value) return "";
  const path = resolve(value);
  const candidateRoot = resolve(engineRoot, "candidates");
  const relative = path.slice(candidateRoot.length);
  if (!path.startsWith(`${candidateRoot}\\`) && !path.startsWith(`${candidateRoot}/`)) throw new Error("候选路径不在 content-engine/candidates 内");
  if (!relative || !existsSync(path)) throw new Error("候选文件不存在");
  JSON.parse(readFileSync(path, "utf8"));
  return path;
}
