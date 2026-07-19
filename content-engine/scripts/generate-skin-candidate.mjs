import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { validateContentAssets, validateContentUnit } from "./validate-content.mjs";
import { buildSkinGenerationMessages, callJsonModel, mockSkinPayload, nextMinorVersion, skinQualityWarnings, themeSlug, validateGeneratedSkinPayload } from "./generation-common.mjs";
import { createPreview, generateSkinImages } from "./image-generation.mjs";
import { smokeTestCandidate } from "./smoke-test-candidate.mjs";
import { inspectCandidatePreview } from "./visual-quality.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const engineRoot = resolve(scriptDir, "..");
const projectRoot = resolve(engineRoot, "..");
const defaultTemplatePath = join(engineRoot, "source", "data-garden-loop.json");
const defaultOriginalTemplatePath = join(engineRoot, "source", "data-garden-loop.original.json");
const projectDir = join(projectRoot, "my_topdown_game-main");
const godotExe = join(projectRoot, "tools", "godot-4.5.2", "Godot_v4.5.2-stable_win64_console.exe");
const QUALITY_CONTRACT_VERSION = 4;
export const FIXED_ORIGINAL_SKIN_ASSET_KEYS = Object.freeze(["npc"]);

function reportCandidateProgress(onProgress, event) {
  if (typeof onProgress !== "function") return;
  try {
    onProgress({ ...event, reported_at: event.reported_at ?? new Date().toISOString() });
  } catch (error) {
    console.warn(`[content-engine] 工坊进度回写失败：${error instanceof Error ? error.message : String(error)}`);
  }
}

function render(value, target, display) {
  return String(value ?? "")
    .replaceAll("{main_target}", String(target))
    .replaceAll("{main_entity}", display.entity_name)
    .replaceAll("{main_action}", display.action_name);
}

function normalizedEntityType(value, theme) {
  const candidate = String(value ?? "").trim().toLowerCase();
  const generic = /^(group|target|entity|object|item|animal|creature|sea_animal)$/u.test(candidate);
  return /^[a-z][a-z0-9_]{2,48}$/u.test(candidate) && !generic ? candidate : `${themeSlug(theme)}_target`;
}

function normalizeGeneratedSkinPayload(raw) {
  const normalized = structuredClone(raw);
  const repairs = [];
  if (Array.isArray(normalized.hint_policy) && normalized.hint_policy.length === 5) {
    const templates = normalized.hint_policy.map((hint) => String(hint?.template ?? ""));
    if (!templates.some((template) => template.includes("{main_entity}"))) {
      normalized.hint_policy[0].template = "先确认目标：你希望所有{main_entity}最后都完成变化，对吗？";
      repairs.push("hint_level_1_main_entity_placeholder");
    }
    if (!templates.some((template) => template.includes("{main_action}"))) {
      normalized.hint_policy[2].template = "“{main_action}”已经有效，检查重复结构里的执行次数。";
      repairs.push("hint_level_3_main_action_placeholder");
    }
    if (!String(normalized.hint_policy[4]?.template ?? "").includes("{main_target}")) {
      normalized.hint_policy[4].template = "完整结构是“重复{main_target}次：{main_action}”。仍由你亲手修改并运行。";
      repairs.push("hint_level_5_main_target_placeholder");
    }
  }
  return { payload: normalized, repairs };
}

function repairSurfaceCopy(payload, theme) {
  const repaired = structuredClone(payload);
  const entityName = repaired.display.entity_name;
  const actionName = repaired.display.action_name;
  const copyContainsEntity = repaired.display.objective.includes(entityName);
  const copyContainsAction = repaired.display.objective.includes(actionName) || repaired.display.scenario_frame.includes(actionName);
  if (!copyContainsEntity || !copyContainsAction) {
    repaired.display.objective = `使用“${actionName}”，让每个${entityName}依次完成变化`;
    return { payload: validateGeneratedSkinPayload(repaired, { theme }), repaired: true };
  }
  return { payload: repaired, repaired: false };
}

