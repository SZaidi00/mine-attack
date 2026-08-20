const stage = document.querySelector('#stage');
const compareToggle = document.querySelector('#compareToggle');
const presetButtons = [...document.querySelectorAll('.preset-button')];
const presetTitle = document.querySelector('#presetTitle');
const presetDescription = document.querySelector('#presetDescription');
const implementationNotes = document.querySelector('#implementationNotes');

const inputs = {
  intensity: document.querySelector('#intensity'),
  wind: document.querySelector('#wind'),
  visibility: document.querySelector('#visibility'),
  shelter: document.querySelector('#shelter'),
  softness: document.querySelector('#softness'),
  shelterToggle: document.querySelector('#shelterToggle'),
  groundToggle: document.querySelector('#groundToggle'),
  streakToggle: document.querySelector('#streakToggle'),
};

const outputs = {
  intensity: document.querySelector('#intensityValue'),
  wind: document.querySelector('#windValue'),
  visibility: document.querySelector('#visibilityValue'),
  shelter: document.querySelector('#shelterValue'),
  softness: document.querySelector('#softnessValue'),
};

const presets = {
  current: {
    title: 'Current blue vignette',
    description: 'The existing treatment: a flat radial blue overlay with simple snow particles.',
    values: { intensity: 0, wind: 0, visibility: 0, shelter: 0, softness: 0 },
    notes: [
      'Shown from the supplied in-game capture for direct comparison.',
      'The blue edge tint is visually clear but reads as a screen bubble.',
      'The proposed directions replace it with world-space occlusion.'
    ],
  },
  veil: {
    title: 'A · Blizzard Veil',
    description: 'Patchy wind-driven occlusion with readable silhouettes and warm shelter pockets.',
    values: { intensity: 72, wind: 38, visibility: 64, shelter: 58, softness: 70 },
    fogColor: [188, 216, 232],
    fogAlpha: 0.23,
    blobCount: 32,
    snowCount: 250,
    groundAlpha: 0.32,
    bandTop: 0.095,
    bandBottom: 0.382,
    streakBias: 1.0,
    notes: [
      'Best balance of drama and RTS readability.',
      'Fog arrives in rolling clumps instead of a symmetrical vignette.',
      'Lanterns carve soft warm visibility pockets into the storm.'
    ],
  },
  whiteout: {
    title: 'B · Ground Whiteout',
    description: 'Maximum surface whiteout with small shelter pockets, soft cloud-like fog banks, and no underground bleed.',
    values: { intensity: 100, wind: 16, visibility: 100, shelter: 23, softness: 100 },
    fogColor: [226, 240, 247],
    fogAlpha: 0.34,
    blobCount: 42,
    cloudCount: 12,
    snowCount: 360,
    groundAlpha: 0,
    bandTop: 0.095,
    bandBottom: 0.382,
    streakBias: 1.25,
    notes: [
      'Locked to 100% intensity and visibility loss for the storm peak.',
      'Wide fog banks drift horizontally like low clouds across the surface.',
      'The effect is clipped at the terrain line, keeping underground layers clean.'
    ],
  },
  frost: {
    title: 'C · Frost Fog',
    description: 'Cold desaturation, crystalline edge build-up, and softer visibility loss for a more survival-horror read.',
    values: { intensity: 56, wind: -22, visibility: 52, shelter: 68, softness: 88 },
    fogColor: [164, 210, 232],
    fogAlpha: 0.2,
    blobCount: 24,
    snowCount: 190,
    groundAlpha: 0.24,
    bandTop: 0.09,
    bandBottom: 0.382,
    streakBias: 0.72,
    notes: [
      'Most atmospheric and least obstructive option.',
      'Uses icy edge growth and desaturation instead of raw white density.',
      'Could pair with subtle frost crystals on exposed unit sprites.'
    ],
  },
};

const state = {
  preset: 'whiteout',
  compare: false,
  values: { ...presets.whiteout.values },
  shelterEnabled: true,
  groundEnabled: false,
  streaksEnabled: true,
};

