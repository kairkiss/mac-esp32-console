#!/usr/bin/env python3
import json
from pathlib import Path

controller = r'''// BKB Desk Pet v6 Lite Mac Brain publisher.
const STATUS_INTERVAL_MS = 2500;
const CONFIG_INTERVAL_MS = 5 * 60 * 1000;
const now = Date.now();

function mqtt(topic, payload, retain = true) {
  return { topic, payload: JSON.stringify(payload), retain, qos: 0 };
}

function httpOk(text = "OK") {
  const r = Object.assign({}, msg);
  r.statusCode = 200;
  r.headers = { "content-type": "text/plain" };
  r.payload = text;
  return r;
}

function httpJson(payload, statusCode = 200) {
  const r = Object.assign({}, msg);
  r.statusCode = statusCode;
  r.headers = { "content-type": "application/json" };
  r.payload = JSON.stringify(payload);
  return r;
}

function parsePayload(x) {
  if (!x) return {};
  if (typeof x === "object") return x;
  try { return JSON.parse(x); } catch (_) { return {}; }
}

function clamp(n, lo, hi) {
  n = Number(n);
  if (!Number.isFinite(n)) n = 0;
  return Math.max(lo, Math.min(hi, n));
}

function isNight(time) {
  const m = String(time || "").match(/^(\d{1,2}):/);
  const h = m ? Number(m[1]) : new Date().getHours();
  return h >= 23 || h < 8;
}

function modeHint(s) {
  if (s.locked) return "locked";
  if (isNight(s.time) && Number(s.idle_s || 0) >= 60) return "night";
  if (Number(s.temp_c) >= 80) return "hot";
  if (Number(s.cpu_pct || 0) >= 85 || Number(s.mem_pct || 0) >= 90) return "busy";
  if (Number(s.idle_s || 0) >= 180) return "idle";
  const app = String(s.app || "").toLowerCase();
  if (app.includes("terminal") || app.includes("code") || app.includes("xcode") || app.includes("arduino") || app.includes("node-red")) return "focus";
  return "active";
}

function configPayload() {
  return {
    v: 1,
    screen: {
      locked: "off",
      offline: "face",
      night_idle: "off",
      sleep_screen_off_ms: 1200000
    },
    fan: {
      mode: "auto",
      offline_pct: 20,
      failsafe_pct: 80,
      curve: [[45,0],[55,25],[65,40],[75,65],[85,85],[95,100]]
    }
  };
}

function publishConfigIfDue(force) {
  const last = Number(flow.get("bkb_v6_last_config_ms") || 0);
  if (!force && now - last < CONFIG_INTERVAL_MS) return [];
  flow.set("bkb_v6_last_config_ms", now);
  return [mqtt("bkb/desk1/pet/config", configPayload(), true)];
}

function buildState(raw) {
  const last = flow.get("bkb_v6_last_status") || {};
  const lockedFlow = flow.get("bkb_v6_locked");
  const appFlow = flow.get("bkb_v6_app") || "";
  const s = Object.assign({}, last, raw || {});

  const locked = typeof lockedFlow === "boolean" ? lockedFlow : Boolean(s.locked);
  const app = appFlow || s.app || "Unknown";
  const temp = (s.temp_c === null || s.temp_c === undefined || s.temp_c === "") ? null : Number(s.temp_c);
  const tempValid = Number.isFinite(temp) && temp >= 10 && temp <= 110;

  const state = {
    v: 1,
    ts: Number(s.ts || Math.floor(now / 1000)),
    online: true,
    locked,
    idle_s: clamp(s.idle_s, 0, 86400),
    app: String(app).substring(0, 64),
    cpu_pct: clamp(s.cpu_pct, 0, 100),
    mem_pct: clamp(s.mem_pct, 0, 100),
    temp_c: tempValid ? Math.round(temp) : null,
    thermal_source: tempValid ? String(s.thermal_source || "unknown") : "unavailable",
    time: String(s.time || "--:--").substring(0, 8)
  };
  state.mode_hint = modeHint(state);
  flow.set("bkb_v6_last_state", state);
  return state;
}

function publishStateAndHeartbeat(state) {
  const seq = Number(flow.get("bkb_v6_seq") || 0) + 1;
  flow.set("bkb_v6_seq", seq);
  return [
    mqtt("bkb/desk1/mac/state", state, true),
    mqtt("bkb/desk1/mac/heartbeat", { v: 1, ts: Math.floor(now / 1000), seq, online: true }, true)
  ];
}

const ev = msg.bkb_event || "";
const topic = msg.topic || "";
const payload = parsePayload(msg.payload);
const reqUrl = msg.req && msg.req.url ? String(msg.req.url) : "";

function routeIs(oldPath, newPath) {
  return reqUrl === oldPath || reqUrl === newPath;
}

if (ev === "init") {
  if (flow.get("bkb_v6_locked") === undefined) flow.set("bkb_v6_locked", true);
  const state = buildState({});
  const out = publishConfigIfDue(true).concat(publishStateAndHeartbeat(state));
  node.status({ fill: "green", shape: "dot", text: "v6 init" });
  return [out, { payload: "refresh" }, null];
}

if (topic === "bkb/desk1/pet/state") {
  flow.set("bkb_v6_pet_state", payload);
  flow.set("bkb_v6_pet_state_ms", now);
  return [null, null, null];
}

if (topic === "bkb/desk1/pet/telemetry") {
  flow.set("bkb_v6_pet_telemetry", payload);
  flow.set("bkb_v6_pet_telemetry_ms", now);
  return [null, null, null];
}

if (topic === "bkb/desk1/state/online") {
  flow.set("bkb_v6_pet_online", String(msg.payload || "") === "online");
  flow.set("bkb_v6_pet_online_ms", now);
  return [null, null, null];
}

if (msg.req && routeIs("/bkb/console/status", "/mac-esp32/console/status")) {
  const petState = flow.get("bkb_v6_pet_state") || {};
  const macState = flow.get("bkb_v6_last_state") || {};
  const telemetry = flow.get("bkb_v6_pet_telemetry") || {};
  const onlineRaw = flow.get("bkb_v6_pet_online");
  const stateAge = now - Number(flow.get("bkb_v6_pet_state_ms") || 0);
  const telemetryAge = now - Number(flow.get("bkb_v6_pet_telemetry_ms") || 0);
  const freshAge = Math.min(stateAge, telemetryAge);
  const online = onlineRaw === true && freshAge < 60000;
  const petView = Object.assign({}, telemetry, petState);
  return [null, null, httpJson({
    ok: true,
    online,
    state_age_ms: freshAge,
    pet_state: petView,
    pet_telemetry: telemetry,
    mac_state: macState
  })];
}

if (msg.req && routeIs("/bkb/console/text", "/mac-esp32/console/text")) {
  const text = String(payload.text || "").substring(0, 240);
  const style = String(payload.style || "full").substring(0, 16);
  const duration = clamp(payload.duration_ms || 5000, 500, 30000);
  if (!text) return [null, null, httpJson({ ok: false, error: "missing text" }, 400)];
  const cmd = {
    v: 1,
    text,
    duration_ms: duration,
    style,
    source: String(payload.source || "console").substring(0, 32)
  };
  node.status({ fill: "blue", shape: "dot", text: `console text ${duration}ms` });
  return [[mqtt("bkb/desk1/cmd/text", cmd, false)], null, httpJson({ ok: true })];
}

if (msg.req && routeIs("/bkb/console/bitmap", "/mac-esp32/console/bitmap")) {
  const cmd = {
    v: 1,
    id: String(payload.id || `console-${now}`).substring(0, 64),
    w: clamp(payload.w || 128, 1, 128),
    h: clamp(payload.h || 64, 1, 64),
    format: String(payload.format || "1bpp"),
    encoding: String(payload.encoding || "base64"),
    duration_ms: clamp(payload.duration_ms || 6000, 500, 30000),
    data: String(payload.data || "")
  };
  if (cmd.w !== 128 || cmd.h !== 64 || cmd.format !== "1bpp" || cmd.encoding !== "base64" || !cmd.data) {
    return [null, null, httpJson({ ok: false, error: "invalid bitmap command" }, 400)];
  }
  node.status({ fill: "blue", shape: "ring", text: `console bitmap ${cmd.duration_ms}ms` });
  return [[mqtt("bkb/desk1/cmd/bitmap", cmd, false)], null, httpJson({ ok: true })];
}

if (msg.req && routeIs("/bkb/console/bitmap/page", "/mac-esp32/console/bitmap/page")) {
  const cmd = {
    v: 1,
    id: String(payload.id || `console-pages-${now}`).substring(0, 64),
    page_index: clamp(payload.page_index || 0, 0, 20),
    page_count: clamp(payload.page_count || 1, 1, 20),
    w: clamp(payload.w || 128, 1, 128),
    h: clamp(payload.h || 64, 1, 64),
    format: String(payload.format || "1bpp"),
    encoding: String(payload.encoding || "base64"),
    duration_ms: clamp(payload.duration_ms || 6000, 6000, 30000),
    source: String(payload.source || "console").substring(0, 32),
    data: String(payload.data || "")
  };
  if (cmd.w !== 128 || cmd.h !== 64 || cmd.format !== "1bpp" || cmd.encoding !== "base64" || !cmd.data) {
    return [null, null, httpJson({ ok: false, error: "invalid bitmap page command" }, 400)];
  }
  node.status({ fill: "blue", shape: "ring", text: `bitmap page ${cmd.page_index + 1}/${cmd.page_count}` });
  return [[mqtt("bkb/desk1/cmd/bitmap/page", cmd, false)], null, httpJson({ ok: true })];
}

if (msg.req && routeIs("/bkb/console/scene", "/mac-esp32/console/scene")) {
  const cmd = {
    v: 1,
    scene: String(payload.scene || ""),
    duration_ms: clamp(payload.duration_ms || 5000, 500, 30000),
    source: String(payload.source || "console").substring(0, 32)
  };
  if (!cmd.scene) return [null, null, httpJson({ ok: false, error: "missing scene" }, 400)];
  node.status({ fill: "purple", shape: "dot", text: `scene ${cmd.scene}` });
  return [[mqtt("bkb/desk1/cmd/scene", cmd, false)], null, httpJson({ ok: true })];
}

if (msg.req && routeIs("/bkb/console/device", "/mac-esp32/console/device")) {
  const action = String(payload.action || "");
  if (!action) return [null, null, httpJson({ ok: false, error: "missing action" }, 400)];
  const cmd = { v: 1, action, source: "console" };
  node.status({ fill: "green", shape: "dot", text: `device ${action}` });
  return [[mqtt("bkb/desk1/cmd/device", cmd, false)], null, httpJson({ ok: true })];
}

if (msg.req && routeIs("/bkb/console/netconfig", "/mac-esp32/console/netconfig")) {
  const cmd = {
    v: 1,
    ssid: String(payload.ssid || ""),
    password: String(payload.password || ""),
    mqtt_host: String(payload.mqtt_host || ""),
    mqtt_port: clamp(payload.mqtt_port || 1883, 1, 65535),
    source: "console"
  };
  if (!cmd.ssid || !cmd.mqtt_host) return [null, null, httpJson({ ok: false, error: "missing ssid or mqtt_host" }, 400)];
  node.status({ fill: "yellow", shape: "ring", text: `netconfig ${cmd.mqtt_host}` });
  return [[mqtt("bkb/desk1/cmd/netconfig", cmd, false)], null, httpJson({ ok: true })];
}

if (msg.req) {
  const e = String(payload.event || payload.bkb_event || "");
  if (e === "locked") {
    flow.set("bkb_v6_locked", true);
    const state = buildState({ locked: true });
    node.status({ fill: "grey", shape: "dot", text: "locked" });
    return [publishStateAndHeartbeat(state), { payload: "refresh" }, httpOk("LOCKED")];
  }
  if (e === "unlocked") {
    flow.set("bkb_v6_locked", false);
    const state = buildState({ locked: false });
    node.status({ fill: "green", shape: "dot", text: "unlocked" });
    return [publishStateAndHeartbeat(state), { payload: "refresh" }, httpOk("UNLOCKED")];
  }
  if (e === "app") {
    const app = String(payload.app || "Unknown").substring(0, 64);
    flow.set("bkb_v6_app", app);
    const state = buildState({ app });
    node.status({ fill: "blue", shape: "dot", text: `app ${app}` });
    return [publishStateAndHeartbeat(state), null, httpOk("APP")];
  }
  return [null, null, httpOk("IGNORED")];
}

if (ev === "status") {
  const s = payload || {};
  if (typeof s.locked === "boolean") flow.set("bkb_v6_locked", s.locked);
  if (s.app) flow.set("bkb_v6_app", String(s.app).substring(0, 64));
  flow.set("bkb_v6_last_status", s);
  const state = buildState(s);
  const out = publishConfigIfDue(false).concat(publishStateAndHeartbeat(state));
  node.status({ fill: "green", shape: "dot", text: `${state.mode_hint} cpu ${state.cpu_pct}% temp ${state.temp_c ?? "?"}` });
  return [out, null, null];
}

if (ev === "tick") {
  const last = Number(flow.get("bkb_v6_last_status_ms") || 0);
  if (now - last >= STATUS_INTERVAL_MS) {
    flow.set("bkb_v6_last_status_ms", now);
    return [publishConfigIfDue(false), { payload: "refresh" }, null];
  }
}

return [null, null, null];
'''

