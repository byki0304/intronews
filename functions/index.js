const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");
const crypto = require("crypto");
const { templateFor } = require("./prompts");
const rules = require("./prompt_rules");

setGlobalOptions({
  region: "asia-northeast3",
  timeoutSeconds: 540,
  memory: "1GiB",
});

admin.initializeApp({
  storageBucket: "intronews.firebasestorage.app",
});

const db = admin.firestore();
const bucket = admin.storage().bucket();
const ADMIN_EMAILS = new Set(["nfriend02@naver.com", "byki@daum.net"]);
const ADMIN_PHONE = "821052799244";
const PHONE_DOMAIN = "phone.intronews.app";
const MAX_PROPOSED = 12;
const MAX_GENERATED = 9;

let allowlistReady = null;

function ensureAllowlist() {
  if (!allowlistReady) {
    const admins = [
      ...[...ADMIN_EMAILS].map((id) => ({ id, kind: "email" })),
      { id: ADMIN_PHONE, kind: "phone" },
    ];
    allowlistReady = Promise.all(
      admins.map(async (adminUser) => {
        const ref = db.collection("allowlist").doc(adminUser.id);
        const snap = await ref.get();
        if (!snap.exists) {
          await ref.set({ role: "admin", active: true, kind: adminUser.kind });
        }
      }),
    ).catch((error) => {
      allowlistReady = null;
      throw error;
    });
  }
  return allowlistReady;
}

function phoneFromAuthEmail(email) {
  const escaped = PHONE_DOMAIN.replace(/\./g, "\\.");
  const match = String(email || "").toLowerCase().match(new RegExp(`^p(\\d+)@${escaped}$`));
  return match ? match[1] : null;
}

function isAdminAccount(email, phone) {
  if (email && ADMIN_EMAILS.has(String(email).toLowerCase())) return true;
  return phone === ADMIN_PHONE;
}

function nicknameProblem(value) {
  const name = String(value || "").trim();
  if (!/^[\p{L}\p{N}]{1,16}$/u.test(name)) {
    return "닉네임은 16자 이내의 문자와 숫자만 사용할 수 있습니다.";
  }
  return null;
}

function newAdminId() {
  return crypto.randomBytes(18).toString("hex");
}

async function ensureAdminRecord(uid) {
  const ref = db.collection("adminRecords").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set({
      adminId: newAdminId(),
      withdrawn: false,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
}

function geminiKey() {
  const key = process.env.GEMINI_API_KEY;
  if (!key || !String(key).trim()) {
    throw new HttpsError(
      "failed-precondition",
      "Functions 환경 변수 GEMINI_API_KEY가 필요합니다",
    );
  }
  return String(key).trim();
}

function parseJson(text) {
  const trimmed = String(text || "").replace(/```json|```/gi, "").trim();
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start < 0 || end < start) {
    console.error("Gemini JSON missing", trimmed.length, trimmed.slice(0, 180));
    throw new HttpsError("internal", "Gemini 응답을 읽지 못했습니다. 다시 실행해 주세요.");
  }
  try {
    return JSON.parse(trimmed.slice(start, end + 1));
  } catch (error) {
    console.error("Gemini JSON invalid", trimmed.length, trimmed.slice(-180));
    throw new HttpsError("internal", "Gemini 응답을 읽지 못했습니다. 다시 실행해 주세요.");
  }
}

async function gemini(model, body, key) {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": key,
      },
      body: JSON.stringify(body),
    },
  );
  if (!response.ok) {
    const detail = (await response.text()).replaceAll(key, "[redacted]");
    console.error("Gemini request failed", response.status, detail.slice(0, 400));
    if (response.status === 429 && /free_tier/.test(detail) && /limit:\s*0/.test(detail)) {
      throw new HttpsError(
        "failed-precondition",
        "이 모델은 Gemini API 무료 한도가 0입니다. Google AI Studio에서 이 키의 프로젝트에 결제 계정을 연결해 주세요.",
      );
    }
    throw new HttpsError("internal", "Gemini 호출에 실패했습니다. 다시 실행해 주세요.");
  }
  return response.json();
}

function textFrom(json) {
  const parts = json?.candidates?.[0]?.content?.parts || [];
  return parts
    .filter((part) => part.thought !== true && part.text)
    .map((part) => part.text)
    .join("\n")
    .trim();
}

