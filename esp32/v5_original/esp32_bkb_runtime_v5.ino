/* BKB Peripheral Runtime v5: ESP32 + SSD1309 + MQTT + 2 buttons */
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <U8g2lib.h>
#include <SPI.h>

const char* WIFI_SSID = "YOUR_WIFI_SSID";
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";
const char* MQTT_HOST = "192.168.1.100";
const int MQTT_PORT = 1883;
const char* DEVICE_ID = "desk1";

U8G2_SSD1309_128X64_NONAME0_F_4W_HW_SPI oled(U8G2_R0, 33, 27, 26);
WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

const int BTN1_PIN = 32;
const int BTN2_PIN = 25;
bool btn1LastStable = HIGH, btn2LastStable = HIGH, btn1LastRead = HIGH, btn2LastRead = HIGH;
unsigned long btn1LastChange = 0, btn2LastChange = 0;
const unsigned long debounceMs = 35;

bool screenOff = false;
enum ViewMode { VIEW_FACE, VIEW_TEXT };
ViewMode viewMode = VIEW_FACE;
String faceMood = "happy", faceVariant = "normal";
int faceIntensity = 20, faceAnimStep = 0;
unsigned long faceAnimLast = 0;
String line0="BKB Mac Brain", line1="Booting...", line2="Please wait", line3="ESP32";
unsigned long lastReconnectAttempt = 0, lastTelemetry = 0;

String fit16(const String& s){ return s.length()<=16 ? s : s.substring(0,16); }
void clearScreen(){ oled.clearBuffer(); oled.sendBuffer(); }
void drawTextScreen(){ oled.clearBuffer(); if(!screenOff){ oled.setFont(u8g2_font_6x12_tr); oled.drawStr(0,12,line0.c_str()); oled.drawStr(0,28,line1.c_str()); oled.drawStr(0,44,line2.c_str()); oled.drawStr(0,60,line3.c_str()); } oled.sendBuffer(); }
void drawClosedEyes(int cy){ oled.drawLine(28,cy,52,cy); oled.drawLine(76,cy,100,cy); }
void drawSoftEyes(int cy,int dx){ oled.drawCircle(40,cy,9); oled.drawCircle(88,cy,9); oled.drawDisc(40+dx,cy,2); oled.drawDisc(88+dx,cy,2); }
void drawHappyEyes(int y){ oled.drawLine(28,y+6,34,y); oled.drawLine(34,y,46,y); oled.drawLine(46,y,52,y+6); oled.drawLine(76,y+6,82,y); oled.drawLine(82,y,94,y); oled.drawLine(94,y,100,y+6); }
void drawCuteSmile(){ oled.drawLine(54,45,60,49); oled.drawLine(60,49,68,49); oled.drawLine(68,49,74,45); }
void drawTinySmile(){ oled.drawLine(58,47,63,49); oled.drawLine(63,49,70,47); }
void drawBigSmile(){ oled.drawLine(44,42,50,50); oled.drawLine(50,50,58,54); oled.drawLine(58,54,70,54); oled.drawLine(70,54,78,50); oled.drawLine(78,50,84,42); }
void drawFlatMouth(){ oled.drawLine(52,47,76,47); }
void drawConcernMouth(){ oled.drawLine(56,48,72,44); }
void drawSweat(){ oled.drawLine(106,16,111,24); oled.drawLine(111,24,106,29); }
void drawFocusEyes(){ oled.drawLine(28,20,52,20); oled.drawLine(32,28,48,28); oled.drawLine(76,20,100,20); oled.drawLine(80,28,96,28); oled.drawDisc(40,24,2); oled.drawDisc(88,24,2); }
void drawBusyEyes(){ oled.drawLine(30,28,50,20); oled.drawLine(78,20,98,28); }
void drawPowerFace(int shake){ int y=24+shake; oled.drawLine(27,y-7,52,y+3); oled.drawLine(29,y+4,50,y-4); oled.drawLine(76,y+3,101,y-7); oled.drawLine(78,y-4,99,y+4); oled.drawFrame(45,40+shake,38,14); oled.drawLine(45,47+shake,83,47+shake); oled.drawLine(54,40+shake,54,54+shake); oled.drawLine(64,40+shake,64,54+shake); oled.drawLine(74,40+shake,74,54+shake); drawSweat(); oled.drawLine(18,14,23,22); oled.drawLine(110,10,104,19); oled.drawLine(16,30,23,33); oled.drawLine(111,31,104,34); }
void drawSleepFace(int cy,int step){ drawClosedEyes(cy); oled.drawLine(56,45,72,45); oled.setFont(u8g2_font_6x12_tr); if(step%18<9) oled.drawStr(94,52,"zZ"); else oled.drawStr(98,48,"z"); }

