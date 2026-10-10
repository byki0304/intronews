const NEWS_OPENING_COMMON = `Create a premium cinematic opening for a modern television news program.

Use the attached HSBS News Studio image as visual reference.

Keep the main anchor's appearance consistent with the attached character image.

The studio is elegant, contemporary, spacious, and professionally designed with clean architectural lines, soft indirect lighting, premium materials, realistic reflections, and a large LED display wall.

The anchor sits calmly behind the modern news desk, preparing to introduce today's feature story with a confident and welcoming expression.

The camera begins from the anchor's left side, slowly moves toward the front, then finishes with a smooth gentle dolly in.

The anchor is rendered in high-quality cell-shaded anime style.

The studio environment is rendered in photorealistic 4K with cinematic lighting, premium interior details, physically accurate reflections, realistic textures, and smooth natural camera movement.

Aspect Ratio: 16:9

Motion Strength: 0.40

Duration: 8 seconds

Movement: fluid motion

No captions.

No subtitles.

No logos.

No watermarks.

No news ticker.

No lower third.

No headline banner.

No drone aircraft in sight.

Consistency comes from the confirmed reference images and these repeated descriptions.`;

const NEWS_CLOSING_COMMON = `Create a premium cinematic closing for a modern television feature story.

Use the attached HSBS News Studio image as visual reference.

Keep the main anchor's appearance consistent with the attached character image.

The studio remains elegant and contemporary, with soft indirect lighting, premium materials, realistic reflections, and a large LED display wall.

The anchor wraps up today's story with a calm, thoughtful closing message.

The camera starts from a frontal view or a wide view and moves closer toward the anchor.

The anchor is rendered in high-quality cell-shaded anime style.

The studio environment is rendered in photorealistic 4K.

Aspect Ratio: 16:9

Motion Strength: 0.40

Duration: 8 seconds

Movement: fluid motion

No captions.

No subtitles.

No logos.

No watermarks.

No news ticker.

No lower third.

No headline banner.

No drone aircraft in sight.

The anchor's final spoken line is exactly: "Thank you for joining us. I am HS. Have a good day."

Consistency comes from the confirmed reference images and these repeated descriptions.

Do not reuse the opening camera move. Do not say the anchor is preparing to introduce the story.`;

const LECTURE_OPENING_COMMON = `Create a premium cinematic opening for a modern MBA lecture documentary program.

Use the attached lecture hall image as the visual reference for the environment.

Keep Professor HS's appearance fully consistent with the attached character reference image throughout the scene.

The lecture hall has about 150 tiered seats, windows on both sides overlooking a green campus, a large white board at the front, and a sleek digital lectern.

Professor HS stands behind the digital lectern and briefly introduces today's lecture.

The camera begins from the professor's left side, moves toward the front with a gentle dolly-in, and ends as he presses a remote.

The white board becomes the presentation screen. The camera moves forward until the screen fills the frame and the next shot can continue inside that image.

Professor HS is rendered in high-quality cell-shaded anime style.

The lecture hall is rendered in photorealistic 4K.

Aspect Ratio: 16:9

Motion Strength: 0.40

Duration: 8 seconds

Movement: fluid motion

No captions.

No subtitles.

No on-screen text.

No logos.

No watermarks.

No drone aircraft in sight.

Use academic documentary, lecture hall, and presentation screen language.

Do not use television newsroom, broadcast, ticker, lower-third, or headline-banner language.

Consistency comes from the confirmed reference images and these repeated descriptions.`;

