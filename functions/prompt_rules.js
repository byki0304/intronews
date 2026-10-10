const FORBIDDEN_NEWS = [
  "International Television Broadcast",
  "Global News Network",
  "Breaking News",
  "Broadcast-quality newsroom",
  "Ultra-wide LED Wall",
  "News ticker",
  "news ticker",
  "Scrolling captions",
  "Large lower third",
  "lower third",
  "Headline banner",
  "headline banner",
  "Anchor begins broadcasting",
  "broadcast ends",
  "final broadcast",
  "news closing",
  "program ending",
  "station closing",
];

const MAIN_NAMES = new Set([
  "hs",
  "professor hs",
  "prof hs",
  "prof. hs",
  "main anchor",
  "anchor hs",
  "메인",
  "메인 앵커",
  "메인 캐릭터",
  "주인공",
  "professor hs (main)",
]);

function isMainRole(name) {
  const text = String(name || "")
    .trim()
    .toLowerCase()
    .replace(/\./g, "");
  if (!text) return false;
  if (MAIN_NAMES.has(text) || MAIN_NAMES.has(String(name || "").trim().toLowerCase())) {
    return true;
  }
  return text === "professor hs" || text === "prof hs";
}

function isNoCharacter(value) {
  const text = String(value || "").trim().toLowerCase();
  if (!text) return true;
  const exact = [
    "없음",
    "캐릭터 없음",
    "등장인물 없음",
    "인물 없음",
    "no character",
    "none",
    "n/a",
    "불필요",
    "캐릭터 필요없음",
    "캐릭터 필요 없음",
  ];
  if (exact.includes(text)) return true;
  return (
    text.includes("캐릭터 없음") ||
    text.includes("등장인물 없음") ||
    text.includes("no character")
  );
}

