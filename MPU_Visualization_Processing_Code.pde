/*
  MotionPotion — MPU6050 Roll / Pitch / Yaw visualizer 

  Keys
    C        calibrate (hold the MPU flat first)
    F        next object
    1 - 5    pick an object: Jet, Sad Man, Frog, Knife, Gun
    G        play "Sad Man vs the Space Frogs" (G again to come back)

  Every object is built from code — no model files needed.
  Optional: drop a goofy .ttf (e.g. Bangers-Regular.ttf from Google Fonts)
  into this sketch's "data" folder and the fun text will use it.
  Otherwise it uses Comic Sans MS, which ships with Windows.
*/
import processing.serial.*;

// ════════════════════════════════════════════════
//  >>> STUDENTS: CHANGE THIS TO YOUR COM PORT <<<
//  Put the same COM port you used when you uploaded the ESP32 code
//  (Arduino IDE > Tools > Port), e.g. "COM3" or "COM7".
//  On Mac/Linux it looks like "/dev/cu.usbserial-XXXX" or "/dev/ttyUSB0".
//  Close the Arduino Serial Monitor first — only one program can use the port.
// ════════════════════════════════════════════════
String COM_PORT = "COM5";

// Game settings (press G). Only change these if steering feels wrong.
boolean GAME_USE_ROLL   = true;    // true = steer with ROLL, false = steer with PITCH
boolean GAME_INVERT     = false;   // true if Sad Man moves the opposite way to your tilt
float   GAME_TILT_RANGE = 30;      // degrees of tilt needed to reach the edge of the screen

Serial port;
boolean demoMode = true;    // true until the first ESP data arrives: the model sways on its own
int lastDataTime = -1;      // millis() when the last valid line arrived from the ESP (-1 = never)

float pitch = 0, roll = 0, yaw = 0;
float smoothPitch = 0, smoothRoll = 0, smoothYaw = 0;
float lerpSpeed = 0.15;

// Calibration offsets — captured when user presses C
float offsetPitch = 0;
float offsetRoll  = 0;
float offsetYaw   = 0;
boolean calibrated = false;

// Camera: a 3/4 view from slightly above.
// Set both to 0 to get the original straight-on side view back.
float VIEW_TILT = -18;   // degrees: look down at the model
float VIEW_TURN = 28;    // degrees: turn the nose toward you

// ── Objects ────────────────────────────────────
final int JET = 0, SADMAN = 1, FROG = 2, KNIFE = 3, GUN = 4;
String[] modelNames = { "JET", "SAD MAN", "FROG", "KNIFE", "GUN" };
String[] modelQuips = {
  "pew pew pew pew",
  "he saves the day. he is not happy about it.",
  "ribbit. (is that a fly)",
  "unfortunately can't trade",
  "HANDS UP"
};
float[] modelScale = { 1.0, 1.25, 1.45, 1.1, 1.25 };
int currentModel = JET;
int switchTime = -100000;

PFont hudFont, funFont, labelFont;
float t = 0;   // seconds since start, for animations

// Buttons (y positions follow the window height)
float btnX = 20, btnW = 220, btnH = 38;
float funBtnY, calBtnY;

// Background stars
int NSTARS = 160;
float[] starX, starY, starB, starS;

// Sad Man's personal rain cloud
int NDROPS = 22;
float[] dropX, dropZ, dropOff;

void setup() {
  size(900, 650, P3D);
  surface.setResizable(true);
  surface.setTitle("MotionPotion");
  sphereDetail(22);

  hudFont   = createFont("SansSerif", 14, true);
  labelFont = createFont("SansSerif.bold", 32, true);
  funFont   = loadFunFont(40);

  randomSeed(7);
  starX = new float[NSTARS]; starY = new float[NSTARS];
  starB = new float[NSTARS]; starS = new float[NSTARS];
  for (int i = 0; i < NSTARS; i++) {
    starX[i] = random(1); starY[i] = random(1);
    starB[i] = random(40, 200); starS[i] = random(1, 2.6);
  }
  dropX = new float[NDROPS]; dropZ = new float[NDROPS]; dropOff = new float[NDROPS];
  for (int i = 0; i < NDROPS; i++) {
    dropX[i] = random(-84, -26); dropZ[i] = random(-16, 16); dropOff[i] = random(1);
  }

  // Serial: opens the port set in COM_PORT at the top of this sketch
  printArray(Serial.list());   // lists available ports in the console, handy if yours won't open
  try {
    port = new Serial(this, COM_PORT, 115200);
    port.bufferUntil('\n');
  } catch (Exception e) {
    println("Could not open " + COM_PORT + " -> demo mode. Check COM_PORT at the top of the sketch.");
    demoMode = true;
  }
}

// Picks the goofiest font available
PFont loadFunFont(int sz) {
  String[] files = { "Bangers-Regular.ttf", "LuckiestGuy-Regular.ttf", "fun.ttf" };
  for (String f : files) {
    if (new File(dataPath(f)).exists()) return createFont(f, sz, true);
  }
  String[] wanted = { "Comic Sans MS Bold", "Comic Sans MS", "Chalkboard SE Bold", "Comic Neue Bold", "Marker Felt" };
  String[] installed = PFont.list();
  for (String w : wanted) {
    for (String n : installed) {
      if (n.equalsIgnoreCase(w)) return createFont(n, sz, true);
    }
  }
  return createFont("SansSerif.bold", sz, true);
}

void draw() {
  t = millis() / 1000.0;

  // Demo plays until the first real ESP data arrives. After that it stays live:
  // the ESP only sends when the angle changes, so a sensor lying still is silent.
  demoMode = port == null || lastDataTime < 0;

  if (demoMode && !gameMode) {
    pitch = 28 * sin(t * 0.7);
    roll  = 22 * sin(t * 0.5 + 1);
    yaw   = 18 * sin(t * 0.3);
  }

  // Subtract calibration offsets so "flat on table" = 0,0,0
  // wrap180 keeps everything in -180..180, so no more 309° readings
  float adjPitch = wrap180(pitch - offsetPitch);
  float adjRoll  = wrap180(roll  - offsetRoll);
  float adjYaw   = wrap180(yaw   - offsetYaw);

  // Smooth along the shortest way round (no spinning the long way past ±180)
  smoothPitch = wrap180(smoothPitch + wrap180(adjPitch - smoothPitch) * lerpSpeed);
  smoothRoll  = wrap180(smoothRoll  + wrap180(adjRoll  - smoothRoll)  * lerpSpeed);
  smoothYaw   = wrap180(smoothYaw   + wrap180(adjYaw   - smoothYaw)   * lerpSpeed);

  if (gameMode) { drawGame(); return; }   // "Don't Press G" (game code is at the bottom)

  background(12, 12, 28);
  drawStars();

  // ── 3D scene ──
  pushMatrix();
  setupLights();
  translate(width / 2, height / 2 + 10, 0);
  rotateX(radians(VIEW_TILT));
  rotateY(radians(VIEW_TURN));

  float s = 1.9 * min(width / 900.0, height / 650.0);
  scale(s);
  drawFloor();

  rotateX(radians(smoothPitch));
  rotateY(radians(smoothYaw));
  rotateZ(radians(-smoothRoll));

  // little "boing" when you switch objects
  float since = (millis() - switchTime) / 1000.0;
  float pop = since < 0.45 ? easeOutBack(since / 0.45) : 1;
  scale(modelScale[currentModel] * max(pop, 0.05));

  noStroke();
  switch (currentModel) {
    case JET:    drawJet();    break;
    case SADMAN: drawSadMan(); break;
    case FROG:   drawFrog();   break;
    case KNIFE:  drawKnife();  break;
    case GUN:    drawGun();    break;
  }
  emissive(0);
  specular(0);
  popMatrix();

  // ── 2D HUD layer (drawn last so it sits on top) ──
  hint(DISABLE_DEPTH_TEST);
  camera();
  noLights();
  drawHUD();
  drawButtons();
  drawToast();
  drawDemoBanner();
  hint(ENABLE_DEPTH_TEST);
}

float wrap180(float a) {
  a = (a + 180) % 360;
  if (a < 0) a += 360;
  return a - 180;
}

float easeOutBack(float x) {
  x = constrain(x, 0, 1);
  float c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2);
}

// ── Calibration ────────────────────────────────
// Call this with MPU flat on the table.
// Captures current raw pitch/roll/yaw as the "zero" reference.
void calibrate() {
  if (demoMode) return;   // don't calibrate against the fake demo motion
  offsetPitch = pitch;
  offsetRoll  = roll;
  offsetYaw   = yaw;
  // Snap smoothed values immediately — no lerp lag after calibration
  smoothPitch = 0;
  smoothRoll  = 0;
  smoothYaw   = 0;
  calibrated  = true;
}

void setModel(int m) {
  currentModel = (m + modelNames.length) % modelNames.length;
  switchTime = millis();
}

boolean over(float x, float y, float w, float h) {
  return mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
}

void mousePressed() {
  if (gameMode) return;
  if (over(btnX, calBtnY, btnW, btnH)) calibrate();
  if (over(26, 192 - 24, funFW, 30)) setModel(currentModel + 1);   // "Don't Press F !"
  if (over(26, 218 - 24, funGW, 30)) enterGame();                  // "Don't Press G !"
}
void keyPressed() {
  if (key == 'g' || key == 'G') {
    if (gameMode) exitGame(); else enterGame();
    return;
  }
  if (gameMode) { gameKeyPressed(); return; }
  if (key == 'c' || key == 'C') calibrate();
  if (key == 'f' || key == 'F') setModel(currentModel + 1);
  if (key >= '1' && key <= '5') setModel(key - '1');
}
void keyReleased() {
  if (gameMode) gameKeyReleased();
}

// ── Scene helpers ──────────────────────────────
void setupLights() {
  ambientLight(52, 54, 70);
  lightSpecular(255, 255, 255);
  directionalLight(225, 218, 205, 0.3, 0.75, -0.6);   // key light: above, front
  lightSpecular(0, 0, 0);
  directionalLight(95, 100, 118, -0.55, 0.1, -0.85);  // soft fill from the front-left
  directionalLight(70, 95, 150, -0.4, -0.5, 0.75);    // cool rim light from behind
}

void drawStars() {
  hint(DISABLE_DEPTH_TEST);
  for (int i = 0; i < NSTARS; i++) {
    float tw = starB[i] * (0.6 + 0.4 * sin(t * 1.7 + i * 1.3));
    stroke(200, 210, 255, tw);
    strokeWeight(starS[i]);
    point(starX[i] * width, starY[i] * height);
  }
  noStroke();
  hint(ENABLE_DEPTH_TEST);
}

// A faint grid floor + soft shadow, so you can see which way is "down"
void drawFloor() {
  float gy = 150, step = 40;
  int n = 10;
  strokeWeight(1);
  for (int i = -n; i <= n; i++) {
    for (int j = -n; j < n; j++) {
      float d1 = dist(0, 0, i * step, (j + 0.5) * step) / (n * step);
      float a = 80 * max(0, 1 - d1);
      if (a < 2) continue;
      stroke(70, 105, 200, a);
      line(i * step, gy, j * step, i * step, gy, (j + 1) * step);
      line(j * step, gy, i * step, (j + 1) * step, gy, i * step);
    }
  }
  noStroke();
  hint(DISABLE_DEPTH_MASK);
  fill(0, 0, 0, 55);
  pushMatrix();
  translate(0, gy - 0.5, 0);
  rotateX(HALF_PI);
  ellipse(0, 0, 220, 130);
  popMatrix();
  hint(ENABLE_DEPTH_MASK);
}

// ── Materials ──────────────────────────────────
void mat(float r, float g, float b) {
  fill(r, g, b); specular(25); shininess(6); emissive(0);
}
void shiny(float r, float g, float b, float spec, float shin) {
  fill(r, g, b); specular(spec); shininess(shin); emissive(0);
}
void glass(float r, float g, float b, float a) {
  fill(r, g, b, a); specular(255); shininess(60); emissive(0);
}
void glow(float r, float g, float b, float a) {
  fill(r, g, b, a); specular(0); emissive(r * 0.85, g * 0.85, b * 0.85);
}

// ── Geometry helpers ───────────────────────────
void ellipsoid(float x, float y, float z, float rx, float ry, float rz) {
  pushMatrix();
  translate(x, y, z);
  scale(rx, ry, rz);
  sphere(1);
  popMatrix();
}

void ball(float x, float y, float z, float r) {
  ellipsoid(x, y, z, r, r, r);
}

// Tapered cylinder between two points
void tube(float x1, float y1, float z1, float x2, float y2, float z2, float r1, float r2, boolean caps) {
  float dx = x2 - x1, dy = y2 - y1, dz = z2 - z1;
  float L = sqrt(dx * dx + dy * dy + dz * dz);
  if (L < 0.0001) return;
  pushMatrix();
  translate(x1, y1, z1);
  // rotate the +Y axis onto the direction (dx,dy,dz)
  float ax = dz, az = -dx;               // (0,1,0) x d
  float am = sqrt(ax * ax + az * az);
  float ang = acos(constrain(dy / L, -1, 1));
  if (am > 0.0001) rotate(ang, ax / am, 0, az / am);
  else if (dy < 0) rotateX(PI);
  int seg = 16;
  float slope = (r1 - r2) / L;
  beginShape(QUAD_STRIP);
  for (int i = 0; i <= seg; i++) {
    float a = TWO_PI * i / seg, c = cos(a), sn = sin(a);
    normal(c, slope, sn);
    vertex(r1 * c, 0, r1 * sn);
    vertex(r2 * c, L, r2 * sn);
  }
  endShape();
  if (caps) {
    for (int e = 0; e < 2; e++) {
      float r = e == 0 ? r1 : r2, yy = e == 0 ? 0 : L;
      if (r < 0.2) continue;
      beginShape(TRIANGLE_FAN);
      normal(0, e == 0 ? -1 : 1, 0);
      vertex(0, yy, 0);
      for (int i = 0; i <= seg; i++) {
        float a = TWO_PI * i / seg;
        vertex(r * cos(a), yy, r * sin(a));
      }
      endShape();
    }
  }
  popMatrix();
}

// Rounded "pipe" through a list of points
void chain(float[][] p, float r) {
  for (int i = 0; i < p.length - 1; i++) {
    tube(p[i][0], p[i][1], p[i][2], p[i + 1][0], p[i + 1][1], p[i + 1][2], r, r, false);
  }
  for (int i = 0; i < p.length; i++) ball(p[i][0], p[i][1], p[i][2], r);
}

// Smooth body along the X axis with elliptical cross sections
void loftX(float[] xs, float[] ys, float[] ry, float[] rz, int seg) {
  int n = xs.length;
  for (int i = 0; i < n - 1; i++) {
    beginShape(QUAD_STRIP);
    for (int j = 0; j <= seg; j++) {
      float a = TWO_PI * j / seg, ca = cos(a), sa = sin(a);
      for (int k = i; k <= i + 1; k++) {
        int lo = max(k - 1, 0), hi = min(k + 1, n - 1);
        float sl = ((ry[hi] + rz[hi]) - (ry[lo] + rz[lo])) * 0.5 / (xs[hi] - xs[lo]);
        float ny = sa / max(ry[k], 0.01), nz = ca / max(rz[k], 0.01);
        float m = sqrt(ny * ny + nz * nz);
        normal(-sl, ny / m, nz / m);
        vertex(xs[k], ys[k] + ry[k] * sa, rz[k] * ca);
      }
    }
    endShape();
  }
  capX(xs[0], ys[0], ry[0], rz[0], seg, -1);
  capX(xs[n - 1], ys[n - 1], ry[n - 1], rz[n - 1], seg, 1);
}

void capX(float x, float y, float ry, float rz, int seg, int dir) {
  if (ry < 0.3 && rz < 0.3) return;
  beginShape(TRIANGLE_FAN);
  normal(dir, 0, 0);
  vertex(x, y, 0);
  for (int j = 0; j <= seg; j++) {
    float a = TWO_PI * j / seg;
    vertex(x, y + ry * sin(a), rz * cos(a));
  }
  endShape();
}

// A thin plate (wing, fin, panel). p = 4 corners of its middle surface,
// th = thickness at each corner, axis = thickness direction (0=x, 1=y, 2=z)
void slab(float[][] p, float[] th, int axis) {
  float[][] a = new float[4][], b = new float[4][];
  float cx = 0, cy = 0, cz = 0;
  for (int i = 0; i < 4; i++) {
    a[i] = p[i].clone(); b[i] = p[i].clone();
    a[i][axis] -= th[i] * 0.5;
    b[i][axis] += th[i] * 0.5;
    cx += p[i][0] / 4; cy += p[i][1] / 4; cz += p[i][2] / 4;
  }
  beginShape(QUADS);
  quadOut(a[0], a[1], a[2], a[3], cx, cy, cz);
  quadOut(b[0], b[1], b[2], b[3], cx, cy, cz);
  for (int i = 0; i < 4; i++) {
    int j = (i + 1) % 4;
    quadOut(a[i], a[j], b[j], b[i], cx, cy, cz);
  }
  endShape();
}

void slab(float[][] p, float th, int axis) {
  slab(p, new float[] { th, th, th, th }, axis);
}

// One quad, with its normal flipped to point away from (cx,cy,cz)
void quadOut(float[] a, float[] b, float[] c, float[] d, float cx, float cy, float cz) {
  float ux = c[0] - a[0], uy = c[1] - a[1], uz = c[2] - a[2];
  float vx = d[0] - b[0], vy = d[1] - b[1], vz = d[2] - b[2];
  float nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
  float fx = (a[0] + b[0] + c[0] + d[0]) / 4 - cx;
  float fy = (a[1] + b[1] + c[1] + d[1]) / 4 - cy;
  float fz = (a[2] + b[2] + c[2] + d[2]) / 4 - cz;
  if (nx * fx + ny * fy + nz * fz < 0) { nx = -nx; ny = -ny; nz = -nz; }
  normal(nx, ny, nz);
  vertex(a[0], a[1], a[2]);
  vertex(b[0], b[1], b[2]);
  vertex(c[0], c[1], c[2]);
  vertex(d[0], d[1], d[2]);
}

// Front surface x of an ellipsoid at height y, depth z (for putting faces on heads)
float frontX(float cx, float cy, float cz, float rx, float ry, float rz, float y, float z) {
  float k = 1 - sq((y - cy) / ry) - sq((z - cz) / rz);
  return cx - rx * sqrt(max(0, k));
}

// Flat disk lying in the XZ plane, facing up (-Y)
void decal(float x, float y, float z, float d) {
  pushMatrix();
  translate(x, y, z);
  rotateX(HALF_PI);
  ellipse(0, 0, d, d);
  popMatrix();
}

