import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { compileContentUnit } from "./compile-content.mjs";
import { validateContentUnit } from "./validate-content.mjs";
import { smokeTestCandidate } from "./smoke-test-candidate.mjs";
import { candidatePathFromFields } from "./world-workshop.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const engineRoot = resolve(scriptDir, "..");
const projectRoot = resolve(engineRoot, "..");
const configPath = join(engineRoot, "feishu", "publish-config.json");
const sourcePath = join(engineRoot, "source", "data-garden-loop.json");
const stateDir = join(engineRoot, ".state");

function readJson(filePath) {
  return JSON.parse(readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
}

function safeMessage(error) {
  return String(error instanceof Error ? error.message : error).replace(/\s+/g, " ").trim().slice(0, 300);
}

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

export function copyRelativeAssetsToSource(assetRecords, targetSourcePath) {
  const sourceRoot = dirname(resolve(targetSourcePath));
  for (const asset of assetRecords ?? []) {
    if (String(asset.source_ref ?? "").startsWith("project://")) continue;
    const destination = resolve(sourceRoot, String(asset.source_ref));
    const relativeDestination = relative(sourceRoot, destination);
    if (!relativeDestination || relativeDestination.startsWith("..") || relativeDestination.startsWith("/")) {
      throw new Error(`正式 source 素材路径越界：${asset.source_ref}`);
    }
    mkdirSync(dirname(destination), { recursive: true });
    if (resolve(asset.source) !== destination) copyFileSync(asset.source, destination);
  }
}

export function assertCandidateVisualAudit(candidatePath) {
  if (/\.variants\.candidate\.json$/iu.test(candidatePath)) return { status: "not_applicable" };
  const auditPath = join(dirname(candidatePath), "generation-audit.json");
  if (!existsSync(auditPath)) throw new Error("AI 世界候选缺少 generation-audit.json，禁止发布");
  const audit = readJson(auditPath);
  const visualQuality = audit.visual_quality;
  if (visualQuality?.status !== "passed" || visualQuality?.passed !== true) {
    throw new Error(`AI 世界候选未通过豆包视觉质检：${visualQuality?.summary ?? "缺少视觉质检结果"}`);
  }
  return visualQuality;
}

function runLark(args) {
  const executable = process.platform === "win32" ? (process.env.ComSpec || "cmd.exe") : "lark-cli";
  const executableArgs = process.platform === "win32" ? ["/d", "/s", "/c", ["lark-cli", ...args].join(" ")] : args;
  const result = spawnSync(executable, executableArgs, {
    cwd: engineRoot,
    encoding: "utf8",
    windowsHide: true,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr?.trim() || result.stdout?.trim() || `lark-cli 退出码 ${result.status}`);
  const parsed = JSON.parse(result.stdout);
  if (!parsed.ok) throw new Error(parsed.error?.message || "飞书命令执行失败");
  return parsed.data;
}

function tableRows(data) {
  const names = data.fields ?? [];
  return (data.data ?? []).map((values, index) => ({
    record_id: data.record_id_list[index],
    fields: Object.fromEntries(names.map((name, fieldIndex) => [name, values[fieldIndex]])),
  }));
}

function listRecords(config, tableId) {
  return tableRows(runLark([
    "base", "+record-list",
    "--base-token", config.base_token,
    "--table-id", tableId,
    "--format", "json",
    "--as", "user",
  ]));
}

function integerField(value, fallback, name) {
  const result = value === null || value === undefined || value === "" ? Number(fallback) : Number(value);
  if (!Number.isInteger(result) || result < 2 || result > 8) throw new Error(`${name}必须是 2—8 的整数`);
  return result;
}

function replaceTokens(text, mainTarget, transferTarget) {
  return String(text ?? "")
    .replaceAll("{main_target}", String(mainTarget))
    .replaceAll("{transfer_target}", String(transferTarget));
}

function linkIncludes(value, recordId) {
  return Array.isArray(value) && value.some((item) => String(item?.id ?? item) === recordId);
}

export function buildContentFromBase(template, unitRow, hintRows) {
  const unit = structuredClone(template);
  const fields = unitRow.fields;
  const mainTarget = integerField(fields["主任务目标数"], unit.world.main_target, "主任务目标数");
  const transferTarget = integerField(fields["迁移目标数"], unit.world.transfer_target, "迁移目标数");
  const version = String(fields["版本"] ?? unit.version).trim();

  unit.version = version;
  unit.status = "automatic_test";
  unit.world.main_target = mainTarget;
  unit.world.transfer_target = transferTarget;
  unit.world.main_context = `${mainTarget}_dormant_light_seeds`;
  unit.world.transfer_context = `${transferTarget}_target_patrol_device`;
  unit.world.exact_feedback = `${mainTarget}_seeds_light_in_sequence`;
  unit.release.automatic_tests = false;
  unit.release.research_review = Boolean(fields["教研审核通过"]);
  unit.release.safety_review = Boolean(fields["安全审核通过"]);

  for (const skin of unit.world_skins) {
    if (skin.skin_id === unit.world.main_skin_id) {
      skin.target_count = mainTarget;
      const entityName = skin.display?.entity_name ?? "目标";
      skin.objective = `让 ${mainTarget} 个${entityName}依次完成变化`;
      if (skin.display) skin.display.objective = skin.objective;
    } else if (skin.skin_id === unit.world.transfer_skin_id) {
      skin.target_count = transferTarget;
      const actionName = skin.display?.action_name ?? "处理";
      skin.objective = `依次${actionName} ${transferTarget} 个目标`;
      if (skin.display) skin.display.objective = skin.objective;
    }
  }

  const masteryIndex = unit.knowledge.mastery.findIndex((item) => String(item).includes("验证次数"));
  if (masteryIndex >= 0) unit.knowledge.mastery[masteryIndex] = `能通过把 ${mainTarget} 改成 ${mainTarget - 1} 验证次数对世界结果的影响`;
  const mainDisplay = unit.world_skins.find((skin) => skin.skin_id === unit.world.main_skin_id)?.display ?? {};
  const transferDisplay = unit.world_skins.find((skin) => skin.skin_id === unit.world.transfer_skin_id)?.display ?? {};
  const stageCopy = {
    observe: `只展示 ${mainTarget} 个${mainDisplay.entity_name ?? "目标"}，不提前命名概念`,
    counterfactual: `把 ${mainTarget} 改成 ${mainTarget - 1}，明确保留最后一个未完成目标`,
    transfer: `在 ${transferTarget} 目标的${transferDisplay.world_name ?? "陌生情境"}中无术语提示迁移`,
  };
  for (const stage of unit.stages) {
    if (stageCopy[stage.id]) stage.purpose = stageCopy[stage.id];
  }
  unit.surprise.causal_copy = `${mainTarget} 个${mainDisplay.entity_name ?? "目标"}按你的执行轨迹依次完成变化。`;

  const linkedHints = hintRows
    .filter((row) => linkIncludes(row.fields["关联单元"], unitRow.record_id))
    .sort((left, right) => Number(left.fields["提示等级"]) - Number(right.fields["提示等级"]));
  if (linkedHints.length !== 5) throw new Error(`关联提示策略应为 5 条，当前为 ${linkedHints.length} 条`);
  unit.hint_policy = linkedHints.map((row) => {
    const level = Number(row.fields["提示等级"]);
    return {
      level,
      intent: replaceTokens(row.fields["教学意图"], mainTarget, transferTarget),
      template: replaceTokens(row.fields["提示模板"], mainTarget, transferTarget),
      reveal_answer: Boolean(row.fields["允许显式答案"]),
      ...(level === 5 ? { needs_review: true } : {}),
      next_action: replaceTokens(row.fields["下一步动作"], mainTarget, transferTarget),
    };
  });

  return validateContentUnit(unit);
}

function contentSummary(unit, contentHash) {
  return JSON.stringify({
    unit_id: unit.unit_id,
    version: unit.version,
    content_hash: contentHash,
    main_target: unit.world.main_target,
    transfer_target: unit.world.transfer_target,
    template_id: unit.templates[0]?.template_id,
    event_schema_version: unit.evidence.event_schema_version,
    allowed_nodes: unit.program_semantics.allowed_nodes,
    skins: unit.world_skins.map((skin) => skin.skin_id),
    active_skin: unit.world.main_skin_id,
    theme: unit.world.theme,
    asset_keys: Object.keys(unit.world_skins.find((skin) => skin.skin_id === unit.world.main_skin_id)?.assets ?? {}),
    transfer_variants: (unit.transfer_variants ?? []).map((variant) => variant.variant_id),
    diagnoses: unit.diagnostic_rules.map((rule) => rule.diagnosis_id),
    session_metrics: unit.evidence.session_metrics,
    max_execution_steps: unit.program_semantics.max_execution_steps,
  });
}

function updateUnitRecord(config, recordId, fields) {
  mkdirSync(stateDir, { recursive: true });
  const updatePath = join(stateDir, "unit-record-update.json");
  writeFileSync(updatePath, `${JSON.stringify(fields, null, 2)}\n`, "utf8");
  const cliPath = `@./${relative(engineRoot, updatePath).replaceAll("\\", "/")}`;
  return runLark([
    "base", "+record-upsert",
    "--base-token", config.base_token,
    "--table-id", config.tables.content_units,
    "--record-id", recordId,
    "--json", cliPath,
    "--format", "json",
    "--as", "user",
  ]);
}

export function publishFromFeishu({ force = false } = {}) {
  const config = readJson(configPath);
  const units = listRecords(config, config.tables.content_units);
  const unitRow = units.find((row) => row.record_id === config.unit_record_id || row.fields["单元ID"] === config.unit_id);
  if (!unitRow) throw new Error(`飞书中找不到内容单元 ${config.unit_id}`);
  if (!force && unitRow.fields["发布请求"] !== true) return { status: "no_request", unitId: config.unit_id };

  try {
    const template = readJson(sourcePath);
    const requestedVersion = String(unitRow.fields["版本"] ?? "").trim();
    const approvedCandidatePath = candidatePathFromFields(unitRow.fields, engineRoot);
    let unit;
    if (approvedCandidatePath) {
      if (unitRow.fields["候选审核通过"] !== true) throw new Error("候选包尚未勾选“候选审核通过”");
      if (!force && unitRow.fields["安全审核通过"] !== true) throw new Error("候选包尚未通过安全审核");
      assertCandidateVisualAudit(approvedCandidatePath);
      unit = validateContentUnit(readJson(approvedCandidatePath));
      const publishedVersion = String(unitRow.fields["版本"] ?? "").trim();
      if (unit.version === publishedVersion) throw new Error(`候选版本仍是已发布版本 ${publishedVersion}，不能覆盖同一不可变版本`);
      unit.release.automatic_tests = true;
      unit.release.research_review = true;
      unit.release.safety_review = Boolean(unitRow.fields["安全审核通过"]);
    } else {
      if (!force && requestedVersion === template.version) {
        throw new Error(`版本号仍是 ${template.version}；请先升级版本号再发布，避免覆盖同一不可变内容版本`);
      }
      const hintRows = listRecords(config, config.tables.hints);
      unit = buildContentFromBase(template, unitRow, hintRows);
      if (!force && (!unit.release.research_review || !unit.release.safety_review)) throw new Error("正式发布前必须同时通过教研审核与安全审核");
      unit.release.automatic_tests = true;
    }
    const candidatePath = join(stateDir, `${unit.unit_id}.${unit.version}.candidate.json`);
    mkdirSync(stateDir, { recursive: true });
    const sourceText = `${JSON.stringify(unit, null, 2)}\n`;
    writeFileSync(candidatePath, sourceText, "utf8");
    const assetSourcePath = approvedCandidatePath || candidatePath;
    const smoke = smokeTestCandidate(candidatePath, {
      projectDir: join(projectRoot, "my_topdown_game-main"),
      godotExe: join(projectRoot, "tools", "godot-4.5.2", "Godot_v4.5.2-stable_win64_console.exe"),
      assetSourcePath,
    });
    const compiled = compileContentUnit(candidatePath, { assetSourcePath });
    copyRelativeAssetsToSource(compiled.sourceAssets, sourcePath);
    writeFileSync(sourcePath, sourceText, "utf8");

    updateUnitRecord(config, unitRow.record_id, {
      "版本": unit.version,
      "主任务目标数": unit.world.main_target,
      "迁移目标数": unit.world.transfer_target,
      "发布请求": false,
      "候选审核通过": false,
      "候选路径": "",
      "候选版本": "",
      "候选哈希": "",
      "候选结果": `已发布：${unit.world.theme}｜${unit.version}｜${compiled.contentHash.slice(0, 12)}`,
      "图片生成状态": `已发布｜${unit.world.theme}｜${unit.version}`,
      "图片生成进度": 100,
      "图片生成心跳": heartbeatText(),
      "发布结果": `发布成功：${unit.version}｜${unit.world.theme}｜主任务 ${unit.world.main_target}｜迁移 ${unit.world.transfer_target}｜${compiled.contentHash.slice(0, 12)}｜${smoke.output}`,
      "已发布哈希": compiled.contentHash,
      "发布时间": Date.now(),
      "配置JSON": contentSummary(unit, compiled.contentHash),
      "世界机制": `${unit.templates[0].template_id} 统一驱动 ${unit.world_skins.length} 套世界皮肤；当前为 ${unit.world.theme}/${unit.world.main_skin_id}。Sequence/Repeat/Action 安全 IR 经同一解释器执行。`,
      "惊喜因果": `${unit.surprise.causal_copy} 演出只放大程序因果，不替代程序逻辑。`,
      "任务链": `感知世界→预测一次动作→单次验证→积木编排→逐步轨迹→${unit.world.main_target}→${unit.world.main_target - 1} 反事实→${unit.world.transfer_target} 目标陌生迁移→概念命名与 C 代码映射→确定性 Debug Boss`,
      "迁移任务": `在 ${unit.world.transfer_target} 目标巡检器中，不给循环术语提示，复用同一 Repeat 模板和解释器完成 inspect_next_target；以首次无提示成功为主证据。`,
      "学习证据": `原始事件经版本与哈希校验后聚合；记录无提示迁移首过、${unit.world.main_target}→${unit.world.main_target - 1} 反事实、概念显形、Boss 调试、复练及惊喜后探索，再自动回写飞书课堂证据。`,
      "自动测试通过": true,
      "发布状态": "自动测试"
    });
    return { status: "published", unit, contentHash: compiled.contentHash, paths: compiled.paths };
  } catch (error) {
    const message = safeMessage(error);
    try {
      updateUnitRecord(config, unitRow.record_id, {
        "发布请求": false,
        "发布结果": `发布失败：${message}`,
        "自动测试通过": false,
        "发布状态": "草稿"
      });
    } catch (writeError) {
      throw new Error(`${message}；且失败状态未能回写飞书：${safeMessage(writeError)}`);
    }
    throw error;
  }
}

function runCli() {
  const force = process.argv.includes("--force");
  const result = publishFromFeishu({ force });
  if (result.status === "no_request") {
    console.log(`CONTENT_PUBLISH_IDLE ${result.unitId}`);
  } else {
    console.log(`CONTENT_PUBLISH_OK ${result.unit.unit_id}@${result.unit.version} ${result.contentHash.slice(0, 12)}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    runCli();
  } catch (error) {
    console.error(`CONTENT_PUBLISH_FAILED ${safeMessage(error)}`);
    process.exitCode = 1;
  }
}
