// The UI harness owns the server process; all HTTP traffic stays on authenticated loopback.
enum FakeOpenCode {
    static let urlFileName = "fake-opencode-url.txt"
    static let credentialFileName = "fake-opencode-auth.txt"
    static let binaryName = "opencode"
    static let scriptFileName = "opencode.js"
    static let nodeEnvironmentKey = "PIBOARD_FAKE_OPENCODE_NODE"
    static let pidFileName = "server-pid.txt"
    static let tuiPidFileName = "tui-pids.txt"
    static let deterministicFileName = "deterministic"
    static let serveArgument = "__serve__"
    static let version = "opencode v0.0.0"
    // Shell parameter expansion needs no utilities on PATH.
    static let wrapper = "#!/bin/sh\nexec \"$\(nodeEnvironmentKey)\" \"${0%/*}/\(scriptFileName)\" \"$@\"\n"

    static let script = #"""
    'use strict';
    const fs = require('fs');
    const path = require('path');
    const http = require('http');
    const crypto = require('crypto');
    const { spawn } = require('child_process');
    const ROOT = path.dirname(__filename);
    const URL_FILE = path.join(ROOT, '\#(urlFileName)');
    const AUTH_FILE = path.join(ROOT, '\#(credentialFileName)');
    const SERVE_MODE = '\#(serveArgument)', AUTH_USER = 'opencode';
    const HEARTBEAT_MS = 1000, POLL_MS = 50, LINE_MS = 50, AUTO_MS = 6000, IDLE_EXIT_MS = 600000;
    const LINES_PER_TURN = 40;
    const DETERMINISTIC = fs.existsSync(path.join(ROOT, '\#(deterministicFileName)'));
    const EVENT = {
      started: 'session.execution.started', succeeded: 'session.execution.succeeded',
      interrupted: 'session.execution.interrupted', asked: 'permission.asked', replied: 'permission.replied',
    };
    const COMMAND = { permission: 'permission', finish: 'finish', quit: 'quit' };
    const args = process.argv.slice(2);
    const authorization = () => 'Basic ' + Buffer.from(AUTH_USER + ':' + fs.readFileSync(AUTH_FILE, 'utf8')).toString('base64');

    function publishConfig() {
      const directory = process.env.PIBOARD_FAKE_OPENCODE_CONFIG;
      if (!directory) throw new Error('Missing isolated fake config directory');
      fs.mkdirSync(directory, { recursive: true });
      fs.writeFileSync(path.join(directory, 'service.json'), JSON.stringify({ password: fs.readFileSync(AUTH_FILE, 'utf8') }), { mode: 0o600 });
    }

