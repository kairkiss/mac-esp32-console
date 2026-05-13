import json
from pathlib import Path

controller = r'''// BKB Desk Node v5 Controller
const BUTTON_OVERLAY_MS = 10 * 1000;
const APP_OVERLAY_MS = 2 * 1000;
const APP_COOLDOWN_MS = 8 * 1000;
const STATUS_INTERVAL_MS = 3000;
const FACE_REFRESH_MS = 2500;
const NIGHT_START_HOUR = 23;
const NIGHT_END_HOUR = 8;
const NIGHT_IDLE_OFF_SEC = 60;
const now = Date.now();

function mqtt(topic, payload, retain = true) { return { topic, payload: JSON.stringify(payload), retain, qos: 0 }; }
function screenOn() { return mqtt("bkb/desk1/desired/system", { screen: "on" }, true); }
function screenOff() { return mqtt("bkb/desk1/desired/system", { screen: "off" }, true); }
function face(mood, intensity = 20, variant = "normal") { return mqtt("bkb/desk1/desired/face", { mood, intensity, variant }, true); }
function display(l0, l1, l2, l3) { return mqtt("bkb/desk1/desired/display", { l0:String(l0||"").substring(0,16), l1:String(l1||"").substring(0,16), l2:String(l2||"").substring(0,16), l3:String(l3||"").substring(0,16) }, true); }
function httpOk(text = "OK") { return { statusCode:200, headers:{"content-type":"text/plain"}, payload:text }; }
function setOverlay(type, ms, data = {}) { flow.set("bkb_overlay", type); flow.set("bkb_overlay_until", now + ms); flow.set("bkb_overlay_data", data); }
function clearOverlay() { flow.set("bkb_overlay", ""); flow.set("bkb_overlay_until", 0); flow.set("bkb_overlay_data", {}); }
function isLocked() { return flow.get("bkb_locked") === true; }
function rememberStatus(s) { flow.set("bkb_last_status", s || {}); }
function getLastStatus() { return flow.get("bkb_last_status") || {}; }
function clamp(n, lo, hi) { n = Number(n || 0); return Math.max(lo, Math.min(hi, n)); }
function hourFromStatus(s) { const m = String(s.time || "").match(/^(\d{1,2}):/); return m ? Number(m[1]) : new Date().getHours(); }
function isNight(s) { const h = hourFromStatus(s); return h >= NIGHT_START_HOUR || h < NIGHT_END_HOUR; }
function appClass(app) {
  const a = String(app || "").toLowerCase();
  if (a.includes("terminal") || a.includes("code") || a.includes("xcode") || a.includes("arduino") || a.includes("node-red")) return "dev";
  if (a.includes("music") || a.includes("spotify") || a.includes("tv")) return "media";
  if (a.includes("safari") || a.includes("chrome") || a.includes("edge") || a.includes("firefox")) return "browser";
  return "normal";
}
function decideMood(s) {
  const cpu = clamp(s.cpu,0,100), mem = clamp(s.mem,0,100), idle = Number(s.idle || 0), app = String(s.app || "");
  let mood = "happy", intensity = Math.max(cpu, Math.floor(mem * 0.65)), variant = "normal";
  if (idle >= 180) { mood = "idle"; intensity = Math.min(40, intensity); }
  if (cpu >= 85 || mem >= 90) { mood = "power"; intensity = Math.max(cpu, mem); }
  else if (cpu >= 65 || mem >= 78) { mood = "busy"; intensity = Math.max(cpu, mem); }
  else if (cpu >= 35) { mood = "focus"; intensity = cpu; }
  else if (idle < 180) { mood = "happy"; intensity = cpu; }
  const cls = appClass(app);
  if (mood === "happy" || mood === "idle") {
    if (cls === "dev") { mood = "focus"; intensity = Math.max(intensity, 42); }
    else if (cls === "media") { mood = "happy"; variant = "soft"; }
  }
  if (isNight(s) && idle >= NIGHT_IDLE_OFF_SEC) { mood = "sleep"; intensity = 10; variant = "night"; }
  return {mood, intensity, variant};
}
function statusPage(s, label="SYS STATUS") {
  const cpu = Number(s.cpu ?? 0), mem = Number(s.mem ?? 0), time = String(s.time ?? "--:--"), idle = Number(s.idle ?? 0);
  let mode = isLocked() ? "LOCKED" : "ACTIVE";
  if (!isLocked() && idle >= 180) mode = "IDLE";
  if (!isLocked() && isNight(s)) mode = "NIGHT";
  return display(label, (`CPU ${cpu}% MEM ${mem}%`).substring(0,16), (`${time} ${mode}`).substring(0,16), (`IDLE ${idle}s`).substring(0,16));
}
function activeFaceMessages(s) {
  const d = decideMood(s), idle = Number(s.idle || 0);
  if (isNight(s) && idle >= NIGHT_IDLE_OFF_SEC) { node.status({fill:"grey",shape:"dot",text:"night idle off"}); return [screenOff()]; }
  const lastMood = flow.get("bkb_last_mood") || "", lastIntensity = Number(flow.get("bkb_last_intensity") || -1), lastVariant = flow.get("bkb_last_variant") || "", lastFaceMs = Number(flow.get("bkb_last_face_ms") || 0);
  const bucket = Math.floor(d.intensity / 10), lastBucket = Math.floor(lastIntensity / 10);
  if (d.mood !== lastMood || d.variant !== lastVariant || bucket !== lastBucket || now - lastFaceMs >= FACE_REFRESH_MS) {
    flow.set("bkb_last_mood", d.mood); flow.set("bkb_last_intensity", d.intensity); flow.set("bkb_last_variant", d.variant); flow.set("bkb_last_face_ms", now);
    node.status({fill:"green",shape:"dot",text:`${d.mood} ${d.intensity}%`});
    return [screenOn(), face(d.mood, d.intensity, d.variant)];
  }
  return [];
}
function goLocked() { flow.set("bkb_locked", true); clearOverlay(); node.status({fill:"grey",shape:"dot",text:"locked/off"}); return [[screenOff()], null, null]; }
function goUnlocked() { flow.set("bkb_locked", false); clearOverlay(); flow.set("bkb_last_face_ms",0); node.status({fill:"green",shape:"dot",text:"unlocked"}); return [[screenOn(), face("happy",20,"normal")], {payload:"refresh"}, null]; }
function parsePayload(x) { if(!x) return {}; if(typeof x === "object") return x; try { return JSON.parse(x); } catch(e) { return {}; } }

const ev = msg.bkb_event || "", topic = msg.topic || "", payload = parsePayload(msg.payload);
if (ev === "init") { flow.set("bkb_locked", true); clearOverlay(); node.status({fill:"grey",shape:"dot",text:"init locked/off"}); return [[screenOff()], null, null]; }
if (msg.req && msg.req.url === "/bkb/mac/event") {
  const e = payload.event || payload.bkb_event || "";
  if (e === "locked") { const r = goLocked(); r[2] = httpOk("LOCKED"); return r; }
  if (e === "unlocked") { const r = goUnlocked(); r[2] = httpOk("UNLOCKED"); return r; }
  if (e === "app") {
    if (isLocked()) return [null,null,httpOk("LOCKED_IGNORE_APP")];
    const app = String(payload.app || "App"), last = Number(flow.get("bkb_last_app_overlay_ms") || 0), overlay = flow.get("bkb_overlay") || "";
    if (overlay && overlay !== "app") return [null,null,httpOk("BUSY_IGNORE_APP")];
    if (now - last < APP_COOLDOWN_MS) return [null,null,httpOk("COOLDOWN_IGNORE_APP")];
    flow.set("bkb_last_app_overlay_ms", now); setOverlay("app", APP_OVERLAY_MS, {app}); node.status({fill:"purple",shape:"dot",text:`app ${app}`});
    return [[screenOn(), display("Now using", app, "", "")], null, httpOk("APP")];
  }
  return [null,null,httpOk("IGNORED")];
}
if (topic === "bkb/desk1/event/button/1") {
  if (isLocked()) { setOverlay("sleep_peek", BUTTON_OVERLAY_MS, {}); node.status({fill:"yellow",shape:"dot",text:"sleep peek"}); return [[screenOn(), face("sleep",10,"peek")], null, null]; }
  setOverlay("play", BUTTON_OVERLAY_MS, {}); node.status({fill:"yellow",shape:"dot",text:"play"}); return [[screenOn(), face("play",15,"play")], null, null];
}
if (topic === "bkb/desk1/event/button/2") { setOverlay("status", BUTTON_OVERLAY_MS, {}); node.status({fill:"blue",shape:"dot",text:"status"}); const s = getLastStatus(); return [[screenOn(), statusPage(s, isLocked()?"LOCKED STATUS":"SYS STATUS")], {payload:"refresh"}, null]; }
if (ev === "status") {
  const s = payload || {}; rememberStatus(s);
  const overlay = flow.get("bkb_overlay") || "", until = Number(flow.get("bkb_overlay_until") || 0), data = flow.get("bkb_overlay_data") || {};
  if (overlay && until && now >= until) { clearOverlay(); if (isLocked()) return [[screenOff()], null, null]; flow.set("bkb_last_face_ms",0); return [activeFaceMessages(s), null, null]; }
  if (isLocked()) { if (overlay === "status") return [[screenOn(), statusPage(s,"LOCKED STATUS")], null, null]; return [null,null,null]; }
  if (overlay === "status") return [[screenOn(), statusPage(s,"SYS STATUS")], null, null];
  if (overlay === "app") return [[screenOn(), display("Now using", String(data.app || "App"), "", "")], null, null];
  if (overlay === "play" || overlay === "sleep_peek") return [null,null,null];
  return [activeFaceMessages(s), null, null];
}
if (ev === "tick") { const last = Number(flow.get("bkb_last_status_ms") || 0); if (now - last >= STATUS_INTERVAL_MS) { flow.set("bkb_last_status_ms", now); return [null, {payload:"refresh"}, null]; } }
return [null,null,null];
'''

