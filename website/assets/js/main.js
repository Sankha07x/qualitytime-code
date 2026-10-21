/**
 * QualityTime - Main Client Script
 * Handles real-time update.json fetch, dynamic release hydration,
 * interactive quality calculator, FAQ accordions, and mobile navigation.
 */

// Official GitHub Raw Manifest endpoint
const UPDATE_MANIFEST_URL = 'https://raw.githubusercontent.com/Sankha07x/qualitytime-releases/main/update.json';
const FALLBACK_MANIFEST_URL = './update.json';

// Default release state in case of offline or first render
const defaultReleaseState = {
  version_code: 25,
  version_name: "0.8.4",
  min_version_code: 8,
  apk_url: "https://github.com/Sankha07x/qualitytime-releases/releases/download/v0.8.4/app-arm64-v8a-release.apk",
  size_mb: 51,
  notes: [
    "Bug fixes & connection stability",
    "Extreme Quality 1080p 60 fps mode",
    "Animations OnScreen & interactive reactions",
    "New customizable themes & glass aesthetic"
  ]
};

// Fetch and hydrate latest release information across all pages
async function fetchLatestRelease() {
  let releaseData = defaultReleaseState;
  
  try {
    const cacheBuster = `?t=${Date.now()}`;
    const response = await fetch(UPDATE_MANIFEST_URL + cacheBuster, {
      cache: 'no-cache',
      headers: { 'Accept': 'application/json' }
    });

    if (response.ok) {
      const json = await response.json();
      if (json && json.version_name && json.apk_url) {
        releaseData = json;
      }
    } else {
      // Fallback to local copy
      const localRes = await fetch(FALLBACK_MANIFEST_URL);
      if (localRes.ok) {
        const localJson = await localRes.json();
        if (localJson && localJson.apk_url) releaseData = localJson;
      }
    }
  } catch (err) {
    console.warn('Network fetch from GitHub raw failed, using fallback manifest:', err);
    try {
      const localRes = await fetch(FALLBACK_MANIFEST_URL);
      if (localRes.ok) {
        const localJson = await localRes.json();
        if (localJson && localJson.apk_url) releaseData = localJson;
      }
    } catch (_) {}
  }

  hydrateReleaseUI(releaseData);
}

function hydrateReleaseUI(data) {
  // Version Names (e.g. "v0.8.4")
  const versionFormatted = data.version_name.startsWith('v') ? data.version_name : `v${data.version_name}`;
  document.querySelectorAll('.dyn-version').forEach(el => {
    el.textContent = versionFormatted;
  });

  // Version Code
  document.querySelectorAll('.dyn-code').forEach(el => {
    el.textContent = data.version_code || '25';
  });

  // Size MB
  document.querySelectorAll('.dyn-size').forEach(el => {
    el.textContent = `${data.size_mb || 51} MB`;
  });

  // APK Download Links
  document.querySelectorAll('.dyn-apk-link').forEach(el => {
    el.setAttribute('href', data.apk_url);
  });

  // File Name
  const fileName = data.apk_url.substring(data.apk_url.lastIndexOf('/') + 1) || 'app-arm64-v8a-release.apk';
  document.querySelectorAll('.dyn-filename').forEach(el => {
    el.textContent = fileName;
  });

  // Release Notes
  const notesContainers = document.querySelectorAll('.dyn-notes-list');
  if (notesContainers.length > 0 && Array.isArray(data.notes)) {
    notesContainers.forEach(container => {
      container.innerHTML = '';
      data.notes.forEach(note => {
        const li = document.createElement('li');
        li.textContent = note;
        container.appendChild(li);
      });
    });
  }

  // Live timestamp indicator
  document.querySelectorAll('.dyn-fetch-status').forEach(el => {
    el.textContent = 'Synced with GitHub Releases';
  });
}

// Interactive Quality & Data Calculator
const qualityProfiles = {
  low: {
    name: 'Low (Data Saver)',
    fps: 15,
    resolution: '360p / 240p scaled',
    videoBitrate: 150, // kbps
    audioBitrate: 16,  // kbps
    desc: 'Optimized for 2G/3G connections and low battery consumption.'
  },
  medium: {
    name: 'Medium (Balanced)',
    fps: 24,
    resolution: '480p standard',
    videoBitrate: 500, // kbps
    audioBitrate: 32,  // kbps
    desc: 'Smooth daily calls with minimal data usage.'
  },
  high: {
    name: 'High (HD 720p)',
    fps: 30,
    resolution: '720p crystal clear',
    videoBitrate: 1200, // kbps
    audioBitrate: 64,   // kbps
    desc: 'Crisp HD video and clear stereo voice for high-speed Wi-Fi/4G.'
  },
  extreme: {
    name: 'Extreme (1080p 60 FPS)',
    fps: 60,
    resolution: '1080p cinema 60fps',
    videoBitrate: 8000, // kbps
    audioBitrate: 128,  // kbps Opus
    desc: 'Ultra high-fidelity lossless P2P stream for flagship devices.'
  }
};

let currentProfile = 'extreme';
let callDurationMinutes = 30;