function retryableTextError(error) {
  const message = String(error?.message || "");
  return (
    message.includes("Gemini 응답을 읽지 못했습니다") ||
    message.includes("Gemini가 빈 응답을 보냈습니다")
  );
}

async function generateTextOnce(system, parts) {
  const key = geminiKey();
  const model = process.env.GEMINI_TEXT_MODEL || "gemini-3.8-flash";
  const json = await gemini(
    model,
    {
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: "user", parts }],
      generationConfig: {
        responseMimeType: "application/json",
        thinkingConfig: { thinkingLevel: "high" },
      },
    },
    key,
  );
  const text = textFrom(json);
  if (!text) {
    throw new HttpsError("internal", "Gemini가 빈 응답을 보냈습니다. 다시 실행해 주세요.");
  }
  return parseJson(text);
}

async function generateText(system, parts) {
  let lastError;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      return await generateTextOnce(system, parts);
    } catch (error) {
      lastError = error;
      if (attempt === 1 || !retryableTextError(error)) throw error;
      console.error("Gemini text response unreadable, retrying once");
    }
  }
  throw lastError;
}

async function generateImage(prompt) {
  const key = geminiKey();
  const model = process.env.GEMINI_IMAGE_MODEL || "gemini-3-pro-image";
  const text = `${prompt}

Vertical portrait, aspect ratio 3:4, waist-up or full body, near-solid plain background.
Cell-shaded anime character. Do not create a 16:9 frame. No text, no logo, no watermark.`;
  const payloads = [
    {
      contents: [{ role: "user", parts: [{ text }] }],
      generationConfig: {
        responseModalities: ["IMAGE"],
        imageConfig: { aspectRatio: "3:4", imageSize: "2K" },
      },
    },
    {
      contents: [{ role: "user", parts: [{ text }] }],
      generationConfig: { responseModalities: ["IMAGE"] },
    },
  ];
  let lastError = null;
  for (const body of payloads) {
    try {
      const json = await gemini(model, body, key);
      const parts = json?.candidates?.[0]?.content?.parts || [];
      for (const part of parts) {
        const inline = part.inlineData || part.inline_data;
        if (inline?.data) {
          return {
            bytes: Buffer.from(inline.data, "base64"),
            mime: inline.mimeType || inline.mime_type || "image/png",
          };
        }
      }
      lastError = new HttpsError("internal", "캐릭터 이미지를 만들지 못했습니다. 다시 실행해 주세요.");
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

async function loadProject(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  const projectId = request.data?.projectId;
  if (!projectId) throw new HttpsError("invalid-argument", "프로젝트가 없습니다.");
  const ref = db.collection("projects").doc(projectId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "프로젝트를 찾을 수 없습니다.");
  const project = snap.data();
  if (project.ownerUid !== request.auth.uid) {
    throw new HttpsError("permission-denied", "소유자만 생성할 수 있습니다.");
  }
  const fileSnap = await ref.collection("files").get();
  const files = fileSnap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((file) => file.included !== false)
    .sort((a, b) => (a.order || 0) - (b.order || 0));
  return { ref, project, files };
}

async function loadScenes(ref) {
  const snap = await ref.collection("scenes").get();
  return snap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .sort((a, b) => a.id.localeCompare(b.id));
}

async function loadRoles(ref) {
  const snap = await ref.collection("characters").get();
  return snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

function assertFiles(project, files) {
  if (!files.length) throw new HttpsError("failed-precondition", "PDF가 필요합니다.");
  if (project.pdfMode === "single" && files.length !== 1) {
    throw new HttpsError("failed-precondition", "PDF 1개 모드입니다.");
  }
  if (files.length > 10) throw new HttpsError("failed-precondition", "PDF는 최대 10개입니다.");
}

async function pdfParts(files) {
  const parts = [];
  for (const file of files) {
    const [buffer] = await bucket.file(file.storagePath).download();
    parts.push({ text: `PDF file name: ${file.name}` });
    parts.push({
      inlineData: {
        mimeType: "application/pdf",
        data: buffer.toString("base64"),
      },
    });
  }
  return parts;
}

function namesOf(files) {
  return files.map((file) => file.name);
}

function sourceNames(value, files) {
  const known = namesOf(files);
  const picked = (Array.isArray(value) ? value : value ? [value] : [])
    .map(String)
    .filter((name) => known.includes(name));
  return picked.length ? picked : known.slice(0, 1);
}

function staleAfter(project, fromStep) {
  const produced = fromStep + 1;
  if ((project.currentStep || 1) > produced && produced + 1 <= 8) return produced + 1;
  return null;
}

async function advance(ref, project, fromStep, extra = {}) {
  await ref.update({
    ...extra,
    currentStep: Math.max(project.currentStep || 1, fromStep + 1),
    staleFromStep: staleAfter(project, fromStep),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

function storyParts(project, scenes, roles) {
  return [
    {
      text: JSON.stringify({
        title: project.title || "",
        directionNote: project.directionNote || "",
        synopsis: project.synopsis || "",
        scenes,
        supportingRoles: roles,
      }),
    },
  ];
}

async function assetPath(assetId) {
  if (!assetId) return null;
  const snap = await db.collection("assetLibrary").doc(assetId).get();
  return snap.exists ? snap.data().storagePath || null : null;
}

async function selectedReferences(project) {
  const mainCharacter = await assetPath(project.mainCharacterId);
  const mainBackground = await assetPath(project.mainBackgroundId);
  const extras = [];
  for (const id of [...(project.extraCharacterIds || []), ...(project.extraBackgroundIds || [])]) {
    const path = await assetPath(id);
    if (path) extras.push(path);
  }
  return { mainCharacter, mainBackground, extras };
}

function selectedRolePath(role) {
  if (role.selectedIndex === -2) return null;
  if (role.selectedIndex === -1 && role.replacementPath) return role.replacementPath;
  if (Number.isInteger(role.selectedIndex) && role.selectedIndex >= 0 && role.imagePaths?.[role.selectedIndex]) {
    return role.imagePaths[role.selectedIndex];
  }
  if (role.replacementPath && (role.selectedIndex === undefined || role.selectedIndex === null)) {
    return role.replacementPath;
  }
  return null;
}

function finishPrompt(text, genre) {
  return rules.ensureVideoSettings(rules.softenForbidden(text, genre));
}

function roleInUse(role) {
  return role.generate === true && selectedRolePath(role);
}

function composeScenePrompt(text, genre, sceneId, roles) {
  const inScene = roles.filter((role) => (role.sceneIds || []).includes(sceneId));
  const selected = inScene.filter(roleInUse);
  const unselected = inScene.filter((role) => !roleInUse(role));
  const body = rules.appendUnselectedCharacters(finishPrompt(text, genre), unselected);
  const header = rules.selectedReferenceHeader(selected);
  return header ? `${header}\n\n${body}` : body;
}

exports.syncUser = onCall({ timeoutSeconds: 60, memory: "256MiB" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  await ensureAllowlist();
  const uid = request.auth.uid;
  const provider = request.auth.token?.firebase?.sign_in_provider;
  const existing = await db.collection("users").doc(uid).get();
  if (existing.exists && existing.data().withdrawn === true) {
    throw new HttpsError("permission-denied", "탈퇴한 계정입니다.");
  }
  if (provider === "anonymous") {
    await admin.auth().setCustomUserClaims(uid, { role: "member" });
    await db.collection("users").doc(uid).set(
      { email: null, phone: null, role: "member", authProvider: "anonymous" },
      { merge: true },
    );
    return { role: "member", authProvider: "anonymous", email: null, phone: null, nickname: null };
  }
  const authEmail = String(request.auth.token.email || "").toLowerCase();
  const phone = phoneFromAuthEmail(authEmail);
  const email = phone ? null : authEmail || null;
  const authProvider = provider === "google.com" ? "google" : phone ? "phone" : "password";
  const role = isAdminAccount(email, phone) ? "admin" : "member";
  await admin.auth().setCustomUserClaims(uid, { role });
  await db.collection("users").doc(uid).set(
    { email, phone, role, authProvider },
    { merge: true },
  );
  const profile = (await db.collection("users").doc(uid).get()).data() || {};
  return {
    role,
    authProvider,
    email,
    phone,
    nickname: profile.nickname || null,
  };
});

exports.saveNickname = onCall({ timeoutSeconds: 60, memory: "256MiB" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (request.auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("failed-precondition", "비로그인 닉네임은 저장되지 않습니다.");
  }
  const name = String(request.data?.nickname || "").trim();
  const problem = nicknameProblem(name);
  if (problem) throw new HttpsError("invalid-argument", problem);
  await db.collection("users").doc(request.auth.uid).set(
    { nickname: name, nicknameKey: name.toLocaleLowerCase() },
    { merge: true },
  );
  await ensureAdminRecord(request.auth.uid);
  return { ok: true };
});

exports.ensurePrivateRecord = onCall({ timeoutSeconds: 60, memory: "256MiB" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  await ensureAdminRecord(request.auth.uid);
  return { ok: true };
});

exports.deleteAccount = onCall({ timeoutSeconds: 60, memory: "256MiB" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  const uid = request.auth.uid;
  await db.collection("adminRecords").doc(uid).set(
    {
      adminId: `withdrawn_${newAdminId()}`,
      withdrawn: true,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await db.collection("users").doc(uid).set(
    {
      email: null,
      phone: null,
      nickname: null,
      nicknameKey: null,
      role: "withdrawn",
      authProvider: "withdrawn",
      withdrawn: true,
    },
    { merge: true },
  );
  await admin.auth().setCustomUserClaims(uid, { role: "withdrawn" });
  await admin.auth().deleteUser(uid);
  return { ok: true };
});

exports.generateOutline = onCall(async (request) => {
  const { ref, project, files } = await loadProject(request);
  assertFiles(project, files);
  const parsed = await generateText(
    templateFor("outline", project.genre, project.pdfMode),
    [
      { text: `Direction note:\n${project.directionNote || ""}` },
      ...(await pdfParts(files)),
    ],
  );
  const input = Array.isArray(parsed.scenes) ? parsed.scenes : [];
  if (!input.length) {
    throw new HttpsError("internal", "장면 10개를 만들지 못했습니다. 다시 실행해 주세요.");
  }
  const batch = db.batch();
  for (let index = 0; index < 10; index += 1) {
    const id = String(index + 1).padStart(2, "0");
    const found = input.find((scene, item) => rules.sceneId(scene.id, item) === id) || {};
    batch.set(
      ref.collection("scenes").doc(id),
      {
        outline: {
          title: String(found.title || ""),
          summary: String(found.summary || ""),
        },
        sourcePdfNames: sourceNames(found.sourcePdfNames, files),
        status: "outline",
      },
      { merge: true },
    );
  }
  await batch.commit();
  await advance(ref, project, 1, { synopsis: String(parsed.synopsis || "") });
  return { ok: true };
});

exports.generateCards = onCall(async (request) => {
  const { ref, project, files } = await loadProject(request);
  const scenes = await loadScenes(ref);
  const parsed = await generateText(
    templateFor("cards", project.genre, project.pdfMode),
    storyParts(project, scenes, []),
  );
  const input = Array.isArray(parsed.scenes) ? parsed.scenes : [];
  if (!input.length) {
    throw new HttpsError("internal", "장면 카드를 만들지 못했습니다. 다시 실행해 주세요.");
  }
  const batch = db.batch();
  for (let index = 0; index < 10; index += 1) {
    const id = String(index + 1).padStart(2, "0");
    const found = input.find((scene, item) => rules.sceneId(scene.id, item) === id) || {};
    const previous = scenes.find((scene) => scene.id === id) || {};
    batch.set(
      ref.collection("scenes").doc(id),
      {
        card: {
          title: String(found.title || previous.outline?.title || ""),
          description: String(found.description || ""),
          characters: String(found.characters || ""),
          region: String(found.region || ""),
          place: String(found.place || ""),
          background: String(found.background || ""),
          era: String(found.era || ""),
          year: String(found.year || ""),
          action: String(found.action || ""),
          dialogue: String(found.dialogue || ""),
          narration: String(found.narration || ""),
          cameraMove: String(found.cameraMove || ""),
          shotChange: String(found.shotChange || ""),
          mood: String(found.mood || ""),
          sfx: String(found.sfx || ""),
          bgm: String(found.bgm || ""),
          generationNotes: String(found.generationNotes || ""),
          visualStorytellingGoal: String(found.visualStorytellingGoal || ""),
          emotionalTone: String(found.emotionalTone || ""),
          scenePurpose: String(found.scenePurpose || ""),
          directorIntent: String(found.directorIntent || ""),
          timeOfDay: String(found.timeOfDay || ""),
          weather: String(found.weather || ""),
          lighting: String(found.lighting || ""),
          colorTone: String(found.colorTone || ""),
          visualFocus: String(found.visualFocus || ""),
          transitionToNext: String(found.transitionToNext || ""),
        },
        sourcePdfNames: sourceNames(found.sourcePdfNames || previous.sourcePdfNames, files),
        status: "card",
      },
      { merge: true },
    );
  }
  await batch.commit();
  await advance(ref, project, 2);
  return { ok: true };
});

function imageExtension(mime) {
  const type = String(mime || "");
  if (type.includes("jpeg") || type.includes("jpg")) return "jpg";
  if (type.includes("webp")) return "webp";
  return "png";
}

async function writeRoleImages(ref, project, roleId, prompt) {
  const paths = [];
  for (let index = 0; index < 1; index += 1) {
    const image = await generateImage(prompt);
    const storagePath = `users/${project.ownerUid}/projects/${ref.id}/characters/${roleId}/${Date.now()}-${index}.${imageExtension(image.mime)}`;
    await bucket.file(storagePath).save(image.bytes, {
      contentType: image.mime,
      resumable: false,
    });
    paths.push(storagePath);
  }
  return paths;
}

async function writeProposals(ref, project, roles) {
  const existing = await ref.collection("characters").get();
  const batch = db.batch();
  existing.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  for (let index = 0; index < roles.length; index += 1) {
    const role = roles[index];
    await ref.collection("characters").doc(`role-${index + 1}`).set({
      name: role.name,
      prompt: role.prompt,
      sceneIds: role.sceneIds,
      members: role.members,
      grouped: role.grouped === true,
      generate: false,
      imagePaths: [],
      selectedIndex: null,
      replacementPath: null,
    });
  }
  await advance(ref, project, 3);
}

exports.generateCharacters = onCall(async (request) => {
  const { ref, project } = await loadProject(request);
  const scenes = await loadScenes(ref);
  let roles;
  if (Array.isArray(request.data?.selectedRoles)) {
    roles = rules.proposalsFromSelection(request.data.selectedRoles);
    if (roles.length > MAX_PROPOSED) {
      throw new HttpsError("invalid-argument", "제안은 12개까지입니다.");
    }
  } else {
    const parsed = await generateText(
      templateFor("characters", project.genre, project.pdfMode),
      storyParts(project, scenes, []),
    );
    roles = rules.buildCharacterProposals(parsed.roles);
  }
  if (roles.length > MAX_PROPOSED) {
    return {
      ok: false,
      code: "TOO_MANY_ROLES",
      max: MAX_PROPOSED,
      roles: roles.map((role, index) => ({ id: String(index), ...role })),
    };
  }
  await writeProposals(ref, project, roles);
  return { ok: true, count: roles.length };
});

exports.generateSelectedCharacters = onCall(async (request) => {
  const { ref, project } = await loadProject(request);
  const ids = [...new Set((Array.isArray(request.data?.roleIds) ? request.data.roleIds : []).map(String))];
  if (ids.length > MAX_GENERATED) {
    throw new HttpsError("invalid-argument", "캐릭터는 9개까지 생성할 수 있습니다.");
  }
  const chosen = new Set(ids);
  const snap = await ref.collection("characters").get();
  for (const doc of snap.docs) {
    const data = doc.data();
    const use = chosen.has(doc.id);
    let imagePaths = Array.isArray(data.imagePaths) ? data.imagePaths : [];
    if (use && imagePaths.length === 0) {
      imagePaths = await writeRoleImages(ref, project, doc.id, data.prompt || "");
    }
    await doc.ref.update({
      generate: use,
      imagePaths,
    });
  }
  if ((project.currentStep || 1) > 4) {
    const nextStale = project.staleFromStep == null ? 5 : Math.min(project.staleFromStep, 5);
    await ref.update({
      staleFromStep: nextStale,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  return { ok: true, count: ids.length };
});

exports.regenerateRoleImages = onCall(async (request) => {
  const { ref, project } = await loadProject(request);
  const roleId = String(request.data?.roleId || "");
  const roleRef = ref.collection("characters").doc(roleId);
  const role = await roleRef.get();
  if (!role.exists) throw new HttpsError("not-found", "역할을 찾을 수 없습니다.");
  const imagePaths = await writeRoleImages(ref, project, roleId, role.data().prompt || "");
  await roleRef.update({
    imagePaths,
    selectedIndex: null,
    replacementPath: null,
  });
  if ((project.currentStep || 1) > 4) {
    const nextStale = project.staleFromStep == null ? 5 : Math.min(project.staleFromStep, 5);
    await ref.update({
      staleFromStep: nextStale,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  return { ok: true };
});

exports.generateBody = onCall(async (request) => {
  const { ref, project } = await loadProject(request);
  const scenes = await loadScenes(ref);
  const roles = await loadRoles(ref);
  if (roles.some((role) => role.generate === true && !selectedRolePath(role))) {
    throw new HttpsError("failed-precondition", "생성한 조연의 선택 이미지가 필요합니다.");
  }
  const refs = await selectedReferences(project);
  const parsed = await generateText(
    templateFor("body", project.genre, project.pdfMode),
    storyParts(project, scenes, roles),
  );
  const input = Array.isArray(parsed.scenes) ? parsed.scenes : [];
  if (input.length < 8) {
    throw new HttpsError("internal", "본편 프롬프트 8개를 만들지 못했습니다. 다시 실행해 주세요.");
  }
  const batch = db.batch();
  for (let number = 2; number <= 9; number += 1) {
    const id = String(number).padStart(2, "0");
    const found = input.find((scene, index) => rules.sceneId(scene.id, index) === id) || {};
    const mapped = roles.filter((role) => (role.sceneIds || []).includes(id) && roleInUse(role));
    const referenceAssetIds = [
      refs.mainCharacter,
      refs.mainBackground,
      ...refs.extras,
      ...mapped.map(selectedRolePath),
    ].filter(Boolean);
    batch.set(
      ref.collection("scenes").doc(id),
      {
        flowPrompt: composeScenePrompt(found.flowPrompt || "", project.genre, id, roles),
        continuityHint: String(found.continuityHint || ""),
        characterMapping: mapped.map((role) => ({
          roleId: role.id,
          name: role.name,
          storagePath: selectedRolePath(role),
        })),
        referenceAssetIds: [...new Set(referenceAssetIds)],
        status: "prompt",
      },
      { merge: true },
    );
  }
  await batch.commit();
  await advance(ref, project, 4);
  return { ok: true };
});

async function writeEdge(request, kind, sceneId, fromStep) {
  const { ref, project } = await loadProject(request);
  const scenes = await loadScenes(ref);
  const roles = await loadRoles(ref);
  const refs = await selectedReferences(project);
  const parsed = await generateText(
    templateFor(kind, project.genre, project.pdfMode),
    storyParts(project, scenes, roles),
  );
  const mapped = roles.filter((role) => (role.sceneIds || []).includes(sceneId) && roleInUse(role));
  const referenceAssetIds = [
    refs.mainCharacter,
    refs.mainBackground,
    ...refs.extras,
    ...mapped.map(selectedRolePath),
  ].filter(Boolean);
  await ref.collection("scenes").doc(sceneId).set(
    {
      flowPrompt: composeScenePrompt(parsed.flowPrompt || "", project.genre, sceneId, roles),
      continuityHint: String(parsed.continuityHint || ""),
      characterMapping: mapped.map((role) => ({
        roleId: role.id,
        name: role.name,
        storagePath: selectedRolePath(role),
      })),
      referenceAssetIds: [...new Set(referenceAssetIds)],
      status: "prompt",
    },
    { merge: true },
  );
  await advance(ref, project, fromStep);
  return { ok: true };
}

exports.generateOpening = onCall(async (request) => writeEdge(request, "opening", "01", 5));
exports.generateClosing = onCall(async (request) => writeEdge(request, "closing", "10", 6));

exports.generateMusic = onCall(async (request) => {
  const { ref, project } = await loadProject(request);
  const scenes = await loadScenes(ref);
  const parsed = await generateText(
    templateFor("music", project.genre, project.pdfMode),
    storyParts(project, scenes, []),
  );
  const promptA = String(parsed.promptA || "").trim();
  const promptB = String(parsed.promptB || "").trim();
  if (!promptA || !promptB) {
    throw new HttpsError("internal", "음악 프롬프트 2개를 만들지 못했습니다. 다시 실행해 주세요.");
  }
  await ref.collection("music").doc("score").set(
    {
      promptA,
      promptB,
      audioA: null,
      audioB: null,
    },
    { merge: true },
  );
  await advance(ref, project, 7);
  return { ok: true };
});
