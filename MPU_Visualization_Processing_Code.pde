/*
  MotionPotion — MPU6050 Roll / Pitch / Yaw visualizer 

  Keys
    C        calibrate (hold the MPU flat first)
    F        next object
    1 - 5    pick an object: Jet, Sad Man, Frog, Knife, Gun

  Every object is built from code — no model files needed.
  Optional: drop a goofy .ttf (e.g. Bangers-Regular.ttf from Google Fonts)
  into this sketch's "data" folder and the fun text will use it.
  Otherwise it uses Comic Sans MS, which ships with Windows.
*/
import processing.serial.*;

Serial port;
boolean demoMode = false;   // true when no serial port opens: the model sways on its own

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

  // Serial: change the [0] if your ESP32 is on a different port
  String[] ports = Serial.list();
  printArray(ports);
  if (ports.length > 0) {
    try {
      port = new Serial(this, ports[0], 115200);
      port.bufferUntil('\n');
    } catch (Exception e) {
      println("Could not open " + ports[0] + " -> demo mode");
      demoMode = true;
    }
  } else {
    println("No serial port found -> demo mode");
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
  background(12, 12, 28);
  drawStars();

  if (demoMode) {
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
  if (over(btnX, calBtnY, btnW, btnH)) calibrate();
  else if (over(btnX, funBtnY, btnW, btnH)) setModel(currentModel + 1);
}

void keyPressed() {
  if (key == 'c' || key == 'C') calibrate();
  if (key == 'f' || key == 'F') setModel(currentModel + 1);
  if (key >= '1' && key <= '5') setModel(key - '1');
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
void drawButtons() {
  calBtnY = height - 60;
  funBtnY = height - 108;
  textFont(hudFont);

  // Fun button
  boolean fh = over(btnX, funBtnY, btnW, btnH);
  fill(fh ? color(170, 70, 200) : color(110, 45, 140));
  noStroke();
  rect(btnX, funBtnY, btnW, btnH, 7);
  // little star icon
  fill(255, 220, 90);
  float sx = btnX + 20, sy = funBtnY + btnH / 2;
  beginShape();
  for (int i = 0; i < 10; i++) {
    float a = -HALF_PI + i * PI / 5;
    float r = i % 2 == 0 ? 8 : 3.5;
    vertex(sx + r * cos(a), sy + r * sin(a));
  }
  endShape(CLOSE);
  fill(240, 225, 255);
  textSize(13);
  textAlign(LEFT, CENTER);
  text("Next object  [F]", btnX + 38, funBtnY + btnH / 2);

  // Calibrate button
  boolean ch = over(btnX, calBtnY, btnW, btnH);
  if (calibrated && !ch) fill(20, 80, 40);   // green tint after first calibration
  else if (ch) fill(50, 100, 200);
  else fill(30, 60, 130);
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
  text(calibrated ? "Re-calibrate Horizon  [C]" : "Calibrate Horizon  [C]", btnX + 38, calBtnY + btnH / 2);
}

// ── HUD ────────────────────────────────────────
void drawHUD() {
  fill(0, 0, 0, 150);
  noStroke();
  rect(14, 14, 240, 196, 8);

  textFont(hudFont);
  fill(180, 210, 255);
  textSize(12);
  textAlign(LEFT, BASELINE);
  text("MPU6050  |  ESP32C6", 26, 34);

  // Calibration status
  textSize(11);
  if (demoMode) {
    fill(255, 120, 200);
    text("● DEMO MODE (no serial port)", 26, 52);
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
  text(modelNames[currentModel] + "   (" + (currentModel + 1) + "/" + modelNames.length + ", keys 1-5)", 80, 156);

  drawFunLine(26, 192);
}

// "Press F for fun!" — every letter bounces in its own rainbow colour
void drawFunLine(float x, float y) {
  String s = "Don't Press F !";
  textFont(funFont);
  textSize(21);
  textAlign(LEFT, BASELINE);
  colorMode(HSB, 360, 100, 100);
  float cx = x;
  for (int i = 0; i < s.length(); i++) {
    char c = s.charAt(i);
    float dy = sin(t * 5 + i * 0.55) * 2.4;
    float rot = sin(t * 4 + i * 1.7) * 0.09;
    fill((t * 90 + i * 22) % 360, 65, 100);
    pushMatrix();
    translate(cx, y + dy);
    rotate(rot);
    text(c, 0, 0);
    popMatrix();
    cx += textWidth(c);
  }
  colorMode(RGB, 255);
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
        pitch = float(vals[0]);
        roll  = float(vals[1]);
        yaw   = float(vals[2]);
      } catch (Exception e) {
        println("Parse error: " + e.getMessage());
      }
    }
  }
}
