#!/usr/bin/env bash
# deploy_karen_hologram.sh
# ------------------------------------------------------------
# Creates a full Vercel-ready monorepo with:
#   • static hologram UI  (public/)
#   • Edge functions      (api/)
#   • vercel.json / tsconfig / package.json
# ------------------------------------------------------------
set -euo pipefail

PROJECT="karen-hologram"
[[ -d $PROJECT ]] && { echo "❌  '$PROJECT' already exists."; exit 1; }

echo "▶ Creating directory tree …"
mkdir -p "$PROJECT/public/assets/avatar" "$PROJECT/api"

###############################################################################
# 1 ▸ vercel.json
###############################################################################
cat > "$PROJECT/vercel.json" <<'JSON'
{
  "version": 3,
  "name": "karen-hologram",
  "routes": [
    { "src": "/api/(.*)", "dest": "/api/$1.ts" },
    { "src": "/(.*)", "dest": "/public/index.html" }
  ]
}
JSON

###############################################################################
# 2 ▸ tsconfig.json
###############################################################################
cat > "$PROJECT/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "nodenext",
    "strict": true,
    "verbatimModuleSyntax": true
  }
}
JSON

###############################################################################
# 3 ▸ package.json
###############################################################################
cat > "$PROJECT/package.json" <<'JSON'
{
  "name": "karen-hologram",
  "type": "module",
  "engines": { "node": "20.x" },
  "scripts": {
    "dev": "vercel dev",
    "build": "echo \"static only\""
  },
  "dependencies": {
    "@livekit/server-sdk": "^1.4.5",
    "openai": "^5.2.0",
    "undici": "^6.17.0"
  },
  "devDependencies": { "typescript": "^5.4.5" }
}
JSON

###############################################################################
# 4 ▸ Edge functions
###############################################################################
## 4.1 token.ts
cat > "$PROJECT/api/token.ts" <<'TS'
import { NextRequest } from "next/server";
import { AccessToken, RoomJoinPermission } from "@livekit/server-sdk";

export const config = { runtime: "edge" };

export default async (req: NextRequest) => {
  const url = new URL(req.url);
  const id  = url.searchParams.get("identity") ?? `guest-${Date.now()}`;

  const at = new AccessToken(
    process.env.LIVEKIT_API_KEY!, 
    process.env.LIVEKIT_API_SECRET!,
    { identity: id }
  );
  at.addGrant({ roomJoin: true, room: "avatar", canPublish: true, canSubscribe: true } as RoomJoinPermission);

  return Response.json({ token: at.toJwt() });
};
TS

## 4.2 stt.ts
cat > "$PROJECT/api/stt.ts" <<'TS'
import { NextRequest } from "next/server";
import OpenAI from "openai";
export const config = { runtime: "edge" };

export default async (req: NextRequest) => {
  const audio = await req.arrayBuffer();
  const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY! });

  const out = await openai.audio.transcriptions.create({
    file: new File([audio], "mic.webm"),
    model: "whisper-1"
  });

  return Response.json(out);
};
TS

## 4.3 chat.ts
cat > "$PROJECT/api/chat.ts" <<'TS'
import { NextRequest } from "next/server";
import OpenAI from "openai";
export const config = { runtime: "edge" };

const PROMPT = `
You are Karen, a highly competent and professional Direction Secretary for VOKA in your 40s. ...

OUTPUT FORMAT:
• Plain text.
• One sentence per line.
• Each sentence starts with "Speaker:".
`.trim();

export default async (req: NextRequest) => {
  const { user } = await req.json();
  const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY! });

  const chat = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: PROMPT },
      { role: "user",   content: user }
    ]
  });

  return Response.json({ text: chat.choices[0].message.content });
};
TS

## 4.4 tts.ts
cat > "$PROJECT/api/tts.ts" <<'TS'
import { NextRequest } from "next/server";
import { fetch } from "undici";
export const config = { runtime: "edge" };

