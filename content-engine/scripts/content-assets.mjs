import { createHash } from "node:crypto";
import { copyFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { basename, dirname, extname, join, relative, resolve } from "node:path";

const REQUIRED_ASSETS = ["background_before", "background_after", "target_entity", "console"];
const OPTIONAL_ASSETS = ["npc"];
const SUPPORTED_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".webp"]);

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function inside(parent, child) {
  const path = relative(resolve(parent), resolve(child));
  return path === "" || (!path.startsWith("..") && !path.startsWith("/"));
}

export function resolveAssetSource(assetRef, sourcePath, projectDir) {
  const value = String(assetRef ?? "").trim();
  invariant(value, "素材路径不能为空");
  if (value.startsWith("project://")) {
    invariant(projectDir, `素材 ${value} 使用 project://，但未提供 Godot 项目目录`);
    const path = resolve(projectDir, value.slice("project://".length));
    invariant(inside(projectDir, path), `素材路径越出 Godot 项目目录：${value}`);
    return path;
  }
  invariant(!value.includes(":"), `候选素材必须使用相对路径或 project://：${value}`);
  const root = dirname(resolve(sourcePath));
  const path = resolve(root, value);
  invariant(inside(root, path), `候选素材路径越出候选目录：${value}`);
  return path;
}

export function readImageDimensions(filePath) {
  const buffer = readFileSync(filePath);
  if (buffer.length >= 24 && buffer.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
    return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20), format: "png" };
  }
  if (buffer.length >= 12 && buffer.toString("ascii", 0, 4) === "RIFF" && buffer.toString("ascii", 8, 12) === "WEBP") {
    const kind = buffer.toString("ascii", 12, 16);
    if (kind === "VP8X" && buffer.length >= 30) {
      return {
        width: 1 + buffer.readUIntLE(24, 3),
        height: 1 + buffer.readUIntLE(27, 3),
        format: "webp",
      };
    }
  }
  if (buffer.length >= 4 && buffer[0] === 0xff && buffer[1] === 0xd8) {
    let offset = 2;
    while (offset + 9 < buffer.length) {
      if (buffer[offset] !== 0xff) { offset += 1; continue; }
      const marker = buffer[offset + 1];
      if (marker === 0xd8 || marker === 0xd9) { offset += 2; continue; }
      const length = buffer.readUInt16BE(offset + 2);
      if (length < 2 || offset + length + 2 > buffer.length) break;
      if (marker >= 0xc0 && marker <= 0xc3) {
        return { width: buffer.readUInt16BE(offset + 7), height: buffer.readUInt16BE(offset + 5), format: "jpeg" };
      }
      offset += length + 2;
    }
  }
  throw new Error(`无法读取素材尺寸或格式不受支持：${filePath}`);
}

function validateDimensions(key, dimensions, skinId) {
  if (key.startsWith("background_")) {
    invariant(dimensions.width >= 1280 && dimensions.height >= 720, `皮肤 ${skinId} 的 ${key} 至少需要 1280×720`);
    const ratio = dimensions.width / dimensions.height;
    invariant(ratio >= 1.6 && ratio <= 1.9, `皮肤 ${skinId} 的 ${key} 宽高比必须接近 16:9`);
  } else {
    invariant(dimensions.width >= 128 && dimensions.height >= 128, `皮肤 ${skinId} 的 ${key} 至少需要 128×128`);
    invariant(dimensions.width <= 4096 && dimensions.height <= 4096, `皮肤 ${skinId} 的 ${key} 尺寸不能超过 4096×4096`);
  }
}

export function collectContentAssets(unit, { sourcePath, projectDir, requireActiveSkinAssets = true } = {}) {
  invariant(sourcePath, "素材校验需要 sourcePath");
  const activeSkinId = String(unit.world?.main_skin_id ?? unit.world_skins?.[0]?.skin_id ?? "");
  const records = [];
  for (const skin of unit.world_skins ?? []) {
    const assets = skin.assets;
    if (!assets) {
      invariant(!requireActiveSkinAssets || skin.skin_id !== activeSkinId, `主世界皮肤 ${skin.skin_id} 缺少 assets`);
      continue;
    }
    invariant(assets && typeof assets === "object" && !Array.isArray(assets), `皮肤 ${skin.skin_id} 的 assets 必须是对象`);
    for (const key of REQUIRED_ASSETS) invariant(typeof assets[key] === "string" && assets[key].trim(), `皮肤 ${skin.skin_id} 缺少素材 ${key}`);
    for (const key of Object.keys(assets)) invariant([...REQUIRED_ASSETS, ...OPTIONAL_ASSETS].includes(key), `皮肤 ${skin.skin_id} 含未知素材字段 ${key}`);
    for (const [key, assetRef] of Object.entries(assets)) {
      const source = resolveAssetSource(assetRef, sourcePath, projectDir);
      invariant(existsSync(source), `皮肤 ${skin.skin_id} 素材不存在：${assetRef}`);
      const extension = extname(source).toLowerCase();
      invariant(SUPPORTED_EXTENSIONS.has(extension), `皮肤 ${skin.skin_id} 素材格式不支持：${extension}`);
      const dimensions = readImageDimensions(source);
      validateDimensions(key, dimensions, skin.skin_id);
      records.push({
        skin_id: String(skin.skin_id),
        key,
        source_ref: String(assetRef),
        source,
        extension,
        bytes: readFileSync(source).length,
        ...dimensions,
        sha256: createHash("sha256").update(readFileSync(source)).digest("hex"),
      });
    }
  }
  return records.sort((left, right) => `${left.skin_id}/${left.key}`.localeCompare(`${right.skin_id}/${right.key}`));
}

export function contentHashFor(sourceText, assets = []) {
  const hash = createHash("sha256").update(sourceText);
  if (assets.length > 0) {
    hash.update("\nWALNUT_ASSET_INTEGRITY_V1\n");
    for (const asset of assets) hash.update(`${asset.skin_id}/${asset.key}:${asset.sha256}:${asset.width}x${asset.height}\n`);
  }
  return hash.digest("hex");
}

export function copyAssetsForManifest(unit, assets, projectContentDir) {
  const packageSkins = structuredClone(unit.world_skins ?? []);
  const integrity = {};
  for (const asset of assets) {
    const fileName = `${asset.key}${asset.extension === ".jpeg" ? ".jpg" : asset.extension}`;
    const targetDir = join(projectContentDir, "skins", asset.skin_id);
    const targetPath = join(targetDir, fileName);
    mkdirSync(targetDir, { recursive: true });
    copyFileSync(asset.source, targetPath);
    const manifestPath = `../skins/${asset.skin_id}/${fileName}`;
    const skin = packageSkins.find((candidate) => String(candidate.skin_id) === asset.skin_id);
    if (skin) skin.assets[asset.key] = manifestPath;
    integrity[`${asset.skin_id}/${asset.key}`] = {
      path: manifestPath,
      sha256: asset.sha256,
      width: asset.width,
      height: asset.height,
      bytes: asset.bytes,
      source_name: basename(asset.source),
    };
  }
  return { packageSkins, integrity };
}

export const CONTENT_ASSET_KEYS = Object.freeze({
  required: [...REQUIRED_ASSETS],
  optional: [...OPTIONAL_ASSETS],
});
