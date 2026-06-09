# MultiViewer website

Marketing landing page for [MultiViewer by Brekke](https://multiviewer.brek.ke), built with Next.js and deployed on Vercel.

## Development

```bash
cd website
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Environment variables

Copy `.env.example` to `.env.local`:

| Variable | Purpose |
|----------|---------|
| `NEXT_PUBLIC_DOWNLOAD_URL` | Full URL to the DMG. Leave empty for "Download coming soon". |
| `NEXT_PUBLIC_APP_VERSION` | Version label on the download button (default `1.0`). |

## Deploy on Vercel

1. Import this repository in Vercel.
2. Set **Root Directory** to `website`.
3. Add environment variables in the Vercel dashboard.
4. Add custom domain **multiviewer.brek.ke**.

### DNS (brek.ke)

Create a CNAME record:

```
multiviewer  →  cname.vercel-dns.com
```

Use the exact target shown in the Vercel domain settings.

## Structure

- `app/` — Next.js App Router pages and global styles
- `components/` — Landing page sections
- `public/` — App icon and OG image assets
- `lib/site.ts` — Site metadata and env-backed config
