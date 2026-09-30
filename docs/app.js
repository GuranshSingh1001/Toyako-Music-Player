(function(){
  const root = document.documentElement;
  const toggle = document.getElementById('themeToggle');
  const label = document.getElementById('themeLabel');
  const icon = toggle;
  const meta = document.getElementById('themeColor');
  const heroImage = document.querySelector('.hero-image img');

  function applyTheme(theme) {
    const dark = theme === 'dark';
    root.classList.toggle('dark', dark);
    root.classList.toggle('light', !dark);
    if (label) label.textContent = dark ? 'Light' : 'Dark';
    if (icon) icon.setAttribute('data-theme', dark ? 'dark' : 'light');
    if (toggle) {
      toggle.setAttribute('aria-pressed', String(dark));
      toggle.setAttribute('aria-label', dark ? 'Switch to light mode' : 'Switch to dark mode');
    }
    if (meta) meta.setAttribute('content', dark ? '#0d1015' : '#ffffff');
    if (heroImage) {
      heroImage.src = dark ? 'assets/screenshots/dark/home.jpeg' : 'assets/screenshots/light/home.jpeg';
      heroImage.alt = dark ? 'Toyako Home screen in Dark Mode' : 'Toyako Home screen in Light Mode';
    }
  }

  // Light is the default. The selection persists in this browser.
  const saved = localStorage.getItem('toyako-theme');
  applyTheme(saved === 'dark' ? 'dark' : 'light');

  toggle?.addEventListener('click', () => {
    const next = root.classList.contains('dark') ? 'light' : 'dark';
    localStorage.setItem('toyako-theme', next);
    applyTheme(next);
  });
})();

(function(){
  // The site automatically derives OWNER/REPO from a normal GitHub Pages URL:
  // https://owner.github.io/repo/ -> owner/repo
  // For a custom domain, set window.TOYAKO_REPO before this script loads.
  const configured = window.TOYAKO_REPO || '';
  const host = location.hostname;
  const path = location.pathname.split('/').filter(Boolean);
  let repo = configured;
  if (!repo && host.endsWith('.github.io')) {
    const owner = host.split('.')[0];
    const project = path[0];
    if (owner && project) repo = owner + '/' + project;
  }
  // Replace this fallback with "your-name/your-repo" if using a custom domain.
  const fallback = 'Toyako-Music-Player/Toyako-Music-Player';
  repo = repo || fallback;

  const urls = {
    repo: `https://github.com/${repo}`,
    releases: `https://github.com/${repo}/releases`,
    api: `https://api.github.com/repos/${repo}/releases/latest`
  };

  ['githubLink','heroGithub','footerGithub'].forEach(id => { const el=document.getElementById(id); if(el) el.href=urls.repo; });

  const set = (id, href, text) => { const el=document.getElementById(id); if(!el)return; el.href=href; if(text)el.textContent=text; };
  set('releasePage', urls.releases);

  function showFallback(message){
    set('heroDownload', urls.releases, 'View latest release ↗');
    set('navDownload', urls.releases, 'Download');
    set('downloadButton', urls.releases, 'View latest release ↗');
    const status=document.getElementById('releaseStatus'); if(status) status.textContent=message;
    const status2=document.getElementById('downloadStatus'); if(status2) status2.textContent='No direct IPA asset was found yet. Open GitHub Releases to download the latest build.';
  }

  fetch(urls.api, {headers:{Accept:'application/vnd.github+json'}})
    .then(r=>{ if(!r.ok) throw new Error('GitHub release unavailable'); return r.json(); })
    .then(release=>{
      const ipa = (release.assets||[]).find(a=>a.name.toLowerCase().endsWith('.ipa'));
      if(!ipa) return showFallback('Latest GitHub release found, but it does not contain an IPA asset yet.');
      const label = release.tag_name ? `Download ${release.tag_name}` : 'Download latest IPA';
      set('heroDownload', ipa.browser_download_url, '↓ Download IPA');
      set('downloadButton', ipa.browser_download_url, '↓ Download latest IPA');
      set('releasePage', release.html_url, 'View release details on GitHub ↗');
      set('navDownload', ipa.browser_download_url, 'Download');
      const status=document.getElementById('releaseStatus'); if(status) status.textContent=`${label} · ${Math.round(ipa.size/1024/1024*10)/10} MB`;
      const status2=document.getElementById('downloadStatus'); if(status2) status2.textContent=`${release.name || release.tag_name || 'Latest release'} · ${ipa.name}`;
    })
    .catch(()=>showFallback('GitHub Releases could not be reached right now.'));
})();