export function applyGeneratedSkin(template, payload, { version, assets } = {}) {
  const unit = structuredClone(template);
  const oldMainSkinId = unit.world.main_skin_id ?? unit.world_skins[0].skin_id;
  const oldMainSkin = unit.world_skins.find((skin) => skin.skin_id === oldMainSkinId) ?? unit.world_skins[0];
  const target = Number(oldMainSkin.target_count ?? unit.world.main_target);
  const display = { ...payload.display, objective: render(payload.display.objective, target, payload.display) };
  const skin = {
    skin_id: payload.skin_id,
    template_id: oldMainSkin.template_id,
    entity_type: payload.entity_type,
    target_count: target,
    initial_state: oldMainSkin.initial_state,
    completed_state: oldMainSkin.completed_state,
    action_id: oldMainSkin.action_id,
    objective: display.objective,
    display,
    assets,
  };
  unit.version = version ?? nextMinorVersion(template.version);
  unit.status = "candidate";
  unit.world.theme = payload.theme;
  unit.world.main_skin_id = payload.skin_id;
  unit.world.main_context = `${target}_${payload.entity_type}`;
  unit.world.exact_feedback = `${target}_${payload.entity_type}_completed_in_sequence`;
  unit.world_skins = unit.world_skins.map((candidate) => candidate.skin_id === oldMainSkinId ? skin : candidate);
  unit.stages = unit.stages.map((stage) => ({ ...stage, purpose: payload.stage_purposes[stage.id] }));
  unit.hint_policy = payload.hint_policy;
  unit.surprise = { ...unit.surprise, causal_copy: render(payload.causal_copy, target, payload.display) };
  unit.release = { ...unit.release, automatic_tests: false, research_review: false, safety_review: false };
  return validateContentUnit(unit);
}

export function applyOriginalGarden(template, originalTemplate, { version } = {}) {
  const unit = structuredClone(template);
  const currentMainSkinId = unit.world.main_skin_id ?? unit.world_skins[0].skin_id;
  const originalMainSkinId = originalTemplate.world.main_skin_id ?? originalTemplate.world_skins[0].skin_id;
  const originalMainSkin = originalTemplate.world_skins.find((skin) => skin.skin_id === originalMainSkinId);
  if (!originalMainSkin) throw new Error("原版花园模板缺少主皮肤");

  unit.version = version ?? nextMinorVersion(template.version);
  unit.status = "candidate";
  unit.world = {
    ...unit.world,
    theme: originalTemplate.world.theme,
    main_skin_id: originalMainSkinId,
    main_context: originalTemplate.world.main_context,
    exact_feedback: originalTemplate.world.exact_feedback,
  };
  unit.world_skins = [
    structuredClone(originalMainSkin),
    ...unit.world_skins.filter((skin) => skin.skin_id !== currentMainSkinId && skin.skin_id !== originalMainSkinId),
  ];
  unit.stages = structuredClone(originalTemplate.stages);
  unit.hint_policy = structuredClone(originalTemplate.hint_policy);
  unit.surprise = { ...unit.surprise, causal_copy: originalTemplate.surprise.causal_copy };
  unit.release = { ...unit.release, automatic_tests: false, research_review: false, safety_review: false };
  return validateContentUnit(unit);
}

function payloadFromCandidate(unit) {
  const skin = unit.world_skins.find((item) => item.skin_id === unit.world.main_skin_id);
  if (!skin) throw new Error("已有候选缺少主皮肤");
  return {
    skin_id: skin.skin_id,
    theme: unit.world.theme,
    entity_type: skin.entity_type,
    display: skin.display,
    stage_purposes: Object.fromEntries(unit.stages.map((stage) => [stage.id, stage.purpose])),
    hint_policy: unit.hint_policy,
    causal_copy: unit.surprise.causal_copy,
  };
}

