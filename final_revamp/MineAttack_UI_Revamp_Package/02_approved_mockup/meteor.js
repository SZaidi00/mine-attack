const stage = document.querySelector('#meteorStage');
const compareToggle = document.querySelector('#meteorCompare');
const presetButtons = [...document.querySelectorAll('.meteor-button')];
const title = document.querySelector('#meteorTitle');
const description = document.querySelector('#meteorDescription');
const notes = document.querySelector('#meteorNotes');

const inputs = {
  density: document.querySelector('#meteorDensity'),
  ember: document.querySelector('#emberGlow'),
  markers: document.querySelector('#impactMarkers'),
  plume: document.querySelector('#plumePower'),
  heat: document.querySelector('#heatGrade'),
  targetZones: document.querySelector('#targetZonesToggle'),
  emberField: document.querySelector('#emberFieldToggle'),
  warningRail: document.querySelector('#warningRailToggle'),
};

const outputs = {
  density: document.querySelector('#meteorDensityValue'),
  ember: document.querySelector('#emberGlowValue'),
  markers: document.querySelector('#impactMarkersValue'),
  plume: document.querySelector('#plumePowerValue'),
  heat: document.querySelector('#heatGradeValue'),
};

const presets = {
  current: {
    title: 'Current red vignette',
    description: 'The existing eruption treatment: a strong red-orange radial overlay with limited impact forecasting.',
    values: { density: 0, ember: 0, markers: 0, plume: 0, heat: 0 },
    meteorCount: 0,
    emberCount: 0,
    notes: [
      'Shown from the supplied eruption capture for direct comparison.',
      'The event is visible, but impact timing and landing locations are not readable.',
      'The proposed directions move danger information into the world and warning UI.'
    ],
  },
  impact: {
    title: 'A · Impact Forecast',
    description: 'A readable warning system with impact zones, bright trails, and moderate atmospheric heat.',
    values: { density: 58, ember: 52, markers: 76, plume: 58, heat: 34 },
    meteorCount: 34,
    emberCount: 90,
    zoneAlpha: 0.78,
    notes: [
      'Impact zones communicate the next few seconds of danger.',
      'Meteor trails are sparse enough to preserve unit readability.',
      'Warm HUD accents stay reserved for actual event severity.'
    ],
  },
  siege: {
    title: 'B · Volcanic Siege',
    description: 'Maximum meteor and ember density with a moderate crater plume, no impact rings, and all atmosphere clipped to the surface.',
    values: { density: 100, ember: 100, markers: 0, plume: 45, heat: 68 },
    meteorCount: 82,
    emberCount: 220,
    zoneAlpha: 0,
    notes: [
      'Locked to 100% meteor density and ember glow for the eruption peak.',
      'Crater plume is the smoke and glow rising from the volcano mouth; it is set to 45%.',
      'All heat, trails, embers, and plume effects stop at the surface line.'
    ],
  },
};

const state = {
  preset: 'siege',
  compare: false,
  values: { ...presets.siege.values },
  targetZones: true,
  emberField: true,
  warningRail: true,
};

class MeteorScene {
  constructor(root) {
    this.root = root;
    this.canvas = root.querySelector('.meteor-canvas');
    if (!this.canvas) return;
    this.ctx = this.canvas.getContext('2d');
    this.meteors = [];
    this.embers = [];
    this.lastTime = performance.now();
    this.resize();
    this.seed();
  }

  resize() {
    const rect = this.root.getBoundingClientRect();
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.w = Math.max(1, Math.round(rect.width * this.dpr));
    this.h = Math.max(1, Math.round(rect.height * this.dpr));
    this.canvas.width = this.w;
    this.canvas.height = this.h;
    this.seed();
  }

  seed() {
    const preset = presets[state.preset === 'current' ? 'siege' : state.preset];
    this.meteors = Array.from({ length: preset.meteorCount }, (_, index) => ({
      x: 0.08 + Math.random() * 1.05,
      y: -0.12 + Math.random() * 0.5,
      speed: 0.17 + Math.random() * 0.34,
      length: 0.045 + Math.random() * 0.09,
      width: 1.2 + Math.random() * 2.2,
      phase: Math.random() * Math.PI * 2,
      delay: (index % 9) * 0.17,
    }));
    this.embers = Array.from({ length: preset.emberCount }, () => ({
      x: Math.random(),
      y: 0.11 + Math.random() * 0.36,
      radius: 0.7 + Math.random() * 2.6,
      speed: 0.012 + Math.random() * 0.036,
      sway: 0.3 + Math.random() * 0.9,
      alpha: 0.24 + Math.random() * 0.66,
      phase: Math.random() * Math.PI * 2,
    }));
  }