const LECTURE_CLOSING_COMMON = `Create a premium cinematic closing for a modern MBA lecture documentary program.

Use the attached lecture hall image as the visual reference.

Keep Professor HS's appearance fully consistent with the attached character reference image.

This is the return from the documentary. Scene 10, not Scene 09, comes back to the lecture hall.

The presentation image settles onto the white board, then the board clears. Professor HS is at the digital lectern, facing the students, and finishes today's lecture.

The camera begins on a frontal view or a wide view of the hall and moves closer to Professor HS.

The hall still shows about 150 tiered seats, windows on both sides, the white board, and the digital lectern.

Professor HS is rendered in high-quality cell-shaded anime style.

The lecture hall is rendered in photorealistic 4K.

Aspect Ratio: 16:9

Motion Strength: 0.40

Duration: 8 seconds

Movement: fluid motion

No captions.

No subtitles.

No on-screen text.

No logos.

No watermarks.

No drone aircraft in sight.

The professor's final spoken line is exactly: "This is for today. Thank you."

Do not copy the opening camera path, the remote-press entrance, or the sentence that sends the camera into the documentary.

Use academic documentary language. Do not use newsroom or broadcast language.

Consistency comes from the confirmed reference images and these repeated descriptions.`;

const TECHNICAL = `Technical settings for every video prompt:
Aspect Ratio: 16:9
Duration: 8 seconds
Motion Strength: 0.40
Movement: fluid motion
People are cell-shaded animation. Backgrounds and props are photorealistic 4K.
Dialogue is English. Narration is voice-over. The narrator is never seen.
No captions, subtitles, logos, watermarks, tickers, lower thirds, or headline banners.
No drone aircraft in sight.
Do not say that a numeric seed guarantees the same video.
Keep consistency by repeating the confirmed reference-image instructions.`;

function sourceLine(genre, pdfMode) {
  if (genre === "news" && pdfMode === "single") {
    return "News Intro만들기(1). One PDF. The broadcaster is HS of HS Broadcasting System, in a modern television studio.";
  }
  if (genre === "news") {
    return "News Intro만들기(2). PDFs are ordered, up to 10. Read them in order. Still make exactly 10 scenes, not 10 scenes per file.";
  }
  if (pdfMode === "single") {
    return "Lecture Intro만들기(1). One PDF. Professor HS teaches in the lecture hall described below.";
  }
  return "Lecture Intro만들기(2). PDFs are ordered lecture materials, up to 10. Read them in order. Still make exactly 10 scenes. Do not label the files as news.";
}

function hallLine() {
  return "The lecture hall has about 150 tiered seats, windows on both sides, a white board, and a digital lectern.";
}

function sharedRules(genre) {
  if (genre === "news") {
    return `Use feature story, documentary-style, and modern television studio language.
Never use: International Television Broadcast, Global News Network, Breaking News, news ticker, lower third, headline banner, broadcast-quality newsroom.
The main anchor HS is already photographed. Do not invent a new main-anchor prompt.
News music must cover Scene 01 through Scene 10 as one 120-second cue.
Do not write a Transition Prompt. Connection belongs in each scene's Continuity Hint.`;
  }
  return `Use academic documentary, lecture hall, and presentation screen language.
Never use broadcast newsroom language, news anchors, or field reporters.
${hallLine()}
Documentary scenes are pictures inside the lecture. The return to the lecture hall is Scene 10, not Scene 09.
The main professor HS is already photographed. Do not invent a new prompt for Professor HS.
Music covers Scene 01 through Scene 10 as one 120-second cue.
Do not write a Transition Prompt. Connection belongs in each scene's Continuity Hint.
Direction examples must stay inside the lecture. Do not ask for a Japanese or Caucasian field reporter, and do not cut back to a studio anchor in Scene 06.`;
}