export default async (req: NextRequest) => {
  const { text } = await req.json();
  const voice   = process.env.ELEVENLABS_VOICE_ID!;
  const apiKey  = process.env.ELEVENLABS_API_KEY!;
  const modelId = process.env.ELEVENLABS_MODEL_ID ?? "eleven_v3_alpha";
  const stability = parseFloat(process.env.ELEVENLABS_STABILITY ?? "0.30");

  const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice}/stream`, {
    method: "POST",
    headers: {
      "xi-api-key": apiKey,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      text,
      model_id: modelId,
      voice_settings: { stability, similarity_boost: 0.5 }
    })
  });

  return new Response(r.body, { headers: { "content-type": "audio/wav" } });
};
TS

###############################################################################
# 5 ▸ public/index.html
###############################################################################
cat > "$PROJECT/public/index.html" <<'HTML'
<!DOCTYPE html><html lang="nl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>VOKA Hologram</title>
<script src="https://unpkg.com/livekit-client/dist/livekit-client.umd.js"></script>
<style>
/* …… identical CSS as earlier message …… */
html,body{height:100%;margin:0;font-family:system-ui;background:#071019;overflow:hidden}
body::before{content:"";position:fixed;inset:0;background-image:radial-gradient(circle at 50% 50%,rgba(0,233,255,.07),transparent 60%),repeating-linear-gradient(120deg,rgba(0,233,255,.03) 0 2px,transparent 2px 40px),repeating-linear-gradient(60deg,rgba(0,233,255,.03) 0 2px,transparent 2px 40px);animation:bg 30s linear infinite}
@keyframes bg{to{background-position:300px 300px,200px 0,0 200px}}
#stage{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;perspective:1200px}
#holo{position:relative;width:480px;height:640px;max-width:90vw;max-height:80vh;transform:rotateX(6deg);border-radius:16px;overflow:hidden;background:none;box-shadow:0 30px 60px rgba(0,0,0,.45)}
#avatar-video,#avatar-img{width:100%;height:100%;object-fit:cover}#avatar-video{display:none}
#mic{position:fixed;bottom:40px;left:50%;transform:translateX(-50%);width:72px;height:72px;border-radius:50%;cursor:pointer;display:flex;align-items:center;justify-content:center;background:rgba(0,233,255,.15);box-shadow:0 0 12px 4px rgba(0,233,255,.25);transition:background .2s}
#mic svg{width:38px;height:38px;fill:#00e9ff;transition:opacity .2s}#mic.muted{background:rgba(233,0,78,.25)}#mic.muted svg.on{opacity:0}#mic:not(.muted) svg.off{opacity:0}
#setup{position:fixed;inset:0;background:rgba(7,16,25,.95);display:flex;align-items:center;justify-content:center}
#setup form{width:320px;padding:32px;display:flex;flex-direction:column;gap:16px;background:#0e1f2f;border-radius:12px;box-shadow:0 0 24px 4px rgba(0,233,255,.15)}
#setup h1{color:#00e9ff;text-align:center;font-size:1.4rem;margin:0}
#setup input{padding:8px;border:none;border-radius:6px;background:#081420;color:#fff}
#setup button{padding:10px;border:none;border-radius:8px;background:#00e9ff;color:#071019;font-weight:600}
@media(max-width:480px){#holo{width:90vw;height:70vh}}
</style></head><body>

<div id="setup">
  <form id="cfg">
    <h1>LiveKit JWT</h1>
    <input name="token" placeholder="plak token" required>
    <button>Start</button>
  </form>
</div>

<div id="stage" hidden>
  <div id="holo">
    <img id="avatar-img" src="assets/avatar/standby-avatar.gif">
    <video id="avatar-video" autoplay playsinline muted></video>
  </div>
  <button id="mic" class="muted">
    <svg class="on" viewBox="0 0 24 24"><path d="M12 14a3 3 0 0 0 3-3V5a3 3 0 0 0-6 0v6a3 3 0 0 0 3 3zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 14 0h-2zm-5 9v2h4v2H8v-2h4v-2z"/></svg>
    <svg class="off" viewBox="0 0 24 24"><path d="M19 11a7 7 0 0 1-11 5.9l1.45-1.45A5 5 0 0 0 17 11h2zm-7-8a3 3 0 0 1 3 3v4.17l5.31 5.31 1.42-1.42L4.1 2.1 2.69 3.51 7 7.82V11a3 3 0 0 0 1.28 2.47L10 13.17V8a3 3 0 0 1 2-2.83V3zM5 11h2a5 5 0 0 1 .15-1.16L5.4 7.1A7 7 0 0 0 5 11zm7 9v2h4v2H8v-2h4v-2z"/></svg>
  </button>
</div>

<script type="module">
import { connect } from "https://esm.sh/@livekit/client@2";

const LIVEKIT_WS = "wss://tts-mozilla-f1zttm7l.livekit.cloud";
const micBtn = document.getElementById("mic");
const vidEl  = document.getElementById("avatar-video");
const imgEl  = document.getElementById("avatar-img");

let room, mediaRec, micOn=false;

// 0  ── join room ───────────────────────────────────────────
document.getElementById("cfg").addEventListener("submit", async e=>{
  e.preventDefault();
  const token = e.target.token.value.trim();
  room = await connect(LIVEKIT_WS, token, { audio:true, video:false, autoSubscribe:true });
  await room.localParticipant.setMicrophoneEnabled(false);
  room.on("trackSubscribed",(t)=>{ if(t.kind==="video") t.attach(vidEl); });
  document.getElementById("setup").hidden = true;
  document.getElementById("stage").hidden = false;
});

// 1  ── mic toggle + pipeline ───────────────────────────────
micBtn.addEventListener("click", async ()=>{
  micOn = !micOn;
  micBtn.classList.toggle("muted",!micOn);
  if(!room) return;
  await room.localParticipant.setMicrophoneEnabled(micOn);
  if(micOn){ startRecorder(); vidEl.style.display="block"; imgEl.style.display="none"; }
  else     { stopRecorder();  vidEl.style.display="none"; imgEl.style.display="block"; }
});

function startRecorder(){
  navigator.mediaDevices.getUserMedia({ audio:true }).then(stream=>{
    mediaRec = new MediaRecorder(stream,{ mimeType:"audio/webm" });
    mediaRec.ondataavailable = async ev=>{
      const blob=ev.data; if(!blob.size) return;
      const text = await fetch("/api/stt",{method:"POST",body:blob}).then(r=>r.json()).then(j=>j.text);
      const reply= await fetch("/api/chat",{method:"POST",body:JSON.stringify({user:text})}).then(r=>r.json()).then(j=>j.text);
      const wav  = await fetch("/api/tts",{method:"POST",body:JSON.stringify({text:reply})});
      const audio=new Audio(URL.createObjectURL(await wav.blob()));
      audio.play();
    };
    mediaRec.start(6000); // 6-second chunks
  });
}
function stopRecorder(){ mediaRec?.stop(); }
</script>
</body></html>
HTML

touch "$PROJECT/public/assets/avatar/standby-avatar.gif"

###############################################################################
# 6 ▸ Placeholder gitignore
###############################################################################
cat > "$PROJECT/.gitignore" <<'TXT'
node_modules
.vercel
.DS_Store
TXT

echo "✅  Project '$PROJECT' created."
echo "   Next steps:"
echo "     cd $PROJECT"
echo "     npm i  # or pnpm i"
echo "     vercel link && vercel --prod"