// ════════════════════════════════════════════════
//  JET  (nose points to -X, top is -Y, wings along Z)
// ════════════════════════════════════════════════
void drawJet() {
  float ail  = constrain(smoothPitch * 0.35, -22, 22);  // ailerons wiggle with banking
  float elev = constrain(smoothRoll  * 0.30, -18, 18);  // tail planes follow nose up/down

  // Radome (nose cone)
  mat(92, 97, 108);
  loftX(new float[] { -150, -141, -127, -112 },
        new float[] { 3, 2.6, 1.9, 1.2 },
        new float[] { 0, 3.8, 6.8, 8.6 },
        new float[] { 0, 3.8, 6.8, 8.6 }, 22);

  // Fuselage
  mat(160, 167, 178);
  loftX(new float[] { -112, -95, -75, -55, -35, -10, 20, 50, 80, 100, 112 },
        new float[] { 1.2, 0.8, 0.5, 0.5, 0.5, 0, 0, 0, -0.5, -0.5, -0.5 },
        new float[] { 8.6, 10.5, 12, 12.5, 13, 13, 12.5, 12, 11, 10, 9.5 },
        new float[] { 8.6, 10, 11, 13, 17, 19, 19, 17, 13, 10.5, 9.5 }, 26);

  // Spine hump behind the cockpit
  ellipsoid(5, -9, 0, 62, 7.5, 8.5);

  // Belly air intake with a dark mouth
  mat(140, 146, 158);
  loftX(new float[] { -56, -42, -10, 18 },
        new float[] { 13, 13, 12, 9 },
        new float[] { 5.5, 6.2, 6, 4 },
        new float[] { 10, 10.5, 9.5, 7 }, 20);
  mat(18, 18, 24);
  capX(-56.4, 13, 4.3, 8.6, 20, -1);

  // Leading-edge strakes
  mat(150, 157, 168);
  for (int sd = -1; sd <= 1; sd += 2) {
    slab(new float[][] { { -98, 2.5, 7 * sd }, { -45, 3, 18 * sd }, { -20, 3, 14 * sd }, { -20, 3, 8 * sd } }, 2, 1);
  }

  // Main wings + ailerons
  for (int sd = -1; sd <= 1; sd += 2) {
    mat(150, 157, 168);
    slab(new float[][] { { -45, 3, 16 * sd }, { 22, 3, 16 * sd }, { 22, 3, 90 * sd }, { 15, 3, 90 * sd } },
         new float[] { 3.6, 3.6, 1.5, 1.5 }, 1);
    mat(128, 134, 146);
    slab(new float[][] { { 22, 3, 16 * sd }, { 36, 3, 16 * sd }, { 36, 3, 22 * sd }, { 22, 3, 22 * sd } }, 2.6, 1);
    pushMatrix();
    translate(22, 3, 0);
    rotateZ(radians(ail * sd));
    slab(new float[][] { { 0, 0, 23 * sd }, { 13, 0, 23 * sd }, { 13, 0, 88 * sd }, { 0, 0, 88 * sd } },
         new float[] { 2.2, 1.2, 1.0, 1.6 }, 1);
    popMatrix();

    // roundel on top of each wing
    fill(255, 153, 51);  decal(-2, 1.4, 62 * sd, 15);
    fill(250, 250, 250); decal(-2, 1.3, 62 * sd, 10);
    fill(19, 136, 8);    decal(-2, 1.2, 62 * sd, 5);
  }

  // All-moving tail planes
  mat(145, 152, 164);
  for (int sd = -1; sd <= 1; sd += 2) {
    pushMatrix();
    translate(94, 4, 0);
    rotateZ(radians(elev));
    slab(new float[][] { { -16, 0, 9 * sd }, { 16, 0, 9 * sd }, { 18, 0, 46 * sd }, { 6, 0, 46 * sd } },
         new float[] { 2.4, 2.4, 1.2, 1.2 }, 1);
    popMatrix();
  }

  // Vertical tail with a coloured tip
  mat(150, 157, 168);
  slab(new float[][] { { 52, -9, 0 }, { 108, -9, 0 }, { 120, -64, 0 }, { 101, -64, 0 } },
       new float[] { 3.2, 3.2, 1.4, 1.4 }, 2);
  mat(255, 120, 40);
  slab(new float[][] { { 99, -56, 0 }, { 117.5, -56, 0 }, { 120.5, -65, 0 }, { 100.5, -65, 0 } }, 1.9, 2);

  // tail number
  textFont(labelFont);
  textSize(8);
  textAlign(CENTER, CENTER);
  fill(40, 44, 56);
  pushMatrix(); translate(88, -30, 1.5); text("MP-01", 0, 0); popMatrix();
  pushMatrix(); translate(88, -30, -1.5); rotateY(PI); text("MP-01", 0, 0); popMatrix();

  // Ventral fins
  mat(130, 136, 148);
  for (int sd = -1; sd <= 1; sd += 2) {
    slab(new float[][] { { 70, 8, 7 * sd }, { 96, 8, 7 * sd }, { 96, 19, 10 * sd }, { 86, 19, 10 * sd } }, 1.2, 2);
  }

  // Engine nozzle
  shiny(72, 72, 80, 160, 25);
  loftX(new float[] { 108, 114, 126, 133 },
        new float[] { -0.5, -0.5, -0.5, -0.5 },
        new float[] { 9.5, 10.2, 9, 8.5 },
        new float[] { 9.5, 10.2, 9, 8.5 }, 24);
  mat(20, 18, 18);
  capX(133.3, -0.5, 6.8, 6.8, 20, 1);

  // Missiles: wingtips + under the wings
  for (int sd = -1; sd <= 1; sd += 2) {
    missile(8, 3, 93.5 * sd, 46, 2.2);
    mat(128, 134, 146);
    slab(new float[][] { { -12, 4, 55 * sd }, { 12, 4, 55 * sd }, { 10, 9.5, 55 * sd }, { -8, 9.5, 55 * sd } }, 1.6, 2);
    missile(0, 12.5, 55 * sd, 56, 2.8);
  }

  // Pitot probe
  mat(60, 60, 66);
  tube(-150, 3, 0, -168, 3, 0, 0.9, 0.5, false);

  // Pilot (visible through the glass)
  mat(240, 240, 235);
  ball(-80, -12, 0, 4.6);
  shiny(30, 30, 40, 200, 40);
  ellipsoid(-83.6, -12, 0, 2, 2.3, 3.4);

  // Lights: red = left wing, green = right wing, white strobe on the tail
  glow(255, 40, 40, 255);  ball(14, 3, 91, 2.2);
  glow(40, 255, 90, 255);  ball(14, 3, -91, 2.2);
  float st = (millis() % 1300) / 1300.0;
  if (st < 0.06 || (st > 0.12 && st < 0.18)) { glow(255, 255, 255, 255); ball(120, -64, 0, 2.6); }
  emissive(0);

  // ── see-through parts last ──
  hint(DISABLE_DEPTH_MASK);
  float L = 26 + 22 * noise(t * 9);
  glow(255, 110, 30, 120);
  tube(133, -0.5, 0, 133 + L, -0.5, 0, 7.5, 1, false);
  glow(255, 215, 150, 190);
  tube(133, -0.5, 0, 133 + L * 0.55, -0.5, 0, 4.6, 0.6, false);
  glow(255, 255, 230, 200);
  for (int k = 1; k <= 3; k++) ellipsoid(133 + L * 0.2 * k, -0.5, 0, 2.6, 1.8, 1.8);
  emissive(0);

  glass(110, 170, 225, 150);
  ellipsoid(-80, -10, 0, 25, 9.5, 8.2);
  hint(ENABLE_DEPTH_MASK);
}

void missile(float x, float y, float z, float len, float r) {
  float x0 = x - len / 2, x1 = x + len / 2;
  shiny(232, 232, 236, 90, 20);
  tube(x0, y, z, x1, y, z, r, r, true);
  shiny(70, 72, 80, 80, 20);
  tube(x0, y, z, x0 - r * 3.5, y, z, r, 0.15, false);
  mat(90, 94, 104);
  for (int sd = -1; sd <= 1; sd += 2) {
    // tail fins
    slab(new float[][] { { x1 - r * 4, y, z }, { x1, y, z }, { x1, y, z + r * 2.6 * sd }, { x1 - r * 1.5, y, z + r * 2.6 * sd } }, 0.5, 1);
    slab(new float[][] { { x1 - r * 4, y, z }, { x1, y, z }, { x1, y + r * 2.6 * sd, z }, { x1 - r * 1.5, y + r * 2.6 * sd, z } }, 0.5, 2);
    // small front fins
    slab(new float[][] { { x0 + r * 2, y, z }, { x0 + r * 4.5, y, z }, { x0 + r * 4, y, z + r * 1.6 * sd }, { x0 + r * 3, y, z + r * 1.6 * sd } }, 0.4, 1);
    slab(new float[][] { { x0 + r * 2, y, z }, { x0 + r * 4.5, y, z }, { x0 + r * 4, y + r * 1.6 * sd, z }, { x0 + r * 3, y + r * 1.6 * sd, z } }, 0.4, 2);
  }
  mat(200, 60, 50);  // red band
  tube(x0 + r * 5, y, z, x0 + r * 5.8, y, z, r * 1.03, r * 1.03, false);
}

// ════════════════════════════════════════════════
//  SAD MAN  (flies head-first toward -X, back is -Y)
// ════════════════════════════════════════════════
void drawSadMan() {
  pushMatrix();
  translate(15, 0, 0);

  float suitR = 72, suitG = 96, suitB = 168;
  float sway = constrain(smoothPitch, -60, 60) * 0.35;

  // Head — turned a little toward you so you can see how sad he is.
  // Everything inside this block is relative to the centre of the head.
  float hx = -100, hy = -6, hr = 18;
  pushMatrix();
  translate(hx, hy, 0);
  rotateY(radians(38));
  rotateZ(radians(-12));                               // chin down
  mat(238, 198, 168);
  ball(0, 0, 0, hr);
  ball(-18.4, 2, 0, 2.6);                              // nose

  // Cowl (hood) — sits behind the face
  mat(suitR, suitG, suitB);
  ball(9, -3.5, 0, 18.4);

  // Eyes: looking down, as one does
  for (int sd = -1; sd <= 1; sd += 2) {
    float ez = 6.2 * sd;
    float ex = frontX(0, 0, 0, hr, hr, hr, -4, ez);
    mat(250, 250, 250);
    ellipsoid(ex + 0.7, -4, ez, 2, 3.4, 3.1);
    mat(20, 20, 30);
    ball(ex - 1.1, -2.7, ez, 1.6);
    // sad eyebrows: inner end raised
    mat(60, 40, 30);
    float bx1 = frontX(0, 0, 0, hr, hr, hr, -10.5, 2.4 * sd) - 0.4;
    float bx2 = frontX(0, 0, 0, hr, hr, hr, -7.5, 10 * sd) - 0.4;
    chain(new float[][] { { bx1, -10.5, 2.4 * sd }, { bx2, -7.5, 10 * sd } }, 1);
  }

  // The frown
  mat(110, 40, 40);
  float[][] mouth = new float[11][];
  for (int i = 0; i < 11; i++) {
    float z = map(i, 0, 10, -7.5, 7.5);
    float y = 7 + 4 * sq(z / 7.5);
    mouth[i] = new float[] { frontX(0, 0, 0, hr, hr, hr, y, z) - 0.3, y, z };
  }
  chain(mouth, 1.05);

  // Tear, sliding down the cheek
  float tp = (t % 2.4) / 2.4;
  float ty = lerp(-1, 9, tp), tz = 9;
  float tx = frontX(0, 0, 0, hr, hr, hr, ty, tz) - 0.6;
  shiny(90, 170, 255, 255, 50);
  ball(tx, ty, tz, 1.8);
  tube(tx, ty, tz, tx + 0.3, ty - 3.4, tz, 1.7, 0.1, false);
  popMatrix();

  // Neck + torso (a little bit of dad bod)
  mat(238, 198, 168);
  tube(-92, -2, 0, -80, 0, 0, 7, 7, false);
  mat(suitR, suitG, suitB);
  loftX(new float[] { -86, -72, -52, -32, -14, -4 },
        new float[] { 0, 0, 1, 2, 1, 0 },
        new float[] { 9, 12, 13, 13.5, 11, 9.5 },
        new float[] { 14, 21, 20, 17, 14, 13 }, 24);

  // Belt + undies-over-tights
  shiny(205, 165, 55, 120, 20);
  loftX(new float[] { -9, -3 }, new float[] { 0.5, 0.3 }, new float[] { 11.2, 10.4 }, new float[] { 14.4, 13.6 }, 24);
  mat(45, 50, 92);
  loftX(new float[] { -3, 6, 13 }, new float[] { 0.3, 0.5, 1 }, new float[] { 10.2, 10, 8.5 }, new float[] { 13.6, 14.5, 13 }, 24);

  // Legs, sagging a bit
  for (int sd = -1; sd <= 1; sd += 2) {
    float z = 7.5 * sd;
    mat(suitR, suitG, suitB);
    tube(8, 1, z, 48, 6, z * 1.2, 7.2, 6.2, false);
    ball(48, 6, z * 1.2, 6.2);
    tube(48, 6, z * 1.2, 68, 10, z * 1.2, 6.2, 5.6, false);
    mat(112, 42, 52);                                    // boots
    tube(66, 9.6, z * 1.2, 84, 13, z * 1.2, 6.4, 6, false);
    ellipsoid(88, 15, z * 1.2, 8.5, 5.2, 5.6);
  }

  // Arms: one heroic, one... not really trying
  mat(suitR, suitG, suitB);
  chain(new float[][] { { -74, 0, -19 }, { -100, -3, -21 }, { -124, -6, -14 } }, 5.4);
  chain(new float[][] { { -74, 0, 19 }, { -72, 16, 24 }, { -66, 31, 22 } }, 5.4);
  mat(112, 42, 52);                                      // gloves
  ball(-129, -6, -13, 6.4);
  ellipsoid(-65, 36, 22, 5.4, 6.5, 5.4);

  // Cape, flapping, with a raindrop emblem
  drawCape(sway);

  // Personal rain cloud
  float bob = sin(t * 1.3) * 3;
  mat(150, 155, 172);
  ball(-54, -62 + bob, 0, 14);
  ball(-69, -58 + bob, 6, 10);
  ball(-39, -59 + bob, -4, 11);
  ball(-56, -68 + bob, -7, 10);
  ball(-45, -64 + bob, 9, 9);
  ball(-66, -64 + bob, -9, 9);
  stroke(120, 175, 255, 220);
  strokeWeight(2);
  for (int i = 0; i < NDROPS; i++) {
    float ph = (t * 1.4 + dropOff[i]) % 1;
    float y = lerp(-50 + bob, -14, ph);
    line(dropX[i], y, dropZ[i], dropX[i], y + 5, dropZ[i]);
  }
  noStroke();

  popMatrix();
}

void drawCape(float sway) {
  int nu = 14, nv = 8;
  float[][][] P = new float[nu + 1][nv + 1][];
  for (int i = 0; i <= nu; i++) {
    float u = i / (float) nu;
    for (int j = 0; j <= nv; j++) {
      float v = map(j, 0, nv, -1, 1);
      float x = -78 + u * 150;
      float z = v * (18 + u * 16) + u * u * sway;
      float y = -14.5 - u * 2 + sin(u * 7 - t * 6) * 5 * u + v * v * u * 7;
      P[i][j] = new float[] { x, y, z };
    }
  }
  for (int side = 0; side < 2; side++) {
    if (side == 0) mat(120, 98, 150); else mat(78, 58, 108);
    float off = side == 0 ? 0 : 0.7;
    float flip = side == 0 ? -1 : 1;   // top faces up (-Y), underside faces down
    beginShape(QUADS);
    for (int i = 0; i < nu; i++) {
      for (int j = 0; j < nv; j++) {
        float[] a = P[i][j], b = P[i + 1][j], c = P[i + 1][j + 1], d = P[i][j + 1];
        float ux = c[0] - a[0], uy = c[1] - a[1], uz = c[2] - a[2];
        float vx = d[0] - b[0], vy = d[1] - b[1], vz = d[2] - b[2];
        float nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
        if (ny * flip < 0) { nx = -nx; ny = -ny; nz = -nz; }
        normal(nx, ny, nz);
        vertex(a[0], a[1] + off, a[2]);
        vertex(b[0], b[1] + off, b[2]);
        vertex(c[0], c[1] + off, c[2]);
        vertex(d[0], d[1] + off, d[2]);
      }
    }
    endShape();
  }
  // emblem: a mustard patch with a blue raindrop, riding the cape
  float u = 0.3;
  int i0 = round(u * nu);
  float[] m = P[i0][nv / 2];
  shiny(210, 170, 60, 80, 15);
  ellipsoid(m[0], m[1] - 1.2, m[2], 13, 1.4, 11);
  shiny(80, 160, 255, 200, 40);
  pushMatrix();
  translate(m[0] + 3, m[1] - 2.3, m[2]);
  scale(1, 0.35, 1);
  ball(0, 0, 0, 5.2);
  tube(0, 0, 0, -12, 0, 0, 5, 0.2, false);
  popMatrix();
}

