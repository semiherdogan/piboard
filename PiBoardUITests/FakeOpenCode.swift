// Stands in for OpenCode in UI tests: answers the CLI probes, serves a tiny HTTP API and runs a fake TUI in a real pty. Never contacts a model.
enum FakeOpenCode {
    /// Sidecar the script writes next to itself; a stale one from an earlier run must be removed before launch.
    static let urlFileName = "fake-opencode-url.txt"
    static let binaryName = "opencode"
    static let scriptFileName = "opencode.js"
    /// Env keys the app sets; they must match `fakeOpenCodeNodeKey` and `fakeOpenCodeConfigKey` in AppEnvironment.swift. The script reads the config key itself.
    /// The wrapper lets the fake run without a `node` on PATH.
    static let wrapper = "#!/bin/sh\nexec \"$PIBOARD_FAKE_OPENCODE_NODE\" \"$(dirname \"$0\")/opencode.js\" \"$@\"\n"

    static let script = #"""
    #!/usr/bin/env node
    'use strict';
    const fs = require('fs');
    const path = require('path');
    const http = require('http');
    const crypto = require('crypto');
    const { spawn } = require('child_process');

    const URL_FILE = path.join(path.dirname(__filename), 'fake-opencode-url.txt');
    const PASSWORD = 'fake', AUTH_USER = 'opencode';
    const SERVE_MODE = '__serve__';
    const START_POLL_MS = 50, START_TIMEOUT_MS = 3000;
    const HEARTBEAT_MS = 1000, EXECUTION_MS = 2000;
    const NOT_FOUND = '{"_tag":"SessionNotFoundError"}';
    const IDLE_EXIT_MS = 600000;

    const args = process.argv.slice(2);

    function startService() {
      spawn(process.execPath, [__filename, SERVE_MODE], { detached: true, stdio: 'ignore' }).unref();
      const deadline = Date.now() + START_TIMEOUT_MS;
      const wait = () => {
        if (fs.existsSync(URL_FILE) || Date.now() > deadline) process.exit(0);
        else setTimeout(wait, START_POLL_MS);
      };
      wait();
    }

    function serve() {
      const configDir = process.env.PIBOARD_FAKE_OPENCODE_CONFIG;
      if (configDir) {
        fs.mkdirSync(configDir, { recursive: true });
        fs.writeFileSync(path.join(configDir, 'service.json'), JSON.stringify({ password: PASSWORD }));
      }
      const expected = 'Basic ' + Buffer.from(AUTH_USER + ':' + PASSWORD).toString('base64');
      const sessions = new Map();
      const streams = new Set();

      const emit = (type, sessionID) => {
        const payload = 'data: ' + JSON.stringify({ type, data: { sessionID } }) + '\n\n';
        for (const res of streams) res.write(payload);
      };

      const reply = (res, status, body) => {
        res.writeHead(status, { 'Content-Type': 'application/json' });
        res.end(body);
      };

      // The server is detached and would outlive every test run, so it exits when nobody talks to it.
      let idleTimer;
      const resetIdle = () => {
        clearTimeout(idleTimer);
        idleTimer = setTimeout(() => {
          try { fs.unlinkSync(URL_FILE); } catch (e) {}
          process.exit(0);
        }, IDLE_EXIT_MS);
      };
      resetIdle();

      const server = http.createServer((req, res) => {
        resetIdle();
        if (req.headers.authorization !== expected) return reply(res, 401, '{}');
        const url = new URL(req.url, 'http://127.0.0.1');
        const parts = url.pathname.split('/').filter(Boolean);
        if (parts[0] !== 'api') return reply(res, 404, '{}');
        const route = parts.slice(1);

        if (req.method === 'GET' && route[0] === 'event') {
          res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
          res.write('data: {"type":"server.connected","data":{}}\n\n');
          streams.add(res);
          const beat = setInterval(() => res.write(': heartbeat\n\n'), HEARTBEAT_MS);
          req.on('close', () => { clearInterval(beat); streams.delete(res); });
          return;
        }
        if (route[0] !== 'session') return reply(res, 404, '{}');

        if (req.method === 'POST' && route.length === 1) {
          const chunks = [];
          req.on('data', (c) => chunks.push(c));
          req.on('end', () => {
            let body = {};
            try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch (e) {}
            const now = Date.now();
            const session = {
              id: body.id || 'ses_' + crypto.randomBytes(12).toString('hex'),
              title: body.title || '',
              location: body.location || { directory: '/' },
              tokens: { input: 0, output: 0, reasoning: 0, cache: { read: 0, write: 0 } },
              cost: 0,
              time: { created: now, updated: now },
            };
            sessions.set(session.id, session);
            reply(res, 200, JSON.stringify({ data: session }));
            emit('session.execution.started', session.id);
            setTimeout(() => emit('session.execution.succeeded', session.id), EXECUTION_MS);
          });
          return;
        }
        if (req.method === 'GET' && route[1] === 'active') return reply(res, 200, '{"data":{}}');
        const session = sessions.get(route[1]);
        if (req.method === 'GET' && route[2] === 'message') return reply(res, 200, '{"data":[]}');
        if (req.method === 'GET' && route.length === 2) {
          return session ? reply(res, 200, JSON.stringify({ data: session })) : reply(res, 404, NOT_FOUND);
        }
        if (req.method === 'DELETE' && route.length === 2) {
          sessions.delete(route[1]);
          res.writeHead(204);
          return res.end();
        }
        reply(res, 404, '{}');
      });

      server.listen(0, '127.0.0.1', () => {
        fs.writeFileSync(URL_FILE, 'http://127.0.0.1:' + server.address().port);
      });
    }

