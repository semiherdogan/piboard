// Imitates the Claude Code 2.1.294 surface PiBoard touches: version, auth status, title glyphs, hook POSTs and session JSONL.
enum FakeClaudeCode {
    static let binaryName = "claude"
    static let scriptFileName = "claude.js"
    static let nodeEnvironmentKey = "PIBOARD_FAKE_CLAUDE_NODE"
    static let homeEnvironmentKey = "PIBOARD_FAKE_CLAUDE_HOME"
    static let tuiPidFileName = "claude-tui-pids.txt"
    static let deterministicFileName = "deterministic"
    static let version = "0.0.0 (Claude Code)"
    // Shell parameter expansion needs no utilities on PATH.
    static let wrapper = "#!/bin/sh\nexec \"$\(nodeEnvironmentKey)\" \"${0%/*}/\(scriptFileName)\" \"$@\"\n"

    static let script = #"""
    'use strict';
    const fs = require('fs');
    const path = require('path');
    const http = require('http');
    const ROOT = path.dirname(__filename);
    const HOME = process.env['\#(homeEnvironmentKey)'];
    const DETERMINISTIC = fs.existsSync(path.join(ROOT, '\#(deterministicFileName)'));
    const LINE_MS = 50, AUTO_MS = 6000, TITLE_MS = 300, HOOK_TIMEOUT_MS = 5000;
    const LINES_PER_TURN = 40;
    const GLYPH = { busy: ['\u25D0', '\u25D1'], idle: '\u2733' };
    const HOOK = { submit: 'UserPromptSubmit', permission: 'PermissionRequest', stop: 'Stop', end: 'SessionEnd' };
    const COMMAND = { permission: 'permission', finish: 'finish', exit: 'exit' };
    const DEFAULT_TEXT = 'fake prompt', MODEL = 'fake-model', COST_PER_TURN = 0.01;
    const args = process.argv.slice(2);

    function findUrl(node) {
      if (!node || typeof node !== 'object') return undefined;
      if (typeof node.url === 'string') return node.url;
      for (const child of Object.values(node)) {
        const url = findUrl(child);
        if (url) return url;
      }
      return undefined;
    }

    function runTui() {
      // The harness kills these by pid: a TUI can outlive a force-killed app and ignore its hangup.
      fs.appendFileSync(path.join(ROOT, '\#(tuiPidFileName)'), process.pid + '\n');
      const ESC = '\x1b', BEL = '\x07', PASTE_ON = ESC + '[?2004h', PASTE_OFF = ESC + '[?2004l';
      const MOUSE_OFF = ESC + '[?1000l' + ESC + '[?1002l' + ESC + '[?1003l' + ESC + '[?1006l';
      const COLORS = [31, 32, 33, 34, 35, 36];
      let sessionId, name = '', hookUrl, prompt = '';
      for (let i = 0; i < args.length; i++) {
        if (args[i] === '--session-id' || args[i] === '--resume') sessionId = args[++i];
        else if (args[i] === '--name') name = args[++i];
        else if (args[i] === '--settings') {
          try { hookUrl = findUrl(JSON.parse(args[++i]).hooks); } catch { hookUrl = undefined; }
        } else if (args[i] === '--') { prompt = args[i + 1] || ''; break; }
      }
      const cwd = fs.realpathSync(process.cwd());
      const out = s => process.stdout.write(s);
      let turns = 0, busy = false, waiting = false, typed = '', lines = 0, tick = 0, titleTimer, sessionStarted = false, quitting = false;

      function setTitle(glyph) { out(ESC + ']0;' + glyph + ' ' + name + BEL); }
      function startBusyTitle() {
        clearInterval(titleTimer);
        setTitle(GLYPH.busy[tick++ % GLYPH.busy.length]);
        titleTimer = setInterval(() => setTitle(GLYPH.busy[tick++ % GLYPH.busy.length]), TITLE_MS);
      }
      function setIdleTitle() { clearInterval(titleTimer); setTitle(GLYPH.idle); }

      // A failed POST must not break the TUI; the app side is what the tests assert on.
      function post(event) {
        if (!hookUrl) return Promise.resolve();
        return new Promise(resolve => {
          const req = http.request(hookUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' } }, res => {
            res.resume();
            res.on('end', resolve);
          });
          req.setTimeout(HOOK_TIMEOUT_MS, () => req.destroy());
          req.on('error', resolve);
          req.end(JSON.stringify({ hook_event_name: event, session_id: sessionId, cwd }));
        });
      }

