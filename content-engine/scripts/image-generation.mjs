import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, extname, join, resolve } from "node:path";
import { readImageDimensions } from "./content-assets.mjs";

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function reportProgress(onProgress, event) {
  if (typeof onProgress !== "function") return;
  try {
    onProgress({ ...event, reported_at: new Date().toISOString() });
  } catch (error) {
    console.warn(`[content-engine] 图片进度回写失败：${error instanceof Error ? error.message : String(error)}`);
  }
}

export function checkpointPromptCanResume(previousPrompt, requestedPrompt) {
  const previous = String(previousPrompt ?? "");
  const requested = String(requestedPrompt ?? "");
  return previous === requested
    || previous.startsWith(`${requested}\nHigh-priority visual QA repair:`);
}

function mimeFor(filePath) {
  const extension = extname(filePath).toLowerCase();
  if (extension === ".jpg" || extension === ".jpeg") return "image/jpeg";
  if (extension === ".webp") return "image/webp";
  return "image/png";
}

function dataUrl(filePath) {
  return `data:${mimeFor(filePath)};base64,${readFileSync(filePath).toString("base64")}`;
}

export function imagePrompts(theme, display) {
  const style = "friendly 2D pixel-art game asset, top-down view, coherent shapes, clean silhouette, no text, no logo, no watermark, child-safe, same palette and lighting as reference";
  return {
    background_before: `${theme} world before restoration, ${display.scenario_frame}, dormant and recoverable, 16:9 environment, ${style}`,
    background_after: `Edit the supplied before-world image into the restored ${theme} world. This is a strict image edit, not a redesign. Preserve the exact camera, terrain silhouette, paths, platforms and every major object's position and scale; do not add trees, gates, buildings or characters that are absent from the input. Only change dormant objects into their causal restored state and make the existing scene lively and luminous, 16:9 environment, ${style}`,
    target_entity: `single ${display.entity_name} game sprite, centered, transparent or plain background, dormant-but-hopeful state, ${style}`,
    console: `single ${display.console_name} game console sprite, centered, transparent or plain background, designed for action ${display.action_name}, ${style}`,
    npc: `single friendly optional NPC from ${theme}, centered, transparent or plain background, supportive learning companion, ${style}`,
  };
}

async function requestImage(prompt, referencePaths, size, config) {
  const endpoint = config.endpoint ?? process.env.SKIN_IMAGE_API_URL ?? "https://ark.cn-beijing.volces.com/api/v3/images/generations";
  const apiKey = config.apiKey ?? process.env.ARK_API_KEY ?? process.env.SKIN_IMAGE_API_KEY ?? "";
  const model = config.model ?? process.env.SKIN_IMAGE_MODEL ?? "doubao-seedream-5-0-lite-260128";
  invariant(apiKey, "缺少 ARK_API_KEY；可使用 --mock 验证离线管线");
  const body = {
    model,
    prompt,
    size,
    response_format: config.responseFormat ?? process.env.SKIN_IMAGE_RESPONSE_FORMAT ?? "url",
    output_format: "png",
    sequential_image_generation: "disabled",
    stream: false,
    watermark: false,
  };
  const references = (Array.isArray(referencePaths) ? referencePaths : [referencePaths]).filter(Boolean);
  const referenceMode = config.referenceMode ?? process.env.SKIN_IMAGE_REFERENCE_MODE ?? "array";
  if (referenceMode === "array") body.image = references.map(dataUrl);
  else if (referenceMode === "data_url") body.image = dataUrl(references[0]);
  if (process.env.SKIN_IMAGE_EXTRA_JSON) Object.assign(body, JSON.parse(process.env.SKIN_IMAGE_EXTRA_JSON));
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(Number(config.timeoutMs ?? process.env.SKIN_IMAGE_TIMEOUT_MS ?? 360_000)),
  });
  if (!response.ok) throw new Error(`生图 API HTTP ${response.status}: ${(await response.text()).slice(0, 240)}`);
  const result = await response.json();
  const item = result?.data?.[0] ?? result?.images?.[0] ?? {};
  const apiMetadata = {
    model: String(result?.model ?? model),
    created: result?.created ?? null,
    usage: result?.usage ?? null,
    request_id: response.headers.get("x-request-id") ?? response.headers.get("x-tt-logid") ?? "",
  };
  if (item.b64_json || item.base64) return { buffer: Buffer.from(item.b64_json ?? item.base64, "base64"), api: apiMetadata };
  if (item.url) {
    let lastDownloadError;
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        const imageResponse = await fetch(item.url, { signal: AbortSignal.timeout(120_000) });
        if (!imageResponse.ok) throw new Error(`HTTP ${imageResponse.status}`);
        return { buffer: Buffer.from(await imageResponse.arrayBuffer()), api: apiMetadata };
      } catch (error) {
        lastDownloadError = error;
        if (attempt < 3) await new Promise((resolveDelay) => setTimeout(resolveDelay, attempt * 750));
      }
    }
    const host = (() => { try { return new URL(item.url).host; } catch { return "unknown-host"; } })();
    throw new Error(`生图结果下载失败（${host}）：${lastDownloadError instanceof Error ? lastDownloadError.message : String(lastDownloadError)}`);
  }
  throw new Error("生图 API 返回中没有 b64_json/base64/url");
}