function stripSeedClaims(text) {
  return String(text || "")
    .replace(/Seed:\s*\d+/gi, "")
    .replace(/numeric seed[^.!\n]*[.!]?/gi, "")
    .replace(/시드\s*\d+\s*가[^\n]*/gi, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function ensureVideoSettings(text) {
  let value = stripSeedClaims(text);
  const required = [
    [/16\s*:\s*9/i, "Aspect Ratio: 16:9"],
    [/duration:\s*8 seconds/i, "Duration: 8 seconds"],
    [/motion strength:\s*0\.40/i, "Motion Strength: 0.40"],
    [/fluid motion/i, "Movement: fluid motion"],
    [/no captions/i, "No captions."],
    [/no subtitles/i, "No subtitles."],
    [/no logos/i, "No logos."],
    [/no watermarks/i, "No watermarks."],
    [/no drone/i, "No drone aircraft in sight."],
    [/attached (main )?(character|anchor|professor)/i, "Keep the main character's appearance consistent with the attached main character image."],
    [/attached[\s\S]{0,80}(background|studio|lecture hall|location)/i, "Keep the main location consistent with the attached main background image."],
  ];
  for (const [pattern, line] of required) {
    if (!pattern.test(value)) value += `\n${line}`;
  }
  if (!/reference image/i.test(value)) {
    value +=
      "\nConsistency comes from the confirmed reference images and these repeated descriptions.";
  }
  return value.trim();
}

function protectPromptLines(text) {
  const kept = [];
  const masked = String(text || "")
    .split("\n")
    .map((line) => {
      if (
        /^\s*(do not use|never use)\b/i.test(line) ||
        /^\s*Selected reference characters for this scene:/i.test(line) ||
        /^\s*- .+: use the attached reference image\./i.test(line)
      ) {
        kept.push(line);
        return `\u0000KEEP${kept.length - 1}\u0000`;
      }
      return line;
    })
    .join("\n");
  return { masked, kept };
}

function restorePromptLines(text, kept) {
  return String(text || "").replace(/\u0000KEEP(\d+)\u0000/g, (_, index) => kept[Number(index)] || "");
}

function softenForbidden(text, genre) {
  const protectedLines = protectPromptLines(text);
  let value = protectedLines.masked;
  if (genre === "news") {
    const replacements = [
      [/International Television Broadcast/gi, "modern television studio"],
      [/Global News Network/gi, "feature story"],
      [/Breaking News Graphics/gi, "documentary-style visuals"],
      [/Breaking News/gi, "feature story"],
      [/Broadcast-quality newsroom/gi, "professional studio environment"],
      [/Ultra-wide LED Wall/gi, "large LED display"],
      [/News ticker/gi, ""],
      [/news ticker/gi, ""],
      [/Scrolling captions/gi, ""],
      [/Large lower third/gi, ""],
      [/lower third/gi, ""],
      [/Headline banner/gi, ""],
      [/headline banner/gi, ""],
      [/Anchor begins broadcasting/gi, "preparing to introduce today's feature story"],
      [/broadcast ends/gi, "the anchor concludes today's feature story"],
      [/final broadcast/gi, "today's feature story"],
      [/news closing/gi, "thoughtful closing message"],
      [/program ending/gi, "the close of today's feature story"],
      [/station closing/gi, "the close of today's feature story"],
    ];
    for (const [pattern, next] of replacements) value = value.replace(pattern, next);
  } else {
    const replacements = [
      [/newsroom/gi, "lecture hall"],
      [/breaking news/gi, "academic documentary"],
      [/news ticker/gi, ""],
      [/lower[- ]third/gi, ""],
      [/headline banner/gi, ""],
      [/television studio/gi, "lecture hall"],
      [/news anchor/gi, "guest"],
      [/field reporter/gi, "guest"],
      [/현장 기자/g, "조연"],
      [/앵커/g, "교수"],
    ];
    for (const [pattern, next] of replacements) value = value.replace(pattern, next);
  }
  value = restorePromptLines(value, protectedLines.kept);
  return value.replace(/[ \t]{2,}/g, " ").replace(/\n{3,}/g, "\n\n").trim();
}

function normalizeSceneIds(value) {
  if (!Array.isArray(value)) return [];
  const ids = [];
  for (const item of value) {
    const digits = String(item ?? "").replace(/\D/g, "");
    const number = Number(digits);
    if (number >= 1 && number <= 10) {
      const id = String(number).padStart(2, "0");
      if (!ids.includes(id)) ids.push(id);
    }
  }
  return ids;
}

function memberNames(role) {
  const source = Array.isArray(role.members) && role.members.length ? role.members : [role.name];
  return source
    .map((item) => String(item || "").trim())
    .filter((name) => name && !isMainRole(name) && !isNoCharacter(name));
}

function composeGroupPrompt(members, people) {
  const lines = members.map((name) => {
    const prompt = people.get(name)?.prompt || "";
    return prompt ? `${name}: ${prompt}` : name;
  });
  return [
    "Cell-shaded anime group portrait, aspect ratio 3:4, waist-up, of these characters together in one frame on a near-solid background. Do not use 16:9. Do not use a numeric seed.",
    ...lines,
  ].join("\n");
}

function buildCharacterProposals(raw) {
  const input = Array.isArray(raw) ? raw : [];
  const people = new Map();
  const providedGroups = new Map();

  function addPerson(name, prompt, scenes) {
    const current = people.get(name) || { prompt: "", scenes: new Set() };
    if (prompt && !current.prompt) current.prompt = prompt;
    for (const scene of scenes) current.scenes.add(scene);
    people.set(name, current);
  }

  for (const role of input) {
    if (!role || role.noCharacter === true || isNoCharacter(role.name) || isMainRole(role.name)) continue;
    if (String(role.prompt || "").trim() && isNoCharacter(role.prompt)) continue;
    const members = memberNames(role);
    const scenes = normalizeSceneIds(role.sceneIds);
    if (!members.length || !scenes.length) continue;
    if (members.length >= 2) {
      const key = members.slice().sort((a, b) => a.localeCompare(b)).join("\u0001");
      const existing = providedGroups.get(key) || { prompt: "", scenes: new Set(), members: members.slice().sort((a, b) => a.localeCompare(b)) };
      if (role.prompt) existing.prompt = String(role.prompt);
      for (const scene of scenes) existing.scenes.add(scene);
      providedGroups.set(key, existing);
      for (const member of members) addPerson(member, "", scenes);
    } else {
      addPerson(members[0], String(role.prompt || ""), scenes);
    }
  }

  const sceneNames = new Map();
  for (const [name, person] of people) {
    for (const scene of person.scenes) {
      if (!sceneNames.has(scene)) sceneNames.set(scene, new Set());
      sceneNames.get(scene).add(name);
    }
  }

  const groupScenes = new Map();
  const soloScenes = new Map();
  for (const [scene, names] of sceneNames) {
    const list = [...names].sort((a, b) => a.localeCompare(b));
    if (list.length >= 2) {
      const key = list.join("\u0001");
      if (!groupScenes.has(key)) groupScenes.set(key, new Set());
      groupScenes.get(key).add(scene);
    } else if (list.length === 1) {
      const name = list[0];
      if (!soloScenes.has(name)) soloScenes.set(name, new Set());
      soloScenes.get(name).add(scene);
    }
  }

  const proposals = [];
  for (const [key, scenes] of groupScenes) {
    const members = key.split("\u0001");
    const provided = providedGroups.get(key);
    proposals.push({
      name: members.join(" & "),
      members,
      grouped: true,
      sceneIds: [...scenes].sort(),
      prompt: (provided && provided.prompt) || composeGroupPrompt(members, people),
    });
  }
  for (const [name, scenes] of soloScenes) {
    if (!scenes.size) continue;
    const person = people.get(name);
    proposals.push({
      name,
      members: [name],
      grouped: false,
      sceneIds: [...scenes].sort(),
      prompt: (person && person.prompt) || `Cell-shaded anime portrait of ${name}, aspect ratio 3:4, waist-up, near-solid background.`,
    });
  }
  proposals.sort((a, b) => {
    const scene = a.sceneIds[0].localeCompare(b.sceneIds[0]);
    return scene || a.name.localeCompare(b.name);
  });
  return proposals;
}

function proposalsFromSelection(raw) {
  const roles = [];
  for (const role of Array.isArray(raw) ? raw : []) {
    if (!role || role.noCharacter === true || isMainRole(role.name) || isNoCharacter(role.name)) continue;
    const members = memberNames(role);
    const sceneIds = normalizeSceneIds(role.sceneIds);
    const name = String(role.name || "").trim();
    if (!name || !members.length || !sceneIds.length) continue;
    roles.push({
      name,
      prompt: String(role.prompt || ""),
      sceneIds,
      members,
      grouped: role.grouped === true || members.length >= 2,
    });
  }
  return roles;
}

function selectedReferenceHeader(roles) {
  const lines = [];
  for (const role of roles) {
    const name = String(role.name || "").trim();
    if (!name) continue;
    const members = Array.isArray(role.members) ? role.members.map((item) => String(item || "").trim()).filter(Boolean) : [];
    if (role.grouped === true && members.length >= 2) {
      lines.push(`- ${name} (${members.join(", ")}): use the attached reference image.`);
    } else {
      lines.push(`- ${name}: use the attached reference image.`);
    }
  }
  if (!lines.length) return "";
  return `Selected reference characters for this scene:\n${lines.join("\n")}`;
}

function appendUnselectedCharacters(text, roles) {
  let value = String(text || "");
  const extras = [];
  for (const role of roles) {
    const name = String(role.name || "").trim();
    if (!name) continue;
    const note = `No reference image is attached for ${name}.`;
    const hasName = value.toLowerCase().includes(name.toLowerCase());
    const hasNote = value.toLowerCase().includes(note.toLowerCase());
    if (hasName && hasNote) continue;
    const appearance = String(role.prompt || "").trim();
    extras.push(`- ${name}: ${appearance}${appearance ? " " : ""}${note}`);
  }
  if (!extras.length) return value.trim();
  return `${value.trim()}\n\nCharacters in this scene without a reference image:\n${extras.join("\n")}`.trim();
}

function containsForbiddenNews(text) {
  const value = String(text || "");
  return FORBIDDEN_NEWS.some((phrase) => value.includes(phrase));
}

function sceneId(value, index) {
  const digits = String(value ?? "").replace(/\D/g, "");
  const number = Number(digits);
  if (number >= 1 && number <= 10) return String(number).padStart(2, "0");
  return String(index + 1).padStart(2, "0");
}

module.exports = {
  isMainRole,
  isNoCharacter,
  stripSeedClaims,
  ensureVideoSettings,
  softenForbidden,
  containsForbiddenNews,
  sceneId,
  buildCharacterProposals,
  proposalsFromSelection,
  selectedReferenceHeader,
  appendUnselectedCharacters,
};
