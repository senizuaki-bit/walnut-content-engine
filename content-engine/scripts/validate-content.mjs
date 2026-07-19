import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { collectContentAssets } from "./content-assets.mjs";
import { validateTransferVariants } from "./variant-structure.mjs";

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

export function validateContentUnit(unit) {
  invariant(unit && typeof unit === "object" && !Array.isArray(unit), "内容单元必须是 JSON 对象");
  invariant(/^UNIT-[A-Z0-9-]+$/.test(unit.unit_id ?? ""), "unit_id 必须是稳定的 UNIT-* 机器ID");
  invariant(/^\d+\.\d+\.\d+$/.test(unit.version ?? ""), "version 必须使用 semver");
  invariant(Number.isInteger(unit.audience?.lesson_minutes) && unit.audience.lesson_minutes <= 45, "课堂时长必须是 45 分钟以内的整数");
  invariant(/^CONCEPT-[A-Z0-9-]+$/.test(unit.knowledge?.concept_id ?? ""), "缺少稳定 concept_id");
  invariant(Array.isArray(unit.knowledge?.mastery) && unit.knowledge.mastery.length >= 3, "掌握标准至少覆盖预测、迁移和解释");

  const world = unit.world ?? {};
  invariant(Number.isInteger(world.main_target) && world.main_target >= 2 && world.main_target <= 8, "main_target 必须是 2—8 的整数");
  invariant(Number.isInteger(world.transfer_target) && world.transfer_target >= 2 && world.transfer_target <= 8, "transfer_target 必须是 2—8 的整数");
  const targetChanged = world.main_target !== world.transfer_target;
  const contextChanged = Boolean(world.main_context) && Boolean(world.transfer_context) && world.main_context !== world.transfer_context;
  invariant(targetChanged || contextChanged, "迁移任务必须改变目标数量或表面情境，不能原样复刻主任务");

  const semantics = unit.program_semantics ?? {};
  invariant(Array.isArray(semantics.allowed_nodes), "缺少统一程序语义 allowed_nodes");
  for (const required of ["Sequence", "Repeat", "Action"]) {
    invariant(semantics.allowed_nodes.includes(required), `程序语义缺少节点：${required}`);
  }
  invariant(Number.isInteger(semantics.max_execution_steps) && semantics.max_execution_steps > 0, "必须设置安全执行步数上限");

  const templates = unit.templates ?? [];
  invariant(templates.some((template) => template.template_id === "TEMPLATE-REPEAT-TARGETS"), "缺少固定次数循环模板");
  const skins = unit.world_skins ?? [];
  invariant(skins.length >= 2, "同一模板至少需要两个世界皮肤才能证明复用");
  invariant(new Set(skins.map((skin) => skin.template_id)).size === 1, "MVP 的两个世界皮肤必须共享同一模板");
  invariant(new Set(skins.map((skin) => skin.action_id)).size >= 2, "迁移皮肤必须改变世界动作语义");
  invariant(new Set(skins.map((skin) => skin.entity_type)).size >= 2, "迁移皮肤必须改变目标对象类型");
  const mainSkinId = world.main_skin_id ?? skins[0]?.skin_id;
  const transferSkinId = world.transfer_skin_id ?? skins[1]?.skin_id;
  invariant(skins.some((skin) => skin.skin_id === mainSkinId), "world.main_skin_id 必须引用现有世界皮肤");
  invariant(skins.some((skin) => skin.skin_id === transferSkinId), "world.transfer_skin_id 必须引用现有世界皮肤");
  invariant(mainSkinId !== transferSkinId, "主任务与迁移任务不能使用同一皮肤");
  const mainSkin = skins.find((skin) => skin.skin_id === mainSkinId);
  for (const key of ["world_name", "entity_name", "action_name", "console_name", "objective"]) {
    invariant(typeof mainSkin?.display?.[key] === "string" && mainSkin.display[key].trim(), `主世界皮肤缺少 display.${key}`);
  }
  invariant(Array.isArray(unit.world_actions) && unit.world_actions.length >= 2, "缺少世界动作绑定");
  invariant(Array.isArray(unit.diagnostic_rules) && unit.diagnostic_rules.some((rule) => rule.diagnosis_id === "COUNT_TOO_SMALL"), "缺少确定性次数不足诊断");
  invariant(unit.diagnostic_rules.some((rule) => rule.diagnosis_id === "COUNT_TOO_LARGE"), "缺少确定性次数过多诊断");

  const stageIds = new Set((unit.stages ?? []).map((stage) => stage.id));
  for (const required of ["observe", "predict", "single_action", "program", "trace", "counterfactual", "transfer", "concept_name", "debug_boss", "explain"]) {
    invariant(stageIds.has(required), `缺少必要阶段：${required}`);
  }

  invariant(Array.isArray(unit.misconceptions) && unit.misconceptions.length > 0, "至少需要一个可观察误区");
  for (const misconception of unit.misconceptions) {
    invariant(misconception.id && misconception.signal && misconception.intervention, `误区 ${misconception.id ?? "<unknown>"} 缺少 signal/intervention`);
  }

  const hints = [...(unit.hint_policy ?? [])].sort((a, b) => a.level - b.level);
  invariant(hints.length === 5, "提示策略必须恰好包含 5 级");
  invariant(hints.map((hint) => hint.level).join(",") === "1,2,3,4,5", "提示等级必须连续为 1–5");
  const chineseTarget = { 1: "一", 2: "二", 3: "三", 4: "四", 5: "五", 6: "六", 7: "七", 8: "八" }[world.main_target];
  const answerPattern = new RegExp(`重复\\s*${world.main_target}|${world.main_target}\\s*[次遍]${chineseTarget ? `|${chineseTarget}\\s*[次遍]` : ""}`, "u");
  for (const hint of hints.slice(0, 4)) {
    invariant(hint.reveal_answer === false, `第 ${hint.level} 级不得显式答案`);
    invariant(!answerPattern.test(hint.template), `第 ${hint.level} 级提示疑似泄露答案`);
  }
  invariant(hints[4].reveal_answer === true, "第 5 级必须明确声明可兜底答案");
  invariant(unit.surprise?.must_be_student_triggered === true, "惊喜必须由学生真实操作触发");
  invariant(unit.safety?.ai_can_write_core_code === false, "AI 不得替学生写核心代码");
  invariant(unit.evidence?.primary === "transfer_first_pass_without_hint", "MVP 主效果指标必须是无提示迁移首过");

  const events = unit.evidence?.events ?? [];
  invariant(/^\d+\.\d+\.\d+$/.test(unit.evidence?.event_schema_version ?? ""), "缺少事件 schema 版本");
  invariant(events.length === new Set(events).size, "事件名不能重复");
  for (const required of ["program_run", "hint_requested", "hint_delivered", "surprise_triggered", "counterfactual_run", "transfer_run", "concept_revealed", "boss_debug_run", "session_completed"]) {
    invariant(events.includes(required), `缺少必要事件：${required}`);
  }
  const effectivenessMetrics = unit.evidence?.session_metrics?.effectiveness ?? {};
  const delightMetrics = unit.evidence?.session_metrics?.delight ?? {};
  invariant(typeof effectivenessMetrics === "object" && !Array.isArray(effectivenessMetrics), "缺少效果指标权重定义");
  invariant(typeof delightMetrics === "object" && !Array.isArray(delightMetrics), "缺少趣味指标权重定义");
  invariant(Object.values(effectivenessMetrics).reduce((sum, value) => sum + value, 0) === 100, "效果指标权重之和必须为100");
  invariant(Object.values(delightMetrics).reduce((sum, value) => sum + value, 0) === 100, "趣味指标权重之和必须为100");

  const variants = unit.transfer_variants ?? [];
  invariant(Array.isArray(variants), "transfer_variants 必须是数组");
  invariant(variants.length === new Set(variants.map((variant) => variant.variant_id)).size, "variant_id 不能重复");
  validateTransferVariants(variants, unit);

  return unit;
}

export function validateContentAssets(unit, sourcePath, options = {}) {
  validateContentUnit(unit);
  return collectContentAssets(unit, {
    sourcePath: resolve(sourcePath),
    projectDir: options.projectDir,
    requireActiveSkinAssets: options.requireActiveSkinAssets ?? true,
  });
}

function runCli() {
  const sourcePath = process.argv[2];
  invariant(sourcePath, "用法：node validate-content.mjs <content.json>");
  const unit = JSON.parse(readFileSync(sourcePath, "utf8"));
  validateContentUnit(unit);
  if (process.argv.includes("--assets")) {
    const projectArg = process.argv.find((value) => value.startsWith("--project-dir="));
    validateContentAssets(unit, sourcePath, { projectDir: projectArg?.slice("--project-dir=".length) });
  }
  console.log(`CONTENT_VALIDATION_OK ${unit.unit_id}@${unit.version}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) runCli();