function setupCalculator() {
  const calcContainer = document.getElementById('quality-calculator');
  if (!calcContainer) return;

  const buttons = calcContainer.querySelectorAll('.quality-btn');
  const durationSlider = document.getElementById('calc-duration-slider');
  const durationLabel = document.getElementById('calc-duration-label');

  buttons.forEach(btn => {
    btn.addEventListener('click', () => {
      buttons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentProfile = btn.getAttribute('data-profile');
      updateCalculatorOutput();
    });
  });

  if (durationSlider && durationLabel) {
    durationSlider.addEventListener('input', (e) => {
      callDurationMinutes = parseInt(e.target.value, 10);
      durationLabel.textContent = `${callDurationMinutes} min`;
      updateCalculatorOutput();
    });
  }

  updateCalculatorOutput();
}

function updateCalculatorOutput() {
  const prof = qualityProfiles[currentProfile];
  if (!prof) return;

  const totalKbps = prof.videoBitrate + prof.audioBitrate;
  // bytes per second = (totalKbps * 1000) / 8
  // total megabytes = (bytesPerSec * (callDurationMinutes * 60)) / (1024 * 1024)
  const mbPerSec = (totalKbps * 1000) / (8 * 1024 * 1024);
  const totalMB = Math.round(mbPerSec * callDurationMinutes * 60);

  const mbPerHour = Math.round(mbPerSec * 3600);

  const resTotalMB = document.getElementById('calc-total-mb');
  const resFps = document.getElementById('calc-fps');
  const resBitrate = document.getElementById('calc-bitrate');
  const resPerHour = document.getElementById('calc-per-hour');
  const resAudio = document.getElementById('calc-audio');
  const resDesc = document.getElementById('calc-desc');

  if (resTotalMB) resTotalMB.textContent = totalMB > 1024 ? `${(totalMB / 1024).toFixed(1)} GB` : `${totalMB} MB`;
  if (resFps) resFps.textContent = `${prof.fps} FPS`;
  if (resBitrate) resBitrate.textContent = `${(prof.videoBitrate / 1000).toFixed(prof.videoBitrate < 1000 ? 2 : 1)} Mbps`;
  if (resPerHour) resPerHour.textContent = mbPerHour > 1024 ? `${(mbPerHour / 1024).toFixed(1)} GB/hr` : `${mbPerHour} MB/hr`;
  if (resAudio) resAudio.textContent = `${prof.audioBitrate} kbps Opus`;
  if (resDesc) resDesc.textContent = prof.desc;
}

// Accordion Component for FAQ
function setupAccordion() {
  const faqItems = document.querySelectorAll('.faq-item');
  faqItems.forEach(item => {
    const question = item.querySelector('.faq-question');
    if (!question) return;

    question.addEventListener('click', () => {
      const isOpen = item.classList.contains('open');
      // Close other items
      faqItems.forEach(i => {
        if (i !== item) i.classList.remove('open');
      });
      // Toggle current
      if (isOpen) {
        item.classList.remove('open');
      } else {
        item.classList.add('open');
      }
    });
  });
}

// Mobile Menu Toggle with Full Touch & Accessibility Support
function setupMobileMenu() {
  const toggleBtn = document.querySelector('.menu-toggle');
  const navLinks = document.querySelector('.nav-links');

  if (toggleBtn && navLinks) {
    const closeMenu = () => {
      navLinks.classList.remove('show');
      toggleBtn.setAttribute('aria-expanded', 'false');
      toggleBtn.innerHTML = '☰';
      document.body.classList.remove('nav-open');
    };

    const openMenu = () => {
      navLinks.classList.add('show');
      toggleBtn.setAttribute('aria-expanded', 'true');
      toggleBtn.innerHTML = '✕';
      document.body.classList.add('nav-open');
    };

    toggleBtn.setAttribute('aria-expanded', 'false');

    toggleBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      const isOpen = navLinks.classList.contains('show');
      if (isOpen) {
        closeMenu();
      } else {
        openMenu();
      }
    });

    // Close when tapping on any link in the mobile drawer
    navLinks.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', () => {
        closeMenu();
      });
    });

    // Close when clicking outside
    document.addEventListener('click', (e) => {
      if (!toggleBtn.contains(e.target) && !navLinks.contains(e.target)) {
        closeMenu();
      }
    });

    // Close on Escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && navLinks.classList.contains('show')) {
        closeMenu();
      }
    });

    // Close when window resized to desktop size
    window.addEventListener('resize', () => {
      if (window.innerWidth > 768 && navLinks.classList.contains('show')) {
        closeMenu();
      }
    });
  }
}

// Copy to Clipboard Utility
function setupCopyButtons() {
  document.querySelectorAll('[data-copy]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const textToCopy = btn.getAttribute('data-copy');
      try {
        await navigator.clipboard.writeText(textToCopy);
        const originalText = btn.innerHTML;
        btn.textContent = 'Copied!';
        setTimeout(() => {
          btn.innerHTML = originalText;
        }, 2000);
      } catch (e) {
        console.error('Clipboard copy failed:', e);
      }
    });
  });
}

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => {
  fetchLatestRelease();
  setupCalculator();
  setupAccordion();
  setupMobileMenu();
  setupCopyButtons();
});