// ════════════════════════════════════════════════
//  FROG  (faces -X, sits on a lily pad, has a fly problem)
// ════════════════════════════════════════════════
void drawFrog() {
  float cyc = t % 6.0;
  float green_r = 92, green_g = 176, green_b = 74;

  // Lily pad
  drawLilyPad();

  // Gulp after catching the fly
  float gulp = (cyc > 5.0 && cyc < 5.6) ? sin(PI * (cyc - 5.0) / 0.6) : 0;

  // Body, belly, head (wet look = a bit of shine)
  shiny(green_r, green_g, green_b, 90, 18);
  ellipsoid(8, -2, 0, 42, 26, 36);
  shiny(226, 226, 150, 40, 10);
  ellipsoid(-6, 6 + gulp * 3, 0, 36, 18 + gulp * 4, 30 + gulp * 3);
  shiny(green_r, green_g, green_b, 90, 18);
  ellipsoid(-30, -12, 0, 30, 20, 33);

  // Spots
  shiny(56, 120, 48, 60, 12);
  float[][] spots = { { 15, 8, 7, 6 }, { 28, -14, 6, 5 }, { -2, -8, 5, 4.5 }, { 38, 14, 5, 4 }, { 8, -22, 4, 3.5 }, { 22, 24, 4, 3.5 } };
  for (float[] sp : spots) {
    float k = 1 - sq((sp[0] - 8) / 42) - sq(sp[1] / 36);
    float y = -2 - 26 * sqrt(max(0, k)) + 1.6;
    ellipsoid(sp[0], y, sp[1], sp[2], 2.4, sp[3]);
  }

  // Back legs (folded) with webbed toes
  for (int sd = -1; sd <= 1; sd += 2) {
    shiny(green_r, green_g, green_b, 90, 18);
    ellipsoid(28, 6, 30 * sd, 22, 11, 10);
    ellipsoid(12, 16, 38 * sd, 18, 7, 7);
    for (int k = 0; k < 3; k++) {
      float tz = (36 + k * 7) * sd;
      shiny(green_r, green_g, green_b, 90, 18);
      tube(0, 23, 40 * sd, -15, 24, tz, 2.4, 2, false);
      shiny(140, 210, 110, 60, 12);
      ball(-15.5, 24, tz, 3);
    }
    // Front legs
    shiny(green_r, green_g, green_b, 90, 18);
    tube(-28, 6, 20 * sd, -36, 23, 24 * sd, 4.6, 4, false);
    ball(-36, 23, 24 * sd, 4);
    for (int k = 0; k < 3; k++) {
      float tz = (18 + k * 6) * sd;
      tube(-36, 23.5, 24 * sd, -47, 24.5, tz, 1.8, 1.6, false);
      shiny(140, 210, 110, 60, 12);
      ball(-47.5, 24.5, tz, 2.5);
      shiny(green_r, green_g, green_b, 90, 18);
    }
  }

  // Big bulgy eyes (blinks every few seconds)
  boolean blink = (t % 3.7) < 0.15;
  for (int sd = -1; sd <= 1; sd += 2) {
    float ez = 17 * sd;
    shiny(green_r, green_g, green_b, 90, 18);
    ball(-34, -29, ez, 12);
    if (blink) {
      ellipsoid(-40.5, -33, ez, 8.8, 9.8, 9.8);           // eyelid
    } else {
      shiny(250, 250, 245, 120, 30);
      ellipsoid(-40, -33, ez, 8, 9, 9);
      shiny(222, 178, 40, 150, 30);
      ellipsoid(-47.3, -34, ez, 2.2, 5, 5);
      mat(10, 10, 10);
      ellipsoid(-49.2, -34, ez, 1, 2, 3.6);
      glow(255, 255, 255, 255);
      ball(-49.6, -36.2, ez - 1.8 * sd, 0.9);
      emissive(0);
    }
  }

  // Smile (corners up) and nostrils
  mat(35, 80, 35);
  float[][] smile = new float[11][];
  for (int i = 0; i < 11; i++) {
    float z = map(i, 0, 10, -26, 26);
    float y = -4 - 6 * sq(z / 26);
    smile[i] = new float[] { frontX(-30, -12, 0, 30, 20, 33, y, z) - 0.4, y, z };
  }
  chain(smile, 1.1);
  mat(30, 60, 30);
  for (int sd = -1; sd <= 1; sd += 2) ball(frontX(-30, -12, 0, 30, 20, 33, -17, 5 * sd), -17, 5 * sd, 1.1);

  // Fly + tongue
  float[] mouthP = { frontX(-30, -12, 0, 30, 20, 33, -4, 0) - 1, -4, 0 };
  float[] target = flyPos(t - cyc + 4.5);
  boolean flyAlive = cyc < 4.75;
  float e = 0;
  if (cyc >= 4.5 && cyc < 5.0) e = sin(PI * (cyc - 4.5) / 0.5);
  if (e > 0) {
    float tx = lerp(mouthP[0], target[0], e), ty = lerp(mouthP[1], target[1], e), tz = lerp(mouthP[2], target[2], e);
    shiny(232, 92, 122, 120, 25);
    tube(mouthP[0], mouthP[1], mouthP[2], tx, ty, tz, 2.4, 2, false);
    ball(tx, ty, tz, 4.2);
    if (!flyAlive && e > 0.2) drawFly(tx - 3, ty, tz);   // fly stuck on the tongue
  }
  if (flyAlive) {
    float[] f = cyc >= 4.5 ? target : flyPos(t);
    drawFly(f[0], f[1], f[2]);
  }
}

float[] flyPos(float tm) {
  return new float[] { -100 + 18 * sin(tm * 1.7), -42 + 10 * sin(tm * 2.3), 28 * sin(tm * 1.1) };
}

void drawFly(float x, float y, float z) {
  mat(25, 25, 30);
  ellipsoid(x, y, z, 3.2, 2.3, 2.3);
  ball(x - 3, y, z, 1.7);
  glow(255, 40, 40, 255);
  ball(x - 4, y - 0.8, z + 1, 0.7);
  ball(x - 4, y - 0.8, z - 1, 0.7);
  emissive(0);
  hint(DISABLE_DEPTH_MASK);
  float flap = 0.4 + 0.6 * abs(sin(t * 55));
  glass(230, 240, 255, 140);
  ellipsoid(x + 1.5, y - 2.5 * flap, z + 3, 3.2, 0.5, 2.4);
  ellipsoid(x + 1.5, y - 2.5 * flap, z - 3, 3.2, 0.5, 2.4);
  hint(ENABLE_DEPTH_MASK);
}

void drawLilyPad() {
  float y = 25.5, r = 72, th = 2.5;
  int seg = 44;
  float a0 = radians(22), a1 = radians(338);
  mat(58, 128, 62);
  beginShape(TRIANGLE_FAN);
  normal(0, -1, 0);
  vertex(0, y, 0);
  for (int i = 0; i <= seg; i++) {
    float a = lerp(a0, a1, i / (float) seg);
    vertex(r * cos(a), y, r * sin(a));
  }
  endShape();
  mat(40, 96, 46);
  beginShape(TRIANGLE_FAN);
  normal(0, 1, 0);
  vertex(0, y + th, 0);
  for (int i = 0; i <= seg; i++) {
    float a = lerp(a0, a1, i / (float) seg);
    vertex(r * cos(a), y + th, r * sin(a));
  }
  endShape();
  beginShape(QUAD_STRIP);
  for (int i = 0; i <= seg; i++) {
    float a = lerp(a0, a1, i / (float) seg);
    normal(cos(a), 0, sin(a));
    vertex(r * cos(a), y, r * sin(a));
    vertex(r * cos(a), y + th, r * sin(a));
  }
  endShape();
  // veins
  stroke(90, 160, 80, 200);
  strokeWeight(1.2);
  for (int i = 0; i < 9; i++) {
    float a = lerp(a0, a1, (i + 0.5) / 9.0);
    line(0, y - 0.2, 0, r * 0.92 * cos(a), y - 0.2, r * 0.92 * sin(a));
  }
  noStroke();
  // a tiny flower
  float fx = 30, fz = -52;
  for (int k = 0; k < 6; k++) {
    float a = k * TWO_PI / 6;
    shiny(255, 150, 200, 60, 10);
    ellipsoid(fx + 5 * cos(a), y - 2.5, fz + 5 * sin(a), 5, 2, 3);
  }
  shiny(255, 220, 60, 60, 10);
  ball(fx, y - 3.5, fz, 2.6);
}

// ════════════════════════════════════════════════
//  KNIFE  (tip to -X, edge down +Y, flat sides face ±Z)
// ════════════════════════════════════════════════
void drawKnife() {
  pushMatrix();
  translate(18, 0, 0);

  float x0 = -150, x1 = 8;
  int N = 46;
  float[][][] sec = new float[N + 1][][];
  for (int i = 0; i <= N; i++) {
    float u = i / (float) N;                    // 0 at tip, 1 at the guard
    float x = lerp(x0, x1, u);
    float spine = u < 0.35 ? -13 + 16 * sq(1 - u / 0.35) : -13;
    float edge  = u < 0.5  ? 3 + 11 * (1 - sq(1 - u / 0.5)) : 14;
    float th    = u < 0.4  ? 2.6 * pow(u / 0.4, 0.7) : 2.6;
    float bev   = spine + 0.55 * (edge - spine);
    sec[i] = new float[][] {
      { x, spine, th }, { x, bev, th }, { x, edge, 0 }, { x, bev, -th }, { x, spine, -th }
    };
  }
  // faces: 0 flat+, 1 bevel+, 2 bevel-, 3 flat-, 4 spine
  for (int f = 0; f < 5; f++) {
    if (f == 1 || f == 2) shiny(236, 240, 246, 255, 80);
    else shiny(185, 190, 202, 230, 35);
    int k0 = f, k1 = (f + 1) % 5;
    beginShape(QUADS);
    for (int i = 0; i < N; i++) {
      float cx = (sec[i][0][0] + sec[i + 1][0][0]) / 2;
      float cy = (sec[i][0][1] + sec[i][2][1]) / 2;
      quadOut(sec[i][k0], sec[i + 1][k0], sec[i + 1][k1], sec[i][k1], cx, cy, 0);
    }
    endShape();
  }
  // close the blade's back end
  mat(150, 155, 165);
  beginShape(TRIANGLE_FAN);
  normal(1, 0, 0);
  for (int k = 0; k < 5; k++) vertex(sec[N][k][0], sec[N][k][1], sec[N][k][2]);
  endShape();

  // Etched logo on both sides
  textFont(labelFont);
  textSize(6.5);
  textAlign(CENTER, CENTER);
  fill(95, 100, 112);
  pushMatrix(); translate(-42, -7, 2.7); text("MOTION POTION", 0, 0); popMatrix();
  pushMatrix(); translate(-42, -7, -2.7); rotateY(PI); text("MOTION POTION", 0, 0); popMatrix();

  // Guard
  shiny(70, 70, 78, 200, 40);
  pushMatrix(); translate(11, 0.5, 0); box(5, 34, 11); popMatrix();
  ellipsoid(11, -16.5, 0, 3.5, 3.5, 6);
  ellipsoid(11, 17.5, 0, 3.5, 3.5, 6);

  // Wooden handle with finger grooves
  int H = 24;
  float[] hx = new float[H], hy = new float[H], hry = new float[H], hrz = new float[H];
  for (int i = 0; i < H; i++) {
    float u = i / (float) (H - 1);
    hx[i] = lerp(14, 108, u);
    hy[i] = 1 + 1.4 * u;
    hry[i] = 10.5 + 1.6 * sin(u * TWO_PI * 2 - HALF_PI) * (1 - u * 0.5) + u * 1.2;
    hrz[i] = 7.2 + 0.6 * sin(u * TWO_PI * 2 - HALF_PI);
  }
  shiny(98, 58, 34, 50, 10);
  loftX(hx, hy, hry, hrz, 22);
  // brass rivets
  shiny(225, 180, 80, 220, 40);
  for (int k = 0; k < 3; k++) {
    float rx = 36 + k * 26;
    float u = (rx - 14) / 94.0;
    float rz = 7.2 + 0.6 * sin(u * TWO_PI * 2 - HALF_PI);
    ellipsoid(rx, 1 + 1.4 * u, rz - 0.4, 2.2, 2.2, 1.2);
    ellipsoid(rx, 1 + 1.4 * u, -rz + 0.4, 2.2, 2.2, 1.2);
  }
  // Pommel
  shiny(70, 70, 78, 200, 40);
  ellipsoid(111, 2.6, 0, 6, 12.5, 8.5);

  // *ting!* sparkle on the tip every few seconds
  float sp = (t % 3.0);
  if (sp < 0.35) {
    float k = sin(PI * sp / 0.35);
    hint(DISABLE_DEPTH_MASK);
    glow(255, 255, 255, 230);
    float cxs = -148, cys = 2;
    ellipsoid(cxs, cys, 0, 14 * k, 1, 1);
    ellipsoid(cxs, cys, 0, 1, 14 * k, 1);
    ellipsoid(cxs, cys, 0, 1, 1, 14 * k);
    ball(cxs, cys, 0, 2.5 * k);
    emissive(0);
    hint(ENABLE_DEPTH_MASK);
  }
  popMatrix();
}

// ════════════════════════════════════════════════
//  GUN  (a cartoon pistol: muzzle to -X, top is -Y)
// ════════════════════════════════════════════════
void drawGun() {
  pushMatrix();
  translate(40, -22, 0);

  float cyc = (t % 4.0) / 4.0;
  float since = cyc - 0.55;
  float recoil = (since > 0 && since < 0.1) ? 9 * sin(PI * since / 0.1) : 0;

  // Frame
  mat(72, 74, 84);
  pushMatrix(); translate(-48, 4, 0); box(110, 10, 18); popMatrix();
  pushMatrix(); translate(-84, 10.5, 0); box(36, 4, 15); popMatrix();
  mat(88, 90, 100);
  pushMatrix(); translate(-25, -0.5, 9.6); box(14, 3, 2); popMatrix();   // slide stop lever

  // Grip, angled back
  pushMatrix();
  translate(10, 8, 0);
  rotateZ(radians(-16));
  mat(72, 74, 84);
  pushMatrix(); translate(0, 38, 0); box(30, 76, 18); popMatrix();
  pushMatrix(); translate(0, 77.5, 0); box(32, 5, 19.5); popMatrix();   // magazine base
  for (int sd = -1; sd <= 1; sd += 2) {
    shiny(112, 66, 36, 40, 8);                                          // wood panels
    pushMatrix(); translate(0, 37, 9.4 * sd); box(24, 60, 1.6); popMatrix();
    mat(70, 40, 22);                                                    // grip texture
    for (int gx = 0; gx < 4; gx++) {
      for (int gy = 0; gy < 8; gy++) {
        pushMatrix(); translate(-7.5 + gx * 5, 14 + gy * 6.5, 10.3 * sd); box(2, 2, 0.6); popMatrix();
      }
    }
    shiny(225, 180, 80, 200, 40);                                       // medallion
    pushMatrix(); translate(0, 10, 10.4 * sd); box(6, 6, 0.6); popMatrix();
  }
  popMatrix();

  // Trigger guard + trigger
  mat(72, 74, 84);
  chain(new float[][] { { -38, 9, 0 }, { -39, 20, 0 }, { -34, 28, 0 }, { -24, 30.5, 0 }, { -12, 30, 0 }, { -3, 25, 0 }, { -1, 20, 0 } }, 2);
  shiny(160, 162, 170, 200, 40);
  chain(new float[][] { { -18, 9, 0 }, { -20.5, 16, 0 }, { -18, 23, 0 } }, 1.6);

  // Slide (kicks back when it fires)
  pushMatrix();
  translate(recoil, 0, 0);
  shiny(104, 107, 118, 200, 35);
  pushMatrix(); translate(-42, -11, 0); box(132, 20, 20); popMatrix();
  shiny(70, 72, 80, 150, 25);
  pushMatrix(); translate(-42, -21.3, 0); box(126, 1.2, 12); popMatrix(); // top rib
  for (int k = 0; k < 6; k++) {                                           // serrations
    pushMatrix(); translate(4 + k * 3.2, -11, 0); box(1.2, 15, 20.8); popMatrix();
  }
  mat(22, 22, 26);
  pushMatrix(); translate(-14, -14, 9.8); box(24, 8, 1); popMatrix();     // ejection port
  mat(55, 56, 62);
  pushMatrix(); translate(-102, -23.5, 0); box(4, 5, 3); popMatrix();     // front sight
  for (int sd = -1; sd <= 1; sd += 2) {
    pushMatrix(); translate(17, -23.5, 5 * sd); box(5, 5, 4); popMatrix(); // rear sight
  }
  glow(255, 255, 255, 255);                                               // sight dots
  ball(-103.9, -24.5, 0, 0.8);
  ball(14.4, -24.5, 5, 0.8);
  ball(14.4, -24.5, -5, 0.8);
  emissive(0);
  popMatrix();

  // Hammer
  mat(88, 90, 100);
  pushMatrix(); translate(27, -12, 0); rotateZ(radians(18)); box(6, 11, 6); popMatrix();

  // Barrel / muzzle
  shiny(80, 82, 90, 200, 40);
  tube(-107.5 + recoil, -12, 0, -110, -12, 0, 5.6, 5.6, true);
  mat(8, 8, 10);
  pushMatrix(); translate(-110.2, -12, 0); rotateY(HALF_PI); ellipse(0, 0, 6.4, 6.4); popMatrix();

  // The famous BANG! flag
  if (since > 0) {
    float e = easeOutBack(min(since / 0.12, 1));
    float sx = -110, ex = -110 - 58 * e, y = -12;
    shiny(225, 205, 160, 40, 10);
    tube(sx, y, 0, ex, y, 0, 0.9, 0.9, false);
    if (e > 0.25) {
      float w = 54 * e, h = 26 * e;
      float fx0 = ex, fx1 = ex + w, fy0 = y + 0.5, fy1 = y + 0.5 + h;
      float wv = sin(t * 9) * 2;   // the flag's bottom flutters
      mat(250, 250, 245);
      slab(new float[][] { { fx0, fy0, 0 }, { fx1, fy0, 0 }, { fx1 + wv, fy1, 0 }, { fx0 + wv, fy1, 0 } }, 0.6, 2);
      textFont(funFont);
      textSize(12 * e);
      textAlign(CENTER, CENTER);
      glow(235, 30, 40, 255);
      float mx = (fx0 + fx1) / 2 + wv / 2, my = (fy0 + fy1) / 2;
      pushMatrix(); translate(mx, my, 0.45); text("BANG!", 0, 0); popMatrix();
      pushMatrix(); translate(mx, my, -0.45); rotateY(PI); text("BANG!", 0, 0); popMatrix();
      emissive(0);
    }
    // little smoke puffs
    if (since < 0.3) {
      float k = since / 0.3;
      hint(DISABLE_DEPTH_MASK);
      specular(0);
      for (int p = 0; p < 5; p++) {
        fill(225, 225, 235, 110 * (1 - k) * (1 - p * 0.15));
        ball(-114 - p * 7 * k, -15 - p * 4 * k - 8 * k, (p - 2) * 4 * k, 3 + 5 * k + p);
      }
      hint(ENABLE_DEPTH_MASK);
    }
  }
  popMatrix();
}

// ── Buttons ────────────────────────────────────
// ── Buttons ────────────────────────────────────
void drawButtons() {
  calBtnY = height - 60;
  textFont(hudFont);

  // Calibrate button
  boolean ch = over(btnX, calBtnY, btnW, btnH);
  if (calibrated && !ch) fill(20, 80, 40);   // green tint after first calibration
  else if (ch) fill(50, 100, 200);
  else fill(30, 60, 130);
  noStroke();
  rect(btnX, calBtnY, btnW, btnH, 7);

  // Small crosshair icon
  stroke(180, 210, 255, 180);
  strokeWeight(1.5);
  noFill();
  float cx = btnX + 20, cy = calBtnY + btnH / 2;
  line(cx - 7, cy, cx + 7, cy);
  line(cx, cy - 7, cx, cy + 7);
  ellipse(cx, cy, 10, 10);
  noStroke();

  fill(200, 220, 255);
  textSize(13);
  textAlign(LEFT, CENTER);
  text(calibrated ? "Re-calibrate Horizon  [C]" : "Calibrate Horizon  [C]", btnX + 38, calBtnY + btnH / 2);
}