void drawFaceFrame(){
  if(screenOff){ clearScreen(); return; }
  oled.clearBuffer();
  int step=faceAnimStep; bool blink=(step%24==0||step%24==1); int bob=(step%12<6)?0:1; int shake=(faceMood=="power"&&faceIntensity>=85)?((step%2==0)?-1:1):0; int cy=24+bob+shake;
  if(faceMood=="sleep") drawSleepFace(cy,step);
  else if(faceMood=="happy"){ if(blink) drawClosedEyes(cy); else drawHappyEyes(20+bob); if(faceVariant=="soft"||faceIntensity<18) drawCuteSmile(); else drawBigSmile(); if(step%8<4){ oled.drawPixel(20,13); oled.drawPixel(108,15); } }
  else if(faceMood=="focus"){ if(blink) drawClosedEyes(cy); else drawFocusEyes(); drawFlatMouth(); oled.drawLine(18,15,22,15); oled.drawLine(106,15,110,15); }
  else if(faceMood=="busy"){ if(blink) drawClosedEyes(cy); else drawBusyEyes(); drawConcernMouth(); drawSweat(); }
  else if(faceMood=="power") drawPowerFace(shake);
  else if(faceMood=="idle"){ if(blink) drawClosedEyes(cy); else { int dx=(step%28<14)?-3:3; drawSoftEyes(cy,dx); } if(step%40<20) drawTinySmile(); else drawFlatMouth(); }
  else if(faceMood=="play"){ int dx=(step%12<6)?-4:4; drawSoftEyes(cy,dx); drawBigSmile(); oled.drawLine(12,42,24,34+(step%2)*4); oled.drawLine(116,42,104,34+(step%2)*4); if(step%6<3){ oled.drawPixel(18,12); oled.drawPixel(19,13); oled.drawPixel(110,12); oled.drawPixel(109,13); } }
  else { if(blink) drawClosedEyes(cy); else drawSoftEyes(cy,0); drawCuteSmile(); }
  oled.sendBuffer();
}

void refreshScreen(){ if(screenOff) clearScreen(); else if(viewMode==VIEW_TEXT) drawTextScreen(); else drawFaceFrame(); }
void showBoot(const char* a,const char* b,const char* c){ screenOff=false; viewMode=VIEW_TEXT; line0="BKB Mac Brain"; line1=a; line2=b; line3=c; drawTextScreen(); }

void publishOnline(const char* status){ mqttClient.publish("bkb/desk1/state/online", status, true); }
void publishTelemetry(){ StaticJsonDocument<160> doc; doc["id"]=DEVICE_ID; doc["ip"]=WiFi.localIP().toString(); doc["rssi"]=WiFi.RSSI(); doc["ms"]=millis(); char buf[160]; serializeJson(doc,buf); mqttClient.publish("bkb/desk1/state/telemetry",buf,false); }
void publishButtonEvent(int id){ StaticJsonDocument<96> doc; doc["id"]=DEVICE_ID; doc["button"]=id; doc["pressed"]=1; doc["ms"]=millis(); char buf[96]; serializeJson(doc,buf); mqttClient.publish(id==1?"bkb/desk1/event/button/1":"bkb/desk1/event/button/2",buf,false); }