    function runTui() {
      const ESC = '\x1b';
      const BRACKETED_PASTE_ON = ESC + '[?2004h', BRACKETED_PASTE_OFF = ESC + '[?2004l';
      const MOUSE_OFF = ESC + '[?1000l' + ESC + '[?1002l' + ESC + '[?1003l' + ESC + '[?1006l';
      const LINES_PER_TURN = 40, LINE_INTERVAL_MS = 50, AUTO_TURN_MS = 6000;
      const COLORS = [31, 32, 33, 34, 35, 36];

      let sessionId = 'unknown', prompt = '';
      for (let i = 0; i < args.length; i++) {
        if (args[i] === '--session') sessionId = args[++i];
        else if (args[i] === '--prompt') prompt = args[++i];
      }

      const out = (s) => process.stdout.write(s);
      let turns = 0, busy = false, typed = '';

      function finishTurn() {
        out('\r\n> ');
        busy = false;
      }

      function turn() {
        if (busy) return;
        busy = true;
        turns++;
        let n = 0;
        const timer = setInterval(() => {
          n++;
          const color = COLORS[n % COLORS.length];
          out(ESC + '[' + color + 'mturn ' + turns + ' line ' + n + ESC + '[0m\r\n');
          if (n % 10 === 0) out(ESC + '[A' + ESC + '[2K' + 'turn ' + turns + ' progress ' + n + '/' + LINES_PER_TURN + '\r\n');
          if (n >= LINES_PER_TURN) {
            clearInterval(timer);
            finishTurn();
          }
        }, LINE_INTERVAL_MS);
      }

      function quit(code) {
        out(BRACKETED_PASTE_OFF);
        process.exit(code);
      }

      function onInput(chunk) {
        for (const ch of chunk.toString('latin1')) {
          if (ch === '\x03') quit(130);
          else if (ch === '\x04') quit(0);
          else if (ch === '\r' || ch === '\n') {
            out('\r\n');
            if (typed.trim() === 'exit') quit(0);
            typed = '';
            turn();
          } else if (ch === '\x7f') {
            if (typed.length > 0) { typed = typed.slice(0, -1); out('\b \b'); }
          } else { typed += ch; out(ch); }
        }
      }

      out('fake opencode session ' + sessionId + '\r\n');
      if (prompt) out(prompt + '\r\n');
      out(BRACKETED_PASTE_ON + MOUSE_OFF);
      if (process.stdin.isTTY) process.stdin.setRawMode(true);
      process.stdin.on('data', onInput);
      process.stdin.on('end', () => quit(0));
      process.on('SIGTERM', () => quit(0));
      process.on('SIGHUP', () => quit(0));
      setInterval(turn, AUTO_TURN_MS);
      turn();
    }

    if (args[0] === '--version') {
      console.log('opencode v0.0.0');
    } else if (args[0] === 'service' && args[1] === 'status') {
      if (fs.existsSync(URL_FILE)) console.log(fs.readFileSync(URL_FILE, 'utf8').trim());
    } else if (args[0] === 'service' && args[1] === 'start') {
      startService();
    } else if (args[0] === SERVE_MODE) {
      serve();
    } else {
      runTui();
    }
    """#
}
