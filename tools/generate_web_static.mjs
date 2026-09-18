import fs from 'node:fs';

const source = fs.readFileSync('lib/src/features/auth/legal_texts.dart', 'utf8');
const match = source.match(/const String attaPrivacyText = r'''([\s\S]*?)''';/);

if (!match) {
  throw new Error('attaPrivacyText not found');
}

const escapeHtml = (value) =>
  value.replace(/[&<>"]/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
  })[char]);

const privacyText = match[1].trim();
const privacyBody = privacyText
  .split(/\n{2,}/)
  .map((paragraph) => `<p>${escapeHtml(paragraph).replace(/\n/g, '<br>')}</p>`)
  .join('\n');

const privacyHtml = `<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Политика конфиденциальности ATTA</title>
  <meta name="description" content="Политика конфиденциальности ATTA — Атта Маркет.">
  <link rel="canonical" href="https://attamarket.online/privacy">
  <link rel="icon" type="image/png" href="/favicon.png">
  <style>
    body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;line-height:1.58;color:#1f2933;background:#fff}
    main{max-width:860px;margin:0 auto;padding:32px 20px 56px}
    h1{font-size:30px;line-height:1.2;margin:0 0 24px}
    p{margin:0 0 16px}
    @media(max-width:600px){main{padding:24px 16px 44px}h1{font-size:25px}}
  </style>
</head>
<body>
<main>
<h1>Политика конфиденциальности ATTA</h1>
${privacyBody}
</main>
</body>
</html>
`;

fs.mkdirSync('build/web/privacy', { recursive: true });
fs.writeFileSync('build/web/privacy/index.html', privacyHtml);

fs.writeFileSync(
  'build/web/robots.txt',
  `User-agent: *
Allow: /
Allow: /privacy
Allow: /listing/
Disallow: /auth
Disallow: /admin
Disallow: /chats
Disallow: /messages
Disallow: /wallet
Disallow: /payments
Disallow: /support
Disallow: /reports
Sitemap: https://attamarket.online/sitemap.xml
`,
);

fs.writeFileSync(
  'build/web/sitemap.xml',
  `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://attamarket.online/</loc></url>
  <url><loc>https://attamarket.online/privacy</loc></url>
</urlset>
`,
);

console.log('Generated build/web/privacy/index.html, robots.txt, sitemap.xml');
