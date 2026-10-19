// Renders app_icons/*.svg into every icon the app ships.
// Run: npm install --no-save sharp png-to-ico && node tool/generate_icons.js
const fs = require("fs");
const path = require("path");
const sharp = require("sharp");
const pngToIco = require("png-to-ico").default || require("png-to-ico");

const ROOT = path.resolve(__dirname, "..");
const SRC = path.join(ROOT, "app_icons");
const NAVY = "#0B1F3A";

const sources = {
  mobile: fs.readFileSync(path.join(SRC, "mobile", "icon.svg")),
  foreground: fs.readFileSync(path.join(SRC, "mobile", "adaptive_foreground.svg")),
  desktop: fs.readFileSync(path.join(SRC, "desktop", "icon.svg")),
  small: fs.readFileSync(path.join(SRC, "desktop", "icon_small.svg")),
};

function render(svg, size, { opaque = false } = {}) {
  let image = sharp(svg, { density: 384 }).resize(size, size);
  if (opaque) image = image.flatten({ background: NAVY });
  return image.png().toBuffer();
}

function desktopFor(size) {
  return size <= 32 ? sources.small : sources.desktop;
}

async function write(file, buffer) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, buffer);
}

async function main() {
  for (const size of [1024, 512, 192, 180, 167, 152, 120, 96, 72, 48]) {
    await write(path.join(SRC, "mobile", `icon_${size}.png`), await render(sources.mobile, size, { opaque: true }));
  }
  await write(path.join(SRC, "mobile", "adaptive_foreground_1024.png"), await render(sources.foreground, 1024));

  const icoSizes = [16, 24, 32, 48, 64, 128, 256];
  for (const size of [16, 24, 32, 48, 64, 128, 256, 512, 1024]) {
    await write(path.join(SRC, "desktop", `icon_${size}.png`), await render(desktopFor(size), size));
  }
  const icoPngs = await Promise.all(icoSizes.map((size) => render(desktopFor(size), size)));
  await write(path.join(SRC, "desktop", "icon.ico"), await pngToIco(icoPngs));

  const res = path.join(ROOT, "android", "app", "src", "main", "res");
  const densities = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
  for (const [name, scale] of Object.entries(densities)) {
    await write(path.join(res, `mipmap-${name}`, "ic_launcher.png"), await render(sources.mobile, 48 * scale, { opaque: true }));
    await write(path.join(res, `drawable-${name}`, "ic_launcher_foreground.png"), await render(sources.foreground, 108 * scale));
  }

  const appIcon = path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset");
  for (const file of fs.readdirSync(appIcon)) {
    const match = /^Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$/.exec(file);
    if (!match) continue;
    const size = Math.round(Number(match[1]) * Number(match[2]));
    await write(path.join(appIcon, file), await render(sources.mobile, size, { opaque: true }));
  }

  const web = path.join(ROOT, "web");
  await write(path.join(web, "favicon.png"), await render(sources.small, 32));
  await write(path.join(web, "favicon.ico"), await pngToIco(await Promise.all([16, 32, 48].map((size) => render(desktopFor(size), size)))));
  await write(path.join(web, "icons", "Icon-192.png"), await render(sources.desktop, 192));
  await write(path.join(web, "icons", "Icon-512.png"), await render(sources.desktop, 512));
  await write(path.join(web, "icons", "Icon-maskable-192.png"), await render(sources.mobile, 192, { opaque: true }));
  await write(path.join(web, "icons", "Icon-maskable-512.png"), await render(sources.mobile, 512, { opaque: true }));
  await write(path.join(web, "icons", "apple-touch-icon.png"), await render(sources.mobile, 180, { opaque: true }));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