// ── HUD ────────────────────────────────────────
void drawHUD() {
  fill(0, 0, 0, 150);
  noStroke();
  rect(14, 14, 240, 222, 8);

  textFont(hudFont);
  fill(180, 210, 255);
  textSize(12);
  textAlign(LEFT, BASELINE);
  text("MPU6050  |  ESP32C6", 26, 34);

  // Calibration status
  textSize(11);
  if (demoMode) {
    fill(255, 75, 75);
    text(port == null ? "● DEMO: can't open " + COM_PORT
                      : "● DEMO: no ESP data on " + COM_PORT, 26, 52);
  } else {
    fill(calibrated ? color(80, 200, 100) : color(255, 160, 60));
    text(calibrated ? "● Calibrated" : "● Place flat and press C", 26, 52);
  }

  textSize(14);
  fill(100, 220, 140);
  text("PITCH  " + nfs(smoothPitch, 3, 1) + "°", 26, 74);
  fill(100, 180, 255);
  text("ROLL   " + nfs(smoothRoll,  3, 1) + "°", 26, 94);
  fill(255, 200, 80);
  text("YAW    " + nfs(smoothYaw,   3, 1) + "°", 26, 114);

  drawBar(26,  126, smoothPitch, color(100, 220, 140));
  drawBar(98,  126, smoothRoll,  color(100, 180, 255));
  drawBar(170, 126, smoothYaw,   color(255, 200, 80));

  textSize(12);
  fill(200, 200, 220);
  text("OBJECT", 26, 156);
  fill(255);
  text(modelNames[currentModel], 80, 156);

  funFW = drawFunLine("Don't Press F !", 26, 192, 0);
  funGW = drawFunLine("Don't Press G !", 26, 218, 160);
}

// "Don't Press F / G" — every letter bounces in its own rainbow colour.
// Returns the width so the line can be clicked like a button.
float funFW = 0, funGW = 0;
float drawFunLine(String s, float x, float y, float hueOff) {
  textFont(funFont);
  textSize(21);
  textAlign(LEFT, BASELINE);
  colorMode(HSB, 360, 100, 100);
  float cx = x;
  for (int i = 0; i < s.length(); i++) {
    char c = s.charAt(i);
    float dy = sin(t * 5 + i * 0.55) * 2.4;
    float rot = sin(t * 4 + i * 1.7) * 0.09;
    fill((t * 90 + i * 22 + hueOff) % 360, 65, 100);
    pushMatrix();
    translate(cx, y + dy);
    rotate(rot);
    text(c, 0, 0);
    popMatrix();
    cx += textWidth(c);
  }
  colorMode(RGB, 255);
  return cx - x;
}

// ── Demo mode banner ───────────────────────────
// Big red warning at the top so nobody mistakes the animation for the real sensor
void drawDemoBanner() {
  if (!demoMode) return;

  String title, detail;
  if (port == null) {
    title  = "DEMO MODE - CAN'T OPEN " + COM_PORT;
    detail = "Check COM_PORT at the top of the sketch. This is NOT live MPU6050 data.";
  } else {
    title  = "DEMO MODE - NO ESP DATA ON " + COM_PORT;
    detail = "Waiting for ESP32 data - tilt the sensor once. Until then this is NOT live MPU6050 data.";
  }

  float left = 270;                          // keep clear of the HUD panel
  float cx = (left + width) / 2;
  float pulse = 0.5 + 0.5 * sin(t * 6);

  textFont(labelFont);
  textSize(20);
  float tw = textWidth(title);
  textFont(hudFont);
  textSize(14);
  float dw = textWidth(detail);
  float w = min(max(tw + 56, dw + 32), width - left - 16);
  float h = 66;
  float x = cx - w / 2, y = 14;

  // background + pulsing red border
  noStroke();
  fill(40, 0, 0, 200);
  rect(x, y, w, h, 10);
  stroke(255, 70, 70, 110 + 145 * pulse);
  strokeWeight(3);
  noFill();
  rect(x, y, w, h, 10);
  noStroke();

  // blinking warning dot
  fill(255, 70, 70, 70 * pulse);
  ellipse(x + 22, y + 22, 22, 22);
  fill(255, 70, 70);
  ellipse(x + 22, y + 22, 11, 11);

  textFont(labelFont);
  textSize(20);
  textAlign(LEFT, CENTER);
  fill(255, 90, 90);
  text(title, x + 40, y + 21);

  textFont(hudFont);
  textSize(14);
  textAlign(CENTER, CENTER);
  fill(240, 225, 225);
  text(detail, cx, y + 48);
}

void drawBar(float x, float y, float val, int c) {
  float w = 60;
  float filled = map(constrain(val, -90, 90), -90, 90, 0, w);
  fill(40, 40, 60);
  noStroke();
  rect(x, y, w, 7, 3);
  fill(c);
  rect(x, y, filled, 7, 3);
}

// Big goofy name pops up when you switch objects
// Big goofy name pops up when you switch objects
void drawToast() {
  float showTime = 6.0;   // seconds fully visible
  float fadeTime = 1.0;   // seconds to fade out afterwards

  float e = (millis() - switchTime) / 1000.0;
  if (e > showTime + fadeTime) return;

  float a = e < showTime ? 255 : map(e, showTime, showTime + fadeTime, 255, 0);
  float pop = easeOutBack(e / 0.35);

  pushMatrix();
  translate(width / 2, height - 92);
  scale(max(pop, 0.01));
  textFont(funFont);
  textAlign(CENTER, CENTER);

  // Title with a drop shadow
  textSize(46);
  fill(0, 0, 0, a * 0.6);
  text(modelNames[currentModel] + " MODE!", 3, 3);
  colorMode(HSB, 360, 100, 100, 255);
  fill((t * 120) % 360, 60, 100, a);
  text(modelNames[currentModel] + " MODE!", 0, 0);
  colorMode(RGB, 255);

  // Quip line ("he saves the day...")
  textSize(18);
  fill(220, 220, 240, a);
  text(modelQuips[currentModel], 0, 38);
  popMatrix();
}

void serialEvent(Serial p) {
  String data = trim(p.readStringUntil('\n'));
  if (data != null && data.length() > 0) {
    String[] vals = split(data, ',');
    if (vals.length >= 3) {
      try {
        float p0 = float(trim(vals[0]));
        float r0 = float(trim(vals[1]));
        float y0 = float(trim(vals[2]));
        // only count it as real data if all three are numbers
        if (!Float.isNaN(p0) && !Float.isNaN(r0) && !Float.isNaN(y0)) {
          pitch = p0;
          roll  = r0;
          yaw   = y0;
          lastDataTime = millis();
        }
      } catch (Exception e) {
        println("Parse error: " + e.getMessage());
      }
    }
  }
}

// ════════════════════════════════════════════════════════════════════
//  DON'T PRESS G  ->  SAD MAN vs THE SPACE FROGS
//  A retro vertical shooter. Tilt the sensor (roll) to steer Sad Man.
//  He cries automatically: his tears are the bullets.
//
//  In the game:  SPACE  start / play again        P  pause
//                C      recenter the tilt (hold the sensor flat first)
//                G/Esc  back to the visualizer
//                Arrow keys or A / D move him when there is no sensor data
// ════════════════════════════════════════════════════════════════════

boolean gameMode = false;

final int GW = 300, GH = 216;          // game screen size in chunky retro pixels
final int PF_L = 60, PF_R = 240;       // playfield edges (score panels on either side)
final float PF_C = 150;                // playfield centre
int PX = 3;                            // real screen pixels per retro pixel
int artPX = -1;                        // the PX the sprites were last built for
int gox, goy;                          // where the game starts on screen

final int G_TITLE = 0, G_PLAY = 1, G_OVER = 2;
int gState = G_TITLE;
boolean gPaused = false;
int gLastMillis = 0;
float gTime = 0, overT = 0, shake = 0, bannerT = 0;
String bannerText = "";

// Sad Man
final float P_Y = 190;
float pX = PF_C;
int lives = 3;
float invuln = 0, fireT = 0, stormT = 0, shieldT = 0, stormMax = 1, shieldMax = 1;
boolean eyeToggle = false, keyL = false, keyR = false;
int lvFire = 1, lvSpread = 1, lvDamage = 1, overcharge = 0;
final int MAX_FIRE = 8, MAX_SPREAD = 5, MAX_DAMAGE = 6;
final int[]   SPREAD_N   = { 1, 2, 3, 5, 7, 9, 11 };
final float[] SPREAD_DEG = { 0, 6, 24, 48, 90, 120, 150 };
final float[] DAMAGE_LV  = { 1, 1.4, 1.9, 2.5, 3.2, 4 };
final float[] TEAR_R     = { 1.5, 2, 2.5, 3.5 };

// the current run
int score = 0, best = 0, wave = 0, bossCount = 0, spawnLeft = 0, killsSinceDrop = 0;
boolean bossWave = false, bossSpawned = false, newBest = false, bestLoaded = false;
float spawnT = 0, waveIntro = 0;

final int E_FROG = 0, E_JET = 1, E_BOSS = 2;
final int PK_FIRE = 0, PK_SPREAD = 1, PK_DAMAGE = 2, PK_STORM = 3, PK_SHIELD = 4, PK_HEART = 5;
final String[] FROG_LINES = { "WHAT AM I DOING", "IN SPACE?" };
final String[] BOSS_LINES = { "WHAT ARE YOU DOING", "IN MY SPACE?!" };

// Sad Man's lines. Each one is 1 or 2 short lines (keep them under ~22 letters).
final String[][] MAN_START     = { { "HERE WE GO AGAIN..." }, { "I DIDN'T WANT TO", "GO TO SPACE" }, { "WHY IS IT", "ALWAYS ME?" } };
final String[][] MAN_HIT       = { { "WHY ME?" }, { "OUCH. MY FEELINGS." }, { "THAT WAS RUDE" }, { "I'M OKAY.", "I'M NOT OKAY." }, { "THIS IS FINE." } };
final String[][] MAN_LASTLIFE  = { { "ONE LIFE LEFT...", "JUST LIKE MY MOOD" }, { "THIS IS MY", "LAST LIFE. GREAT." } };
final String[][] MAN_FIRE      = { { "I'M CRYING FASTER!" }, { "THE TEARS", "WON'T STOP!" } };
final String[][] MAN_SPREAD    = { { "I CRY IN ALL", "DIRECTIONS NOW" }, { "MORE TEARS!", "MORE SADNESS!" } };
final String[][] MAN_DAMAGE    = { { "BIGGER TEARS,", "BIGGER FEELINGS" }, { "THESE TEARS", "HIT HARD" } };
final String[][] MAN_BOOST     = { { "MAXIMUM SADNESS!" }, { "EVEN SADDER.", "EVEN STRONGER." } };
final String[][] MAN_STORM     = { { "I CAN'T STOP", "CRYING!!" }, { "TEAR STORM!", "NOBODY LOOK AT ME" } };
final String[][] MAN_SHIELD    = { { "A BUBBLE! FINALLY", "SOME PERSONAL SPACE" }, { "MY SAFE SPACE" } };
final String[][] MAN_HEART     = { { "SOMEBODY", "LOVES ME?" }, { "A HEART?", "FOR ME??" } };
final String[][] MAN_BOSS      = { { "THAT IS A", "VERY BIG FROG" }, { "OH NO.", "IT HAS A CROWN." } };
final String[][] MAN_BOSS_DOWN = { { "I WON...", "I'M STILL SAD THOUGH" }, { "SORRY, BIG FROG" } };
final String[][] MAN_CLEAR     = { { "IS IT OVER?", "...NO. NEVER." }, { "I NEED A NAP" }, { "MORE FROGS?", "OF COURSE." } };
final String[][] MAN_IDLE      = { { "SPACE IS SO COLD" }, { "I MISS MY MOM" }, { "THESE ARE NOT", "HAPPY TEARS" },
                                   { "WHY ARE THERE", "FROGS IN SPACE?" }, { "MY CAPE IS WET" }, { "I SHOULD HAVE", "STAYED IN BED" },
                                   { "DOES ANYONE HAVE", "A TISSUE?" } };
final String[][] MAN_PAIN      = { { "EXISTENCE IS PAIN" }, { "EXISTENCE...", "IS PAIN" } };
final String[][] MAN_WTF       = { { "WHAT THE HELL", "WAS THAT?" } };
final String[][] MAN_WHY       = { { "...WHY?" } };
final String[][] MAN_REPLY     = { { "ME TOO, BUDDY" }, { "SAME QUESTION" }, { "NOBODY KNOWS, FROG" } };
final String[][] MAN_TITLE     = { { "PLEASE DON'T", "PRESS SPACE" }, { "I JUST WANTED", "A NAP" }, { "NOT THE FROGS", "AGAIN..." } };
final String[][] MAN_NO_MPU    = { { "MY MPU ISN'T", "CONNECTED... SAD" }, { "I FEEL SO", "DISCONNECTED" }, { "WHERE IS MY MPU?" } };
final String[][] MAN_MPU_ON    = { { "I CAN FEEL", "THE TILT NOW!" }, { "MPU CONNECTED!", "A RARE HAPPY MOMENT" } };

String[] manLines = { "" };
String[][] manNextPool = null;    // a follow-up line (e.g. "...WHY?")
float manNextT = 0;

// The random HUGE frog: says hi, licks a heart off Sad Man, leaves. Can't be dodged or hurt.
final String[] HUGE_HI  = { "HEY I AM RANDOM" };
final String[] HUGE_BYE = { "OK BYE" };
boolean hugeOn = false, hugeHit = false, hugeNoDmg = false;
int hugeState = 0, hugeTint = 0;      // states: 0 arriving, 1 talking, 2 tongue, 3 leaving
float hugeX, hugeY, hugeT, hugeTongue, hugeCool = 90;
float manSayT = 0, manQuiet = 0, manIdleT = 8, manReplyT = -1;
int manPri = 0;
boolean wasDemo = true;

ArrayList<Enemy>    enemies = new ArrayList<Enemy>();
ArrayList<Tear>     tears   = new ArrayList<Tear>();
ArrayList<EShot>    eshots  = new ArrayList<EShot>();
ArrayList<Pickup>   pickups = new ArrayList<Pickup>();
ArrayList<Particle> parts   = new ArrayList<Particle>();
ArrayList<Popup>    popups  = new ArrayList<Popup>();

// background
final int NGSTARS = 70;
float[] gsX = new float[NGSTARS], gsY = new float[NGSTARS];
int[] gsL = new int[NGSTARS];
float planetX = 110, planetY = 40;
int planetKind = 0;

// ── Things in the game ────────────────────────────────────────────────
class Enemy {
  int type, tier, state, value, bossN, attack;
  float x, y, vx, vy, baseX, amp, freq, phase, hp, maxHp, hw, hh;
  float age, fireT, flash, flashCool, timer, targetY, sayAt = -1, sayLeft = 0;
  float attackT, tongueWarn, tongueT, tongueX, wanderT;
  boolean dead, deco;
}

class Tear {
  float x, y, vx, vy, dmg;
  int sz;
  boolean dead;
  Tear(float x0, float y0, float ang, float d, int s) {
    x = x0; y = y0; dmg = d; sz = s;
    vx = sin(ang) * 210;
    vy = -cos(ang) * 210;
  }
}

class EShot {
  float x, y, vx, vy, r;
  int kind;            // 0 jet pellet, 1 frog spit, 2 big boss spit
  boolean dead;
  EShot(float x0, float y0, float vx0, float vy0, int k) {
    x = x0; y = y0; vx = vx0; vy = vy0; kind = k;
    r = k == 0 ? 1.5 : k == 1 ? 2 : 2.5;
  }
}

class Pickup {
  float x, y, age;
  int kind;
  boolean dead;
  Pickup(float x0, float y0, int k) { x = x0; y = y0; kind = k; }
}

class Particle {
  float x, y, vx, vy, life, maxLife;
  int col, sz;
}

class Popup {
  float x, y, life;
  String txt;
  int col;
}