class StormScene {
  constructor(root) {
    this.root = root;
    this.fogCanvas = root.querySelector('.fog-canvas');
    this.snowCanvas = root.querySelector('.snow-canvas');
    if (!this.fogCanvas || !this.snowCanvas) return;
    this.fog = this.fogCanvas.getContext('2d');
    this.snow = this.snowCanvas.getContext('2d');
    this.blobs = [];
    this.cloudBanks = [];
    this.flakes = [];
    this.lastTime = performance.now();
    this.resize();
    this.seed();
  }

  resize() {
    const rect = this.root.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.w = Math.max(1, Math.round(rect.width * dpr));
    this.h = Math.max(1, Math.round(rect.height * dpr));
    this.dpr = dpr;
    for (const canvas of [this.fogCanvas, this.snowCanvas]) {
      canvas.width = this.w;
      canvas.height = this.h;
    }
    this.seed();
  }

  seed() {
    const preset = presets[state.preset === 'current' ? 'whiteout' : state.preset];
    this.blobs = Array.from({ length: preset.blobCount }, (_, i) => ({
      x: Math.random(),
      y: preset.bandTop + Math.random() * (preset.bandBottom - preset.bandTop),
      rx: 0.05 + Math.random() * 0.15,
      ry: 0.025 + Math.random() * 0.085,
      speed: 0.006 + Math.random() * 0.026,
      alpha: 0.25 + Math.random() * 0.75,
      phase: Math.random() * Math.PI * 2,
      lift: Math.random() * 0.02,
    }));
    this.cloudBanks = Array.from({ length: preset.cloudCount || 8 }, () => ({
      x: Math.random(),
      y: preset.bandTop + 0.015 + Math.random() * (preset.bandBottom - preset.bandTop - 0.03),
      rx: 0.16 + Math.random() * 0.22,
      ry: 0.028 + Math.random() * 0.052,
      speed: 0.018 + Math.random() * 0.045,
      alpha: 0.35 + Math.random() * 0.65,
      phase: Math.random() * Math.PI * 2,
    }));
    this.flakes = Array.from({ length: preset.snowCount }, () => ({
      x: Math.random(),
      y: preset.bandTop + Math.random() * (preset.bandBottom - preset.bandTop),
      length: 0.008 + Math.random() * 0.032,
      width: 0.7 + Math.random() * 1.9,
      speed: 0.07 + Math.random() * 0.24,
      drift: 0.35 + Math.random() * 0.9,
      alpha: 0.2 + Math.random() * 0.72,
      phase: Math.random() * Math.PI * 2,
    }));
  }

  render(now) {
    if (!this.fog || state.preset === 'current') return;
    const dt = Math.min(0.05, (now - this.lastTime) / 1000);
    this.lastTime = now;
    const preset = presets[state.preset];
    const intensity = state.values.intensity / 100;
    const visibilityLoss = state.values.visibility / 100;
    const wind = state.values.wind / 100;
    const softness = state.values.softness / 100;
    const top = preset.bandTop * this.h;
    const bottom = preset.bandBottom * this.h;
    const height = bottom - top;

    this.fog.clearRect(0, 0, this.w, this.h);
    this.snow.clearRect(0, 0, this.w, this.h);

    this.fog.save();
    this.fog.beginPath();
    this.fog.rect(0, top, this.w, bottom - top);
    this.fog.clip();
    this.drawFogBase(preset, top, bottom, intensity, visibilityLoss, softness);
    this.drawCloudBanks(preset, top, height, intensity, visibilityLoss, wind, softness, dt, now);
    this.drawFogBlobs(preset, top, height, intensity, visibilityLoss, wind, softness, dt, now);
    if (state.groundEnabled) this.drawGroundLine(preset, top, bottom, intensity, visibilityLoss, now);
    if (state.preset === 'frost') this.drawFrostEdges(top, bottom, intensity, visibilityLoss, now);
    this.fog.restore();

    if (state.shelterEnabled) this.cutShelterPockets(top, bottom, softness);

    this.snow.save();
    this.snow.beginPath();
    this.snow.rect(0, top, this.w, bottom - top);
    this.snow.clip();
    if (state.streaksEnabled) this.drawSnow(preset, top, bottom, intensity, wind, dt, now);
    this.snow.restore();

    if (state.shelterEnabled) this.drawWarmShelters(top, intensity);
  }

