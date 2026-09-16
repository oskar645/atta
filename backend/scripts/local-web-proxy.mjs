#!/usr/bin/env node
import http from 'node:http';
import https from 'node:https';
import { URL } from 'node:url';
import express from 'express';

const listenHost = process.env.ATTA_LOCAL_WEB_HOST ?? '127.0.0.1';
const listenPort = Number(process.env.ATTA_LOCAL_WEB_PORT ?? '8117');
const flutterHost = process.env.ATTA_FLUTTER_WEB_HOST ?? '127.0.0.1';
const flutterPort = Number(process.env.ATTA_FLUTTER_WEB_PORT ?? '8118');
const backendOrigin =
  process.env.ATTA_PRODUCTION_BACKEND_ORIGIN ?? 'https://attamarket.online';
const backendUrl = new URL(backendOrigin);
const backendProtocol = backendUrl.protocol === 'https:' ? https : http;

const hopByHopHeaders = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
]);

const backendPrefixes = [
  '/api',
  '/auth',
  '/listings',
  '/categories',
  '/favorites',
  '/users',
  '/profile',
  '/media',
  '/uploads',
  '/chats',
  '/notifications',
  '/support',
  '/reports',
  '/reviews',
  '/wallet',
  '/showcase',
  '/promotions',
  '/feed-ads',
  '/saved-searches',
  '/viewed-listings',
  '/socket.io',
];

function shouldProxy(pathname) {
  return backendPrefixes.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`),
  );
}

function sanitizeHeaders(headers, host) {
  const result = { ...headers, host };
  for (const header of hopByHopHeaders) {
    delete result[header];
  }
  return result;
}

function sanitizeResponseHeaders(headers) {
  const result = { ...headers };
  for (const header of hopByHopHeaders) {
    delete result[header];
  }
  return result;
}

function proxyHttp(req, res, target) {
  const options = {
    protocol: backendUrl.protocol,
    hostname: backendUrl.hostname,
    port: backendUrl.port || undefined,
    method: req.method,
    path: `${target.pathname}${target.search}`,
    headers: sanitizeHeaders(req.headers, backendUrl.host),
  };

  const upstream = backendProtocol.request(options, (upstreamRes) => {
    res.writeHead(
      upstreamRes.statusCode ?? 502,
      sanitizeResponseHeaders(upstreamRes.headers),
    );
    upstreamRes.pipe(res);
  });

  upstream.on('error', (error) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'content-type': 'application/json' });
    }
    res.end(JSON.stringify({ error: 'local_proxy_error', message: error.message }));
  });

  req.pipe(upstream);
}

function proxyFlutter(req, res) {
  const upstream = http.request(
    {
      hostname: flutterHost,
      port: flutterPort,
      method: req.method,
      path: req.url,
      headers: sanitizeHeaders(req.headers, `${flutterHost}:${flutterPort}`),
    },
    (upstreamRes) => {
      res.writeHead(upstreamRes.statusCode ?? 502, upstreamRes.headers);
      upstreamRes.pipe(res);
    },
  );
  upstream.on('error', (error) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
    }
    res.end(`Flutter Web dev server is not reachable: ${error.message}`);
  });
  req.pipe(upstream);
}

const app = express();

app.use((req, res) => {
  const target = new URL(req.url ?? '/', backendUrl);
  if (shouldProxy(target.pathname)) {
    proxyHttp(req, res, target);
    return;
  }
  proxyFlutter(req, res);
});

const server = http.createServer(app);

server.on('upgrade', (req, socket, head) => {
  const target = new URL(req.url ?? '/', backendUrl);
  if (!shouldProxy(target.pathname)) {
    socket.destroy();
    return;
  }

  const upstream = backendProtocol.request({
    protocol: backendUrl.protocol,
    hostname: backendUrl.hostname,
    port: backendUrl.port || undefined,
    method: req.method,
    path: `${target.pathname}${target.search}`,
    headers: {
      ...req.headers,
      host: backendUrl.host,
    },
  });

  upstream.on('upgrade', (upstreamRes, upstreamSocket, upstreamHead) => {
    socket.write(
      [
        `HTTP/${upstreamRes.httpVersion} ${upstreamRes.statusCode} ${upstreamRes.statusMessage}`,
        ...Object.entries(upstreamRes.headers).map(
          ([key, value]) => `${key}: ${Array.isArray(value) ? value.join(', ') : value}`,
        ),
        '',
        '',
      ].join('\r\n'),
    );
    if (upstreamHead.length > 0) {
      socket.write(upstreamHead);
    }
    if (head.length > 0) {
      upstreamSocket.write(head);
    }
    upstreamSocket.pipe(socket).pipe(upstreamSocket);
  });

  upstream.on('error', () => socket.destroy());
  upstream.end();
});

server.listen(listenPort, listenHost, () => {
  console.log(
    `ATTA local web proxy: http://${listenHost}:${listenPort} -> Flutter ${flutterHost}:${flutterPort}, backend ${backendOrigin}`,
  );
});