      function append(entry) {
        if (!HOME) return;
        const directory = path.join(HOME, '.claude', 'projects', cwd.replace(/[\/.]/g, '-'));
        fs.mkdirSync(directory, { recursive: true });
        const file = path.join(directory, sessionId + '.jsonl');
        const base = { timestamp: new Date().toISOString(), sessionId, cwd };
        // The real tool creates the file on the first prompt, titled when --name was given.
        if (!sessionStarted) {
          sessionStarted = true;
          if (name) fs.appendFileSync(file, JSON.stringify({ type: 'custom-title', customTitle: name, sessionId }) + '\n');
        }
        fs.appendFileSync(file, JSON.stringify({ ...entry, ...base }) + '\n');
      }

      async function finish() {
        if (!busy || waiting) return;
        busy = false;
        setIdleTitle();
        await post(HOOK.stop);
        append({
          type: 'assistant',
          message: {
            id: 'msg_fake_' + turns, role: 'assistant', model: MODEL,
            content: [{ type: 'text', text: 'Fake reply ' + turns }],
            usage: { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 },
          },
        });
        append({ type: 'cost-state', totalCostUSD: turns * COST_PER_TURN });
        out('\r\n> ');
      }
      async function turn(text) {
        if (busy) return;
        busy = true; lines = 0; turns++;
        startBusyTitle();
        append({ type: 'user', message: { role: 'user', content: text || DEFAULT_TEXT } });
        await post(HOOK.submit);
      }
      async function input(chunk) {
        for (const ch of chunk.toString('latin1')) {
          if (ch === '\x03' || ch === '\x04') return quit();
          if (ch === '\r' || ch === '\n') {
            out('\r\n');
            const line = typed.trim();
            typed = '';
            if (line === COMMAND.exit) return quit();
            if (waiting) { waiting = false; lines = 0; startBusyTitle(); }
            else if (DETERMINISTIC && busy && line === COMMAND.permission) {
              waiting = true;
              setIdleTitle();
              await post(HOOK.permission);
              out('Allow fake operation? Type a reply: ');
            } else if (DETERMINISTIC && line === COMMAND.finish) await finish();
            else await turn(line);
          } else if (ch === '\x7f') {
            if (typed.length) { typed = typed.slice(0, -1); out('\b \b'); }
          } else { typed += ch; out(ch); }
        }
      }
      async function quit() {
        if (quitting) return;
        quitting = true;
        await post(HOOK.end);
        out(PASTE_OFF);
        process.exit(0);
      }

      out('fake claude ' + '\#(version)' + ' ' + name + '\r\n' + PASTE_ON + MOUSE_OFF);
      setIdleTitle();
      if (process.stdin.isTTY) process.stdin.setRawMode(true);
      // Serialize input so a permission reply cannot race a finish command.
      let inputQueue = Promise.resolve();
      process.stdin.on('data', chunk => { inputQueue = inputQueue.then(() => input(chunk)); });
      process.stdin.on('end', quit);
      process.on('SIGTERM', quit);
      process.on('SIGHUP', quit);
      setInterval(() => {
        if (!busy || waiting) return;
        lines++;
        out(ESC + '[' + COLORS[lines % COLORS.length] + 'mturn ' + turns + ' line ' + lines + ESC + '[0m\r\n');
        if (!DETERMINISTIC && lines >= LINES_PER_TURN) finish();
      }, LINE_MS);
      if (!DETERMINISTIC) setInterval(() => turn(), AUTO_MS);
      if (prompt) turn(prompt);
    }

    if (args[0] === '--version') console.log('\#(version)');
    else if (args[0] === 'auth' && args[1] === 'status') console.log(JSON.stringify({ loggedIn: true, authMethod: 'fake' }));
    else runTui();
    """#
}