flow = [
    {
        "id": "bkb_tab_v6_lite",
        "type": "tab",
        "label": "BKB Desk Pet v6 Lite",
        "disabled": False,
        "info": "Mac Brain publisher only. ESP32 Pet Runtime owns display, face animation, fan control, MacLink, and failsafe."
    },
    {
        "id": "bkb_mqtt_broker_v6_lite",
        "type": "mqtt-broker",
        "name": "BKB-MQTT v6",
        "broker": "127.0.0.1",
        "port": "1883",
        "clientid": "",
        "autoConnect": True,
        "usetls": False,
        "protocolVersion": "4",
        "keepalive": "60",
        "cleansession": True,
        "birthTopic": "",
        "birthQos": "0",
        "birthRetain": "false",
        "birthPayload": "",
        "birthMsg": {},
        "closeTopic": "bkb/desk1/mac/heartbeat",
        "closeQos": "0",
        "closeRetain": "true",
        "closePayload": "{\"v\":1,\"online\":false}",
        "closeMsg": {},
        "willTopic": "bkb/desk1/mac/heartbeat",
        "willQos": "0",
        "willRetain": "true",
        "willPayload": "{\"v\":1,\"online\":false}",
        "willMsg": {},
        "sessionExpiry": ""
    },
    {
        "id": "bkb_init_v6_lite",
        "type": "inject",
        "z": "bkb_tab_v6_lite",
        "name": "初始化 v6 config/state",
        "props": [{"p": "bkb_event", "v": "init", "vt": "str"}],
        "repeat": "",
        "crontab": "",
        "once": True,
        "onceDelay": "1",
        "topic": "",
        "x": 170,
        "y": 80,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_tick_v6_lite",
        "type": "inject",
        "z": "bkb_tab_v6_lite",
        "name": "2.5秒 Mac 状态节拍",
        "props": [{"p": "bkb_event", "v": "tick", "vt": "str"}],
        "repeat": "2.5",
        "crontab": "",
        "once": True,
        "onceDelay": "2",
        "topic": "",
        "x": 170,
        "y": 140,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_http_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Hammerspoon locked/app",
        "url": "/bkb/mac/event",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 170,
        "y": 220,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_console_text_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Console text command",
        "url": "/bkb/console/text",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 170,
        "y": 280,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "mac_esp32_console_status_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Mac-esp32 status query",
        "url": "/mac-esp32/console/status",
        "method": "get",
        "upload": False,
        "swaggerDoc": "",
        "x": 180,
        "y": 255,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "mac_esp32_console_text_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Mac-esp32 text command",
        "url": "/mac-esp32/console/text",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 180,
        "y": 285,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_console_bitmap_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Console bitmap command",
        "url": "/bkb/console/bitmap",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 180,
        "y": 340,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "mac_esp32_console_bitmap_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Mac-esp32 bitmap command",
        "url": "/mac-esp32/console/bitmap",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 190,
        "y": 345,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_console_bitmap_page_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Console bitmap page command",
        "url": "/bkb/console/bitmap/page",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 200,
        "y": 400,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "mac_esp32_console_bitmap_page_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Mac-esp32 bitmap page",
        "url": "/mac-esp32/console/bitmap/page",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 180,
        "y": 405,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_console_scene_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Console scene command",
        "url": "/bkb/console/scene",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 180,
        "y": 460,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "mac_esp32_console_scene_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Mac-esp32 scene command",
        "url": "/mac-esp32/console/scene",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 190,
        "y": 465,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_console_device_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Console device command",
        "url": "/bkb/console/device",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 190,
        "y": 520,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "mac_esp32_console_device_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Mac-esp32 device command",
        "url": "/mac-esp32/console/device",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 190,
        "y": 525,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_console_netconfig_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Console network config",
        "url": "/bkb/console/netconfig",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 190,
        "y": 580,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "mac_esp32_console_netconfig_in_v6_lite",
        "type": "http in",
        "z": "bkb_tab_v6_lite",
        "name": "Mac-esp32 network config",
        "url": "/mac-esp32/console/netconfig",
        "method": "post",
        "upload": False,
        "swaggerDoc": "",
        "x": 190,
        "y": 585,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_controller_v6_lite",
        "type": "function",
        "z": "bkb_tab_v6_lite",
        "name": "Mac Brain v6 Publisher",
        "func": controller,
        "outputs": 3,
        "timeout": 0,
        "noerr": 0,
        "initialize": "",
        "finalize": "",
        "libs": [],
        "x": 650,
        "y": 180,
        "wires": [["bkb_mqtt_out_v6_lite"], ["bkb_status_exec_v6_lite"], ["bkb_http_resp_v6_lite"]]
    },
    {
        "id": "bkb_mqtt_out_v6_lite",
        "type": "mqtt out",
        "z": "bkb_tab_v6_lite",
        "name": "发布 v6 mac/state heartbeat config",
        "topic": "",
        "qos": "",
        "retain": "",
        "respTopic": "",
        "contentType": "",
        "userProps": "",
        "correl": "",
        "expiry": "",
        "broker": "bkb_mqtt_broker_v6_lite",
        "x": 1020,
        "y": 100,
        "wires": []
    },
    {
        "id": "bkb_pet_state_in_v6_lite",
        "type": "mqtt in",
        "z": "bkb_tab_v6_lite",
        "name": "ESP32 pet/state",
        "topic": "bkb/desk1/pet/state",
        "qos": "0",
        "datatype": "json",
        "broker": "bkb_mqtt_broker_v6_lite",
        "nl": False,
        "rap": True,
        "rh": 0,
        "inputs": 0,
        "x": 180,
        "y": 660,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_pet_telemetry_in_v6_lite",
        "type": "mqtt in",
        "z": "bkb_tab_v6_lite",
        "name": "ESP32 pet/telemetry",
        "topic": "bkb/desk1/pet/telemetry",
        "qos": "0",
        "datatype": "json",
        "broker": "bkb_mqtt_broker_v6_lite",
        "nl": False,
        "rap": True,
        "rh": 0,
        "inputs": 0,
        "x": 190,
        "y": 720,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_pet_online_in_v6_lite",
        "type": "mqtt in",
        "z": "bkb_tab_v6_lite",
        "name": "ESP32 online",
        "topic": "bkb/desk1/state/online",
        "qos": "0",
        "datatype": "auto",
        "broker": "bkb_mqtt_broker_v6_lite",
        "nl": False,
        "rap": True,
        "rh": 0,
        "inputs": 0,
        "x": 160,
        "y": 780,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_status_exec_v6_lite",
        "type": "exec",
        "z": "bkb_tab_v6_lite",
        "command": "/Users/YOUR_MAC_USERNAME/bin/macbrain_status_v6.sh",
        "addpay": "",
        "append": "",
        "useSpawn": "false",
        "timer": "5",
        "winHide": False,
        "oldrc": False,
        "name": "采集 Mac 状态 v6",
        "x": 980,
        "y": 220,
        "wires": [["bkb_status_json_v6_lite"], ["bkb_exec_err_v6_lite"], ["bkb_exec_rc_v6_lite"]]
    },
    {
        "id": "bkb_status_json_v6_lite",
        "type": "json",
        "z": "bkb_tab_v6_lite",
        "name": "解析状态 JSON",
        "property": "payload",
        "action": "",
        "pretty": False,
        "x": 1220,
        "y": 200,
        "wires": [["bkb_status_mark_v6_lite"]]
    },
    {
        "id": "bkb_status_mark_v6_lite",
        "type": "function",
        "z": "bkb_tab_v6_lite",
        "name": "标记 status 事件",
        "func": "msg.bkb_event = \"status\";\nreturn msg;",
        "outputs": 1,
        "timeout": 0,
        "noerr": 0,
        "initialize": "",
        "finalize": "",
        "libs": [],
        "x": 1440,
        "y": 200,
        "wires": [["bkb_controller_v6_lite"]]
    },
    {
        "id": "bkb_http_resp_v6_lite",
        "type": "http response",
        "z": "bkb_tab_v6_lite",
        "name": "HTTP OK",
        "statusCode": "",
        "headers": {},
        "x": 970,
        "y": 320,
        "wires": []
    },
    {
        "id": "bkb_exec_err_v6_lite",
        "type": "debug",
        "z": "bkb_tab_v6_lite",
        "name": "状态脚本 stderr",
        "active": True,
        "tosidebar": True,
        "console": False,
        "tostatus": False,
        "complete": "payload",
        "targetType": "msg",
        "statusVal": "",
        "statusType": "auto",
        "x": 1220,
        "y": 260,
        "wires": []
    },
    {
        "id": "bkb_exec_rc_v6_lite",
        "type": "debug",
        "z": "bkb_tab_v6_lite",
        "name": "状态脚本 rc",
        "active": False,
        "tosidebar": True,
        "console": False,
        "tostatus": False,
        "complete": "payload",
        "targetType": "msg",
        "statusVal": "",
        "statusType": "auto",
        "x": 1210,
        "y": 320,
        "wires": []
    },
    {
        "id": "bkb_pet_state_in_v6_lite",
        "type": "mqtt in",
        "z": "bkb_tab_v6_lite",
        "name": "ESP32 pet/state",
        "topic": "bkb/desk1/pet/state",
        "qos": "0",
        "datatype": "auto",
        "broker": "bkb_mqtt_broker_v6_lite",
        "nl": False,
        "rap": True,
        "rh": 0,
        "inputs": 0,
        "x": 160,
        "y": 320,
        "wires": [["bkb_pet_state_dbg_v6_lite"]]
    },
    {
        "id": "bkb_pet_state_dbg_v6_lite",
        "type": "debug",
        "z": "bkb_tab_v6_lite",
        "name": "ESP32 Pet 状态",
        "active": True,
        "tosidebar": True,
        "console": False,
        "tostatus": True,
        "complete": "payload",
        "targetType": "msg",
        "statusVal": "payload",
        "statusType": "auto",
        "x": 400,
        "y": 320,
        "wires": []
    }
]

Path("nodered/bkb_desk_pet_v6_lite_flow.json").write_text(
    json.dumps(flow, ensure_ascii=False, indent=2),
    encoding="utf-8",
)
print("wrote nodered/bkb_desk_pet_v6_lite_flow.json")
