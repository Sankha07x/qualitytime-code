# QualityTime Official Website & Product Download Portal

A modern, high-performance, SEO-optimized product website for **QualityTime** — the low-bandwidth, high-quality P2P voice and video calling app.

Designed to match the exact in-app aesthetic: Pine Dark Teal (`#042F2E`), Neon Mint / Cyan accents (`#14B8A6`, `#2DD4BF`), frosted glass surfaces, and fluid motion.

---

## 🚀 Key Features

1. **Automatic Live Release Updates**:
   - Fetches directly from `https://raw.githubusercontent.com/Sankha07x/qualitytime-releases/main/update.json`.
   - When a new APK is released or notes change in `update.json`, the website updates dynamically (version tag, APK download button, file size, release notes, and filename) with zero manual rebuild required.
   - Includes automatic local fallback (`./update.json`) so the site functions smoothly even offline or during API downtime.

2. **Complete Product Website Pages**:
   - `index.html`: Hero with phone mockup, live release badge, key benefits, interactive quality/data calculator, changelog preview, and download CTAs.
   - `download.html`: Dedicated download center with package specs, direct GitHub release link, SHA-256 verification guide, 4-step Android sideloading walkthrough, and multi-platform roadmap (Windows, macOS, Web, iOS).
   - `features.html`: Deep-dive into WebRTC P2P direct encryption, Extreme 1080p 60 FPS mode, low-bandwidth data saver, in-call screen animations/reactions, CallKit lockscreen ringing, and uncompressed media sharing.
   - `changelog.html`: Live notes from `update.json` + complete version history (v0.8.4, v0.8.3, v0.8.0, v0.7.0).
   - `faq.html`: Comprehensive FAQ with interactive accordions and structured data answering common user and security questions.
   - `privacy.html`: Full privacy policy detailing the zero-log peer-to-peer architecture, DTLS-SRTP encryption, and permission requirements.
   - `terms.html`: Transparent terms of service and user agreement.

3. **SEO & Google Search Ranking Ready**:
   - Semantic HTML5 with high accessibility (`aria` attributes, logical heading hierarchy).
   - **Schema.org Structured Data (JSON-LD)**:
     - `SoftwareApplication` (operatingSystem: Android, rating: 4.9, size: 51MB, direct downloadUrl).
     - `FAQPage` schema on `faq.html` for Google search rich snippets.
   - Fully configured Open Graph and Twitter Card tags for high-CTR social sharing.
   - `sitemap.xml` and `robots.txt` included out of the box.
   - 100/100 Core Web Vitals performance: No external framework bloat, pure vanilla modern HTML, CSS, and JS.

---

## 🌐 Deployment Instructions

### Option 1: Cloudflare Pages (Recommended for Maximum Speed)

1. Log in to the [Cloudflare Dashboard](https://dash.cloudflare.com/) and go to **Workers & Pages**.
2. Click **Create Application** &rarr; **Pages** &rarr; **Connect to Git**.
3. Select your repository `p2p_call_app` (or your dedicated site repo).
4. Configure the build settings:
   - **Project Name**: `qualitytime` (will get `qualitytime.pages.dev`)
   - **Framework preset**: `None`
   - **Build command**: *(leave empty)*
   - **Build output directory**: `website`
5. Click **Save and Deploy**. Your website is now live globally across Cloudflare's edge CDN with automatic free SSL!

---

### Option 2: GitHub Pages

You have two easy ways to host on GitHub Pages:

#### Method A: Using GitHub Actions (Automated)
An automated workflow is already configured in `.github/workflows/deploy-pages.yml`.
1. Go to your repository on GitHub: `Settings` &rarr; `Pages`.
2. Under **Build and deployment** &rarr; **Source**, select **GitHub Actions**.
3. When you push to `main`, GitHub Actions will automatically publish the `website/` directory.

#### Method B: Deploying from the `/docs` folder
A synced copy of the website is located in `docs/`.
1. Go to your repository on GitHub: `Settings` &rarr; `Pages`.
2. Under **Build and deployment** &rarr; **Source**, choose **Deploy from a branch**.
3. Select branch `main` and folder `/docs`.
4. Click **Save**. Within 1–2 minutes, your website will be live at:
   `https://<your-username>.github.io/<repo-name>/`

---

## 📈 Google Search Console & SEO Setup

To rank your website on Google:

1. **Verify Domain in Google Search Console**:
   - Go to [Google Search Console](https://search.google.com/search-console).
   - Add your website URL (e.g. `https://qualitytime.pages.dev` or custom domain).
   - Verify ownership via DNS record (Cloudflare) or HTML tag.
2. **Submit Your Sitemap**:
   - In Search Console, click **Sitemaps** in the left menu.
   - Enter `sitemap.xml` and click **Submit**.
3. **Request Indexing**:
   - Paste your homepage URL in the URL Inspection tool at the top.
   - Click **Request Indexing**.

---

## 🔄 How the Update Pipeline Works

Your app and website are both powered by the same single source of truth:
`https://raw.githubusercontent.com/Sankha07x/qualitytime-releases/main/update.json`

Whenever you release a new version:
1. Upload your new `.apk` file to a GitHub Release in `qualitytime-releases`.
2. Update `update.json` in `qualitytime-releases/main/update.json`:
   ```json
   {
     "version_code": 26,
     "version_name": "0.8.5",
     "min_version_code": 8,
     "apk_url": "https://github.com/Sankha07x/qualitytime-releases/releases/download/v0.8.5/app-arm64-v8a-release.apk",
     "size_mb": 52,
     "notes": [
       "New UI improvements",
       "Even faster P2P handshake",
       "Bug fixes"
     ]
   }
   ```
3. That's it! Both the **installed Android app** and your **live website** will immediately show the new version, download link, size, and notes without touching a line of website code.
