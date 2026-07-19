import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { compileContentUnit } from "./compile-content.mjs";
import { assertCandidateVisualAudit, buildContentFromBase, copyRelativeAssetsToSource } from "./publish-from-feishu.mjs";

const engineRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const template = JSON.parse(readFileSync(join(engineRoot, "source", "data-garden-loop.json"), "utf8"));
const unitRow = {
  record_id: "rec_test_unit",
  fields: {
    "版本": "0.6.0",
    "主任务目标数": 5,
    "迁移目标数": 7,
    "教研审核通过": false,
    "安全审核通过": false,
  },
};
const hintTemplates = [
  "先确认目标，再观察世界。",
  "比较完成数量与目标数量。",
  "检查重复结构里的执行次数。",
  "每执行一次只改变一个目标。",
  "完整结构是“重复{main_target}次：生长”。",
];
const hintRows = hintTemplates.map((message, index) => ({
  record_id: `rec_hint_${index + 1}`,
  fields: {
    "关联单元": [{ id: unitRow.record_id }],
    "提示等级": index + 1,
    "教学意图": `第 ${index + 1} 级提示`,
    "提示模板": message,
    "允许显式答案": index === 4,
    "下一步动作": "继续尝试",
  },
}));

const unit = buildContentFromBase(template, unitRow, hintRows);
assert.equal(unit.version, "0.6.0");
assert.equal(unit.world.main_target, 5);
assert.equal(unit.world.transfer_target, 7);
assert.equal(unit.world_skins.find((skin) => skin.skin_id === unit.world.main_skin_id).target_count, 5);
assert.equal(unit.world_skins.find((skin) => skin.skin_id !== unit.world.main_skin_id).target_count, 7);
assert.match(unit.hint_policy[4].template, /重复5次/);
assert.equal(unit.hint_policy[4].needs_review, true);

const visualFixtureDir = mkdtempSync(join(tmpdir(), "walnut-visual-publish-test-"));
try {
  const skinCandidate = join(visualFixtureDir, "UNIT.1.0.0.candidate.json");
  writeFileSync(join(visualFixtureDir, "generation-audit.json"), JSON.stringify({ visual_quality: { status: "passed", passed: true, summary: "ok" } }), "utf8");
  assert.equal(assertCandidateVisualAudit(skinCandidate).status, "passed");
  writeFileSync(join(visualFixtureDir, "generation-audit.json"), JSON.stringify({ visual_quality: { status: "failed", passed: false, summary: "layout changed" } }), "utf8");
  assert.throws(() => assertCandidateVisualAudit(skinCandidate), /未通过豆包视觉质检/);
  assert.equal(assertCandidateVisualAudit(join(visualFixtureDir, "UNIT.1.0.0.variants.candidate.json")).status, "not_applicable");
} finally {
  rmSync(visualFixtureDir, { recursive: true, force: true });
}

const stagedAssetFixtureDir = mkdtempSync(join(tmpdir(), "walnut-staged-assets-test-"));
try {
  const reviewedDir = join(stagedAssetFixtureDir, "reviewed");
  const stagedDir = join(stagedAssetFixtureDir, "state");
  const assetsDir = join(reviewedDir, "assets");
  mkdirSync(assetsDir, { recursive: true });
  mkdirSync(stagedDir, { recursive: true });

  const candidate = structuredClone(template);
  const skin = candidate.world_skins.find((item) => item.skin_id === candidate.world.main_skin_id);
  const assetFiles = {
    background_before: ["assets", "backgrounds", "data_garden_world.png"],
    background_after: ["assets", "backgrounds", "data_garden_world_restored.png"],
    target_entity: ["assets", "sprites", "items", "data_garden_light_seed.png"],
    console: ["assets", "sprites", "items", "data_garden_console.png"],
    npc: ["assets", "sprites", "companion", "xiao_hetao.png"],
  };
  skin.assets = Object.fromEntries(Object.keys(assetFiles).map((key) => [key, `assets/${key}.png`]));
  const projectDir = join(engineRoot, "..", "my_topdown_game-main");
  for (const [key, parts] of Object.entries(assetFiles)) {
    copyFileSync(join(projectDir, ...parts), join(assetsDir, `${key}.png`));
  }

  const reviewedPath = join(reviewedDir, "UNIT.0.5.1.candidate.json");
  const stagedPath = join(stagedDir, "UNIT.0.5.1.candidate.json");
  const candidateText = `${JSON.stringify(candidate, null, 2)}\n`;
  writeFileSync(reviewedPath, candidateText, "utf8");
  writeFileSync(stagedPath, candidateText, "utf8");

  assert.throws(() => compileContentUnit(stagedPath, {
    projectDir,
    projectContentDir: join(stagedAssetFixtureDir, "failed", "content"),
    godotDir: join(stagedAssetFixtureDir, "failed", "godot"),
    aiDir: join(stagedAssetFixtureDir, "failed", "ai"),
  }), /素材不存在/);

  const compiled = compileContentUnit(stagedPath, {
    assetSourcePath: reviewedPath,
    projectDir,
    projectContentDir: join(stagedAssetFixtureDir, "compiled", "content"),
    godotDir: join(stagedAssetFixtureDir, "compiled", "godot"),
    aiDir: join(stagedAssetFixtureDir, "compiled", "ai"),
  });
  assert.equal(Object.keys(compiled.assets).length, 5);
  const canonicalSourcePath = join(stagedAssetFixtureDir, "canonical", "data-garden-loop.json");
  copyRelativeAssetsToSource(compiled.sourceAssets, canonicalSourcePath);
  for (const key of Object.keys(assetFiles)) {
    assert.deepEqual(readFileSync(join(stagedAssetFixtureDir, "canonical", "assets", `${key}.png`)), readFileSync(join(assetsDir, `${key}.png`)));
  }
} finally {
  rmSync(stagedAssetFixtureDir, { recursive: true, force: true });
}
console.log("CONTENT_PUBLISHER_TEST_OK");