flow = [
 {"id":"bkb_tab_v5","type":"tab","label":"BKB Desk Node v5","disabled":False,"info":"Stable daily-use Mac face. Locked/off; unlocked state-driven face; app overlay with cooldown; night policy."},
 {"id":"bkb_mqtt_broker_v5","type":"mqtt-broker","name":"BKB-MQTT","broker":"127.0.0.1","port":"1883","clientid":"","autoConnect":True,"usetls":False,"protocolVersion":"4","keepalive":"60","cleansession":True,"birthTopic":"","birthQos":"0","birthRetain":"false","birthPayload":"","birthMsg":{},"closeTopic":"","closeQos":"0","closeRetain":"false","closePayload":"","closeMsg":{},"willTopic":"","willQos":"0","willRetain":"false","willPayload":"","willMsg":{},"sessionExpiry":""},
 {"id":"bkb_init_v5","type":"inject","z":"bkb_tab_v5","name":"初始化：默认锁屏熄灭","props":[{"p":"bkb_event","v":"init","vt":"str"}],"repeat":"","crontab":"","once":True,"onceDelay":"1","topic":"","x":170,"y":80,"wires":[["bkb_controller_v5"]]},
 {"id":"bkb_tick_v5","type":"inject","z":"bkb_tab_v5","name":"1秒主时钟","props":[{"p":"bkb_event","v":"tick","vt":"str"}],"repeat":"1","crontab":"","once":True,"onceDelay":"2","topic":"","x":140,"y":140,"wires":[["bkb_controller_v5"]]},
 {"id":"bkb_http_in_v5","type":"http in","z":"bkb_tab_v5","name":"Hammerspoon 锁屏/App","url":"/bkb/mac/event","method":"post","upload":False,"swaggerDoc":"","x":170,"y":220,"wires":[["bkb_controller_v5"]]},
 {"id":"bkb_btn1_v5","type":"mqtt in","z":"bkb_tab_v5","name":"按钮1：睡眠/互动","topic":"bkb/desk1/event/button/1","qos":"0","datatype":"auto","broker":"bkb_mqtt_broker_v5","nl":False,"rap":True,"rh":0,"inputs":0,"x":160,"y":310,"wires":[["bkb_controller_v5"]]},
 {"id":"bkb_btn2_v5","type":"mqtt in","z":"bkb_tab_v5","name":"按钮2：状态页","topic":"bkb/desk1/event/button/2","qos":"0","datatype":"auto","broker":"bkb_mqtt_broker_v5","nl":False,"rap":True,"rh":0,"inputs":0,"x":140,"y":370,"wires":[["bkb_controller_v5"]]},
 {"id":"bkb_controller_v5","type":"function","z":"bkb_tab_v5","name":"BKB 状态机 v5","func":controller,"outputs":3,"timeout":0,"noerr":0,"initialize":"","finalize":"","libs":[],"x":650,"y":220,"wires":[["bkb_mqtt_out_v5"],["bkb_status_exec_v5"],["bkb_http_resp_v5"]]},
 {"id":"bkb_mqtt_out_v5","type":"mqtt out","z":"bkb_tab_v5","name":"发布 desired/*","topic":"","qos":"","retain":"","respTopic":"","contentType":"","userProps":"","correl":"","expiry":"","broker":"bkb_mqtt_broker_v5","x":950,"y":120,"wires":[]},
 {"id":"bkb_status_exec_v5","type":"exec","z":"bkb_tab_v5","command":"/Users/YOUR_MAC_USERNAME/bin/macbrain_status.sh","addpay":"","append":"","useSpawn":"false","timer":"","winHide":False,"oldrc":False,"name":"采集 Mac 状态","x":930,"y":260,"wires":[["bkb_status_json_v5"],["bkb_exec_err_v5"],["bkb_exec_rc_v5"]]},
 {"id":"bkb_status_json_v5","type":"json","z":"bkb_tab_v5","name":"解析状态 JSON","property":"payload","action":"","pretty":False,"x":1160,"y":220,"wires":[["bkb_status_mark_v5"]]},
 {"id":"bkb_status_mark_v5","type":"function","z":"bkb_tab_v5","name":"标记 status 事件","func":"msg.bkb_event = \"status\";\nreturn msg;","outputs":1,"timeout":0,"noerr":0,"initialize":"","finalize":"","libs":[],"x":1360,"y":220,"wires":[["bkb_controller_v5"]]},
 {"id":"bkb_http_resp_v5","type":"http response","z":"bkb_tab_v5","name":"HTTP OK","statusCode":"","headers":{},"x":930,"y":340,"wires":[]},
 {"id":"bkb_exec_err_v5","type":"debug","z":"bkb_tab_v5","name":"状态脚本 stderr","active":True,"tosidebar":True,"console":False,"tostatus":False,"complete":"payload","targetType":"msg","statusVal":"","statusType":"auto","x":1150,"y":300,"wires":[]},
 {"id":"bkb_exec_rc_v5","type":"debug","z":"bkb_tab_v5","name":"状态脚本 rc","active":False,"tosidebar":True,"console":False,"tostatus":False,"complete":"payload","targetType":"msg","statusVal":"","statusType":"auto","x":1140,"y":350,"wires":[]},
 {"id":"bkb_online_in_v5","type":"mqtt in","z":"bkb_tab_v5","name":"ESP32 online/offline","topic":"bkb/desk1/state/online","qos":"0","datatype":"auto","broker":"bkb_mqtt_broker_v5","nl":False,"rap":True,"rh":0,"inputs":0,"x":160,"y":450,"wires":[["bkb_online_dbg_v5"]]},
 {"id":"bkb_online_dbg_v5","type":"debug","z":"bkb_tab_v5","name":"ESP32 状态","active":True,"tosidebar":True,"console":False,"tostatus":True,"complete":"payload","targetType":"msg","statusVal":"payload","statusType":"auto","x":410,"y":450,"wires":[]}
]

Path('/mnt/data/bkb_desk_node_v5/bkb_desk_node_v5_flow.json').write_text(json.dumps(flow, ensure_ascii=False, indent=2), encoding='utf-8')