void handleSystemJson(const char* payload){ StaticJsonDocument<128> doc; if(deserializeJson(doc,payload)) return; if(doc["screen"].is<const char*>()){ String m=doc["screen"].as<const char*>(); if(m=="off"){ screenOff=true; refreshScreen(); } else if(m=="on"){ screenOff=false; refreshScreen(); } } }
void handleFaceJson(const char* payload){ StaticJsonDocument<192> doc; if(deserializeJson(doc,payload)) return; if(doc["mood"].is<const char*>()) faceMood=doc["mood"].as<const char*>(); else if(doc["name"].is<const char*>()) faceMood=doc["name"].as<const char*>(); else faceMood="idle"; if(doc["variant"].is<const char*>()) faceVariant=doc["variant"].as<const char*>(); else faceVariant="normal"; if(doc["intensity"].is<int>()) faceIntensity=constrain(doc["intensity"].as<int>(),0,100); else faceIntensity=20; viewMode=VIEW_FACE; faceAnimStep=0; faceAnimLast=0; refreshScreen(); }
void handleDisplayJson(const char* payload){ StaticJsonDocument<256> doc; if(deserializeJson(doc,payload)) return; if(doc["l0"].is<const char*>()) line0=fit16(doc["l0"].as<const char*>()); if(doc["l1"].is<const char*>()) line1=fit16(doc["l1"].as<const char*>()); if(doc["l2"].is<const char*>()) line2=fit16(doc["l2"].as<const char*>()); if(doc["l3"].is<const char*>()) line3=fit16(doc["l3"].as<const char*>()); viewMode=VIEW_TEXT; refreshScreen(); }
void mqttCallback(char* topic, byte* payload, unsigned int length){ String msg; msg.reserve(length+1); for(unsigned int i=0;i<length;i++) msg+=(char)payload[i]; String t=String(topic); if(t=="bkb/desk1/desired/system") handleSystemJson(msg.c_str()); else if(t=="bkb/desk1/desired/face") handleFaceJson(msg.c_str()); else if(t=="bkb/desk1/desired/display") handleDisplayJson(msg.c_str()); }

void connectWiFi(){ WiFi.mode(WIFI_STA); WiFi.begin(WIFI_SSID,WIFI_PASS); showBoot("WiFi Connecting","",""); int dots=0; while(WiFi.status()!=WL_CONNECTED){ delay(500); line2="Wait "+String(++dots); drawTextScreen(); } line1="WiFi Connected"; line2=WiFi.localIP().toString(); line3="MQTT Next"; drawTextScreen(); delay(500); }
boolean connectMQTT(){ String clientId="bkb-esp32-"+String((uint32_t)ESP.getEfuseMac(),HEX); if(mqttClient.connect(clientId.c_str(),"bkb/desk1/state/online",0,true,"offline")){ mqttClient.subscribe("bkb/desk1/desired/system"); mqttClient.subscribe("bkb/desk1/desired/face"); mqttClient.subscribe("bkb/desk1/desired/display"); publishOnline("online"); publishTelemetry(); screenOff=false; viewMode=VIEW_TEXT; line0="BKB Mac Brain"; line1="MQTT Connected"; line2="Topics Ready"; line3=DEVICE_ID; drawTextScreen(); return true; } screenOff=false; viewMode=VIEW_TEXT; line0="BKB Mac Brain"; line1="MQTT Retry"; line2="Check Broker"; line3=String(mqttClient.state()); drawTextScreen(); return false; }
void pollButton(int pin,bool& lastRead,bool& lastStable,unsigned long& lastChange,int id){ bool r=digitalRead(pin); if(r!=lastRead){ lastChange=millis(); lastRead=r; } if(millis()-lastChange>debounceMs && lastStable!=r){ lastStable=r; if(lastStable==LOW && mqttClient.connected()) publishButtonEvent(id); } }

void setup(){ Serial.begin(115200); delay(1000); pinMode(BTN1_PIN,INPUT_PULLUP); pinMode(BTN2_PIN,INPUT_PULLUP); oled.begin(); oled.clearBuffer(); oled.setFont(u8g2_font_6x12_tr); showBoot("ESP32 Runtime","OLED Ready","Starting"); connectWiFi(); mqttClient.setServer(MQTT_HOST,MQTT_PORT); mqttClient.setCallback(mqttCallback); mqttClient.setBufferSize(768); }
void loop(){ unsigned long now=millis(); if(!mqttClient.connected()){ if(now-lastReconnectAttempt>2000){ lastReconnectAttempt=now; connectMQTT(); } } else mqttClient.loop(); pollButton(BTN1_PIN,btn1LastRead,btn1LastStable,btn1LastChange,1); pollButton(BTN2_PIN,btn2LastRead,btn2LastStable,btn2LastChange,2); if(mqttClient.connected() && now-lastTelemetry>=30000){ lastTelemetry=now; publishTelemetry(); } if(!screenOff && viewMode==VIEW_FACE && now-faceAnimLast>=160){ faceAnimLast=now; faceAnimStep++; drawFaceFrame(); } }