  drawFogBase(preset, top, bottom, intensity, visibilityLoss, softness) {
    const ctx = this.fog;
    const [r, g, b] = preset.fogColor;
    const gradient = ctx.createLinearGradient(0, top, 0, bottom);
    const alpha = preset.fogAlpha * intensity * (0.35 + visibilityLoss * 0.85);
    gradient.addColorStop(0, `rgba(${r},${g},${b},${alpha * 0.18})`);
    gradient.addColorStop(0.45, `rgba(${r},${g},${b},${alpha * 0.58})`);
    gradient.addColorStop(1, `rgba(${r},${g},${b},${alpha})`);
    ctx.fillStyle = gradient;
    ctx.fillRect(0, top, this.w, bottom - top);
  }

  drawCloudBanks(preset, top, regionHeight, intensity, visibilityLoss, wind, softness, dt, now) {
    const ctx = this.fog;
    const [r, g, b] = preset.fogColor;
    const direction = wind < 0 ? -1 : 1;
    ctx.save();
    ctx.filter = `blur(${Math.round(18 + softness * 34) * this.dpr}px)`;
    for (const cloud of this.cloudBanks) {
      cloud.x += direction * cloud.speed * dt * (0.7 + Math.abs(wind) * 1.6);
      if (cloud.x > 1.35) cloud.x = -0.35;
      if (cloud.x < -0.35) cloud.x = 1.35;
      const x = cloud.x * this.w;
      const y = cloud.y * this.h + Math.sin(now * 0.00035 + cloud.phase) * this.h * 0.012;
      const rx = cloud.rx * this.w * (0.9 + intensity * 0.35);
      const ry = cloud.ry * this.h * (0.8 + visibilityLoss * 0.55);
      const pulse = 0.82 + 0.18 * Math.sin(now * 0.0005 + cloud.phase);
      ctx.beginPath();
      ctx.ellipse(x, y, rx, ry, wind * 0.06, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(${r},${g},${b},${(0.035 + cloud.alpha * 0.18 * intensity * visibilityLoss) * pulse})`;
      ctx.fill();
    }
    ctx.restore();
  }

  drawFogBlobs(preset, top, regionHeight, intensity, visibilityLoss, wind, softness, dt, now) {
    const ctx = this.fog;
    const [r, g, b] = preset.fogColor;
    ctx.save();
    ctx.filter = `blur(${Math.round(8 + softness * 28) * this.dpr}px)`;
    for (const blob of this.blobs) {
      blob.x += (wind * 0.7 + 0.2) * blob.speed * dt * preset.streakBias;
      if (blob.x > 1.22) blob.x = -0.22;
      if (blob.x < -0.22) blob.x = 1.22;
      const pulse = 0.78 + 0.22 * Math.sin(now * 0.0007 + blob.phase);
      const x = blob.x * this.w;
      const y = blob.y * this.h + Math.sin(now * 0.00045 + blob.phase) * blob.lift * this.h;
      const rx = blob.rx * this.w * (0.75 + intensity * 0.55);
      const ry = blob.ry * regionHeight * (0.9 + visibilityLoss * 0.9);
      ctx.beginPath();
      ctx.ellipse(x, y, rx, ry, wind * 0.18, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(${r},${g},${b},${0.05 + blob.alpha * preset.fogAlpha * intensity * visibilityLoss * pulse})`;
      ctx.fill();
    }
    ctx.restore();
  }

  drawGroundLine(preset, top, bottom, intensity, visibilityLoss, now) {
    const ctx = this.fog;
    const [r, g, b] = preset.fogColor;
    const groundY = bottom - (bottom - top) * 0.16;
    const bandHeight = this.h * 0.045;
    const gradient = ctx.createLinearGradient(0, groundY - bandHeight, 0, groundY + bandHeight * 1.2);
    const alpha = preset.groundAlpha * intensity * (0.35 + visibilityLoss * 0.85);
    gradient.addColorStop(0, `rgba(${r},${g},${b},0)`);
    gradient.addColorStop(0.48, `rgba(${r},${g},${b},${alpha})`);
    gradient.addColorStop(1, `rgba(${r},${g},${b},${alpha * 0.22})`);
    ctx.fillStyle = gradient;
    ctx.fillRect(0, groundY - bandHeight, this.w, bandHeight * 2.2);

    ctx.save();
    ctx.globalAlpha = 0.2 * intensity;
    ctx.strokeStyle = 'rgba(255,255,255,0.45)';
    ctx.lineWidth = 1 * this.dpr;
    for (let i = 0; i < 18; i += 1) {
      const y = groundY + Math.sin(now * 0.0008 + i) * bandHeight * 0.18 + i * 0.6 * this.dpr;
      ctx.beginPath();
      ctx.moveTo(0, y);
      for (let x = 0; x <= this.w; x += this.w / 12) {
        ctx.lineTo(x, y + Math.sin(x * 0.008 + now * 0.001 + i) * 3 * this.dpr);
      }
      ctx.stroke();
    }
    ctx.restore();
  }

  cutShelterPockets(top, bottom, softness) {
    const ctx = this.fog;
    const shelterScale = 0.25 + (state.values.shelter / 100) * 1.15;
    const pockets = [
      { x: 0.205, y: 0.315, r: 0.105 },
      { x: 0.355, y: 0.315, r: 0.072 },
      { x: 0.632, y: 0.31, r: 0.078 },
    ];
    ctx.save();
    ctx.globalCompositeOperation = 'destination-out';
    for (const pocket of pockets) {
      const x = pocket.x * this.w;
      const y = pocket.y * this.h;
      const radius = pocket.r * this.w * shelterScale;
      const inner = Math.max(0.04, 0.34 - softness * 0.22);
      const gradient = ctx.createRadialGradient(x, y, radius * inner, x, y, radius);
      gradient.addColorStop(0, 'rgba(0,0,0,0.74)');
      gradient.addColorStop(0.62, 'rgba(0,0,0,0.38)');
      gradient.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  drawFrostEdges(top, bottom, intensity, visibilityLoss, now) {
    const ctx = this.fog;
    ctx.save();
    ctx.globalCompositeOperation = 'source-over';
    ctx.strokeStyle = `rgba(218,244,255,${0.22 * intensity * visibilityLoss})`;
    ctx.lineWidth = 1.2 * this.dpr;
    const edges = [0, this.w];
    for (const edgeX of edges) {
      const direction = edgeX === 0 ? 1 : -1;
      for (let branch = 0; branch < 12; branch += 1) {
        const startY = top + (bottom - top) * (branch / 12);
        const length = (18 + branch * 3) * this.dpr * intensity;
        ctx.beginPath();
        ctx.moveTo(edgeX, startY);
        for (let segment = 1; segment <= 5; segment += 1) {
          const x = edgeX + direction * (length * segment / 5);
          const y = startY + Math.sin(now * 0.001 + branch + segment) * 4 * this.dpr + segment * 2 * this.dpr;
          ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
    }
    ctx.restore();
  }

  drawSnow(preset, top, bottom, intensity, wind, dt, now) {
    const ctx = this.snow;
    const windX = wind * 1.8;
    const activeCount = Math.floor(this.flakes.length * Math.max(0.12, intensity));
    ctx.save();
    ctx.lineCap = 'round';
    for (let i = 0; i < activeCount; i += 1) {
      const flake = this.flakes[i];
      flake.y += flake.speed * dt * (0.7 + intensity * 0.8);
      flake.x += wind * flake.drift * dt * 0.13;
      if (flake.y > preset.bandBottom) {
        flake.y = preset.bandTop - Math.random() * 0.025;
        flake.x = Math.random();
      }
      if (flake.x > 1.08) flake.x = -0.08;
      if (flake.x < -0.08) flake.x = 1.08;
      const x = flake.x * this.w;
      const y = flake.y * this.h;
      const gust = 1 + Math.sin(now * 0.0012 + flake.phase) * 0.34;
      const length = flake.length * this.h * preset.streakBias * gust;
      const alpha = flake.alpha * (0.28 + intensity * 0.72);
      ctx.strokeStyle = `rgba(241,248,255,${alpha})`;
      ctx.lineWidth = flake.width * this.dpr;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x - windX * length, y - length);
      ctx.stroke();
    }
    ctx.restore();
  }

  drawWarmShelters(top, intensity) {
    const ctx = this.snow;
    const pockets = [
      { x: 0.205, y: 0.315, r: 0.055 },
      { x: 0.355, y: 0.315, r: 0.043 },
      { x: 0.632, y: 0.31, r: 0.045 },
    ];
    ctx.save();
    ctx.globalCompositeOperation = 'screen';
    for (const pocket of pockets) {
      const x = pocket.x * this.w;
      const y = pocket.y * this.h;
      const radius = pocket.r * this.w;
      const gradient = ctx.createRadialGradient(x, y, 0, x, y, radius);
      gradient.addColorStop(0, `rgba(251,191,36,${0.28 * intensity})`);
      gradient.addColorStop(0.48, `rgba(251,191,36,${0.12 * intensity})`);
      gradient.addColorStop(1, 'rgba(251,191,36,0)');
      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }
}

const singleScene = new StormScene(document.querySelector('#singleScene'));
const splitProposedScene = new StormScene(document.querySelector('#splitProposed'));
const scenes = [singleScene, splitProposedScene];

function syncControls() {
  for (const key of ['intensity', 'wind', 'visibility', 'shelter', 'softness']) {
    inputs[key].value = state.values[key];
  }
  inputs.shelterToggle.checked = state.shelterEnabled;
  inputs.groundToggle.checked = state.groundEnabled;
  inputs.streakToggle.checked = state.streaksEnabled;
  updateOutputs();
}

function updateOutputs() {
  outputs.intensity.value = `${state.values.intensity}%`;
  outputs.wind.value = `${state.values.wind > 0 ? '+' : ''}${state.values.wind}°`;
  outputs.visibility.value = `${state.values.visibility}%`;
  outputs.shelter.value = `${state.values.shelter}%`;
  outputs.softness.value = `${state.values.softness}%`;
}

function setPreset(name) {
  state.preset = name;
  const preset = presets[name];
  if (name !== 'current') {
    state.values = { ...preset.values };
  }
  document.body.dataset.preset = name;
  presetTitle.textContent = preset.title;
  presetDescription.textContent = preset.description;
  implementationNotes.innerHTML = preset.notes.map((note) => `<li>${note}</li>`).join('');
  presetButtons.forEach((button) => button.classList.toggle('active', button.dataset.preset === name));
  const disabled = name === 'current';
  for (const input of Object.values(inputs)) input.disabled = disabled;
  syncControls();
  scenes.forEach((scene) => scene.seed());
}

function setCompare(enabled) {
  state.compare = enabled;
  if (enabled && state.preset === 'current') setPreset('whiteout');
  stage.classList.toggle('split', enabled);
  stage.classList.toggle('single', !enabled);
  compareToggle.setAttribute('aria-pressed', String(enabled));
  compareToggle.textContent = enabled ? 'Hide comparison' : 'Compare current';
  requestAnimationFrame(() => scenes.forEach((scene) => scene.resize()));
}

presetButtons.forEach((button) => {
  button.addEventListener('click', () => setPreset(button.dataset.preset));
});

compareToggle.addEventListener('click', () => setCompare(!state.compare));

for (const key of ['intensity', 'wind', 'visibility', 'shelter', 'softness']) {
  inputs[key].addEventListener('input', (event) => {
    state.values[key] = Number(event.target.value);
    updateOutputs();
  });
}

inputs.shelterToggle.addEventListener('change', (event) => {
  state.shelterEnabled = event.target.checked;
});

inputs.groundToggle.addEventListener('change', (event) => {
  state.groundEnabled = event.target.checked;
});

inputs.streakToggle.addEventListener('change', (event) => {
  state.streaksEnabled = event.target.checked;
});

const resizeObserver = new ResizeObserver(() => {
  scenes.forEach((scene) => scene.resize());
});
resizeObserver.observe(stage);

function animate(now) {
  for (const scene of scenes) scene.render(now);
  requestAnimationFrame(animate);
}

setPreset('whiteout');
requestAnimationFrame(animate);