export function runImageProcessor({ input, output, paletteRef, projectDir, godotExe, removeBackground = false, maxDimension = 0 }) {
  const scriptPath = join(projectDir, "content_engine", "tools", "image_processor.gd");
  const toolArgs = ["--headless", "--path", projectDir, "--script", scriptPath, "--", `--input=${input}`, `--output=${output}`, `--palette-ref=${paletteRef}`];
  if (removeBackground) toolArgs.push("--remove-background=true");
  if (maxDimension > 0) toolArgs.push(`--max-dimension=${maxDimension}`);
  const result = spawnSync(godotExe, toolArgs, {
    cwd: projectDir,
    encoding: "utf8",
    windowsHide: true,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr?.trim() || result.stdout?.trim() || `图片后处理退出码 ${result.status}`);
  const line = result.stdout.split(/\r?\n/u).find((value) => value.startsWith("WALNUT_IMAGE_RESULT "));
  invariant(line, "图片后处理未返回结果");
  return JSON.parse(line.slice("WALNUT_IMAGE_RESULT ".length));
}

function hammingDistance(left, right) {
  invariant(/^[a-f0-9]{16}$/iu.test(left) && /^[a-f0-9]{16}$/iu.test(right), "感知哈希格式无效");
  let distance = 0;
  for (let index = 0; index < 16; index += 1) {
    let value = Number.parseInt(left[index], 16) ^ Number.parseInt(right[index], 16);
    while (value) { distance += value & 1; value >>= 1; }
  }
  return distance;
}

export function libraryPerceptualHashes(projectDir, godotExe, paletteRef) {
  const roots = [join(projectDir, "content", "skins")];
  const paths = [];
  const visit = (dir) => {
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) visit(path);
      else if (/\.(png|jpe?g|webp)$/iu.test(entry.name)) paths.push(path);
    }
  };
  for (const root of roots) visit(root);
  return paths.map((path) => ({ path, phash: runImageProcessor({ input: path, output: path, paletteRef, projectDir, godotExe }).phash }));
}

