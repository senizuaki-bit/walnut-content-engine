import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { contentHashFor } from "./content-assets.mjs";
import { applyGeneratedSkin, applyOriginalGarden, FIXED_ORIGINAL_SKIN_ASSET_KEYS } from "./generate-skin-candidate.mjs";
import { mockSkinPayload, skinQualityWarnings, validateGeneratedSkinPayload } from "./generation-common.mjs";
import { checkpointPromptCanResume } from "./image-generation.mjs";
import { validateTransferVariants } from "./variant-structure.mjs";
import { validateVisualQualityPayload } from "./visual-quality.mjs";
import { validateContentUnit } from "./validate-content.mjs";
import { workshopProgressFields } from "./world-workshop.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const engineRoot = resolve(scriptDir, "..");
const template = JSON.parse(readFileSync(join(engineRoot, "source", "data-garden-loop.json"), "utf8"));
const originalTemplate = JSON.parse(readFileSync(join(engineRoot, "source", "data-garden-loop.original.json"), "utf8"));
validateContentUnit(template);
const inconsistentTargets = structuredClone(template);
inconsistentTargets.world.main_target += 1;
assert.throws(() => validateContentUnit(inconsistentTargets), /main_target.*target_count/u);
assert.deepEqual(FIXED_ORIGINAL_SKIN_ASSET_KEYS, ["npc"]);
const dataGardenScript = readFileSync(join(engineRoot, "..", "my_topdown_game-main", "scenes", "demo", "data_garden", "data_garden.gd"), "utf8");
assert.match(dataGardenScript, /companion_sprite\.texture = load\("res:\/\/assets\/sprites\/companion\/xiao_hetao\.png"\)/u);
assert.doesNotMatch(dataGardenScript, /load_skin_texture\([^\n]*"npc"/u);
const restoredOriginal = applyOriginalGarden(template, originalTemplate, { version: "9.9.8" });
assert.equal(restoredOriginal.world.theme, "data_garden");
assert.equal(restoredOriginal.world.main_skin_id, "garden_light_seeds");
assert.equal(restoredOriginal.version, "9.9.8");
assert.equal(restoredOriginal.world_skins.find((skin) => skin.skin_id === "garden_light_seeds").assets.npc, "project://assets/sprites/companion/xiao_hetao.png");
assert.deepEqual(restoredOriginal.diagnostic_rules, template.diagnostic_rules);

const safePayload = validateGeneratedSkinPayload(mockSkinPayload("海底"), { theme: "海底" });
assert.deepEqual(skinQualityWarnings(safePayload), []);

const vaguePayload = structuredClone(safePayload);
vaguePayload.display.entity_name = "小动物";
vaguePayload.display.action_name = "游动";
vaguePayload.display.objective = "帮助小动物游动";
vaguePayload.display.scenario_frame = "让小动物一起游动";
const warningCodes = new Set(skinQualityWarnings(vaguePayload).map((warning) => warning.code));
assert.equal(warningCodes.has("GENERIC_ENTITY"), true);
assert.equal(warningCodes.has("INTRANSITIVE_ACTION"), true);
assert.equal(warningCodes.has("ACTION_MISSING_OBJECT"), true);

const skinned = applyGeneratedSkin(template, safePayload, { version: "9.9.9", assets: template.world_skins[0].assets });
for (const protectedKey of ["program_semantics", "templates", "world_actions", "diagnostic_rules", "misconceptions", "evidence", "safety"]) {
  assert.deepEqual(skinned[protectedKey], template[protectedKey], `AI 皮肤不得修改教学内核：${protectedKey}`);
}
assert.equal(skinned.world.main_target, template.world.main_target);
assert.equal(skinned.world.transfer_target, template.world.transfer_target);
assert.equal(skinned.world.theme, "海底");

const probes = validateTransferVariants(template.transfer_variants, template);
for (const result of probes) {
  assert.equal(result.probes.exact.diagnosis_id, "SUCCESS");
  assert.equal(result.probes.under.diagnosis_id, "COUNT_TOO_SMALL");
  assert.equal(result.probes.over.diagnosis_id, "COUNT_TOO_LARGE");
}

const assetRecord = { skin_id: "skin_test", key: "background_before", sha256: "a".repeat(64), width: 1280, height: 720 };
assert.notEqual(contentHashFor("{}", [assetRecord]), contentHashFor("{}", [{ ...assetRecord, sha256: "b".repeat(64) }]));

const baseImagePrompt = "single space console sprite";
const repairedImagePrompt = `${baseImagePrompt}\nHigh-priority visual QA repair: remove the dirty background`;
assert.equal(checkpointPromptCanResume(baseImagePrompt, baseImagePrompt), true);
assert.equal(checkpointPromptCanResume(repairedImagePrompt, baseImagePrompt), true);
assert.equal(checkpointPromptCanResume(baseImagePrompt, repairedImagePrompt), false);
assert.equal(checkpointPromptCanResume("different theme", baseImagePrompt), false);

const waitingProgress = workshopProgressFields({ phase: "image_waiting", asset_key: "target_entity", asset_index: 3, asset_total: 5, attempt: 1, elapsed_seconds: 90 });
assert.equal(waitingProgress["图片生成进度"], 33);
assert.match(waitingProgress["图片生成状态"], /目标实体.*90 秒/u);
assert.match(waitingProgress["图片生成心跳"], /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/u);
const repairProgress = workshopProgressFields({ phase: "visual_repair", progress: 85, repair_round: 2, repair_keys: ["npc"] });
assert.equal(repairProgress["图片生成进度"], 85);
assert.match(repairProgress["图片生成状态"], /第 2 轮.*NPC/u);

const visualPass = validateVisualQualityPayload({
  theme_match: true,
  before_after_consistent: true,
  target_matches_copy: true,
  sprites_clean: true,
  style_consistent: true,
  child_safe: true,
  summary: "主题、构图、精灵与儿童安全检查均通过。",
  issues: [],
});
assert.equal(visualPass.status, "passed");
const visualFail = validateVisualQualityPayload({
  theme_match: true,
  before_after_consistent: false,
  target_matches_copy: true,
  sprites_clean: true,
  style_consistent: true,
  child_safe: true,
  summary: "修复前后重画了主要地形。",
  issues: [{ code: "BEFORE_AFTER_INCONSISTENT", severity: "blocking", asset_keys: ["background_after"], message: "主要地形与关键物体布局发生变化。" }],
});
assert.equal(visualFail.status, "failed");

console.log("CONTENT_GENERATION_TEST_OK");
