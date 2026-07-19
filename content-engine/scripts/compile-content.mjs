import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { validateContentUnit } from "./validate-content.mjs";
import { collectContentAssets, contentHashFor, copyAssetsForManifest } from "./content-assets.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const engineRoot = resolve(scriptDir, "..");

export function compileContentUnit(sourceFilePath, options = {}) {
  const sourcePath = resolve(sourceFilePath);
  const sourceText = readFileSync(sourcePath, "utf8");
  const unit = validateContentUnit(JSON.parse(sourceText));
  const projectDir = resolve(options.projectDir ?? join(engineRoot, "../my_topdown_game-main"));
  // A release-staged JSON may live in .state while its relative assets remain in
  // the reviewed candidate directory. Keep the JSON identity and asset base explicit.
  const assetSourcePath = resolve(options.assetSourcePath ?? sourcePath);
  const assets = collectContentAssets(unit, { sourcePath: assetSourcePath, projectDir });
  const contentHash = contentHashFor(sourceText, assets);
  const generatedAt = options.generatedAt ?? new Date().toISOString();

  const common = {
    unit_id: unit.unit_id,
    version: unit.version,
    content_hash: contentHash,
    generated_at: generatedAt,
  };

  const projectContentDir = resolve(options.projectContentDir ?? join(projectDir, "content"));
  const { packageSkins, integrity: assetIntegrity } = copyAssetsForManifest(unit, assets, projectContentDir);
  const godotPackage = {
    ...common,
    audience: unit.audience,
    concept: unit.knowledge,
    misconceptions: unit.misconceptions,
    world: unit.world,
    program_semantics: unit.program_semantics,
    templates: unit.templates,
    world_actions: unit.world_actions,
    world_skins: packageSkins,
    transfer_variants: unit.transfer_variants ?? [],
    asset_integrity: assetIntegrity,
    diagnostic_rules: unit.diagnostic_rules,
    stages: unit.stages,
    hint_policy: unit.hint_policy,
    surprise: unit.surprise,
    evidence: unit.evidence,
  };

  const aiPackage = {
    ...common,
    audience: unit.audience,
    concept_id: unit.knowledge.concept_id,
    world: unit.world,
    world_skins: unit.world_skins.map(({ skin_id, display, target_count }) => ({ skin_id, display, target_count })),
    hints: unit.hint_policy,
    diagnostic_rules: unit.diagnostic_rules,
    evidence: unit.evidence,
    transfer_variants: unit.transfer_variants ?? [],
    misconceptions: unit.misconceptions.map(({ id, signal, intervention }) => ({ id, signal, intervention })),
    safety: unit.safety,
  };

  const godotDir = resolve(options.godotDir ?? join(engineRoot, "generated/godot"));
  const aiDir = resolve(options.aiDir ?? join(engineRoot, "generated/ai"));
  const projectGeneratedDir = join(projectContentDir, "generated");
  mkdirSync(godotDir, { recursive: true });
  mkdirSync(aiDir, { recursive: true });
  mkdirSync(projectGeneratedDir, { recursive: true });
  const godotVersionedPath = join(godotDir, `${unit.unit_id}.${unit.version}.json`);
  const aiVersionedPath = join(aiDir, `${unit.unit_id}.${unit.version}.json`);
  const aiAliasPath = join(aiDir, `${unit.unit_id}.json`);
  const godotAliasPath = join(projectGeneratedDir, `${unit.unit_id}.json`);
  writeFileSync(godotVersionedPath, `${JSON.stringify(godotPackage, null, 2)}\n`, "utf8");
  writeFileSync(aiVersionedPath, `${JSON.stringify(aiPackage, null, 2)}\n`, "utf8");
  writeFileSync(aiAliasPath, `${JSON.stringify(aiPackage, null, 2)}\n`, "utf8");
  writeFileSync(godotAliasPath, `${JSON.stringify(godotPackage, null, 2)}\n`, "utf8");

  return {
    unit,
    contentHash,
    generatedAt,
    assets: assetIntegrity,
    sourceAssets: assets,
    paths: { godotVersionedPath, aiVersionedPath, aiAliasPath, godotAliasPath, projectContentDir },
  };
}

function runCli() {
  const sourcePath = resolve(process.cwd(), process.argv[2] ?? join(engineRoot, "source/data-garden-loop.json"));
  const result = compileContentUnit(sourcePath);
  console.log(`CONTENT_COMPILE_OK ${result.unit.unit_id}@${result.unit.version} ${result.contentHash.slice(0, 12)}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) runCli();
