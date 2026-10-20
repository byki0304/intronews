// Parsers load on first use; requiring them at startup pushes deploy-time code analysis past its 10-second limit.
const mammoth = () => require("mammoth");
const WordExtractor = () => require("word-extractor");
const JSZip = () => require("jszip");
const CFB = () => require("cfb");
const XLSX = () => require("xlsx");

const MAX_CHARS = 500000;

function extOf(name) {
  const match = /\.([^.]+)$/.exec(String(name || ""));
  return match ? match[1].toLowerCase() : "";
}

function decodeText(buffer) {
  if (buffer[0] === 0xef && buffer[1] === 0xbb && buffer[2] === 0xbf) {
    return new TextDecoder("utf-8").decode(buffer.subarray(3));
  }
  if (buffer[0] === 0xff && buffer[1] === 0xfe) return new TextDecoder("utf-16le").decode(buffer.subarray(2));
  if (buffer[0] === 0xfe && buffer[1] === 0xff) return new TextDecoder("utf-16be").decode(buffer.subarray(2));
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(buffer);
  } catch (_) {
    return new TextDecoder("euc-kr").decode(buffer);
  }
}

function decodeXml(value) {
  return value
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)))
    .replace(/&amp;/g, "&");
}

async function pptxText(buffer) {
  const zip = await JSZip().loadAsync(buffer);
  const slides = Object.keys(zip.files)
    .map((path) => ({ path, match: /^ppt\/slides\/slide(\d+)\.xml$/.exec(path) }))
    .filter((item) => item.match)
    .sort((a, b) => Number(a.match[1]) - Number(b.match[1]));
  const out = [];
  for (const [index, slide] of slides.entries()) {
    const xml = await zip.file(slide.path).async("string");
    const lines = xml
      .split("</a:p>")
      .map((para) => [...para.matchAll(/<a:t>([^<]*)<\/a:t>/g)].map((m) => decodeXml(m[1])).join(""))
      .filter((line) => line.trim());
    out.push(`[Slide ${index + 1}]\n${lines.join("\n")}`);
  }
  return out.join("\n\n");
}

const PPT_SLIDE = 0x03ee;
const PPT_SLIDE_LIST_WITH_TEXT = 0x0ff0;
const PPT_TEXT_CHARS = 0x0fa0;
const PPT_TEXT_BYTES = 0x0fa8;

// Only slide content counts; master and notes records carry template text such as "Click to edit Master title style".
function walkPptRecords(buf, start, end, out, inSlide) {
  let pos = start;
  while (pos + 8 <= end) {
    const verInstance = buf.readUInt16LE(pos);
    const type = buf.readUInt16LE(pos + 2);
    const length = buf.readUInt32LE(pos + 4);
    const body = pos + 8;
    const next = body + length;
    if (next > end) break;
    if ((verInstance & 0x0f) === 0x0f) {
      const slideText = type === PPT_SLIDE || (type === PPT_SLIDE_LIST_WITH_TEXT && verInstance >> 4 === 0);
      walkPptRecords(buf, body, next, out, inSlide || slideText);
    } else if (inSlide && type === PPT_TEXT_CHARS) {
      out.push(buf.toString("utf16le", body, next));
    } else if (inSlide && type === PPT_TEXT_BYTES) {
      out.push(buf.toString("latin1", body, next));
    }
    pos = next;
  }
}

function pptText(buffer) {
  const container = CFB().read(buffer, { type: "buffer" });
  const entry = CFB().find(container, "PowerPoint Document");
  if (!entry || !entry.content) return "";
  const stream = Buffer.from(entry.content);
  const out = [];
  walkPptRecords(stream, 0, stream.length, out, false);
  return out
    .map((line) => line.replace(/\r/g, "\n").trim())
    .filter(Boolean)
    .join("\n");
}

function sheetText(buffer) {
  const book = XLSX().read(buffer, { type: "buffer" });
  return book.SheetNames
    .map((name) => {
      const csv = XLSX().utils.sheet_to_csv(book.Sheets[name], { blankrows: false });
      return `[Sheet ${name}]\n${csv}`;
    })
    .join("\n\n");
}

async function extractText(ext, buffer) {
  switch (ext) {
    case "txt":
    case "md":
      return decodeText(buffer);
    case "docx":
      return (await mammoth().extractRawText({ buffer })).value;
    case "doc":
      return (await new (WordExtractor())().extract(buffer)).getBody();
    case "pptx":
      return pptxText(buffer);
    case "ppt":
      return pptText(buffer);
    case "xlsx":
    case "xls":
      return sheetText(buffer);
    default:
      throw new Error(`unsupported extension: ${ext}`);
  }
}

async function newsFileParts(name, buffer) {
  const ext = extOf(name);
  if (ext === "pdf") {
    return [
      { text: `Source file name: ${name}` },
      { inlineData: { mimeType: "application/pdf", data: buffer.toString("base64") } },
    ];
  }
  const text = String(await extractText(ext, buffer)).trim();
  if (!text) return [];
  return [{ text: `Source file name: ${name}\n\n${text.slice(0, MAX_CHARS)}` }];
}

module.exports = { newsFileParts };
