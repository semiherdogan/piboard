// Stands in for Pi in UI tests: a Node script that behaves like an interactive agent in a real pty and never contacts a model.
enum FakePi {
    static let script = #"""
    'use strict';
    const ESC = '\x1b', BEL = '\x07';
    const PROGRESS_BUSY = ESC + ']9;4;3' + BEL, PROGRESS_DONE = ESC + ']9;4;0' + BEL;
    const BRACKETED_PASTE_ON = ESC + '[?2004h', BRACKETED_PASTE_OFF = ESC + '[?2004l';
    const MOUSE_OFF = ESC + '[?1000l' + ESC + '[?1002l' + ESC + '[?1003l' + ESC + '[?1006l';
    const LINES_PER_TURN = 40, LINE_INTERVAL_MS = 50, KEEPALIVE_MS = 1000, AUTO_TURN_MS = 6000;
    const BURST_EVERY = 5, BURST_LINES = 3000;
    const COLORS = [31, 32, 33, 34, 35, 36];

    const args = process.argv.slice(2);
    let sessionId = 'unknown', title = '', prompt = '';
    const mode = args.includes('--session') ? 'resume' : 'new';
    for (let i = 0; i < args.length; i++) {
      if (args[i] === '--session-id' || args[i] === '--session') sessionId = args[++i];
      else if (args[i] === '--name') title = args[++i];
      else if (args[i] === '--') { prompt = args.slice(i + 1).join(' '); break; }
    }

    const out = (s) => process.stdout.write(s);
    let turns = 0, busy = false, typed = '';

    function finishTurn() {
      out(PROGRESS_DONE + '\r\n> ');
      busy = false;
    }

    function burst() {
      for (let i = 0; i < BURST_LINES; i++) out(ESC + '[3' + (i % 7) + 'mburst line ' + i + ESC + '[0m\r\n');
      finishTurn();
    }

    function streamTurn() {
      let n = 0;
      const keepalive = setInterval(() => out(PROGRESS_BUSY), KEEPALIVE_MS);
      const timer = setInterval(() => {
        n++;
        const color = COLORS[n % COLORS.length];
        out(ESC + '[' + color + 'mturn ' + turns + ' line ' + n + ESC + '[0m\r\n');
        if (n % 10 === 0) out(ESC + '[A' + ESC + '[2K' + 'turn ' + turns + ' progress ' + n + '/' + LINES_PER_TURN + '\r\n');
        if (n >= LINES_PER_TURN) {
          clearInterval(timer);
          clearInterval(keepalive);
          finishTurn();
        }
      }, LINE_INTERVAL_MS);
    }

    function turn() {
      if (busy) return;
      busy = true;
      turns++;
      out(PROGRESS_BUSY);
      if (turns % BURST_EVERY === 0) setImmediate(burst);
      else streamTurn();
    }

    function quit(code) {
      out(PROGRESS_DONE + BRACKETED_PASTE_OFF);
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

    out('fake pi 0.0.0' + (title ? ' (' + title + ')' : '') + '\r\n');
    out('session ' + sessionId + ' mode ' + mode + '\r\n');
    if (prompt) out(prompt + '\r\n');
    out(BRACKETED_PASTE_ON + MOUSE_OFF);
    if (process.stdin.isTTY) process.stdin.setRawMode(true);
    process.stdin.on('data', onInput);
    process.stdin.on('end', () => quit(0));
    process.on('SIGTERM', () => quit(0));
    process.on('SIGHUP', () => quit(0));
    setInterval(turn, AUTO_TURN_MS);
    turn();
    """#
}