  render(now) {
    if (!this.ctx || state.preset === 'current') return;
    const dt = Math.min(0.05, (now - this.lastTime) / 1000);
    this.lastTime = now;
    const preset = presets[state.preset];
    const top = this.h * 0.095;
    const bottom = this.h * 0.382;
    const heat = state.values.heat / 100;
    const density = state.values.density / 100;
    const ember = state.values.ember / 100;
    const markers = state.values.markers / 100;
    const plume = state.values.plume / 100;

    document.documentElement.style.setProperty('--heat-opacity', String(heat * (state.preset === 'siege' ? 0.72 : 0.48)));
    this.ctx.clearRect(0, 0, this.w, this.h);
    this.ctx.save();
    this.ctx.beginPath();
    this.ctx.rect(0, top, this.w, bottom - top);
    this.ctx.clip();
    this.drawSkyHeat(top, bottom, heat);
    this.drawPlume(plume, now);
    if (state.targetZones) this.drawImpactZones(bottom, markers * preset.zoneAlpha, now);
    this.drawMeteors(top, bottom, density, dt, now);
    if (state.emberField) this.drawEmbers(top, bottom, ember, dt, now);
    this.ctx.restore();
  }

  drawSkyHeat(top, bottom, heat) {
    const ctx = this.ctx;
    const gradient = ctx.createLinearGradient(0, top, 0, bottom);
    gradient.addColorStop(0, `rgba(85,18,10,${0.08 * heat})`);
    gradient.addColorStop(0.45, `rgba(181,55,18,${0.14 * heat})`);
    gradient.addColorStop(1, `rgba(255,102,31,${0.22 * heat})`);
    ctx.fillStyle = gradient;
    ctx.fillRect(0, top, this.w, bottom - top);
  }