function templateFor(kind, genre, pdfMode) {
  const header = `${sourceLine(genre, pdfMode)}
Generator: Gemini.
${sharedRules(genre)}
${TECHNICAL}`;

  if (kind === "outline") {
    return `${header}

Read the attached PDF files and the direction note.
Write a synopsis for the audience, then exactly 10 scenes:
Scene 01 opening, Scenes 02-09 documentary body, Scene 10 closing.
Each scene will later become an 8-second 16:9 video. The master is about 80 seconds.
For every scene, name the source PDF file names you actually used.
Opening and closing stay in the ${genre === "news" ? "HSBS studio" : "lecture hall"}.
Body scenes carry the story. Keep continuity between neighbors.

News opening camera, when genre is news: start at the anchor's left, move to the front, then dolly in as the report begins.
News closing, when genre is news: return to the studio, finish today's story, camera from the front or a wide view moving closer, and end on the line "Thank you for joining us. I am HS. Have a good day."
Lecture opening, when genre is lecture: start at the digital lectern, brief the hall, press the remote, and let the white board become the presentation screen.
Lecture closing, when genre is lecture: Scene 10 returns to the lectern and ends on "This is for today. Thank you."

Return JSON only:
{"synopsis":"","scenes":[{"id":"01","title":"","summary":"","sourcePdfNames":["file.pdf"]}]}
Exactly 10 scenes with ids 01 through 10. Write synopsis, title, and summary in Korean.`;
  }

  if (kind === "cards") {
    return `${header}

Turn the synopsis and outlines into 10 structured scene cards. Keep the same story.
Write the card text in Korean so an editor can revise it.
If a scene needs no person, set characters to "캐릭터 없음".
If a scene needs no spoken line, set dialogue to "대사 없음".
If narration is unnecessary, set narration to "없음".
Put the source PDF file names on every card.
${genre === "lecture" ? "Include the lecture card fields. The documentary return is Scene 10." : "News cards use the studio for 01 and 10 and the field for 02-09."}

Return JSON only:
{"scenes":[{"id":"01","title":"","description":"","characters":"","region":"","place":"","background":"","era":"","year":"","action":"","dialogue":"","narration":"","cameraMove":"","shotChange":"","mood":"","sfx":"","bgm":"","generationNotes":"","visualStorytellingGoal":"","emotionalTone":"","scenePurpose":"","directorIntent":"","timeOfDay":"","weather":"","lighting":"","colorTone":"","visualFocus":"","transitionToNext":"","sourcePdfNames":["file.pdf"]}]}`;
  }

  if (kind === "characters") {
    return `${header}

From the scene cards, write English Gemini image prompts for supporting roles only.
Exclude the main character HS / Professor HS.
Exclude any role whose card says 캐릭터 없음 or no character.
The same person in several scenes is one role, with one prompt and the list of scene ids.
Propose only characters the scenes actually need. Never add extra characters to reach a count. Never return more than 12 roles.
When two or more supporting characters appear together in the same scene, return one grouped role for that group, not separate portraits. One grouped role has one prompt, members listing every person, grouped true, and the scene ids where that same group appears together. The prompt must show all of them together in one 3:4 cell-shaded frame.
Do not also return a solo role for a person who appears only inside that group.
If a person also appears alone in a different scene, return an additional solo role for those solo scenes only.
Describe ethnicity, gender, country or region, era, age, wardrobe, face, and gesture.
Cell-shaded anime character. Portrait 3:4, waist-up or full body, near-solid background. Do not ask for 16:9.
Make the prompt safe and specific. Do not use a numeric seed.
There is no separate transition character.

Return JSON only:
{"roles":[{"name":"","prompt":"","sceneIds":["02"],"members":[""],"grouped":false,"noCharacter":false}]}
If there are no supporting roles, return {"roles":[]}.`;
  }

  if (kind === "body") {
    return `${header}

Write English Google Flow prompts for Scenes 02 through 09 only.
Each prompt includes, in order: Scene number, Scene Title, Scene Purpose, Required Character, Character Mapping, Background Prompt, Google Flow Prompt, Dialogue, Voice-over, Sound Design, Editing Suggestion, Continuity Hint, Generation Settings.
Dialogue is English. Voice-over is English and the narrator is never seen.
Say that the main character image and the main background image must be kept.
Do not write a "Selected reference characters for this scene" header. The app adds that header for supporting roles that have a confirmed reference image.
For a supporting role in the scene that has no confirmed reference image, describe ethnicity, gender, age, wardrobe, and face, and include the sentence "No reference image is attached for {name}."
Continuity Hint links this scene to the previous and next scene. Do not write a separate transition prompt.
${genre === "lecture"
      ? `Scene 02 begins as a continuation of the lecture-hall presentation screen.
At the end of Scene 09, prepare a dissolve that returns to Professor HS in Scene 10. Do not say the return happens in Scene 09.`
      : "Body scenes leave the studio for the story location, then hand continuity toward the studio closing in Scene 10."}

Generation settings inside every prompt:
Aspect Ratio: 16:9
Duration: 8 seconds
Motion Strength: 0.40
Movement: fluid motion
No drone aircraft in sight.

Return JSON only:
{"scenes":[{"id":"02","flowPrompt":"","continuityHint":"","characterMapping":[{"name":"","sceneIds":["02"]}]}]}
Exactly the eight ids 02,03,04,05,06,07,08,09.`;
  }

  if (kind === "opening") {
    const common = genre === "news" ? NEWS_OPENING_COMMON : LECTURE_OPENING_COMMON;
    return `${header}

Write the Scene 01 opening prompt in English for Google Flow.
Use this common block, then a custom block for today's story. Do not contradict the common block.
Do not write a "Selected reference characters for this scene" header. If supportingRoles lists someone for scene 01 without a selected image, describe that person's appearance and say no reference image is attached.

COMMON BLOCK:
${common}

Custom block: today's story, the screen content, the spoken English dialogue, and an optional voice-over.
${genre === "news" ? "Prefer feature story and documentary-style wording." : "Prefer academic documentary wording. The remote press leads into Scene 02."}

Return JSON only:
{"flowPrompt":"","continuityHint":""}`;
  }

  if (kind === "closing") {
    const common = genre === "news" ? NEWS_CLOSING_COMMON : LECTURE_CLOSING_COMMON;
    return `${header}

Write the Scene 10 closing prompt in English for Google Flow.
The closing common block must not reuse the opening sentences.
Do not write a "Selected reference characters for this scene" header. If supportingRoles lists someone for scene 10 without a selected image, describe that person's appearance and say no reference image is attached.

COMMON BLOCK:
${common}

Custom block: wrap up today's story, the screen content, the closing English dialogue, the closing camera, and the ending.
${genre === "news"
      ? 'The last spoken line must be exactly: "Thank you for joining us. I am HS. Have a good day."'
      : 'The last spoken line must be exactly: "This is for today. Thank you." The documentary returns here, in Scene 10.'}

Return JSON only:
{"flowPrompt":"","continuityHint":""}`;
  }

  const musicShape = genre === "news"
    ? `Part 1 covers Scenes 01-02, Part 2 covers Scenes 03-04, Part 3 covers Scenes 05-07, Part 4 covers Scenes 08-10.`
    : `Part 1 covers Scenes 01-02, Part 2 covers Scenes 03-05, Part 3 covers Scenes 06-08, Part 4 covers Scenes 09-10.`;
  return `${header}

Write two English music prompts for one 120-second piece.
The emotional line is Intro and Verse, then Pre-Chorus, then Chorus and Bridge, then Final Chorus and Outro.
${musicShape}
The parts are one continuous cue, not four separate songs.
Premiere will trim this 120-second cue to the picture. The prompt itself asks for 120 seconds.
promptA matches the story. promptB is an alternative with the same emotional shape, not a different story.
Do not write a transition prompt.

Return JSON only:
{"promptA":"","promptB":""}`;
}

module.exports = {
  templateFor,
  NEWS_OPENING_COMMON,
  NEWS_CLOSING_COMMON,
  LECTURE_OPENING_COMMON,
  LECTURE_CLOSING_COMMON,
};
