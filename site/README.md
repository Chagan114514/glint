# Glint website

Static, dependency-free site for Glint. It reads releases from the public GitHub API:

```text
https://api.github.com/repos/Chagan114514/glint/releases?per_page=30
```

If the API is unavailable, the download page falls back to the last known versions. Results are cached in `sessionStorage` for five minutes.

## Local preview

```bash
python3 -m http.server 8765 --directory site
open http://127.0.0.1:8765/
```

## Language

The site supports Chinese and English. Use the `中 / EN` buttons, or force a language:

```text
/?lang=zh
/?lang=en
```

For screenshots and debugging, add `?nodialog=1` to skip the download-speed dialog, and `?static=1` to reveal lazy sections.

## Deploy

GitHub Actions workflow: `.github/workflows/pages.yml`.

The workflow deploys the `site/` directory to GitHub Pages. Repository Pages source is **GitHub Actions**; every push touching `site/**` triggers a fresh deployment.

Expected URL: `https://chagan114514.github.io/glint/`.

## Files

- `index.html` — landing page
- `download.html` — latest and previous releases, speed dialog
- `assets/app.js` — i18n, GitHub release loading, modal, animations
- `assets/style.css` — the whole design system
- `assets/*.webp` — compressed UI screenshots