export async function generateSkinCandidate({ theme, version, templatePath = defaultTemplatePath, originalTemplatePath = defaultOriginalTemplatePath, outputRoot = join(engineRoot, "candidates"), mock = false, runSmoke = true, resume = true, textOnly = false, restoreOriginal = false, onProgress } = {}) {
  if (!theme || !String(theme).trim()) throw new Error("缺少主题；使用 --theme=海底");
  const normalizedTheme = String(theme).trim();
  const resolvedTemplate = resolve(templatePath);
  const template = JSON.parse(readFileSync(resolvedTemplate, "utf8"));
  const requestedVersion = version ?? nextMinorVersion(template.version);
  const candidateDir = join(resolve(outputRoot), themeSlug(normalizedTheme), requestedVersion);
  mkdirSync(candidateDir, { recursive: true });
  reportCandidateProgress(onProgress, { phase: "text_start", progress: 3, theme: normalizedTheme, version: requestedVersion });

  const candidatePath = join(candidateDir, `${template.unit_id}.${requestedVersion}.candidate.json`);
  const textCheckpointPath = join(candidateDir, "text-candidate.checkpoint.json");

  if (restoreOriginal) {
    reportCandidateProgress(onProgress, { phase: "original_restore", progress: 65, theme: normalizedTheme, version: requestedVersion });
    const originalTemplate = JSON.parse(readFileSync(resolve(originalTemplatePath), "utf8"));
    const unit = applyOriginalGarden(template, originalTemplate, { version: requestedVersion });
    const mainSkin = unit.world_skins.find((skin) => skin.skin_id === unit.world.main_skin_id);
    const previewPath = join(candidateDir, "candidate-preview.png");
    const assetOrder = ["background_before", "background_after", "target_entity", "console", "npc"];
    const imagePaths = assetOrder.map((key) => {
      const assetRef = String(mainSkin.assets[key] ?? "");
      if (!assetRef.startsWith("project://")) throw new Error(`原版花园素材必须使用 project://：${key}`);
      return join(projectDir, assetRef.slice("project://".length));
    });
    reportCandidateProgress(onProgress, { phase: "preview", progress: 75, repair_round: 0 });
    createPreview({ imagePaths, outputPath: previewPath, projectDir, godotExe });
    writeFileSync(candidatePath, `${JSON.stringify(unit, null, 2)}\n`, "utf8");
    validateContentAssets(unit, candidatePath, { projectDir });
    reportCandidateProgress(onProgress, { phase: "smoke", progress: 95 });
    const smoke = runSmoke ? smokeTestCandidate(candidatePath, { projectDir, godotExe }) : { ok: false, skipped: true };
    reportCandidateProgress(onProgress, { phase: "smoke_complete", progress: 99, smoke_ok: smoke.ok === true });
    const visualQuality = {
      status: "passed",
      passed: true,
      theme_match: true,
      before_after_consistent: true,
      target_matches_copy: true,
      sprites_clean: true,
      style_consistent: true,
      child_safe: true,
      summary: "官方原版数据花园素材，未调用生图模型。",
      issues: [],
      provider_audit: { mode: "trusted-original" },
    };
    const auditPath = join(candidateDir, "generation-audit.json");
    writeFileSync(auditPath, `${JSON.stringify({
      generated_at: new Date().toISOString(),
      theme: normalizedTheme,
      candidate_path: candidatePath,
      preview_path: previewPath,
      text_generation: { mode: "trusted-original" },
      quality_warnings: [],
      image_generation: { mode: "fixed-original", model: null, cost_summary: { known_generated_images: 0, estimated_cny_at_0_22_per_image: 0 }, reports: {} },
      visual_quality: visualQuality,
      visual_repair_attempts: [],
      smoke,
    }, null, 2)}\n`, "utf8");
    reportCandidateProgress(onProgress, { phase: "complete", progress: 100, content_hash: smoke.contentHash });
    return { unit, candidatePath, previewPath, auditPath, smoke, qualityWarnings: [], visualQuality };
  }

  let modelAudit = { mode: "mock", model: "deterministic-fixture" };
  let rawPayload;
  let payload;
  let qualityWarnings = [];
  let copyRepaired = false;
  if (resume && !mock) {
    try {
      const checkpoint = JSON.parse(readFileSync(textCheckpointPath, "utf8"));
      if (checkpoint.quality_contract_version !== QUALITY_CONTRACT_VERSION || checkpoint.theme !== normalizedTheme || checkpoint.version !== requestedVersion) {
        throw new Error("文本检查点版本或主题不匹配");
      }
      rawPayload = checkpoint.payload;
      payload = validateGeneratedSkinPayload(rawPayload, { theme: normalizedTheme });
      qualityWarnings = skinQualityWarnings(payload);
      modelAudit = { ...checkpoint.model_audit, mode: "resume-text-checkpoint", source: textCheckpointPath, quality_warnings: qualityWarnings };
    } catch {
      try {
        const existing = JSON.parse(readFileSync(candidatePath, "utf8"));
        rawPayload = payloadFromCandidate(existing);
        const validated = validateGeneratedSkinPayload(rawPayload, { theme: normalizedTheme });
        const repair = repairSurfaceCopy(validated, normalizedTheme);
        payload = repair.payload;
        copyRepaired = copyRepaired || repair.repaired;
        qualityWarnings = skinQualityWarnings(payload);
        modelAudit = { mode: "resume-candidate", source: candidatePath, quality_warnings: qualityWarnings };
      } catch {
        payload = undefined;
      }
    }
  }
  if (!payload && mock) {
    rawPayload = mockSkinPayload(normalizedTheme);
    payload = validateGeneratedSkinPayload(rawPayload, { theme: normalizedTheme });
    qualityWarnings = skinQualityWarnings(payload);
  } else if (!payload) {
    let lastValidationError;
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      const messages = buildSkinGenerationMessages(normalizedTheme, template.world.main_target);
      if (lastValidationError) messages.push({ role: "user", content: `上一份 JSON 未通过白名单校验：${lastValidationError.message}。请仅修正格式与文案字段后重新输出完整 JSON。` });
      const response = await callJsonModel(messages);
      const normalizedModelPayload = normalizeGeneratedSkinPayload({
        ...response.value,
        // Technical identity is deterministic and never delegated to the model.
        skin_id: `skin_${themeSlug(normalizedTheme)}`,
        theme: normalizedTheme,
        entity_type: normalizedEntityType(response.value?.entity_type, normalizedTheme),
      });
      rawPayload = normalizedModelPayload.payload;
      copyRepaired = normalizedModelPayload.repairs.length > 0;
      try {
        const validated = validateGeneratedSkinPayload(rawPayload, { theme: normalizedTheme });
        const repair = repairSurfaceCopy(validated, normalizedTheme);
        payload = repair.payload;
        copyRepaired = copyRepaired || repair.repaired;
        qualityWarnings = skinQualityWarnings(payload);
        if (qualityWarnings.length > 0) {
          lastValidationError = new Error(qualityWarnings.map((warning) => warning.message).join("；"));
          payload = undefined;
          if (attempt < 3) continue;
          break;
        }
        modelAudit = {
          mode: "api",
          provider: response.provider,
          model: response.model,
          usage: response.usage,
          request_id: response.request_id,
          provider_attempts: response.provider_attempts,
          fallback_used: response.fallback_used,
          failures: response.failures,
          validation_attempts: attempt,
          copy_repaired: copyRepaired,
          deterministic_repairs: normalizedModelPayload.repairs,
          quality_warnings: qualityWarnings,
        };
        break;
      } catch (error) {
        lastValidationError = error instanceof Error ? error : new Error(String(error));
      }
    }
    if (!payload) throw lastValidationError ?? new Error("文案候选未通过白名单校验");
  }
  writeFileSync(textCheckpointPath, `${JSON.stringify({
    quality_contract_version: QUALITY_CONTRACT_VERSION,
    theme: normalizedTheme,
    version: requestedVersion,
    payload,
    quality_warnings: qualityWarnings,
    model_audit: modelAudit,
    checked_at: new Date().toISOString(),
  }, null, 2)}\n`, "utf8");
  reportCandidateProgress(onProgress, { phase: "text_complete", progress: 10, theme: normalizedTheme, version: requestedVersion, resumed: modelAudit.mode?.startsWith("resume") === true });
  if (textOnly) return { textOnly: true, payload, textCheckpointPath, qualityWarnings, modelAudit };
  const mockSources = {
    background_before: join(projectDir, "assets", "backgrounds", "data_garden_world.png"),
    background_after: join(projectDir, "assets", "backgrounds", "data_garden_world_restored.png"),
    target_entity: join(projectDir, "assets", "sprites", "items", "data_garden_light_seed.png"),
    console: join(projectDir, "assets", "sprites", "items", "data_garden_console.png"),
    npc: join(projectDir, "assets", "sprites", "companion", "xiao_hetao.png"),
  };
  const fixedSources = Object.fromEntries(FIXED_ORIGINAL_SKIN_ASSET_KEYS.map((key) => [key, mockSources[key]]));
  reportCandidateProgress(onProgress, { phase: "images_start", progress: 10, theme: normalizedTheme, version: requestedVersion });
  let images = await generateSkinImages({
    theme: normalizedTheme,
    display: payload.display,
    outputDir: candidateDir,
    referencePath: mockSources.background_before,
    projectDir,
    godotExe,
    mock,
    mockSources,
    fixedSources,
    resume,
    onProgress: (event) => reportCandidateProgress(onProgress, { ...event, repair_round: 0 }),
  });
  reportCandidateProgress(onProgress, { phase: "images_complete", progress: 68, theme: normalizedTheme, version: requestedVersion });
  const unit = applyGeneratedSkin(template, payload, { version: requestedVersion, assets: images.assets });
  const previewPath = join(candidateDir, "candidate-preview.png");
  const visualContext = {
    theme: normalizedTheme,
    world_name: payload.display.world_name,
    entity_name: payload.display.entity_name,
    action_name: payload.display.action_name,
    console_name: payload.display.console_name,
    objective: payload.display.objective,
    scenario_frame: payload.display.scenario_frame,
  };
  const configuredRepairs = Number(process.env.SKIN_VISUAL_REPAIR_ATTEMPTS ?? 2);
  const maxVisualRepairs = mock ? 0 : Math.max(0, Math.min(3, Number.isFinite(configuredRepairs) ? Math.trunc(configuredRepairs) : 2));
  const visualRepairAttempts = [];
  let visualQuality;
  for (let repairRound = 0; repairRound <= maxVisualRepairs; repairRound += 1) {
    reportCandidateProgress(onProgress, { phase: "preview", progress: Math.min(88, 70 + repairRound * 7), repair_round: repairRound });
    const imagePaths = Object.values(images.assets).map((value) => join(candidateDir, value));
    createPreview({ imagePaths, outputPath: previewPath, projectDir, godotExe });
    reportCandidateProgress(onProgress, { phase: "visual_qa", progress: Math.min(90, 75 + repairRound * 7), repair_round: repairRound });
    visualQuality = await inspectCandidatePreview({
      previewPath,
      context: visualContext,
      checkpointPath: join(candidateDir, "visual-quality.checkpoint.json"),
      mock,
      resume,
    });
    reportCandidateProgress(onProgress, { phase: "visual_result", progress: Math.min(92, 78 + repairRound * 7), repair_round: repairRound, status: visualQuality.status, summary: visualQuality.summary });
    visualRepairAttempts.push({
      round: repairRound,
      status: visualQuality.status,
      summary: visualQuality.summary,
      issues: visualQuality.issues,
      provider_audit: visualQuality.provider_audit,
    });
    if (visualQuality.status !== "failed" || repairRound >= maxVisualRepairs) break;
    const repairKeys = [...new Set(visualQuality.issues
      .filter((issue) => issue.severity === "blocking")
      .flatMap((issue) => issue.asset_keys ?? []))];
    if (repairKeys.length === 0) break;
    reportCandidateProgress(onProgress, { phase: "visual_repair", progress: Math.min(92, 80 + repairRound * 7), repair_round: repairRound + 1, repair_keys: repairKeys });
    const promptFeedback = Object.fromEntries(repairKeys.map((key) => [key, visualQuality.issues
      .filter((issue) => (issue.asset_keys ?? []).includes(key))
      .map((issue) => `${issue.code}: ${issue.message}`)
      .join("; ")]));
    images = await generateSkinImages({
      theme: normalizedTheme,
      display: payload.display,
      outputDir: candidateDir,
      referencePath: mockSources.background_before,
      projectDir,
      godotExe,
      mock,
      mockSources,
      fixedSources,
      resume: true,
      forceKeys: repairKeys,
      promptFeedback,
      onProgress: (event) => reportCandidateProgress(onProgress, { ...event, repair_round: repairRound + 1, repair_keys: repairKeys }),
    });
  }
  reportCandidateProgress(onProgress, { phase: "candidate_validation", progress: 93 });
  writeFileSync(candidatePath, `${JSON.stringify(unit, null, 2)}\n`, "utf8");
  validateContentAssets(unit, candidatePath, { projectDir });
  reportCandidateProgress(onProgress, { phase: "smoke", progress: 95 });
  const smoke = runSmoke ? smokeTestCandidate(candidatePath, { projectDir, godotExe }) : { ok: false, skipped: true };
  reportCandidateProgress(onProgress, { phase: "smoke_complete", progress: 99, smoke_ok: smoke.ok === true });
  const auditPath = join(candidateDir, "generation-audit.json");
  writeFileSync(auditPath, `${JSON.stringify({
    generated_at: new Date().toISOString(),
    theme: normalizedTheme,
    candidate_path: candidatePath,
    preview_path: previewPath,
    text_generation: modelAudit,
    quality_warnings: qualityWarnings,
    image_generation: { mode: mock ? "mock" : "api", model: process.env.SKIN_IMAGE_MODEL ?? "doubao-seedream-5-0-lite-260128", checkpoint_path: images.checkpointPath, cost_summary: images.costSummary, reports: images.reports },
    visual_quality: visualQuality,
    visual_repair_attempts: visualRepairAttempts,
    smoke,
  }, null, 2)}\n`, "utf8");
  if (visualQuality.status === "failed" || visualQuality.blocking === true) {
    throw Object.assign(new Error(`候选未通过豆包视觉质检：${visualQuality.summary}`), { auditPath, previewPath, visualQuality });
  }
  reportCandidateProgress(onProgress, { phase: "complete", progress: 100, content_hash: smoke.contentHash });
  return { unit, candidatePath, previewPath, auditPath, smoke, qualityWarnings, visualQuality };
}

