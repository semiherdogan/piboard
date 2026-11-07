import Foundation

// A readable one-turn stand-in for Pi in the README screenshots; its session file only goes to the UI-test agent directory.
enum FakePiDemo {
    private static let agentDirectoryToken = "__AGENT_DIRECTORY__"
    // Must match the start of the reply in the script; the screenshot test waits for it on screen.
    static let replyOpening = "APIClient now sends requests"

    // The script creates the directory itself: while it is missing the app skips the check that would stop the resume.
    static func script(agentDirectory: URL) -> String {
        let encoded = (try? JSONEncoder().encode(agentDirectory.path)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        return template.replacingOccurrences(of: agentDirectoryToken, with: encoded)
    }

    private static let template = #"""
    'use strict';
    const fs = require('fs'), path = require('path');
    const ESC = '\x1b', BEL = '\x07';
    const PROGRESS_BUSY = ESC + ']9;4;3' + BEL, PROGRESS_DONE = ESC + ']9;4;0' + BEL;
    const DIM = ESC + '[2m', BOLD = ESC + '[1m', GREEN = ESC + '[32m', CYAN = ESC + '[36m', RESET = ESC + '[0m';
    const LINE_INTERVAL_MS = 120;

    const args = process.argv.slice(2);
    let sessionId = 'demo';
    for (let i = 0; i < args.length; i++) {
      if (args[i] === '--session-id' || args[i] === '--session') sessionId = args[++i];
      else if (args[i] === '--') break;
    }

    const prompt = 'Extract the networking layer into a dedicated module with testable protocols.';
    const reply = 'APIClient now sends requests through an HTTPClient protocol it takes as a dependency, ' +
      'so tests pass a stub instead of hitting the network.';
    const lines = [
      BOLD + '> ' + prompt + RESET,
      '',
      "I'll start by reading the current networking code.",
      '',
      DIM + '  read ' + RESET + ' Sources/App/Network/APIClient.swift',
      DIM + '  read ' + RESET + ' Sources/App/Network/Endpoint.swift',
      CYAN + '  edit ' + RESET + ' Sources/App/Network/HTTPClient.swift  ' + GREEN + '+5' + RESET + ' -0',
      CYAN + '  edit ' + RESET + ' Sources/App/Network/APIClient.swift   ' + GREEN + '+5' + RESET + ' -3',
      CYAN + '  edit ' + RESET + ' Sources/App/Network/Endpoint.swift    ' + GREEN + '+2' + RESET + ' -1',
      DIM + '  bash ' + RESET + ' swift test --filter NetworkingTests',
      GREEN + '        14 tests passed' + RESET,
      '',
      // Broken by hand like a real agent's reply, so the terminal never wraps it mid-word.
      'APIClient now sends requests through an HTTPClient protocol it takes as a dependency,',
      'so tests pass a stub instead of hitting the network.',
      '',
    ];

    const AGENT_DIRECTORY = __AGENT_DIRECTORY__;

    // The app finds a session in any project folder under sessions/, so a fixed folder name is enough.
    function writeSession() {
      if (!AGENT_DIRECTORY) throw new Error('no agent directory');
      const dir = path.join(AGENT_DIRECTORY, 'sessions', '--piboard-readme-demo--');
      fs.mkdirSync(dir, { recursive: true });
      const now = new Date().toISOString();
      const usage = { input: 18420, output: 3120, cacheRead: 96400, cacheWrite: 0, totalTokens: 117940,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0.42 } };
      const entries = [
        { type: 'session', version: 3, id: sessionId, timestamp: now, cwd: process.cwd() },
        { type: 'message', timestamp: now, message: { role: 'user', content: [{ type: 'text', text: prompt }] } },
        { type: 'message', timestamp: now, message: { role: 'assistant', content: [{ type: 'text', text: reply }],
          model: 'claude-sonnet-5-5', provider: 'anthropic', stopReason: 'stop', usage } },
      ];
      const file = path.join(dir, now.replace(/[:.]/g, '-') + '_' + sessionId + '.jsonl');
      fs.writeFileSync(file, entries.map((e) => JSON.stringify(e)).join('\n') + '\n');
    }

    // A failed write shows in the terminal, and the test then times out waiting for the info line.
    function writeSessionSafely() {
      try { writeSession(); } catch (error) { out('session file not written: ' + error.message + '\r\n'); }
    }

    const out = (s) => process.stdout.write(s);
    out(PROGRESS_BUSY);
    let n = 0;
    const timer = setInterval(() => {
      out(lines[n] + '\r\n');
      n++;
      if (n >= lines.length) {
        clearInterval(timer);
        writeSessionSafely();
        out(PROGRESS_DONE + '> ');
      }
    }, LINE_INTERVAL_MS);

    process.stdin.setRawMode && process.stdin.setRawMode(true);
    process.stdin.on('data', (data) => out(data.toString('utf8').replace(/\r/g, '\r\n')));
    const quit = () => process.exit(0);
    process.on('SIGTERM', quit);
    process.on('SIGHUP', quit);
    """#
}