    function serve() {
      const password = crypto.randomBytes(32).toString('hex');
      fs.writeFileSync(AUTH_FILE, password, { mode: 0o600 });
      const expected = authorization();
      const sessions = new Map(), active = new Set(), streams = new Map(), commands = new Map();
      const pendingSubscriptions = [];
      let blocked = false, subscriptions = 0, resyncs = 0, shuttingDown = false;
      const reply = (res, status, body = {}) => {
        res.writeHead(status, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(body));
      };
      const emit = (type, sessionID) => {
        for (const [res, types] of streams) {
          if (!types.size || types.has(type)) res.write('data: ' + JSON.stringify({ type, data: { sessionID } }) + '\n\n');
        }
      };
      const resync = (res) => {
        resyncs++;
        reply(res, 200, { data: Object.fromEntries([...active].map(id => [id, { type: 'running' }])) });
      };
      const subscribe = (req, res, url) => {
        if (res.destroyed) return;
        subscriptions++;
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
        streams.set(res, new Set(url.searchParams.getAll('types')));
        res.write('data: {"type":"server.connected","data":{}}\n\n');
        const heartbeat = setInterval(() => res.write(': heartbeat\n\n'), HEARTBEAT_MS);
        res.on('close', () => { clearInterval(heartbeat); streams.delete(res); });
      };
      // Backstop so a leaked server cannot outlive the test run.
      let idleTimer;
      const touch = () => {
        clearTimeout(idleTimer);
        idleTimer = setTimeout(() => { fs.rmSync(URL_FILE, { force: true }); process.exit(0); }, IDLE_EXIT_MS);
      };
      touch();
      const server = http.createServer((req, res) => {
        touch();
        if (req.headers.authorization !== expected) return reply(res, 401);
        const url = new URL(req.url, 'http://127.0.0.1');
        const route = url.pathname;
        if (req.method === 'GET' && route === '/api/event') {
          if (blocked) pendingSubscriptions.push(() => subscribe(req, res, url));
          else subscribe(req, res, url);
          return;
        }
        if (req.method === 'GET' && route === '/api/session/active') {
          return resync(res);
        }
        if (req.method === 'GET' && route === '/test/state') {
          return reply(res, 200, { active: [...active], sessions: [...sessions.keys()], subscriptions, resyncs, streams: streams.size, blocked, pid: process.pid, node: process.execPath, searchPath: process.env.PATH });
        }
        const chunks = [];
        req.on('data', chunk => chunks.push(chunk));
        req.on('end', () => {
          let body = {};
          try { if (chunks.length) body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
          catch { return reply(res, 400); }
          if (req.method === 'POST' && route === '/test/shutdown') {
            shuttingDown = true;
            res.on('finish', () => setImmediate(() => {
              fs.rmSync(URL_FILE, { force: true });
              server.close();
              process.exit(0);
            }));
            return reply(res, 200);
          }
          if (req.method === 'POST' && route === '/test/disconnect') {
            blocked = true;
            for (const res of streams.keys()) res.end();
            streams.clear();
            return reply(res, 200);
          }
          if (req.method === 'POST' && route === '/test/reconnect') {
            blocked = false;
            for (const subscribe of pendingSubscriptions.splice(0)) subscribe();
            return reply(res, 200);
          }
          if (req.method === 'POST' && route === '/test/control') {
            if (!sessions.has(body.sessionID) || !Object.values(COMMAND).includes(body.command)) return reply(res, 400);
            const queue = commands.get(body.sessionID) || [];
            queue.push(body.command);
            commands.set(body.sessionID, queue);
            return reply(res, 200);
          }
          if (req.method === 'POST' && route === '/test/turn') {
            if (!sessions.has(body.sessionID) || !Object.values(EVENT).includes(body.type)) return reply(res, 400);
            if (body.type === EVENT.succeeded || body.type === EVENT.interrupted) active.delete(body.sessionID);
            else active.add(body.sessionID);
            emit(body.type, body.sessionID);
            return reply(res, 200);
          }
          if (req.method === 'GET' && route.startsWith('/test/tui/')) {
            const id = route.split('/').pop();
            return reply(res, 200, { command: shuttingDown ? COMMAND.quit : (commands.get(id) || []).shift(), deterministic: DETERMINISTIC });
          }
          if (req.method === 'POST' && route === '/api/session') {
            const now = Date.now();
            const session = {
              id: body.id || 'ses_' + crypto.randomBytes(12).toString('hex'), title: body.title || '',
              location: body.location || { directory: '/' },
              tokens: { input: 0, output: 0, reasoning: 0, cache: { read: 0, write: 0 } },
              cost: 0, time: { created: now, updated: now },
            };
            sessions.set(session.id, session);
            return reply(res, 200, { data: session });
          }
          const parts = route.split('/').filter(Boolean);
          const session = sessions.get(parts[2]);
          if (req.method === 'GET' && parts[3] === 'message') return reply(res, 200, { data: [] });
          if (req.method === 'GET' && parts[1] === 'session') {
            return session ? reply(res, 200, { data: session }) : reply(res, 404, { _tag: 'SessionNotFoundError' });
          }
          if (req.method === 'DELETE' && parts[1] === 'session') {
            sessions.delete(parts[2]); active.delete(parts[2]); commands.delete(parts[2]);
            return reply(res, 204);
          }
          reply(res, 404);
        });
      });
      server.listen(0, '127.0.0.1', () => {
        fs.writeFileSync(path.join(ROOT, '\#(pidFileName)'), String(process.pid));
        fs.writeFileSync(URL_FILE, 'http://127.0.0.1:' + server.address().port);
      });
    }

    function request(method, route, body) {
      return new Promise((resolve, reject) => {
        const req = http.request(new URL(route, fs.readFileSync(URL_FILE, 'utf8')), {
          method, headers: { Authorization: authorization(), 'Content-Type': 'application/json' },
        }, res => {
          const chunks = [];
          res.on('data', chunk => chunks.push(chunk));
          res.on('end', () => {
            if (res.statusCode !== 200) return reject(new Error('Fake HTTP request failed'));
            resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
          });
        });
        req.on('error', reject);
        req.end(body ? JSON.stringify(body) : undefined);
      });
    }

    async function runTui() {
      // The harness kills these by pid: a TUI can outlive a force-killed app and ignore its hangup.
      fs.appendFileSync(path.join(ROOT, '\#(tuiPidFileName)'), process.pid + '\n');
      const ESC = '\x1b', PASTE_ON = ESC + '[?2004h', PASTE_OFF = ESC + '[?2004l';
      const MOUSE_OFF = ESC + '[?1000l' + ESC + '[?1002l' + ESC + '[?1003l' + ESC + '[?1006l';
      const COLORS = [31, 32, 33, 34, 35, 36];
      let sessionID, prompt = '';
      for (let i = 0; i < args.length; i++) {
        if (args[i] === '--session') sessionID = args[++i];
        else if (args[i] === '--prompt') prompt = args[++i];
      }
      const { deterministic } = await request('GET', '/test/tui/' + sessionID);
      const out = s => process.stdout.write(s);
      let turns = 0, busy = false, waiting = false, typed = '', lines = 0, changing = false;
      const event = type => request('POST', '/test/turn', { sessionID, type });
      async function finish() {
        if (!busy || waiting) return;
        busy = false;
        await event(EVENT.succeeded);
        out('\r\n> ');
      }
      async function turn() {
        if (busy) return;
        busy = true; lines = 0; turns++;
        await event(EVENT.started);
      }
      async function input(chunk) {
        for (const ch of chunk.toString('latin1')) {
          if (ch === '\x03' || ch === '\x04') return quit();
          if (ch === '\r' || ch === '\n') {
            out('\r\n');
            if (typed.trim() === 'exit') return quit();
            typed = '';
            if (waiting) { waiting = false; lines = 0; await event(EVENT.replied); }
            else await turn();
          } else if (ch === '\x7f') {
            if (typed.length) { typed = typed.slice(0, -1); out('\b \b'); }
          } else { typed += ch; out(ch); }
        }
      }
      async function quit() {
        await event(EVENT.interrupted).catch(() => {});
        out(PASTE_OFF);
        process.exit(0);
      }
      out('fake opencode session ' + sessionID + '\r\n' + prompt + '\r\n' + PASTE_ON + MOUSE_OFF);
      if (process.stdin.isTTY) process.stdin.setRawMode(true);
      // Serialize input so a permission reply cannot race a completion control.
      let inputQueue = Promise.resolve();
      process.stdin.on('data', chunk => { inputQueue = inputQueue.then(() => input(chunk)); });
      process.stdin.on('end', quit);
      process.on('SIGTERM', quit);
      process.on('SIGHUP', quit);
      setInterval(() => {
        if (!busy || waiting) return;
        lines++;
        out(ESC + '[' + COLORS[lines % COLORS.length] + 'mturn ' + turns + ' line ' + lines + ESC + '[0m\r\n');
        if (!deterministic && lines >= LINES_PER_TURN) finish();
      }, LINE_MS);
      setInterval(async () => {
        if (changing) return;
        changing = true;
        try {
          const { command } = await request('GET', '/test/tui/' + sessionID);
          if (command === COMMAND.permission && busy && !waiting) {
            waiting = true;
            await event(EVENT.asked);
            out('\r\nAllow fake operation? Type a reply: ');
          } else if (command === COMMAND.finish) await finish();
          else if (command === COMMAND.quit) await quit();
        } finally { changing = false; }
      }, POLL_MS);
      if (!deterministic) setInterval(turn, AUTO_MS);
      await turn();
    }

    if (args[0] === '--version') console.log('\#(version)');
    else if (args[0] === 'service' && args[1] === 'status') {
      if (fs.existsSync(URL_FILE)) {
        publishConfig();
        console.log(fs.readFileSync(URL_FILE, 'utf8').trim());
      }
    } else if (args[0] === 'service' && args[1] === 'start') {
      // Xcode sandboxes its UI runner; the app's fake CLI owns startup instead.
      spawn(process.execPath, [__filename, SERVE_MODE], { detached: true, stdio: 'ignore' }).unref();
      const deadline = Date.now() + 3000;
      const wait = () => {
        if (fs.existsSync(URL_FILE)) { publishConfig(); process.exit(0); }
        else if (Date.now() > deadline) process.exit(1);
        else setTimeout(wait, POLL_MS);
      };
      wait();
    } else if (args[0] === SERVE_MODE) serve();
    else runTui().catch(() => process.exit(1));
    """#
}