function argument(name) {
  const prefix = `--${name}=`;
  return process.argv.find((value) => value.startsWith(prefix))?.slice(prefix.length);
}

async function runCli() {
  const restoreOriginal = process.argv.includes("--restore-original");
  const result = await generateSkinCandidate({
    theme: argument("theme") ?? (restoreOriginal ? "原版花园" : undefined),
    version: argument("version"),
    templatePath: argument("template") ?? defaultTemplatePath,
    outputRoot: argument("output") ?? join(engineRoot, "candidates"),
    mock: process.argv.includes("--mock"),
    runSmoke: !process.argv.includes("--no-smoke"),
    resume: !process.argv.includes("--fresh"),
    textOnly: process.argv.includes("--text-only"),
    restoreOriginal,
  });
  if (result.textOnly) {
    console.log(`SKIN_TEXT_CANDIDATE_OK ${result.payload.theme} ${result.textCheckpointPath}`);
    return;
  }
  console.log(`SKIN_CANDIDATE_OK ${result.unit.world.theme} ${result.unit.unit_id}@${result.unit.version} ${result.candidatePath}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { await runCli(); } catch (error) { console.error(`SKIN_CANDIDATE_FAILED ${error instanceof Error ? error.message : String(error)}`); process.exitCode = 1; }
}