  drawPlume(power, now) {
    if (power <= 0.01) return;
    const ctx = this.ctx;
    const cx = this.w * 0.505;
    const craterY = this.h * 0.285;
    ctx.save();
    ctx.globalCompositeOperation = 'screen';
    for (let i = 0; i < 18; i += 1) {
      const t = i / 18;
      const pulse = 0.72 + 0.28 * Math.sin(now * 0.002 + i * 1.7);
      const x = cx + Math.sin(now * 0.001 + i) * this.w * 0.012 * (1 + t * 2.4);
      const y = craterY - t * this.h * 0.2 * power;
      const radius = (10 + t * 42) * this.dpr * power * pulse;
      const gradient = ctx.createRadialGradient(x, y, 0, x, y, radius);
      gradient.addColorStop(0, `rgba(255,188,73,${0.11 * power})`);
      gradient.addColorStop(0.45, `rgba(239,86,28,${0.07 * power})`);
      gradient.addColorStop(1, 'rgba(80,22,12,0)');
      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  drawImpactZones(groundY, alpha, now) {
    if (alpha <= 0.01) return;
    const ctx = this.ctx;
    const zones = [
      { x: 0.25, r: 0.052, label: 'A' },
      { x: 0.49, r: 0.068, label: 'B' },
      { x: 0.73, r: 0.05, label: 'C' },
    ];
    ctx.save();
    for (const [index, zone] of zones.entries()) {
      const x = zone.x * this.w;
      const y = groundY - this.h * 0.018;
      const rx = zone.r * this.w;
      const ry = rx * 0.23;
      const pulse = 0.58 + 0.42 * Math.sin(now * 0.004 + index * 1.8);
      ctx.fillStyle = `rgba(255,89,38,${0.08 * alpha})`;
      ctx.strokeStyle = `rgba(255,196,87,${(0.28 + pulse * 0.42) * alpha})`;
      ctx.lineWidth = 2 * this.dpr;
      ctx.beginPath();
      ctx.ellipse(x, y, rx, ry, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      ctx.strokeStyle = `rgba(255,89,38,${0.28 * alpha})`;
      ctx.lineWidth = 1 * this.dpr;
      ctx.beginPath();
      ctx.ellipse(x, y, rx * (0.55 + pulse * 0.2), ry * (0.55 + pulse * 0.2), 0, 0, Math.PI * 2);
      ctx.stroke();
      ctx.fillStyle = `rgba(255,228,168,${0.76 * alpha})`;
      ctx.font = `${10 * this.dpr}px ui-sans-serif, system-ui`;
      ctx.textAlign = 'center';
      ctx.fillText(zone.label, x, y + 3 * this.dpr);
    }
    ctx.restore();
  }

  drawMeteors(top, bottom, density, dt, now) {
    const ctx = this.ctx;
    const count = Math.floor(this.meteors.length * Math.max(0.08, density));
    ctx.save();
    ctx.lineCap = 'round';
    for (let i = 0; i < count; i += 1) {
      const meteor = this.meteors[i];
      meteor.y += meteor.speed * dt * (0.45 + density * 0.8);
      meteor.x -= meteor.speed * dt * 0.31;
      if (meteor.y > 0.395 || meteor.x < -0.18) {
        meteor.x = 0.42 + Math.random() * 0.78;
        meteor.y = -0.12 - Math.random() * 0.18;
      }
      const x = meteor.x * this.w;
      const y = meteor.y * this.h;
      if (y < top - 30 || y > bottom + 40) continue;
      const length = meteor.length * this.h * (0.8 + density * 0.6);
      const tailX = x + length * 0.5;
      const tailY = y - length;
      const glow = 0.35 + 0.65 * Math.sin(now * 0.006 + meteor.phase) ** 2;
      ctx.strokeStyle = `rgba(255,88,28,${0.24 * density * glow})`;
      ctx.lineWidth = meteor.width * 3.2 * this.dpr;
      ctx.beginPath();
      ctx.moveTo(tailX, tailY);
      ctx.lineTo(x, y);
      ctx.stroke();
      ctx.strokeStyle = `rgba(255,228,146,${0.82 * density})`;
      ctx.lineWidth = meteor.width * this.dpr;
      ctx.beginPath();
      ctx.moveTo(tailX, tailY);
      ctx.lineTo(x, y);
      ctx.stroke();
      ctx.fillStyle = `rgba(255,246,204,${0.9 * density})`;
      ctx.beginPath();
      ctx.arc(x, y, meteor.width * 1.7 * this.dpr, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  drawEmbers(top, bottom, ember, dt, now) {
    const ctx = this.ctx;
    const count = Math.floor(this.embers.length * Math.max(0.06, ember));
    ctx.save();
    ctx.globalCompositeOperation = 'screen';
    for (let i = 0; i < count; i += 1) {
      const particle = this.embers[i];
      particle.y -= particle.speed * dt * (0.55 + ember);
      particle.x += Math.sin(now * 0.001 + particle.phase) * particle.sway * dt * 0.012;
      if (particle.y < 0.08) {
        particle.y = 0.375 + Math.random() * 0.02;
        particle.x = Math.random();
      }
      const x = particle.x * this.w;
      const y = particle.y * this.h;
      if (y < top || y > bottom + this.h * 0.03) continue;
      const flicker = 0.55 + 0.45 * Math.sin(now * 0.008 + particle.phase);
      ctx.fillStyle = `rgba(255,126,38,${particle.alpha * ember * flicker})`;
      ctx.beginPath();
      ctx.arc(x, y, particle.radius * this.dpr, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }
}

const singleScene = new MeteorScene(document.querySelector('#meteorSingle'));
const splitScene = new MeteorScene(document.querySelector('#meteorSplitProposed'));
const scenes = [singleScene, splitScene];

function syncControls() {
  for (const key of ['density', 'ember', 'markers', 'plume', 'heat']) {
    inputs[key].value = state.values[key];
  }
  inputs.targetZones.checked = state.targetZones;
  inputs.emberField.checked = state.emberField;
  inputs.warningRail.checked = state.warningRail;
  updateOutputs();
}

function updateOutputs() {
  outputs.density.value = `${state.values.density}%`;
  outputs.ember.value = `${state.values.ember}%`;
  outputs.markers.value = `${state.values.markers}%`;
  outputs.plume.value = `${state.values.plume}%`;
  outputs.heat.value = `${state.values.heat}%`;
}

function setPreset(name) {
  state.preset = name;
  const preset = presets[name];
  if (name !== 'current') state.values = { ...preset.values };
  document.body.dataset.meteor = name;
  title.textContent = preset.title;
  description.textContent = preset.description;
  notes.innerHTML = preset.notes.map((note) => `<li>${note}</li>`).join('');
  presetButtons.forEach((button) => button.classList.toggle('active', button.dataset.meteorPreset === name));
  const disabled = name === 'current';
  Object.values(inputs).forEach((input) => { input.disabled = disabled; });
  syncControls();
  scenes.forEach((scene) => scene.seed());
}

function setCompare(enabled) {
  state.compare = enabled;
  if (enabled && state.preset === 'current') setPreset('siege');
  stage.classList.toggle('split', enabled);
  stage.classList.toggle('single', !enabled);
  compareToggle.setAttribute('aria-pressed', String(enabled));
  compareToggle.textContent = enabled ? 'Hide comparison' : 'Compare current';
  requestAnimationFrame(() => scenes.forEach((scene) => scene.resize()));
}

presetButtons.forEach((button) => button.addEventListener('click', () => setPreset(button.dataset.meteorPreset)));
compareToggle.addEventListener('click', () => setCompare(!state.compare));

for (const key of ['density', 'ember', 'markers', 'plume', 'heat']) {
  inputs[key].addEventListener('input', (event) => {
    state.values[key] = Number(event.target.value);
    updateOutputs();
  });
}

inputs.targetZones.addEventListener('change', (event) => {
  state.targetZones = event.target.checked;
  document.body.classList.toggle('hide-target-zones', !state.targetZones);
});

inputs.emberField.addEventListener('change', (event) => {
  state.emberField = event.target.checked;
});

inputs.warningRail.addEventListener('change', (event) => {
  state.warningRail = event.target.checked;
  document.body.classList.toggle('hide-warning-rail', !state.warningRail);
});

const resizeObserver = new ResizeObserver(() => scenes.forEach((scene) => scene.resize()));
resizeObserver.observe(stage);

function animate(now) {
  scenes.forEach((scene) => scene.render(now));
  requestAnimationFrame(animate);
}

setPreset('siege');
requestAnimationFrame(animate);