int rgb(int r, int g, int b) {
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

// ── Entering / leaving ────────────────────────────────────────────────
void enterGame() {
  gameMode = true;
  gState = G_TITLE;
  gPaused = false;
  keyL = keyR = false;
  if (!bestLoaded) { loadBest(); bestLoaded = true; }
  clearRun();
  wasDemo = demoMode;
  manSayT = 0; manIdleT = 3;
  for (int i = 0; i < 3; i++) spawnTitleFrog(i);
  initGameStars();
  planetX = PF_R - 26; planetY = 76; planetKind = 0;
  gLastMillis = millis();
}

void exitGame() {
  gameMode = false;
  keyL = keyR = false;
}

void clearRun() {
  enemies.clear(); tears.clear(); eshots.clear();
  pickups.clear(); parts.clear(); popups.clear();
  bannerT = 0; shake = 0;
  hugeOn = false; hugeCool = random(8, 30);    // first visit can be in wave 1
  manNextPool = null;
}

void startRun() {
  clearRun();
  score = 0; wave = 0; bossCount = 0; lives = 3; killsSinceDrop = 0; newBest = false;
  lvFire = 1; lvSpread = 1; lvDamage = 1; overcharge = 0;
  stormT = 0; shieldT = 0; invuln = 1.5; fireT = 0.5; pX = PF_C;
  gState = G_PLAY;
  gPaused = false;
  nextWave();
  manSayT = 0;
  manSay(MAN_START, 2);
  manIdleT = random(10, 16);
}

void nextWave() {
  wave++;
  bossWave = wave % 5 == 0;          // a big frog every 5th wave
  bossSpawned = false;
  // after the first boss there are 40% more enemies per wave
  spawnLeft = bossWave ? 0 : min(70, round((10 + wave * 3) * (bossCount >= 1 ? 1.4 : 1)));
  spawnT = 0;
  waveIntro = bossWave ? 3.0 : 2.2;
  if (bossWave) manSay(MAN_BOSS, 2);
}

float hpMul()  { return (1 + 0.22 * (wave - 1) + 0.02 * sq(max(0, wave - 10))) * (bossCount >= 1 ? 1.15 : 1); }   // enemies get tougher...
float spdMul() { return min(1.9, 1 + 0.05 * (wave - 1)); } // ...and faster every wave

void loadBest() {
  try {
    File f = new File(sketchPath("sadman_highscore.txt"));
    if (f.exists()) best = int(trim(loadStrings(f.getAbsolutePath())[0]));
  } catch (Exception e) {
    best = 0;
  }
}

void saveBest() {
  try {
    saveStrings(sketchPath("sadman_highscore.txt"), new String[] { str(best) });
  } catch (Exception e) {
    println("Could not save the high score");
  }
}

// ── Sad Man talking ──────────────────────────────────────────────────
// pri 0 = chatter, 1 = buffs, 2 = big moments (hits, bosses). Chatter never interrupts.
void manSay(String[][] pool, int pri) {
  if (manSayT > 0 && pri < manPri) return;
  if (pri == 0 && manQuiet > 0) return;
  manLines = pool[(int) random(pool.length)];
  manSayT = 2.6;
  manPri = pri;
  manQuiet = 4;
}

void updateManTalk(float dt) {
  manSayT -= dt;
  manQuiet -= dt;
  if (manReplyT > 0) {
    manReplyT -= dt;
    if (manReplyT <= 0) manSay(MAN_REPLY, 1);
  }
  if (manNextPool != null) {
    manNextT -= dt;
    if (manNextT <= 0) { manSayT = 0; manSay(manNextPool, 3); manNextPool = null; }
  }
  manIdleT -= dt;
  if (manIdleT <= 0) {
    if (random(1) < 0.3) manSay(MAN_PAIN, 0);
    else if (gState == G_TITLE) manSay(MAN_TITLE, 0);
    else if (gState == G_PLAY) manSay(demoMode && random(1) < 0.6 ? MAN_NO_MPU : MAN_IDLE, 0);
    manIdleT = gState == G_TITLE ? random(5, 8) : random(11, 18);
  }
  // the sensor started sending data in the middle of the game
  if (wasDemo && !demoMode && gState != G_OVER) {
    bannerText = "MPU CONNECTED!";
    bannerT = 2.2;
    manSay(MAN_MPU_ON, 2);
  }
  wasDemo = demoMode;
}

void gameKeyPressed() {
  if (key == ESC) { key = 0; exitGame(); return; }     // Esc leaves the game instead of closing Processing
  if (key == CODED) {
    if (keyCode == LEFT)  keyL = true;
    if (keyCode == RIGHT) keyR = true;
    return;
  }
  char k = Character.toLowerCase(key);
  if (k == 'a') keyL = true;
  if (k == 'd') keyR = true;
  if (k == 'c') {
    calibrate();
    if (!demoMode) popup("RECENTERED", pX, P_Y - 44, rgb(120, 255, 160));
  }
  if (k == 'p' && gState == G_PLAY) gPaused = !gPaused;
  if (k == ' ' || k == ENTER || k == RETURN) {
    if (gState == G_TITLE || (gState == G_OVER && overT > 1.0)) startRun();
  }
}

void gameKeyReleased() {
  if (key == CODED) {
    if (keyCode == LEFT)  keyL = false;
    if (keyCode == RIGHT) keyR = false;
    return;
  }
  char k = Character.toLowerCase(key);
  if (k == 'a') keyL = false;
  if (k == 'd') keyR = false;
}

// ── Main game loop ────────────────────────────────────────────────────
void drawGame() {
  float dt = constrain((millis() - gLastMillis) / 1000.0, 0, 0.05);
  gLastMillis = millis();
  if (!gPaused) updateGame(dt);
  renderGame();
}

void updateGame(float dt) {
  gTime += dt;
  scrollGameStars(dt);
  shake = max(0, shake - dt * 14);
  bannerT -= dt;
  updateParticles(dt);
  updateManTalk(dt);
  if (gState == G_TITLE) { updateTitleFrogs(dt); return; }
  if (gState == G_OVER)  { overT += dt; return; }
  updatePlayer(dt);
  updateWave(dt);
  updateHuge(dt);
  updateTears(dt);
  updateEnemies(dt);
  updateShots(dt);
  updatePickups(dt);
  cleanup();
}

// ── Sad Man ───────────────────────────────────────────────────────────
void updatePlayer(float dt) {
  float minX = PF_L + 9, maxX = PF_R - 9;
  if (!demoMode) {
    // tilt -> position: GAME_TILT_RANGE degrees either way reaches the edge
    float tilt = GAME_USE_ROLL ? smoothRoll : smoothPitch;
    if (GAME_INVERT) tilt = -tilt;
    float tx = map(constrain(tilt, -GAME_TILT_RANGE, GAME_TILT_RANGE), -GAME_TILT_RANGE, GAME_TILT_RANGE, minX, maxX);
    pX = lerp(pX, tx, min(1, dt * 14));
  } else {
    int dir = (keyR ? 1 : 0) - (keyL ? 1 : 0);
    pX += dir * 140 * dt;
  }
  pX = constrain(pX, minX, maxX);

  invuln  = max(0, invuln - dt);
  stormT  = max(0, stormT - dt);
  shieldT = max(0, shieldT - dt);
  if (stormT > 0 && random(1) < dt * 25) {
    burst(pX + random(-4, 4), P_Y - 3, rgb(200, 140, 255), rgb(255, 255, 255), 1, 25);
  }

  // automatic crying
  fireT -= dt;
  if (fireT <= 0) {
    fireTears();
    fireT += fireInterval();
    if (fireT < 0) fireT = 0;
  }
}

float fireInterval() {
  float iv = 0.32 / (1 + 0.27 * (lvFire - 1));
  return stormT > 0 ? iv * 0.45 : iv;
}

float tearDamage() { return DAMAGE_LV[lvDamage - 1] * (1 + 0.08 * overcharge); }
int tearSize()     { return lvDamage <= 2 ? 0 : lvDamage <= 4 ? 1 : lvDamage == 5 ? 2 : 3; }

void fireTears() {
  int lv = min(SPREAD_N.length, lvSpread + (stormT > 0 ? 2 : 0));
  int n = SPREAD_N[lv - 1];
  float spread = SPREAD_DEG[lv - 1];
  float d = tearDamage();
  int s = tearSize();
  eyeToggle = !eyeToggle;
  for (int i = 0; i < n; i++) {
    float a = n == 1 ? 0 : map(i, 0, n - 1, -spread / 2, spread / 2);
    float ex = a < 0 ? pX - 1.5 : a > 0 ? pX + 1.5 : (eyeToggle ? pX - 1.5 : pX + 1.5);
    tears.add(new Tear(ex, P_Y - 3, radians(a), d, s));
  }
}

void hitPlayer() {
  lives--;
  invuln = 2.0;
  shake = max(shake, 6);
  burst(pX, P_Y, rgb(75, 110, 205), rgb(255, 255, 255), 22, 70);
  for (EShot s : eshots) if (dist(s.x, s.y, pX, P_Y) < 50) s.dead = true;
  if (lives <= 0) gameOver();
  else manSay(lives == 1 ? MAN_LASTLIFE : MAN_HIT, 2);
}

void gameOver() {
  gState = G_OVER;
  overT = 0;
  manSayT = 0;
  burst(pX, P_Y, rgb(110, 190, 255), rgb(255, 255, 255), 40, 90);
  if (score > best) { best = score; newBest = true; saveBest(); }
}

// ── Waves ─────────────────────────────────────────────────────────────
void updateWave(float dt) {
  if (waveIntro > 0) {
    waveIntro -= dt;
    if (waveIntro <= 0 && bossWave && !bossSpawned) spawnBoss();
    return;
  }
  if (spawnLeft > 0) {
    if (!hugeOn) spawnT -= dt;                 // the huge frog gets everyone's attention
    if (spawnT <= 0) {
      spawnEnemy();
      spawnT = max(0.2, 1.05 - 0.045 * wave) * (bossCount >= 1 ? 0.8 : 1) * random(0.6, 1.4);
    }
  } else if ((!bossWave || bossSpawned) && liveEnemies() == 0) {
    if (!bossWave) dropPickup(PF_C + random(-40, 40), -6, pickPermanent());  // reward for clearing a wave
    if (!bossWave && wave % 5 != 4 && random(1) < 0.4) manSay(MAN_CLEAR, 1);
    nextWave();
  }
}

int liveEnemies() {
  int n = 0;
  for (Enemy e : enemies) if (!e.dead && !e.deco) n++;
  return n;
}

void spawnEnemy() {
  spawnLeft--;
  float jetP  = wave >= 2 ? min(0.30, 0.10 + 0.025 * wave) : 0;
  float redP  = wave >= 6 ? min(0.22, 0.02 + 0.02 * wave) : 0;
  float blueP = wave >= 3 ? min(0.30, 0.04 + 0.025 * wave) : 0;
  float zapP  = wave >= 4 ? min(0.22, 0.08 + 0.012 * wave) : 0;
  float r = random(1);
  if (r < zapP) spawnZapRow();
  else if ((r -= zapP) < jetP) {
    if (wave >= 7 && random(1) < 0.35 && spawnLeft >= 2) {      // a V of three jets
      float bx = random(PF_L + 30, PF_R - 30);
      for (int i = -1; i <= 1; i++) spawnJet(bx + i * 14, -10 - abs(i) * 10, 0);
      spawnLeft -= 2;
    } else {
      spawnJet(random(PF_L + 22, PF_R - 22), -10, random(8, 22));
    }
  } else if (r < jetP + redP) spawnFrog(2);
  else if (r < jetP + redP + blueP) spawnFrog(1);
  else if (bossCount >= 1 && spawnLeft >= 1 && random(1) < 0.35) {   // after the first boss: frogs in little gangs
    int n = min(spawnLeft + 1, random(1) < 0.5 ? 2 : 3);
    float bx = random(PF_L + 22, PF_R - 22 - 18 * (n - 1));
    for (int i = 0; i < n; i++) {
      Enemy f = spawnFrog(wave >= 8 && i == 1 ? 1 : 0);
      f.amp = 4; f.baseX = bx + i * 18; f.y = -8 - i * 4; f.phase = 0;
    }
    spawnLeft -= n - 1;
  }
  else spawnFrog(0);
}

// lightning frogs: line up at the top, crackle, then ZAP straight down one after another
void spawnZapRow() {
  int n = bossCount >= 1 ? (random(1) < 0.5 ? 3 : 2) : 1;
  n = min(n, spawnLeft + 1);
  float gap = 30, x0 = random(PF_L + 14, PF_R - 14 - gap * (n - 1));
  float ty = random(14, 24), charge = max(1.1, 2.3 - 0.04 * wave);
  for (int i = 0; i < n; i++) {
    Enemy f = spawnFrog(3);
    f.baseX = f.x = x0 + i * gap;
    f.targetY = ty;
    f.timer = charge + i * 0.35;
  }
  spawnLeft -= n - 1;
}

Enemy spawnFrog(int tier) {
  Enemy e = new Enemy();
  e.type = E_FROG; e.tier = tier; e.hw = 6; e.hh = 5;
  e.amp = tier >= 2 ? 0 : random(3, 14);
  e.freq = random(0.8, 1.8);
  e.phase = random(TWO_PI);
  e.baseX = random(PF_L + 10 + e.amp, PF_R - 10 - e.amp);
  e.x = e.baseX; e.y = -8;
  float sp = spdMul();
  if (tier == 0) { e.hp = 2 * hpMul(); e.vy = random(15, 23) * sp; e.value = 10; e.fireT = wave >= 12 && random(1) < 0.3 ? random(1.5, 3) : -1; }
  if (tier == 1) { e.hp = 6 * hpMul(); e.vy = random(18, 26) * sp; e.value = 25; e.fireT = random(1.0, 2.5); }
  if (tier == 2) { e.hp = 4 * hpMul(); e.vy = 32 * sp; e.value = 30; e.targetY = random(30, 70); }
  if (tier == 3) { e.amp = 0; e.hp = 3 * hpMul(); e.vy = 0; e.value = 35; e.targetY = 18; e.timer = 2; }
  e.maxHp = e.hp;
  if (random(1) < 0.35 && tier != 3) e.sayAt = random(0.8, 4);
  enemies.add(e);
  return e;
}

void spawnJet(float x, float y, float amp) {
  Enemy e = new Enemy();
  e.type = E_JET; e.hw = 5; e.hh = 5;
  e.amp = amp; e.freq = random(1.5, 2.5); e.phase = random(TWO_PI);
  e.baseX = constrain(x, PF_L + 8 + amp, PF_R - 8 - amp);
  e.x = e.baseX; e.y = y;
  e.vy = random(34, 44) * spdMul();
  e.hp = 3 * hpMul(); e.maxHp = e.hp;
  e.value = 20;
  e.fireT = random(0.5, 1.2);
  enemies.add(e);
}

void spawnBoss() {
  bossSpawned = true;
  bossCount++;
  Enemy e = new Enemy();
  e.type = E_BOSS; e.bossN = bossCount;
  e.hw = 20; e.hh = 15;
  e.x = PF_C; e.y = -24;
  e.hp = 280 * pow(2.0, bossCount - 1); e.maxHp = e.hp;
  e.value = 500 * bossCount;
  e.sayAt = 0.5;
  enemies.add(e);
}

// ── Enemies ───────────────────────────────────────────────────────────
void updateEnemies(float dt) {
  float sp = spdMul();
  for (int i = 0; i < enemies.size(); i++) {
    Enemy e = enemies.get(i);
    if (e.dead) continue;
    e.age += dt;
    e.flash -= dt;
    e.flashCool -= dt;
    if (e.type == E_FROG) updateFrog(e, dt, sp);
    else if (e.type == E_JET) updateJet(e, dt, sp);
    else updateBoss(e, dt, sp);
    updateSpeech(e);
    if (e.y > GH + 24 || e.x < PF_L - 30 || e.x > PF_R + 30) { e.dead = true; continue; }

    // bumping into Sad Man
    if (abs(e.x - pX) < e.hw + 2.5 && abs(e.y - (P_Y + 1)) < e.hh + 5) {
      if (e.type == E_BOSS) { if (shieldT <= 0 && invuln <= 0) hitPlayer(); }
      else if (shieldT > 0) killEnemy(e);
      else if (invuln <= 0) { killEnemy(e); hitPlayer(); }
    }
  }
}

void updateFrog(Enemy e, float dt, float sp) {
  if (e.tier == 3) {                         // lightning frog
    if (e.state == 0) {                      // fly in and line up at the top
      e.y += 40 * dt;
      if (e.y >= e.targetY) { e.y = e.targetY; e.state = 1; }
    } else if (e.state == 1) {               // charge up (its lane flashes on screen)
      e.timer -= dt;
      if (random(1) < dt * 30) burst(e.x + random(-7, 7), e.y + random(-6, 6), rgb(255, 240, 120), rgb(140, 230, 255), 1, 20);
      if (e.timer <= 0) { e.state = 2; e.vy = 230 * sp; shake = max(shake, 1); }
    } else {                                 // ZAP!
      e.y += e.vy * dt;
      burst(e.x + random(-3, 3), e.y - 7, rgb(255, 240, 120), rgb(255, 255, 255), 1, 10);
    }
    return;
  }
  if (e.tier == 2) {                         // red frog: stops, wiggles, then dives at you
    if (e.state == 0) {
      e.y += e.vy * dt;
      if (e.y >= e.targetY) { e.state = 1; e.timer = 0.7; }
    } else if (e.state == 1) {
      e.timer -= dt;
      if (e.timer <= 0) {
        float dx = pX - e.x, dy = P_Y - e.y, m = max(1, sqrt(dx * dx + dy * dy));
        e.vx = dx / m * 95 * sp;
        e.vy = dy / m * 95 * sp;
        e.state = 2;
      }
    } else {
      e.x += e.vx * dt;
      e.y += e.vy * dt;
    }
    return;
  }
  float hop = 0.55 + 0.9 * max(0, sin(e.age * 4 + e.phase));
  e.y += e.vy * hop * dt;
  e.x = e.baseX + sin(e.age * e.freq + e.phase) * e.amp;
  if (e.tier == 1) {                         // blue frog: spits (three at a time later on)
    e.fireT -= dt;
    if (e.fireT <= 0 && e.y > 0 && e.y < 140) {
      if (wave >= 14) for (int k = -1; k <= 1; k++) aimShot(e.x, e.y + 5, 50 * sp, 1, k * 15);
      else if (wave >= 8) aimShot(e.x, e.y + 5, 50 * sp, 1, 0);
      else eshots.add(new EShot(e.x, e.y + 5, 0, 48 * sp, 1));
      e.fireT = random(2.2, 3.6) / sqrt(sp);
    }
  } else if (e.fireT > 0) {                  // from wave 12 some green frogs spit once too
    e.fireT -= dt;
    if (e.fireT <= 0 && e.y > 0 && e.y < 130) aimShot(e.x, e.y + 5, 48 * sp, 1, 0);
    else if (e.fireT <= 0) e.fireT = 0.3;
  }
}

void updateJet(Enemy e, float dt, float sp) {
  e.y += e.vy * dt;
  e.x = e.baseX + sin(e.age * e.freq + e.phase) * e.amp;
  e.fireT -= dt;
  int maxShots = wave < 4 ? 1 : wave < 9 ? 2 : 3;
  if (e.fireT <= 0 && e.attack < maxShots && e.y > 4 && e.y < 140) {
    if (wave >= 12) for (int k = -1; k <= 1; k++) aimShot(e.x, e.y + 6, 64 * sp, 0, k * 11);
    else if (wave >= 4) aimShot(e.x, e.y + 6, 64 * sp, 0, random(-6, 6));
    else eshots.add(new EShot(e.x, e.y + 6, 0, 60 * sp, 0));
    e.attack++;
    e.fireT = max(0.55, 2.0 - 0.07 * wave);
  }
}

void aimShot(float x, float y, float speed, int kind, float offDeg) {
  float a = atan2(P_Y - y, pX - x) + radians(offDeg);
  eshots.add(new EShot(x, y, cos(a) * speed, sin(a) * speed, kind));
}

void updateBoss(Enemy e, float dt, float sp) {
  if (e.state == 0) {                        // flying in
    e.y += 22 * dt;
    if (e.y >= 52) { e.y = 52; e.state = 1; e.attackT = 1.2; }
    return;
  }
  boolean angry = e.hp < e.maxHp * 0.5;
  if (e.tongueWarn > 0) {                    // slides over Sad Man, stops, then...
    e.tongueWarn -= dt;
    if (e.tongueWarn > 0.45) e.x = lerp(e.x, constrain(pX, PF_L + 24, PF_R - 24), min(1, dt * 5));
    if (e.tongueWarn <= 0) { e.tongueT = 0.6; e.tongueX = e.x; shake = max(shake, 2); }
    return;
  }
  if (e.tongueT > 0) {                       // ...TONGUE!
    e.tongueT -= dt;
    float reach = (e.y + 4) + (GH - e.y - 4) * min(1, (0.6 - e.tongueT) / 0.08);
    if (reach > P_Y - 6 && abs(pX - e.tongueX) < 5 && shieldT <= 0 && invuln <= 0) hitPlayer();
    return;
  }
  e.wanderT += dt;
  e.x = lerp(e.x, PF_C + sin(e.wanderT * 0.7) * 58, min(1, dt * 2));
  e.y = 52 + sin(e.wanderT * 1.3) * 3;
  e.attackT -= dt * (angry ? 1.5 : 1);
  if (e.attackT <= 0) {
    int a = e.attack % 4;
    e.attack++;
    if (a == 0) bossFan(e, sp);
    else if (a == 1) e.tongueWarn = 1.0;
    else if (a == 2) bossSummon(e);
    else for (int k = -1; k <= 1; k++) aimShot(e.x, e.y + 6, 70 * sp, 2, k * 12);
    e.attackT = max(1.3, 2.8 - 0.25 * (e.bossN - 1));
  }
  if (e.sayLeft <= 0 && e.sayAt < 0 && random(1) < dt * 0.08) e.sayAt = e.age;
}

void bossFan(Enemy e, float sp) {
  int n = 5 + 2 * min(3, e.bossN - 1) + (e.hp < e.maxHp * 0.5 ? 2 : 0);
  for (int i = 0; i < n; i++) {
    float a = radians(90 + map(i, 0, n - 1, -40, 40));
    eshots.add(new EShot(e.x, e.y + 6, cos(a) * 52 * sp, sin(a) * 52 * sp, 2));
  }
}

void bossSummon(Enemy e) {
  for (int i = -1; i <= 1; i++) {
    Enemy f = spawnFrog(e.bossN >= 2 && i == 0 ? 1 : 0);
    f.baseX = constrain(e.x + i * 22, PF_L + 12 + f.amp, PF_R - 12 - f.amp);
    f.y = e.y + 8;
    f.sayAt = -1;
  }
}

void updateSpeech(Enemy e) {
  if (e.sayLeft > 0) return;
  if (e.sayAt >= 0 && e.age >= e.sayAt) {
    if (canTalk(e)) {
      e.sayLeft = 2.6;
      e.sayAt = -1;
      if (e.type == E_FROG && random(1) < 0.35 && manSayT <= 0) manReplyT = 1.3;   // "ME TOO, BUDDY"
    }
    else e.sayAt = e.age + 0.6;
  }
}

// at most 2 speech bubbles at once (1 on the title screen), and never on top of each other
boolean canTalk(Enemy e) {
  if (e.y <= 8) return false;
  int n = 0;
  for (Enemy o : enemies) {
    if (o.dead || o.sayLeft <= 0 || o == e) continue;
    n++;
    if (abs(o.x - e.x) < 75 && abs(o.y - e.y) < 30) return false;
  }
  return n < (gState == G_TITLE ? 1 : 2);
}

void damageEnemy(Enemy e, float d, float hx, float hy) {
  e.hp -= d;
  if (e.flashCool <= 0) {              // flash white when hit (not every hit, or the boss would stay white)
    e.flash = 0.06;
    e.flashCool = e.type == E_BOSS ? 0.25 : 0.12;
  }
  burst(hx, hy, rgb(150, 210, 255), rgb(255, 255, 255), 3, 30);
  if (e.hp <= 0) killEnemy(e);
}

void killEnemy(Enemy e) {
  if (e.dead) return;
  e.dead = true;
  score += e.value + wave * 2;
  if (e.type == E_BOSS) { bossDown(e); return; }
  int c1 = e.type == E_JET ? rgb(255, 170, 60) : frogColor(e.tier);
  burst(e.x, e.y, c1, rgb(255, 255, 200), 14, 60);
  shake = max(shake, 1.2);
  killsSinceDrop++;
  float chance = (e.type == E_JET ? 0.15 : e.tier == 1 ? 0.16 : e.tier >= 2 ? 0.13 : 0.09) + min(0.06, 0.003 * wave);
  if (random(1) < chance || killsSinceDrop >= 22) dropPickup(e.x, e.y, pickKind());
}

int frogColor(int tier) {
  return tier == 0 ? rgb(95, 190, 70) : tier == 1 ? rgb(85, 150, 235) : tier == 2 ? rgb(235, 95, 70) : rgb(255, 220, 60);
}

void bossDown(Enemy e) {
  for (int i = 0; i < 5; i++) burst(e.x + random(-18, 18), e.y + random(-14, 14), rgb(95, 190, 70), rgb(255, 220, 90), 24, 90);
  shake = 9;
  bannerText = "BOSS DEFEATED!";
  bannerT = 2.6;
  manSay(MAN_BOSS_DOWN, 2);
  dropPickup(e.x - 16, e.y, pickPermanent());
  dropPickup(e.x + 16, e.y, pickPermanent());
  dropPickup(e.x, e.y - 8, random(1) < 0.5 ? PK_STORM : PK_SHIELD);
  if (lives < 5) dropPickup(e.x, e.y + 10, PK_HEART);
  for (EShot s : eshots) s.dead = true;
}

// ── The random HUGE frog ─────────────────────────────────────────────
void updateHuge(float dt) {
  if (!hugeOn) {
    hugeCool -= dt;
    boolean bossAlive = false;
    for (Enemy e : enemies) if (!e.dead && e.type == E_BOSS) bossAlive = true;
    if (hugeCool <= 0 && !bossWave && !bossAlive && waveIntro <= 0 && lives >= 2
        && invuln <= 0 && shieldT <= 0 && random(1) < dt * 0.3) startHuge();
    return;
  }
  hugeT += dt;
  if (hugeState == 0) {                      // slides in from the top
    hugeY = lerp(hugeY, 36, min(1, dt * 3));
    if (hugeT > 1.0) { hugeState = 1; hugeT = 0; }
  } else if (hugeState == 1) {               // "HEY I AM RANDOM"
    if (hugeT > 2.0) { hugeState = 2; hugeT = 0; hugeHit = false; }
  } else if (hugeState == 2) {               // tongue: follows Sad Man, so there's no dodging it
    hugeTongue = min(1, hugeT / 0.22);
    if (hugeTongue >= 1 && !hugeHit) {
      hugeHit = true;
      if (lives > 1) lives--;
      invuln = 2;
      shake = 9;
      burst(pX, P_Y - 4, rgb(255, 120, 160), rgb(255, 255, 255), 30, 80);
      popup("-1 HEART", pX, P_Y - 44, rgb(255, 90, 120));
      manSayT = 0;
      manSay(MAN_WTF, 3);
      manNextPool = MAN_WHY;
      manNextT = 2.8;
    }
    if (hugeT > 0.6) hugeTongue = max(0, 1 - (hugeT - 0.6) / 0.25);
    if (hugeT > 0.85) { hugeState = 3; hugeT = 0; hugeTongue = 0; }
  } else {                                   // "OK BYE", then leaves
    if (hugeT > 1.2) hugeY -= 70 * dt;
    if (hugeY < -50) { hugeOn = false; hugeCool = random(110, 180); }
  }
}

void startHuge() {
  hugeOn = true;
  hugeState = 0; hugeT = 0; hugeTongue = 0;
  hugeX = PF_C + random(-30, 30);
  hugeY = -40;
  hugeNoDmg = false;
  int[] tints = { rgb(190, 120, 255), rgb(255, 130, 200), rgb(255, 170, 80), rgb(90, 230, 210) };
  hugeTint = tints[(int) random(tints.length)];
}

// ── Tears and enemy shots ─────────────────────────────────────────────
void updateTears(float dt) {
  for (Tear tr : tears) {
    if (tr.dead) continue;
    tr.x += tr.vx * dt;
    tr.y += tr.vy * dt;
    if (tr.y < -10 || tr.x < PF_L - 6 || tr.x > PF_R + 6) { tr.dead = true; continue; }
    if (hugeOn && abs(tr.x - hugeX) < 28 && tr.y < hugeY + 22 && tr.y > hugeY - 26) {   // tears do nothing to it
      tr.dead = true;
      burst(tr.x, tr.y, rgb(180, 180, 200), rgb(255, 255, 255), 2, 25);
      if (!hugeNoDmg && hugeState >= 1) { hugeNoDmg = true; popup("NO DAMAGE!", hugeX, 96, rgb(210, 210, 230)); }
      continue;
    }
    float rad = TEAR_R[tr.sz];
    for (int i = 0; i < enemies.size(); i++) {
      Enemy e = enemies.get(i);
      if (e.dead || e.deco || e.y < -e.hh) continue;
      if (abs(tr.x - e.x) < e.hw + rad && abs(tr.y - e.y) < e.hh + rad) {
        tr.dead = true;
        damageEnemy(e, tr.dmg, tr.x, tr.y);
        break;
      }
    }
  }
}

void updateShots(float dt) {
  for (EShot s : eshots) {
    if (s.dead) continue;
    s.x += s.vx * dt;
    s.y += s.vy * dt;
    if (s.y > GH + 6 || s.y < -10 || s.x < PF_L - 6 || s.x > PF_R + 6) { s.dead = true; continue; }
    if (abs(s.x - pX) < 2.5 + s.r && abs(s.y - (P_Y + 1)) < 5 + s.r) {
      s.dead = true;
      if (shieldT > 0) burst(s.x, s.y, rgb(120, 220, 255), rgb(255, 255, 255), 5, 30);
      else if (invuln <= 0) hitPlayer();
    }
  }
}

// ── Buffs ─────────────────────────────────────────────────────────────
int pickKind() {
  float r = random(1);
  if (r < 0.05 && lives < 5) return PK_HEART;
  if (r < 0.17) return random(1) < 0.5 ? PK_STORM : PK_SHIELD;
  return pickPermanent();
}

// favours whichever upgrade is furthest from its max, so Sad Man grows evenly
int pickPermanent() {
  float wF = (MAX_FIRE - lvFire) / (float) MAX_FIRE + 0.12;
  float wS = (MAX_SPREAD - lvSpread) / (float) MAX_SPREAD + 0.12;
  float wD = (MAX_DAMAGE - lvDamage) / (float) MAX_DAMAGE + 0.12;
  float r = random(wF + wS + wD);
  return r < wF ? PK_FIRE : r < wF + wS ? PK_SPREAD : PK_DAMAGE;
}

void dropPickup(float x, float y, int kind) {
  pickups.add(new Pickup(constrain(x, PF_L + 8, PF_R - 8), y, kind));
  killsSinceDrop = 0;
}

void updatePickups(float dt) {
  for (Pickup p : pickups) {
    if (p.dead) continue;
    p.age += dt;
    p.y += 24 * dt;
    float dx = pX - p.x;
    if (abs(dx) < 34 && p.y > P_Y - 60) p.x += constrain(dx, -1, 1) * 30 * dt;   // gentle magnet
    if (abs(dx) < 10 && abs(p.y - P_Y) < 13) { collect(p.kind, p.x, p.y); p.dead = true; }
    if (p.y > GH + 10) p.dead = true;
  }
}

int pickupColor(int k) {
  if (k == PK_FIRE)   return rgb(255, 205, 50);
  if (k == PK_SPREAD) return rgb(70, 215, 255);
  if (k == PK_DAMAGE) return rgb(255, 85, 75);
  if (k == PK_STORM)  return rgb(185, 110, 255);
  if (k == PK_SHIELD) return rgb(90, 140, 255);
  return rgb(255, 95, 150);
}

float superTime() { return 6 + min(6, 0.3 * wave); }   // timed buffs last longer later on

void collect(int k, float x, float y) {
  String msg = "";
  int c = pickupColor(k);
  boolean maxed = false;
  if (k == PK_FIRE)   { if (lvFire < MAX_FIRE)     { lvFire++;   msg = "FIRE RATE UP"; } else maxed = true; }
  if (k == PK_SPREAD) { if (lvSpread < MAX_SPREAD) { lvSpread++; msg = "MORE TEARS"; }   else maxed = true; }
  if (k == PK_DAMAGE) { if (lvDamage < MAX_DAMAGE) { lvDamage++; msg = "BIGGER TEARS"; } else maxed = true; }
  if (maxed) { overcharge++; msg = "BOOST +" + (overcharge * 8) + "%"; c = rgb(255, 150, 60); }
  if (k == PK_STORM)  { stormT = max(stormT, 0) + superTime();   stormMax = stormT;   msg = "TEAR STORM!"; }
  if (k == PK_SHIELD) { shieldT = max(shieldT, 0) + superTime(); shieldMax = shieldT; msg = "SHIELD!"; }
  if (k == PK_HEART)  { lives = min(5, lives + 1); msg = "+1 LIFE"; }
  if (k == PK_FIRE && !maxed && random(1) < 0.5)   manSay(MAN_FIRE, 0);
  if (k == PK_SPREAD && !maxed && random(1) < 0.5) manSay(MAN_SPREAD, 0);
  if (k == PK_DAMAGE && !maxed && random(1) < 0.5) manSay(MAN_DAMAGE, 0);
  if (maxed && random(1) < 0.4) manSay(MAN_BOOST, 0);
  if (k == PK_STORM)  manSay(MAN_STORM, 1);
  if (k == PK_SHIELD) manSay(MAN_SHIELD, 1);
  if (k == PK_HEART)  manSay(MAN_HEART, 1);
  score += 25;
  popup(msg, x, P_Y - 44, c);
  burst(x, y, c, rgb(255, 255, 255), 10, 40);
}

// ── Effects ───────────────────────────────────────────────────────────
void burst(float x, float y, int c1, int c2, int n, float spd) {
  for (int i = 0; i < n && parts.size() < 700; i++) {
    Particle p = new Particle();
    float a = random(TWO_PI), s = random(0.25, 1) * spd;
    p.x = x; p.y = y;
    p.vx = cos(a) * s; p.vy = sin(a) * s;
    p.life = p.maxLife = random(0.3, 0.75);
    p.col = random(1) < 0.5 ? c1 : c2;
    p.sz = random(1) < 0.25 ? 2 : 1;
    parts.add(p);
  }
}

void popup(String txt, float x, float y, int col) {
  if (popups.size() > 5) popups.remove(0);
  Popup p = new Popup();
  p.txt = txt; p.x = x; p.y = y; p.col = col; p.life = 1.3;
  popups.add(p);
}

void updateParticles(float dt) {
  for (int i = parts.size() - 1; i >= 0; i--) {
    Particle p = parts.get(i);
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    p.vx *= 1 - 2.5 * dt;
    p.vy *= 1 - 2.5 * dt;
    p.life -= dt;
    if (p.life <= 0) parts.remove(i);
  }
  for (int i = popups.size() - 1; i >= 0; i--) {
    Popup p = popups.get(i);
    p.y -= 12 * dt;
    p.life -= dt;
    if (p.life <= 0) popups.remove(i);
  }
}

void cleanup() {
  for (int i = tears.size() - 1; i >= 0; i--)   if (tears.get(i).dead)   tears.remove(i);
  for (int i = eshots.size() - 1; i >= 0; i--)  if (eshots.get(i).dead)  eshots.remove(i);
  for (int i = enemies.size() - 1; i >= 0; i--) if (enemies.get(i).dead) enemies.remove(i);
  for (int i = pickups.size() - 1; i >= 0; i--) if (pickups.get(i).dead) pickups.remove(i);
}

// ── Title screen frogs ────────────────────────────────────────────────
void spawnTitleFrog(int i) {
  Enemy e = new Enemy();
  e.type = E_FROG; e.deco = true; e.tier = i % 3; e.hw = 6; e.hh = 5;
  e.x = random(PF_L + 15, PF_R - 15);
  e.y = random(114, 130);
  e.vx = random(10, 18) * (random(1) < 0.5 ? -1 : 1);
  e.vy = random(-7, 7);
  e.phase = random(TWO_PI);
  e.sayAt = 0.8 + i * 2.2;
  enemies.add(e);
}

void updateTitleFrogs(float dt) {
  for (Enemy e : enemies) {
    e.age += dt;
    e.x += e.vx * dt;
    e.y += e.vy * dt;
    if (e.x < PF_L + 10 || e.x > PF_R - 10) e.vx = -e.vx;
    if (e.y < 112 || e.y > 132) e.vy = -e.vy;
    e.x = constrain(e.x, PF_L + 10, PF_R - 10);
    e.y = constrain(e.y, 112, 132);
    if (e.sayLeft > 0) e.sayLeft -= dt;
    updateSpeech(e);
    if (e.sayLeft <= 0 && e.sayAt < 0) e.sayAt = e.age + random(2, 5);
  }
}

// ── Stars and planets ─────────────────────────────────────────────────
void initGameStars() {
  for (int i = 0; i < NGSTARS; i++) {
    gsX[i] = random(PF_L, PF_R);
    gsY[i] = random(GH);
    gsL[i] = i % 3;
  }
}

void scrollGameStars(float dt) {
  float[] spd = { 6, 14, 30 };
  for (int i = 0; i < NGSTARS; i++) {
    gsY[i] += spd[gsL[i]] * dt;
    if (gsY[i] > GH) { gsY[i] = 0; gsX[i] = random(PF_L, PF_R); }
  }
  planetY += 2.5 * dt;
  if (planetY > GH + 30) {
    planetY = -30;
    planetX = random(PF_L + 20, PF_R - 20);
    planetKind = 1 - planetKind;
  }
}

// ════════════════════════════════════════════════════════════════════
//  Drawing the game
// ════════════════════════════════════════════════════════════════════
void renderGame() {
  int np = max(1, min(width / GW, height / GH));
  if (np != PX || artPX != np) { PX = np; buildArt(); }
  int sx = 0, sy = 0;
  if (shake > 0.5 && !gPaused) {
    sx = round(random(-shake, shake) * 0.5);
    sy = round(random(-shake, shake) * 0.5);
  }
  gox = (width - GW * PX) / 2 + sx * PX;
  goy = (height - GH * PX) / 2 + sy * PX;

  PGraphicsOpenGL pg = (PGraphicsOpenGL) g;
  pg.textureSampling(2);                 // keep the pixels crisp and blocky
  hint(DISABLE_DEPTH_TEST);
  camera();
  ortho();
  noLights();
  noStroke();
  noTint();
  imageMode(CORNER);
  rectMode(CORNER);
  background(0);

  fill(rgb(7, 6, 22));
  pixRect(PF_L, 0, PF_R - PF_L, GH);
  drawPlanet();
  drawGameStars();
  if (gState == G_TITLE) blitC(sprManBig, PF_C, 100 + sin(gTime * 2) * 3);
  drawHuge();
  drawPickups();
  drawTongues();
  drawEnemies();
  drawEShots();
  if (gState == G_PLAY) drawPlayer();
  drawHugeTongue();
  drawTears();
  drawParticles();
  drawBubbles();
  if (manSayT > 0 && gState == G_PLAY)  drawBubble(pX, P_Y - 12, manLines, true);
  if (manSayT > 0 && gState == G_TITLE) drawBubble(PF_C, 75 + sin(gTime * 2) * 3, manLines, true);
  drawPopups();
  drawBossBar();
  drawPanels();
  if (gState == G_TITLE) drawTitle();
  else if (gState == G_OVER) drawGameOver();
  else {
    drawWaveText();
    if (gPaused) drawPause();
  }
  if (demoMode && gState != G_TITLE) drawNoMpuStrip();

  perspective();
  hint(ENABLE_DEPTH_TEST);
  pg.textureSampling(5);
}

// draw a sprite centred on a game position
void blitC(PImage img, float cx, float cy) {
  int w = img.width / PX, h = img.height / PX;
  image(img, gox + (round(cx) - w / 2) * PX, goy + (round(cy) - h / 2) * PX);
}

// a rectangle in game pixels
void pixRect(float x, float y, float w, float h) {
  rect(gox + round(x) * PX, goy + round(y) * PX, round(w) * PX, round(h) * PX);
}

void drawPlanet() {
  blitC(planetKind == 0 ? sprPlanetA : sprPlanetB, planetX, planetY);
}

void drawGameStars() {
  for (int i = 0; i < NGSTARS; i++) {
    int L = gsL[i];
    boolean twinkle = L == 2 && ((i * 7 + frameCount / 6) % 23 == 0);
    fill(twinkle ? rgb(255, 255, 255) : L == 0 ? rgb(60, 60, 105) : L == 1 ? rgb(120, 120, 180) : rgb(210, 210, 255));
    pixRect(gsX[i], gsY[i], 1, 1);
  }
}

void drawPickups() {
  for (Pickup p : pickups) {
    if (p.dead) continue;
    float bob = sin(p.age * 6) * 1.5;
    blitC(sprIcon[p.kind], p.x, p.y + bob);
  }
}

void drawEnemies() {
  for (Enemy e : enemies) {
    if (e.dead) continue;
    boolean fl = e.flash > 0;
    if (e.type == E_FROG) {
      int fr = sin(e.age * 4 + e.phase) > 0 ? 1 : 0;
      float wx = (e.tier >= 2 && e.state == 1) ? (frameCount % 4 < 2 ? -1 : 1) : 0;
      blitC(fl ? sprFrogW[e.tier][fr] : sprFrog[e.tier][fr], e.x + wx, e.y);
    } else if (e.type == E_JET) {
      if ((frameCount / 3) % 2 == 0) { fill(rgb(255, 150, 40)); pixRect(round(e.x), round(e.y) - 8, 1, 2); }
      else { fill(rgb(255, 230, 120)); pixRect(round(e.x), round(e.y) - 7, 1, 1); }
      blitC(fl ? sprJetW : sprJet, e.x, e.y);
    } else {
      boolean angry = e.hp < e.maxHp * 0.5;
      if (angry && !fl) tint(255, 175, 175);
      blitC(fl ? sprBossW : sprBoss[sin(e.age * 3) > 0 ? 1 : 0], e.x, e.y);
      noTint();
      blitC(sprCrown, e.x, e.y - 26);
    }
  }
}

void drawHuge() {
  if (!hugeOn) return;
  int sx = round(hugeX), sy = round(hugeY);
  tint(hugeTint);
  blitC(sprHuge[(int) (gTime * 2) % 2], sx, sy);
  noTint();
  fill(rgb(15, 15, 20));                     // very cool sunglasses
  pixRect(sx - 27, sy - 23, 22, 9);
  pixRect(sx + 5, sy - 23, 22, 9);
  pixRect(sx - 5, sy - 21, 10, 2);
  fill(rgb(150, 220, 255));
  pixRect(sx - 24, sy - 21, 4, 2);
  pixRect(sx + 8, sy - 21, 4, 2);
}

void drawHugeTongue() {
  if (!hugeOn || hugeTongue <= 0) return;
  float mx = hugeX, my = hugeY + 4;
  float tx = lerp(mx, pX, hugeTongue), ty = lerp(my, P_Y - 2, hugeTongue);
  int n = max(1, (int) (dist(mx, my, tx, ty) / 2));
  fill(rgb(140, 25, 55));
  for (int i = 0; i <= n; i++) pixRect(lerp(mx, tx, i / (float) n) - 2, lerp(my, ty, i / (float) n) - 2, 5, 5);
  fill(rgb(240, 90, 130));
  for (int i = 0; i <= n; i++) pixRect(lerp(mx, tx, i / (float) n) - 1, lerp(my, ty, i / (float) n) - 1, 3, 3);
  fill(rgb(140, 25, 55));  pixRect(tx - 4, ty - 4, 9, 9);
  fill(rgb(240, 90, 130)); pixRect(tx - 3, ty - 3, 7, 7);
}

void drawTongues() {
  for (Enemy e : enemies) {                  // lightning frog lanes
    if (e.dead || e.type != E_FROG || e.tier != 3 || e.state != 1) continue;
    if ((frameCount / (e.timer < 0.5 ? 2 : 5)) % 2 == 0) {
      fill(e.timer < 0.5 ? rgb(255, 250, 160) : rgb(200, 170, 40));
      for (float y = e.y + 9; y < GH; y += 7) pixRect(round(e.x), y, 1, 4);
    }
  }
  for (Enemy e : enemies) {
    if (e.dead || e.type != E_BOSS) continue;
    if (e.tongueWarn > 0 && (frameCount / (e.tongueWarn < 0.45 ? 2 : 4)) % 2 == 0) {     // warning line
      fill(e.tongueWarn < 0.45 ? rgb(255, 230, 90) : rgb(255, 60, 60));   // turns yellow when it's locked on
      for (float y = e.y + 10; y < GH; y += 6) pixRect(round(e.x), y, 1, 3);
    }
    if (e.tongueT > 0) {
      float k = min(1, min((0.6 - e.tongueT) / 0.08, e.tongueT / 0.12));
      float top = e.y + 4, len = (GH - top) * k;
      fill(rgb(140, 25, 55));  pixRect(e.tongueX - 3, top, 7, len);
      fill(rgb(240, 90, 130)); pixRect(e.tongueX - 2, top, 5, len);
      fill(rgb(255, 160, 190)); pixRect(e.tongueX - 1, top, 1, len);
      fill(rgb(140, 25, 55));  pixRect(e.tongueX - 5, top + len - 7, 11, 7);
      fill(rgb(240, 90, 130)); pixRect(e.tongueX - 4, top + len - 6, 9, 5);
    }
  }
}

void drawEShots() {
  for (EShot s : eshots) {
    if (s.dead) continue;
    blitC(s.kind == 0 ? sprPellet : s.kind == 1 ? sprSpit : sprSpitBig, s.x, s.y);
  }
}

void drawPlayer() {
  boolean blink = invuln > 0 && (frameCount / 4) % 2 == 0;
  if (!blink) blitC(sprMan, pX, P_Y);
  if (shieldT > 0 && (shieldT > 2 || (frameCount / 5) % 2 == 0)) {
    fill(rgb(110, 220, 255), 210);
    for (int[] o : ring) pixRect(round(pX) + o[0], round(P_Y) + o[1], 1, 1);
  }
}

void drawTears() {
  if (stormT > 0) tint(215, 165, 255);
  for (Tear tr : tears) if (!tr.dead) blitC(sprTear[tr.sz], tr.x, tr.y);
  noTint();
}

void drawParticles() {
  for (Particle p : parts) {
    fill(p.col, 255 * p.life / p.maxLife);
    pixRect(p.x, p.y, p.sz, p.sz);
  }
}

void drawBubbles() {
  for (Enemy e : enemies) {
    if (e.dead || e.sayLeft <= 0) continue;
    if (e.type == E_BOSS) drawBubble(e.x, e.y + 24, BOSS_LINES, false);   // under the boss, clear of its health bar
    else drawBubble(e.x, e.y - e.hh - 1, FROG_LINES, true);
  }
  if (hugeOn && hugeState == 1) drawBubble(hugeX, hugeY + 28, HUGE_HI, false);
  if (hugeOn && hugeState == 3 && hugeT < 1.2) drawBubble(hugeX, hugeY + 28, HUGE_BYE, false);
}

// above = true: bubble sits above (ax, ay) with a tail. false: its top edge is at ay.
void drawBubble(float ax, float ay, String[] lines, boolean above) {
  int ps = max(1, PX - 1);
  float tw = 0;
  for (String l : lines) tw = max(tw, gTextW(l, ps));
  float lineH = 9 * ps / (float) PX;
  float bw = ceil(tw) + 6, bh = ceil(lines.length * lineH) + 3;
  float bx = constrain(round(ax - bw / 2), PF_L + 2, PF_R - 2 - bw);
  float by = above ? max(2, round(ay - bh - 4)) : round(ay);
  fill(rgb(20, 20, 30));
  pixRect(bx - 1, by, bw + 2, bh);
  pixRect(bx, by - 1, bw, bh + 2);
  fill(rgb(255, 255, 255));
  pixRect(bx, by, bw, bh);
  if (above && by + bh + 3 < ay + 2) {
    float tx = constrain(round(ax), bx + 3, bx + bw - 4);
    fill(rgb(20, 20, 30));
    pixRect(tx - 1, by + bh, 3, 2);
    pixRect(tx, by + bh + 2, 1, 2);
    fill(rgb(255, 255, 255));
    pixRect(tx, by + bh - 1, 1, 2);
  }
  for (int i = 0; i < lines.length; i++) gTextC(lines[i], bx + bw / 2, by + 2 + i * lineH, rgb(25, 25, 35), ps);
}

void drawPopups() {
  int ps = max(1, PX - 1);
  for (Popup p : popups) {
    float w = gTextW(p.txt, ps);
    float cx = constrain(p.x, PF_L + w / 2 + 2, PF_R - w / 2 - 2);
    gTextSC(p.txt, cx, p.y, p.col, ps);
  }
}

void drawBossBar() {
  for (Enemy e : enemies) {
    if (e.dead || e.type != E_BOSS) continue;
    float w = PF_R - PF_L - 12;
    fill(rgb(45, 20, 35));   pixRect(PF_L + 6, 4, w, 4);
    fill(rgb(230, 60, 70));  pixRect(PF_L + 6, 4, w * max(0, e.hp / e.maxHp), 4);
    fill(rgb(255, 150, 150)); pixRect(PF_L + 6, 4, w * max(0, e.hp / e.maxHp), 1);
    gTextC("BIG FROG", PF_C, 10, rgb(255, 205, 205), max(1, PX - 1));
  }
}

void pips(float x, float y, int lv, int mx, int col) {
  int pw = (48 - (mx - 1)) / mx;
  for (int i = 0; i < mx; i++) {
    fill(i < lv ? col : rgb(45, 40, 85));
    pixRect(x + i * (pw + 1), y, pw, 4);
  }
}

void drawPanels() {
  int lab = rgb(150, 140, 215), white = rgb(255, 255, 255);
  int sm = max(1, PX - 1);
  fill(rgb(18, 14, 44));
  pixRect(0, 0, PF_L, GH);
  pixRect(PF_R, 0, GW - PF_R, GH);
  fill(rgb(75, 60, 150));
  pixRect(PF_L - 1, 0, 1, GH);
  pixRect(PF_R, 0, 1, GH);

  // left: score, best, wave, lives
  gText("SCORE", 6, 8, lab, PX);
  gText(str(score), 6, 18, white, PX);
  gText("BEST", 6, 34, lab, PX);
  gText(str(best), 6, 44, newBest && (frameCount / 10) % 2 == 0 ? rgb(255, 220, 80) : white, PX);
  gText("WAVE", 6, 60, lab, PX);
  gText(str(max(1, wave)), 6, 70, white, PX);
  gText("LIVES", 6, 86, lab, PX);
  for (int i = 0; i < 5; i++) blitC(i < lives ? sprHeart : sprHeartOff, 9 + i * 9, 100);
  gText("MPU", 6, 122, lab, PX);
  if (demoMode) {
    fill(rgb(255, 60, 60));
    if ((frameCount / 25) % 2 == 0) pixRect(6, 133, 5, 5);
    gText("OFF", 14, 132, rgb(255, 80, 80), PX);
    gText("NOT", 6, 142, rgb(255, 80, 80), sm);
    gText("CONNECTED", 6, 148, rgb(255, 80, 80), sm);
  } else {
    fill(rgb(90, 255, 140));
    pixRect(6, 133, 5, 5);
    gText("ON", 14, 132, rgb(120, 255, 160), PX);
    gText("CONNECTED", 6, 145, rgb(120, 255, 160), sm);
  }
  gText("MOVE", 6, 160, lab, PX);
  if (demoMode) gText("< > KEYS", 6, 170, rgb(255, 210, 90), PX);
  else gText("TILT", 6, 170, rgb(120, 255, 160), PX);
  gText("P  PAUSE", 6, 186, lab, sm);
  gText("G  EXIT", 6, 194, lab, sm);
  if (!demoMode) gText("C  RECENTER", 6, 202, lab, sm);

  // right: upgrades and timed buffs
  float rx = PF_R + 6;
  gText("UPGRADES", rx, 8, lab, PX);
  gText("FIRE", rx, 22, white, PX);
  pips(rx, 31, lvFire, MAX_FIRE, pickupColor(PK_FIRE));
  gText("SPREAD", rx, 42, white, PX);
  pips(rx, 51, lvSpread, MAX_SPREAD, pickupColor(PK_SPREAD));
  gText("DAMAGE", rx, 62, white, PX);
  pips(rx, 71, lvDamage, MAX_DAMAGE, pickupColor(PK_DAMAGE));
  if (overcharge > 0) gText("BOOST +" + overcharge * 8 + "%", rx, 82, rgb(255, 150, 60), sm);
  float by = 100;
  if (stormT > 0) {
    gText("STORM", rx, by, pickupColor(PK_STORM), PX);
    fill(rgb(45, 40, 85)); pixRect(rx, by + 9, 48, 3);
    fill(pickupColor(PK_STORM)); pixRect(rx, by + 9, 48 * stormT / stormMax, 3);
    by += 20;
  }
  if (shieldT > 0) {
    gText("SHIELD", rx, by, pickupColor(PK_SHIELD), PX);
    fill(rgb(45, 40, 85)); pixRect(rx, by + 9, 48, 3);
    fill(pickupColor(PK_SHIELD)); pixRect(rx, by + 9, 48 * shieldT / shieldMax, 3);
  }
  gText("TEARS FIRE", rx, 184, lab, sm);
  gText("BY THEMSELVES", rx, 194, lab, sm);
}

// ── "MPU NOT CONNECTED" warnings ─────────────────────────────────────
String mpuProblem() {
  return port == null ? "CAN'T OPEN " + COM_PORT : COM_PORT + " IS OPEN BUT NO DATA";
}

// red strip under Sad Man for the whole game while there is no sensor data
void drawNoMpuStrip() {
  boolean on = (frameCount / 25) % 2 == 0;
  fill(on ? rgb(170, 20, 30) : rgb(120, 10, 20));
  pixRect(PF_L, 204, PF_R - PF_L, 12);
  fill(rgb(255, 90, 90));
  pixRect(PF_L, 204, PF_R - PF_L, 1);
  gTextC(port == null ? "MPU NOT CONNECTED" : "NO DATA FROM MPU", PF_C, 207, rgb(255, 255, 255), PX);
}

// big red box on the title screen explaining what's wrong
void drawNoMpuBox() {
  int sm = max(1, PX - 1);
  float x = PF_L + 6, y = 154, w = PF_R - PF_L - 12, h = 42;
  fill(rgb(255, 80, 80));  pixRect(x - 1, y - 1, w + 2, h + 2);
  fill(rgb(60, 8, 16));    pixRect(x, y, w, h);
  if ((frameCount / 25) % 2 == 0) { fill(rgb(255, 70, 70)); pixRect(x + 4, y + 4, 4, 4); pixRect(x + w - 8, y + 4, 4, 4); }
  gTextC("MPU NOT CONNECTED!", PF_C, y + 3, rgb(255, 90, 90), PX);
  gTextC(mpuProblem(), PF_C, y + 14, rgb(255, 255, 255), sm);
  gTextC(port == null ? "CHECK COM_PORT AT THE TOP OF THE CODE" : "TILT THE SENSOR ONCE / CHECK THE ESP32", PF_C, y + 22, rgb(255, 200, 200), sm);
  gTextC("PLAYING WITH ARROW KEYS FOR NOW", PF_C, y + 31, rgb(255, 220, 90), sm);
}

void dim() {
  fill(0, 0, 0, 165);
  pixRect(PF_L, 0, PF_R - PF_L, GH);
}

void drawTitle() {
  int sm = max(1, PX - 1);
  gTextSC("SAD MAN", PF_C, 18, rgb(120, 170, 255), PX * 2);
  gTextSC("VS THE SPACE FROGS", PF_C, 42, rgb(130, 230, 95), PX);
  if ((frameCount / 20) % 2 == 0) gTextSC("PRESS SPACE TO START", PF_C, 142, rgb(255, 220, 80), PX);
  if (demoMode) {
    drawNoMpuBox();
  } else {
    gTextC("MPU CONNECTED", PF_C, 158, rgb(120, 255, 160), sm);
    gTextC("TILT THE SENSOR LEFT / RIGHT TO MOVE", PF_C, 168, rgb(150, 230, 255), sm);
    gTextC("HOLD IT FLAT + PRESS C TO RECENTER", PF_C, 177, rgb(150, 230, 255), sm);
  }
  gTextC("G: BACK TO THE VISUALIZER", PF_C, 203, rgb(150, 140, 215), sm);
}

void drawGameOver() {
  int sm = max(1, PX - 1);
  dim();
  gTextSC("GAME OVER", PF_C, 46, rgb(255, 80, 80), PX * 2);
  gTextC("SAD MAN IS EVEN SADDER NOW", PF_C, 66, rgb(150, 190, 255), sm);
  gTextC("SCORE " + score, PF_C, 84, rgb(255, 255, 255), PX);
  gTextC("REACHED WAVE " + wave, PF_C, 96, rgb(150, 140, 215), PX);
  if (newBest) { if ((frameCount / 10) % 2 == 0) gTextSC("NEW BEST!", PF_C, 112, rgb(255, 220, 80), PX); }
  else gTextC("BEST " + best, PF_C, 112, rgb(150, 140, 215), PX);
  if (overT > 1.0) {
    if ((frameCount / 20) % 2 == 0) gTextSC("SPACE: PLAY AGAIN", PF_C, 144, rgb(255, 220, 80), PX);
    gTextC("G: BACK TO THE VISUALIZER", PF_C, 160, rgb(150, 140, 215), sm);
  }
}

void drawPause() {
  dim();
  gTextSC("PAUSED", PF_C, 90, rgb(255, 255, 255), PX * 2);
  gTextC("P TO CARRY ON CRYING", PF_C, 116, rgb(150, 190, 255), max(1, PX - 1));
}

void drawWaveText() {
  if (waveIntro > 0) {
    if (bossWave) {
      if ((frameCount / 8) % 2 == 0) gTextSC("WARNING!", PF_C, 72, rgb(255, 70, 70), PX * 2);
      gTextSC("BIG FROG INCOMING!", PF_C, 96, rgb(255, 210, 90), PX);
    } else {
      gTextSC("WAVE " + wave, PF_C, 72, rgb(255, 255, 255), PX * 2);
      gTextSC(waveHint(), PF_C, 96, rgb(150, 220, 255), max(1, PX - 1));
    }
  }
  if (bannerT > 0) gTextSC(bannerText, PF_C, 46, rgb(255, 220, 80), PX * 2);
}

String waveHint() {
  if (wave == 1) return "YOUR TEARS FIRE AUTOMATICALLY";
  if (wave == 2) return "WATCH OUT FOR JETS";
  if (wave == 3) return "BLUE FROGS SPIT";
  if (wave == 4) return "LIGHTNING FROGS! WATCH THE LANES";
  if (wave == 6) return "MORE FROGS. ANGRIER FROGS.";
  if (wave == 7) return "RED FROGS DIVE AT YOU";
  if (wave % 5 == 4) return "BIG FROG NEXT WAVE...";
  return "THEY KEEP COMING";
}

// ════════════════════════════════════════════════════════════════════
//  Retro pixel font (5x7) and text drawing
// ════════════════════════════════════════════════════════════════════
// each entry: the character, then 7 rows as 2-digit hex (5 bits per row)
final String[] FONT = {
  "00E11131519110E", "1040C040404040E", "20E11010204081F", "31F02040201110E",
  "402060A121F0202", "51F101E0101110E", "60608101E11110E", "71F010204080808",
  "80E11110E11110E", "90E11110F01020C", "A0E1111111F1111", "B1E11111E11111E",
  "C0E11101010110E", "D1C12111111121C", "E1F10101E10101F", "F1F10101E101010",
  "G0E11101711110F", "H1111111F111111", "I0E04040404040E", "J0702020202120C",
  "K11121418141211", "L1010101010101F", "M111B1515111111", "N11111915131111",
  "O0E11111111110E", "P1E11111E101010", "Q0E11111115120D", "R1E11111E141211",
  "S0F10100E01011E", "T1F040404040404", "U1111111111110E", "V11111111110A04",
  "W1111111515150A", "X11110A040A1111", "Y1111110A040404", "Z1F01020408101F",
  "?0E110102040004", "!04040404040004", ".00000000000C0C", ",000000000C0408",
  ":000C0C000C0C00", "'0C040800000000", "-0000001F000000", "+0004041F040400",
  "/00010204081000", "%18190204081303", "<02040810080402", ">08040201020408",
  "(02040808080402", ")08040202020408", "*0004150E150400", "=00001F001F0000",
  "_0000000000001F"
};
HashMap<Character, int[]> fontMap = null;
HashMap<String, PImage> glyphCache = new HashMap<String, PImage>();

PImage glyph(char ch, int col, int ps) {
  String k = ch + "|" + col + "|" + ps;
  PImage gi = glyphCache.get(k);
  if (gi != null) return gi;
  if (fontMap == null) {
    fontMap = new HashMap<Character, int[]>();
    for (String f : FONT) {
      int[] rows = new int[7];
      for (int i = 0; i < 7; i++) rows[i] = unhex(f.substring(1 + 2 * i, 3 + 2 * i));
      fontMap.put(f.charAt(0), rows);
    }
  }
  int[] rows = fontMap.get(ch);
  if (rows == null) rows = fontMap.get('?');
  gi = createImage(5 * ps, 7 * ps, ARGB);
  gi.loadPixels();
  for (int r = 0; r < 7; r++) {
    for (int c = 0; c < 5; c++) {
      if (((rows[r] >> (4 - c)) & 1) == 0) continue;
      for (int yy = 0; yy < ps; yy++) for (int xx = 0; xx < ps; xx++) gi.pixels[(r * ps + yy) * 5 * ps + c * ps + xx] = col;
    }
  }
  gi.updatePixels();
  glyphCache.put(k, gi);
  return gi;
}

// x, y in game pixels; ps = screen pixels per font pixel
void gText(String s, float lx, float ly, int col, int ps) {
  s = s.toUpperCase();
  int x = gox + round(lx * PX), y = goy + round(ly * PX);
  for (int i = 0; i < s.length(); i++) {
    char ch = s.charAt(i);
    if (ch != ' ') image(glyph(ch, col, ps), x + i * 6 * ps, y);
  }
}

float gTextW(String s, int ps) {
  return (s.length() * 6 * ps - ps) / (float) PX;
}

void gTextC(String s, float cx, float ly, int col, int ps) {
  gText(s, cx - gTextW(s, ps) / 2, ly, col, ps);
}

// centred, with a drop shadow
void gTextSC(String s, float cx, float ly, int col, int ps) {
  float x = cx - gTextW(s, ps) / 2, o = ps / (float) PX;
  gText(s, x + o, ly + o, rgb(0, 0, 0), ps);
  gText(s, x, ly, col, ps);
}

// ════════════════════════════════════════════════════════════════════
//  Pixel art (drawn from text, one character per pixel)
// ════════════════════════════════════════════════════════════════════
final String[] SPR_MAN = {
  ".oRRo.......oRRo.",
  ".oRRo.......oRRo.",
  ".oBBo..ooo..oBBo.",
  ".oBBo.oBBBo.oBBo.",
  ".oBBooBBBBBooBBo.",
  ".oBBoBBBBBBBoBBo.",
  ".oBBoBSKSKSBoBBo.",
  ".oBBoSKSSSKSoBBo.",
  ".oBBoSWWSWWSoBBo.",
  ".oBBoSKKSKKSoBBo.",
  ".oBBoSSSSSTSoBBo.",
  ".oBBosSKKKSsoBBo.",
  ".oBBooKSSSKooBBo.",
  "cCBBBCosssoCBBBCc",
  "cCCBBBBBBBBBBBCCc",
  "cCCoBBBBBBBBBoCCc",
  ".cCoBBBYYYBBBoCc.",
  ".cCoBBBBBBBBBoCc.",
  ".cc.oBBBoBBBo.cc.",
  ".c..oBBo.oBBo..c.",
  "....oRRo.oRRo....",
  "....oooo.oooo...."
};
final String[] SPR_FROG_A = {
  "..ooo.....ooo..",
  ".oWWWo...oWWWo.",
  ".oWKWoooooWKWo.",
  ".oGGGGGGGGGGGo.",
  "oGGgGGGGGGGgGGo",
  "oGGGGGGGGGGGGGo",
  "oKGGGGGGGGGGGKo",
  "oGKKKKKKKKKKKGo",
  ".oGLLLLLLLLLGo.",
  ".oGGLLLLLLLGGo.",
  "ogGo.ooooo.oGgo",
  "ogo.........ogo",
  "oo...........oo"
};
final String[] SPR_FROG_B = {
  "..ooo.....ooo..",
  ".oWWWo...oWWWo.",
  ".oWKWoooooWKWo.",
  ".oGGGGGGGGGGGo.",
  "oGGgGGGGGGGgGGo",
  "oGGGGGGGGGGGGGo",
  "oKGGGGGGGGGGGKo",
  "oGKKKKKKKKKKKGo",
  ".oGLLLLLLLLLGo.",
  ".oGGLLLLLLLGGo.",
  ".ogGoooooooGgo.",
  "..ooo.....ooo..",
  "..............."
};
final String[] SPR_JET = {
  "....oRo....",
  ".oo.oJo.oo.",
  ".oJooJooJo.",
  "..ojjJjjo..",
  "....oJo....",
  "ooooJJJoooo",
  "oRJJJJJJJRo",
  ".oojJJJjoo.",
  "...oJCJo...",
  "...oJCJo...",
  "....oJo....",
  ".....N....."
};
final String[] SPR_CROWN = {
  "y.....y.....y",
  "yy...yYy...yy",
  "yYy.yYYYy.yYy",
  "yYYyYYRYYyYYy",
  "yYYYYYYYYYYYy",
  "yBYYRYYYRYYBy",
  "yyyyyyyyyyyyy"
};
final String[][] SPR_TEAR = {
  { ".t.", "tTt", "TWT", ".T." },
  { ".tt.", "tTTt", "TWTT", "TTTT", ".TT." },
  { "..t..", ".tTt.", "tTTTt", "TWTTT", "TWTTT", "TTTTT", ".TTT." },
  { "...t...", "..tTt..", ".tTTTt.", "tTTTTTt", "TWWTTTT", "TWTTTTT", "TTTTTTT", ".TTTTT.", "..TTT.." }
};
final String[] SPR_PELLET = { "rRr", "RYR", "rRr" };
final String[] SPR_SPIT = { ".gg.", "gGWg", "gGGg", ".gg." };
final String[] SPR_SPIT_BIG = { "..g..", ".gGg.", "gGWGg", ".gGg.", "..g.." };
final String[] SPR_HEART = { ".RR.RR.", "RWRRRRR", "RRRRRRR", ".RRRRR.", "..RRR..", "...R..." };

PImage sprMan, sprManBig, sprJet, sprJetW, sprCrown, sprPellet, sprSpit, sprSpitBig;
PImage sprHeart, sprHeartOff, sprPlanetA, sprPlanetB, sprBossW;
PImage[] sprTear = new PImage[4], sprIcon = new PImage[6], sprBoss = new PImage[2];
PImage[][] sprFrog = new PImage[4][2], sprFrogW = new PImage[4][2];
PImage[] sprHuge = new PImage[2];
ArrayList<int[]> ring = new ArrayList<int[]>();

void buildArt() {
  artPX = PX;
  glyphCache.clear();
  int[] manCols = { rgb(25, 28, 62), rgb(75, 110, 205), rgb(48, 72, 150), rgb(242, 202, 168), rgb(206, 156, 124),
                    rgb(255, 255, 255), rgb(20, 20, 30), rgb(150, 100, 185), rgb(98, 62, 135), rgb(190, 48, 62),
                    rgb(235, 190, 60), rgb(110, 190, 255) };
  sprMan    = makeSprite(SPR_MAN, "oBbSsWKCcRYT", manCols, PX);
  sprManBig = makeSprite(SPR_MAN, "oBbSsWKCcRYT", manCols, PX * 2);

  int[][] frogPal = {
    { rgb(25, 55, 25), rgb(95, 190, 70), rgb(55, 135, 45), rgb(205, 230, 125), rgb(250, 250, 245), rgb(20, 20, 25) },
    { rgb(20, 35, 80), rgb(85, 150, 235), rgb(50, 95, 180), rgb(190, 215, 255), rgb(250, 250, 245), rgb(20, 20, 25) },
    { rgb(70, 20, 15), rgb(235, 95, 70), rgb(165, 50, 40), rgb(255, 205, 150), rgb(250, 250, 245), rgb(20, 20, 25) },
    { rgb(80, 60, 0), rgb(255, 215, 50), rgb(200, 140, 20), rgb(255, 250, 200), rgb(250, 250, 245), rgb(20, 20, 25) }
  };
  for (int t = 0; t < 4; t++) {
    sprFrog[t][0] = makeSprite(SPR_FROG_A, "oGgLWK", frogPal[t], PX);
    sprFrog[t][1] = makeSprite(SPR_FROG_B, "oGgLWK", frogPal[t], PX);
    sprFrogW[t][0] = whiteOf(sprFrog[t][0]);
    sprFrogW[t][1] = whiteOf(sprFrog[t][1]);
  }
  int[] bossPal = { rgb(20, 45, 20), rgb(70, 160, 60), rgb(40, 110, 40), rgb(215, 230, 140), rgb(250, 250, 245), rgb(20, 20, 25) };
  sprBoss[0] = makeSprite(SPR_FROG_A, "oGgLWK", bossPal, PX * 3);
  sprBoss[1] = makeSprite(SPR_FROG_B, "oGgLWK", bossPal, PX * 3);
  sprBossW = whiteOf(sprBoss[0]);
  int[] hugePal = { rgb(45, 45, 50), rgb(225, 225, 225), rgb(165, 165, 170), rgb(255, 255, 255), rgb(250, 250, 245), rgb(20, 20, 25) };
  sprHuge[0] = makeSprite(SPR_FROG_A, "oGgLWK", hugePal, PX * 4);   // grey, tinted a random colour when drawn
  sprHuge[1] = makeSprite(SPR_FROG_B, "oGgLWK", hugePal, PX * 4);
  sprCrown = makeSprite(SPR_CROWN, "yYRB", new int[] { rgb(190, 135, 25), rgb(255, 205, 60), rgb(230, 50, 60), rgb(70, 150, 255) }, PX * 2);

  sprJet  = makeSprite(SPR_JET, "oJjCRN", new int[] { rgb(30, 32, 44), rgb(185, 190, 205), rgb(120, 125, 145), rgb(100, 180, 255), rgb(230, 60, 50), rgb(80, 80, 95) }, PX);
  sprJetW = whiteOf(sprJet);

  for (int i = 0; i < 4; i++) sprTear[i] = makeSprite(SPR_TEAR[i], "tTW", new int[] { rgb(170, 225, 255), rgb(70, 150, 255), rgb(255, 255, 255) }, PX);
  sprPellet  = makeSprite(SPR_PELLET, "rRY", new int[] { rgb(150, 30, 30), rgb(255, 70, 60), rgb(255, 230, 140) }, PX);
  sprSpit    = makeSprite(SPR_SPIT, "gGW", new int[] { rgb(70, 180, 50), rgb(170, 255, 100), rgb(240, 255, 220) }, PX);
  sprSpitBig = makeSprite(SPR_SPIT_BIG, "gGW", new int[] { rgb(70, 180, 50), rgb(170, 255, 100), rgb(240, 255, 220) }, PX);
  sprHeart    = makeSprite(SPR_HEART, "RW", new int[] { rgb(255, 80, 110), rgb(255, 200, 210) }, PX);
  sprHeartOff = makeSprite(SPR_HEART, "RW", new int[] { rgb(55, 45, 90), rgb(75, 65, 110) }, PX);

  char[] iconCh = { 'F', 'S', 'D', '*', 'O', '+' };
  for (int i = 0; i < 6; i++) sprIcon[i] = makeIcon(pickupColor(i), iconCh[i]);

  sprPlanetA = makePlanet(20, rgb(225, 150, 95), rgb(170, 90, 70), true);
  sprPlanetB = makePlanet(13, rgb(110, 200, 190), rgb(60, 120, 160), false);

  ring.clear();
  for (int a = 0; a < 360; a += 2) {
    int dx = round(13 * cos(radians(a))), dy = round(15 * sin(radians(a)));
    boolean have = false;
    for (int[] o : ring) if (o[0] == dx && o[1] == dy) have = true;
    if (!have) ring.add(new int[] { dx, dy });
  }
}

PImage makeSprite(String[] rows, String keys, int[] cols, int s) {
  int w = rows[0].length(), h = rows.length;
  PImage img = createImage(w * s, h * s, ARGB);
  img.loadPixels();
  for (int r = 0; r < h; r++) {
    for (int c = 0; c < w; c++) {
      int k = keys.indexOf(rows[r].charAt(c));
      int col = k < 0 ? 0 : cols[k];
      for (int yy = 0; yy < s; yy++) for (int xx = 0; xx < s; xx++) img.pixels[(r * s + yy) * w * s + c * s + xx] = col;
    }
  }
  img.updatePixels();
  return img;
}

PImage whiteOf(PImage src) {
  PImage img = src.copy();
  img.loadPixels();
  for (int i = 0; i < img.pixels.length; i++) if ((img.pixels[i] >>> 24) != 0) img.pixels[i] = 0xFFFFFFFF;
  img.updatePixels();
  return img;
}

void setPix(PImage img, int x, int y, int col, int s) {
  for (int yy = 0; yy < s; yy++) for (int xx = 0; xx < s; xx++) img.pixels[(y * s + yy) * img.width + x * s + xx] = col;
}

// an 11x11 buff capsule with a letter on it
PImage makeIcon(int base, char ch) {
  int n = 11, s = PX;
  PImage img = createImage(n * s, n * s, ARGB);
  img.loadPixels();
  int dark = lerpColor(base, rgb(0, 0, 0), 0.55), light = lerpColor(base, rgb(255, 255, 255), 0.45);
  for (int y = 0; y < n; y++) {
    for (int x = 0; x < n; x++) {
      boolean corner = (x == 0 || x == n - 1) && (y == 0 || y == n - 1);
      if (corner) continue;
      boolean edge = x == 0 || y == 0 || x == n - 1 || y == n - 1;
      setPix(img, x, y, edge ? dark : (y == 1 || x == 1) ? light : base, s);
    }
  }
  if (fontMap == null) glyph('A', 0, 1);   // makes sure the font is loaded
  int[] rows = fontMap.get(ch);
  for (int r = 0; r < 7; r++) for (int c = 0; c < 5; c++) {
    if (((rows[r] >> (4 - c)) & 1) == 0) continue;
    setPix(img, 4 + c, 3 + r, dark, s);     // shadow
    setPix(img, 3 + c, 2 + r, rgb(255, 255, 255), s);
  }
  img.updatePixels();
  return img;
}

// a little shaded pixel planet
PImage makePlanet(int r, int c1, int c2, boolean ringed) {
  int pad = ringed ? 8 : 0;
  int w = 2 * r + 1 + 2 * pad, h = 2 * r + 1, s = PX;
  PImage img = createImage(w * s, h * s, ARGB);
  img.loadPixels();
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      float dx = x - pad - r, dy = y - r;
      if (dx * dx + dy * dy > r * r) continue;
      float band = sin(dy * 0.55 + sin(dx * 0.18) * 1.3);
      int col = band > 0.2 ? c1 : c2;
      float lit = 0.55 - (dx * 0.55 + dy * 0.45) / r;
      if (lit < 0.05 || (lit < 0.3 && (x + y) % 2 == 0)) col = lerpColor(col, rgb(10, 8, 30), 0.6);
      setPix(img, x, y, col, s);
    }
  }
  if (ringed) {
    for (int x = 0; x < w; x++) {
      float dx = x - pad - r;
      float ry = r * 0.35 * sqrt(max(0, 1 - sq(dx / (r + pad))));
      int y1 = round(r + ry * 0.4 + dx * 0.15);
      if (y1 < 0 || y1 >= h) continue;
      boolean behind = dx * dx + (y1 - r) * (y1 - r) <= r * r && y1 < r;
      if (!behind) setPix(img, x, y1, rgb(240, 215, 160), s);
    }
  }
  img.updatePixels();
  return img;
}
