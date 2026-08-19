const variantButtons = [...document.querySelectorAll('.variant-button')];
const variantTitle = document.querySelector('#variantTitle');
const variantDescription = document.querySelector('#variantDescription');
const variantNotes = document.querySelector('#variantNotes');
const sceneLabel = document.querySelector('.scene-label');
const scope = ['menu', 'hud', 'build', 'research'].find((key) => document.body.classList.contains(`${key}-page`));

const VARIANT_CONTENT = {
  menu: {
    current: {
      title: 'Current menu',
      description: 'The existing centered title card over the night-sky background, shown from the supplied capture.',
      notes: [
        'The flow is simple and functional, but the presentation feels sparse.',
        'Faction identity does not begin until the next screen.',
        'The background has useful ingredients: sky, bases, snow, and volcano.'
      ],
    },
    command: {
      title: 'A · Command Console',
      description: 'A polished version of the current centered flow, upgraded with tactile metal, animated atmosphere, faction-colored base glows, and world-status details.',
      notes: [
        'The background now has drifting cloud bands, aurora light, and stronger base/volcano glows.',
        'The flow remains the same: title, difficulty, resolution, next, and quit.',
        'The player/enemy status modules reinforce the two-sided siege fantasy.'
      ],
    },
    factions: {
      title: 'B · Faction Gate',
      description: 'Moves faction identity into the opening impression with three large doctrine cards and a stronger deployment action.',
      notes: [
        'Best if faction choice should feel like a major strategic commitment.',
        'The existing faction colors remain intact, but each card gets more presence.',
        'Could replace the current second step rather than the first title card.'
      ],
    },
    briefing: {
      title: 'C · Operation Briefing',
      description: 'A more diegetic mission-start interface with a command rail, operation summary, and event-risk readouts.',
      notes: [
        'Best if MineAttack should feel like a military survival operation.',
        'The left rail can scale into settings, saves, or future modes.',
        'The briefing panel creates room for event expectations before play.'
      ],
    },
  },
  hud: {
    current: {
      title: 'Current HUD',
      description: 'The existing top bar, bottom command bar, and right-side queue shown from the supplied gameplay capture.',
      notes: [
        'All necessary information is present, but the bars read as separate flat rectangles.',
        'Training, stances, upgrades, research, and build compete for the same visual weight.',
        'The empty queue panel takes space even when it has little to communicate.'
      ],
    },
    steel: {
      title: 'A · Frosted Steel',
      description: 'The safest full redesign: same layout, stronger materials, tighter grouping, and a production queue that shows active progress, upcoming units, capacity, and controls.',
      notes: [
        'The queue now reads as a production module instead of a small empty status box.',
        'Active training gets the strongest gold treatment; queued and locked units sit underneath.',
        'Pause and Clear controls are included without changing the bottom command bar.'
      ],
    },
    tactical: {
      title: 'B · Tactical Minimal',
      description: 'A low-chrome RTS direction with floating pills, compact command buttons, and more battlefield visibility.',
      notes: [
        'Best if maximum world visibility is the top priority.',
        'The smaller buttons would need strong tooltips and reliable hotkeys.',
        'This direction feels modern, but less diegetic than the steel concept.'
      ],
    },
    deck: {
      title: 'C · Siege Deck',
      description: 'A more structural command deck with a left navigation rail, grouped production sections, and an event-watch module.',
      notes: [
        'Best if the UI should feel like operating a military machine.',
        'The grouped production bar clarifies economy, army, and command actions.',
        'The left rail takes more screen space but creates room for future systems.'
      ],
    },
  },
  build: {
    current: {
      title: 'Current build menu',
      description: 'The existing centered 720×420 modal with a three-column grid of six construction options.',
      notes: [
        'The grid is compact, but it blocks the center of the battlefield.',
        'All options share the same emphasis even though they serve different roles.',
        'Costs and counts are present, but the panel has little hierarchy or material identity.'
      ],
    },
    tray: {
      title: 'A · Blueprint Tray',
      description: 'A bottom construction tray that keeps the world visible and groups blueprints by use.',
      notes: [
        'Is grouping by Light / Defense / Utility useful?',
        'Should the tray appear above or replace the command bar?',
        'Are hotkeys prominent enough for experienced players?'
      ],
    },
    ring: {
      title: 'B · Tactical Ring',
      description: 'A fast placement concept that surrounds the cursor with six compact blueprints and minimal reading.',
      notes: [
        'Best for experienced players who already know the costs.',
        'The circular layout is visually distinct but less scalable than a tray or list.',
        'Would need strong edge spacing and controller/hotkey behavior.'
      ],
    },
    workshop: {
      title: 'C · Field Workshop',
      description: 'A right-side construction panel with categories, descriptions, availability, and a selected-blueprint footer.',
      notes: [
        'Best if build options need clearer explanations or future upgrade text.',
        'The side placement preserves the battlefield center.',
        'This is the easiest concept to extend with tabs, search, or locked blueprints.'
      ],
    },
  },
  research: {
    current: {
      title: 'Current research tree',
      description: 'The existing centered TreeCanvas panel with connectors, queue, progress, respec, and scan controls.',
      notes: [
        'The tree supports the systems, but nodes and connectors have low visual hierarchy.',
        'Locked, maxed, active, and available states need to be distinguishable faster.',
        'The selected technology has limited room to explain cost, timing, and exclusions.'
      ],
    },
    forge: {
      title: 'A · Forge Tree',
      description: 'A structured tree with branch tabs, tier columns, a selected-tech detail rail, and persistent queue controls.',
      notes: [
        'Does the tier-column layout clarify the mutually exclusive choices?',
        'Is the selected-tech detail rail worth the screen space?',
        'Should branch tabs be faction-colored or remain neutral?'
      ],
    },
    constellation: {
      title: 'B · Doctrine Map',
      description: 'A more cinematic specialization map that frames research as choosing a doctrine path through the mine.',
      notes: [
        'Best for making research feel like a major strategic identity choice.',
        'The freeform map is distinctive, but harder to scale than columns or cards.',
        'Faction colors can communicate branch ownership before the player reads labels.'
      ],
    },
    deck: {
      title: 'C · Research Deck',
      description: 'A card-based technology browser with clear state badges, compact descriptions, progress, and queueing.',
      notes: [
        'Best if the research list may grow or needs easier scanning.',
        'Cards make cost and state clearer, but weaken the visual tree relationship.',
        'This option would be the easiest to maintain as technologies change.'
      ],
    },
    hybrid: {
      title: 'B+C · Doctrine Deck',
      description: 'A hybrid of the cinematic doctrine map and the card-based research deck: visible branch paths, compact technology cards, selected-node details, and persistent queue controls.',
      notes: [
        'The map preserves branch relationships and exclusive choices from option B.',
        'Each node carries option C’s state badge, icon, and compact description.',
        'The detail rail and queue controls keep cost, timing, and exclusions readable.'
      ],
    },
  },
};

function setVariant(name) {
  if (!scope || !VARIANT_CONTENT[scope]?.[name]) return;
  const content = VARIANT_CONTENT[scope][name];
  document.body.dataset[scope] = name;
  variantTitle.textContent = content.title;
  variantDescription.textContent = content.description;
  if (sceneLabel) sceneLabel.textContent = content.title;
  variantNotes.innerHTML = content.notes.map((note) => `<li>${note}</li>`).join('');
  variantButtons.forEach((button) => button.classList.toggle('active', button.dataset.variant === name));
}

variantButtons.forEach((button) => {
  button.addEventListener('click', () => setVariant(button.dataset.variant));
});