export async function generateSkinImages({ theme, display, outputDir, referencePath, projectDir, godotExe, mock = false, mockSources = {}, fixedSources = {}, dedupThreshold = 5, resume = true, forceKeys = [], promptFeedback = {}, onProgress } = {}) {
  const basePrompts = imagePrompts(theme, display);
  const forced = new Set(forceKeys);
  const prompts = Object.fromEntries(Object.entries(basePrompts).map(([key, prompt]) => [
    key,
    promptFeedback[key] ? `${prompt}\nHigh-priority visual QA repair: ${String(promptFeedback[key]).slice(0, 600)}` : prompt,
  ]));
  const rawDir = join(outputDir, ".raw");
  const assetsDir = join(outputDir, "assets");
  const checkpointPath = join(outputDir, "image-generation.checkpoint.json");
  mkdirSync(rawDir, { recursive: true });
  mkdirSync(assetsDir, { recursive: true });
  let checkpoint = { version: 1, assets: {} };
  if (resume && existsSync(checkpointPath)) {
    try { checkpoint = JSON.parse(readFileSync(checkpointPath, "utf8")); } catch { checkpoint = { version: 1, assets: {} }; }
  }
  const assets = {};
  const reports = {};
  const library = mock ? [] : libraryPerceptualHashes(projectDir, godotExe, referencePath);
  const promptEntries = Object.entries(prompts);
  for (const [assetIndex, [key, prompt]] of promptEntries.entries()) {
    const rawPath = join(rawDir, `${key}.png`);
    const outputPath = join(assetsDir, `${key}.png`);
    const isSprite = !key.startsWith("background_");
    let report;
    const fixedSource = fixedSources[key];
    if (fixedSource) {
      invariant(existsSync(fixedSource), `固定原版素材不存在：${fixedSource}`);
      copyFileSync(fixedSource, rawPath);
      copyFileSync(fixedSource, outputPath);
      report = {
        ...readImageDimensions(fixedSource),
        output: outputPath,
        source: fixedSource,
        fixed_original: true,
      };
      checkpoint.assets[key] = {
        mode: "fixed-original",
        prompt: "fixed-original-asset",
        source: fixedSource,
        generated_at: checkpoint.assets[key]?.generated_at ?? new Date().toISOString(),
        postprocess: report,
        postprocessed_at: new Date().toISOString(),
      };
      writeFileSync(checkpointPath, `${JSON.stringify(checkpoint, null, 2)}\n`, "utf8");
      assets[key] = `assets/${key}.png`;
      reports[key] = { ...report, generation: checkpoint.assets[key] };
      reportProgress(onProgress, { phase: "asset_fixed_original", asset_key: key, asset_index: assetIndex + 1, asset_total: promptEntries.length, attempt: 0 });
      continue;
    }
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      // A later retry first enters with the base prompt again. Preserve a newer
      // visual-QA repair checkpoint instead of paying to regenerate the older base image.
      const canResume = resume
        && !forced.has(key)
        && existsSync(rawPath)
        && readFileSync(rawPath).length > 64
        && checkpointPromptCanResume(checkpoint.assets?.[key]?.prompt, prompt);
      if (canResume) {
        // Re-run deterministic post-processing so tool improvements apply without another paid API call.
        reportProgress(onProgress, { phase: "asset_resumed", asset_key: key, asset_index: assetIndex + 1, asset_total: promptEntries.length, attempt });
      } else if (mock) {
        const source = mockSources[key] ?? referencePath;
        copyFileSync(source, rawPath);
        checkpoint.assets[key] = { mode: "mock", prompt, source, generated_at: new Date().toISOString() };
        writeFileSync(checkpointPath, `${JSON.stringify(checkpoint, null, 2)}\n`, "utf8");
      } else {
        // Seedream 5.0 lite requires at least 3,686,400 pixels per image.
        const size = key.startsWith("background_") ? "2560x1440" : "2048x2048";
        const generatedWorldReference = join(rawDir, "background_before.png");
        // Once the themed before-world exists, use it as the sole visual source. Mixing the
        // original garden with the newly themed scene caused Seedream to redesign the layout.
        const references = key === "background_before" || !existsSync(generatedWorldReference)
          ? [referencePath]
          : [generatedWorldReference];
        const requestStartedAt = Date.now();
        reportProgress(onProgress, { phase: "image_request", asset_key: key, asset_index: assetIndex + 1, asset_total: promptEntries.length, attempt, timeout_seconds: Number(process.env.SKIN_IMAGE_TIMEOUT_MS ?? 360_000) / 1000 });
        const heartbeat = setInterval(() => reportProgress(onProgress, {
          phase: "image_waiting",
          asset_key: key,
          asset_index: assetIndex + 1,
          asset_total: promptEntries.length,
          attempt,
          elapsed_seconds: Math.floor((Date.now() - requestStartedAt) / 1000),
        }), 30_000);
        heartbeat.unref?.();
        let generated;
        try {
          generated = await requestImage(`${prompt}\nVariation seed: ${attempt}`, references, size, {});
        } finally {
          clearInterval(heartbeat);
        }
        reportProgress(onProgress, { phase: "image_received", asset_key: key, asset_index: assetIndex + 1, asset_total: promptEntries.length, attempt, elapsed_seconds: Math.floor((Date.now() - requestStartedAt) / 1000) });
        writeFileSync(rawPath, generated.buffer);
        const previous = checkpoint.assets?.[key];
        const generations = Array.isArray(previous?.generations)
          ? [...previous.generations]
          : previous?.api
            ? [{ api: previous.api, prompt: previous.prompt, generated_at: previous.generated_at }]
            : [];
        generations.push({ api: generated.api, prompt, generated_at: new Date().toISOString() });
        checkpoint.assets[key] = {
          mode: "seedream",
          prompt,
          size,
          reference_count: references.length,
          attempt,
          api: generated.api,
          generations,
          generated_at: new Date().toISOString(),
        };
        writeFileSync(checkpointPath, `${JSON.stringify(checkpoint, null, 2)}\n`, "utf8");
      }
      report = runImageProcessor({ input: rawPath, output: outputPath, paletteRef: referencePath, projectDir, godotExe, removeBackground: isSprite, maxDimension: isSprite ? 768 : 0 });
      const duplicate = library.find((item) => hammingDistance(item.phash, report.phash) <= dedupThreshold);
      if (mock || canResume || !duplicate) break;
      if (attempt === 3) throw new Error(`素材 ${key} 与素材库过近：${duplicate.path}`);
    }
    assets[key] = `assets/${key}.png`;
    if (!checkpoint.assets[key]) checkpoint.assets[key] = { mode: "resume-existing", prompt, api_usage_unknown: true };
    checkpoint.assets[key].postprocess = report;
    checkpoint.assets[key].postprocessed_at = new Date().toISOString();
    writeFileSync(checkpointPath, `${JSON.stringify(checkpoint, null, 2)}\n`, "utf8");
    reports[key] = { ...report, prompt, generation: checkpoint.assets[key] };
    reportProgress(onProgress, { phase: "image_complete", asset_key: key, asset_index: assetIndex + 1, asset_total: promptEntries.length, attempt: checkpoint.assets[key]?.attempt ?? 1 });
  }
  const checkpointEntries = Object.values(checkpoint.assets);
  const knownGeneratedImages = checkpointEntries.reduce((total, entry) => {
    if (Array.isArray(entry?.generations) && entry.generations.length > 0) {
      return total + entry.generations.reduce((subtotal, generation) => subtotal + Number(generation?.api?.usage?.generated_images ?? 1), 0);
    }
    return total + Number(entry?.api?.usage?.generated_images ?? (entry?.mode === "seedream" ? 1 : 0));
  }, 0);
  const unknownHistoricalAssets = checkpointEntries.filter((entry) => entry?.api_usage_unknown === true).length;
  return {
    assets,
    reports,
    checkpointPath,
    costSummary: {
      known_generated_images: knownGeneratedImages,
      estimated_cny_at_0_22_per_image: Number((knownGeneratedImages * 0.22).toFixed(2)),
      unknown_historical_assets: unknownHistoricalAssets,
    },
  };
}

export function createPreview({ imagePaths, outputPath, projectDir, godotExe }) {
  const scriptPath = join(projectDir, "content_engine", "tools", "image_processor.gd");
  mkdirSync(dirname(outputPath), { recursive: true });
  const result = spawnSync(godotExe, ["--headless", "--path", projectDir, "--script", scriptPath, "--", `--preview-output=${outputPath}`], {
    cwd: projectDir,
    encoding: "utf8",
    windowsHide: true,
    env: { ...process.env, WALNUT_PREVIEW_INPUTS: JSON.stringify(imagePaths) },
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr?.trim() || result.stdout?.trim() || `预览拼图退出码 ${result.status}`);
  invariant(existsSync(outputPath), "预览拼图没有生成");
  return outputPath;
}
