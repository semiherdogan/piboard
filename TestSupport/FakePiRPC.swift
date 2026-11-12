import Foundation

// Stands in for `pi --mode rpc` in unit and UI tests: a Node script that speaks the JSONL protocol and never contacts a model.
// Flags: --fake-deltas N (text deltas per reply, 20 ms apart), --fake-history N (preloaded user/assistant pairs),
// --fake-ignore <command> (never answer that command; repeatable), --fake-hold-stdout (a detached grandchild keeps stdout open
// for a few seconds after the fake exits), --fake-active-agent <name> (a stored active_agent entry that get_entries returns; prompt
// text /fake-set-agent <name> appends a live one). Prompt text /fake-confirm opens a confirm dialog, /fake-crash exits with code 3 in the
// middle of a run, /fake-stderr-crash writes about 64 KB to stderr ending in a known line and exits with code 1.
enum FakePiRPC {
    static let scriptFileName = "fake-pi-rpc.js"

    static let script = #"""
    'use strict';
    const DELTA_INTERVAL_MS = 20, CRASH_DELAY_MS = 50, CRASH_EXIT_CODE = 3, DEFAULT_DELTAS = 5;
    const SET_AGENT_PROMPT = '/fake-set-agent ', ACTIVE_AGENT_TYPE = 'active_agent';
    const CONFIRM_PROMPT = '/fake-confirm', CRASH_PROMPT = '/fake-crash', STDERR_CRASH_PROMPT = '/fake-stderr-crash';
    const STDERR_LINE_LENGTH = 63, STDERR_LINE_COUNT = 1000, STDERR_LAST_LINE = 'fake trace end', STDERR_CRASH_EXIT_CODE = 1;
    const HOLD_STDOUT_MS = 6000;
    const MODEL = { id: 'fake-model', name: 'Fake Model', provider: 'fake', reasoning: true, input: ['text', 'image'], contextWindow: 100000 };

    const args = process.argv.slice(2);
    const ignored = new Set();
    let deltas = DEFAULT_DELTAS, historyPairs = 0, sessionId = 'fake-session', holdStdout = false, activeAgent = null;
    for (let i = 0; i < args.length; i++) {
      if (args[i] === '--fake-ignore') ignored.add(args[++i]);
      else if (args[i] === '--fake-deltas') deltas = Number(args[++i]);
      else if (args[i] === '--fake-history') historyPairs = Number(args[++i]);
      else if (args[i] === '--fake-hold-stdout') holdStdout = true;
      else if (args[i] === '--fake-active-agent') activeAgent = args[++i];
      else if (args[i] === '--session-id' || args[i] === '--session') sessionId = args[++i];
    }

    if (holdStdout) {
      // The grandchild inherits fd 1, so stdout stays open after this process exits; it ends on its own.
      require('child_process').spawn(process.execPath, ['-e', 'setTimeout(() => {}, ' + HOLD_STDOUT_MS + ')'], { detached: true, stdio: ['ignore', 1, 'ignore'] }).unref();
    }

    process.stderr.write('Warning: No project session found with id \'' + sessionId + '\'; creating a new session with that id.\n');

    const usage = (output) => ({ input: 10, output, cacheRead: 0, cacheWrite: 0, reasoning: 0, totalTokens: 10 + output, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0.001 } });
    const userMessage = (text) => ({ role: 'user', content: [{ type: 'text', text }], timestamp: Date.now() });
    const assistantMessage = (text, stopReason, count) => {
      const message = { role: 'assistant', content: [{ type: 'text', text }], model: MODEL.id, provider: MODEL.provider, usage: usage(count), stopReason, timestamp: Date.now() };
      if (stopReason === 'aborted') message.errorMessage = 'aborted';
      return message;
    };

    const messages = [];
    for (let i = 0; i < historyPairs; i++) {
      messages.push(userMessage('history question ' + i));
      messages.push(assistantMessage('history answer ' + i, 'stop', 3));
    }

    let streaming = false, aborted = false, abortCommand = null, thinkingLevel = 'medium';
    const queue = { steering: [], followUp: [] };
    const dialogs = new Map();

    const send = (record) => process.stdout.write(JSON.stringify(record) + '\n');
    const respond = (command, data) => send({ id: command.id, type: 'response', command: command.type, success: true, ...(data === undefined ? {} : { data }) });
    const fail = (command, error) => send({ id: command.id, type: 'response', command: command.type, success: false, error });
    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    const queueUpdate = () => send({ type: 'queue_update', steering: [...queue.steering], followUp: [...queue.followUp] });

    async function runTurn(text) {
      send({ type: 'turn_start' });
      const user = userMessage(text);
      messages.push(user);
      send({ type: 'message_start', message: user });
      send({ type: 'message_end', message: user });
      send({ type: 'message_start', message: { role: 'assistant', content: [], stopReason: 'pending', timestamp: Date.now() } });
      send({ type: 'message_update', assistantMessageEvent: { type: 'text_start', contentIndex: 0 }, usage: usage(0) });
      let full = '', count = 0;
      for (let i = 0; i < deltas && !aborted; i++) {
        await sleep(DELTA_INTERVAL_MS);
        if (aborted) break;
        const delta = 'd' + i + ' ';
        full += delta;
        count = i + 1;
        send({ type: 'message_update', assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta }, usage: usage(count) });
      }
      send({ type: 'message_update', assistantMessageEvent: { type: 'text_end', contentIndex: 0, content: full }, usage: usage(count) });
      const reply = assistantMessage(full, aborted ? 'aborted' : 'stop', count);
      messages.push(reply);
      send({ type: 'message_end', message: reply });
      send({ type: 'turn_end', message: reply, toolResults: [] });
    }

    async function runPrompt(text) {
      streaming = true;
      aborted = false;
      send({ type: 'agent_start' });
      let next = text;
      while (next !== null && !aborted) {
        await runTurn(next);
        next = null;
        if (!aborted && (queue.steering.length || queue.followUp.length)) {
          next = queue.steering.length ? queue.steering.shift() : queue.followUp.shift();
          queueUpdate();
        }
      }
      streaming = false;
      send({ type: 'agent_end', messages: [], willRetry: false });
      send({ type: 'agent_settled', aborted });
      if (abortCommand) {
        respond(abortCommand);
        abortCommand = null;
      }
    }

    const agentEntry = (name) => ({ type: 'custom', id: 'entry-' + Math.random().toString(36).slice(2), parentId: null, timestamp: new Date().toISOString(), customType: ACTIVE_AGENT_TYPE, data: { name } });
    const entries = activeAgent === null ? [] : [agentEntry(activeAgent)];

    function handlePrompt(command) {
      const text = command.message;
      if (text.startsWith(SET_AGENT_PROMPT)) {
        const entry = agentEntry(text.slice(SET_AGENT_PROMPT.length));
        entries.push(entry);
        send({ type: 'entry_appended', entry });
        respond(command, { disposition: 'handled' });
        return;
      }
      if (text === CONFIRM_PROMPT) {
        const id = 'dialog-' + Date.now();
        dialogs.set(id, command);
        send({ type: 'extension_ui_request', id, method: 'confirm', title: 'Fake', message: 'Proceed?' });
        return;
      }
      if (text === STDERR_CRASH_PROMPT) {
        const line = 'x'.repeat(STDERR_LINE_LENGTH) + '\n';
        process.stderr.write(line.repeat(STDERR_LINE_COUNT) + STDERR_LAST_LINE + '\n', () => process.exit(STDERR_CRASH_EXIT_CODE));
        return;
      }
      if (text === CRASH_PROMPT) {
        respond(command, { disposition: 'started' });
        send({ type: 'agent_start' });
        send({ type: 'turn_start' });
        send({ type: 'message_start', message: { role: 'assistant', content: [], stopReason: 'pending', timestamp: Date.now() } });
        send({ type: 'message_update', assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'partial' } });
        setTimeout(() => process.exit(CRASH_EXIT_CODE), CRASH_DELAY_MS);
        return;
      }
      if (streaming) {
        if (command.streamingBehavior === 'steer') queue.steering.push(text);
        else if (command.streamingBehavior === 'followUp') queue.followUp.push(text);
        else return fail(command, 'Agent is already processing. Specify streamingBehavior.');
        respond(command, { disposition: 'queued' });
        queueUpdate();
        return;
      }
      respond(command, { disposition: 'started' });
      runPrompt(text);
    }

    function handle(command) {
      if (command.type === 'extension_ui_response') {
        const prompt = dialogs.get(command.id);
        if (!prompt) return;
        dialogs.delete(command.id);
        send({ type: 'extension_ui_request', id: 'notify-' + command.id, method: 'notify', message: 'confirmed: ' + (command.confirmed === true) });
        respond(prompt, { disposition: 'handled' });
        return;
      }
      if (ignored.has(command.type)) return;
      switch (command.type) {
        case 'get_state':
          return respond(command, { model: MODEL, thinkingLevel, isStreaming: streaming, sessionFile: '/tmp/fake/' + sessionId + '.jsonl', sessionId, sessionName: 'Fake session', messageCount: messages.length });
        case 'get_messages':
          return respond(command, { messages });
        case 'get_entries':
          return respond(command, { entries, leafId: entries.length ? entries[entries.length - 1].id : null });
        case 'get_session_stats':
          return respond(command, { sessionId, userMessages: messages.filter((m) => m.role === 'user').length, assistantMessages: messages.filter((m) => m.role === 'assistant').length, toolCalls: 0, tokens: { input: 10, output: 5, cacheRead: 0, cacheWrite: 0, total: 15 }, cost: 0.002, contextUsage: { tokens: 1000, contextWindow: MODEL.contextWindow, percent: 1 } });
        case 'get_available_models':
          return respond(command, { models: [MODEL, { ...MODEL, id: 'fake-small', name: 'Fake Small', reasoning: false, input: ['text'] }] });
        case 'get_available_thinking_levels':
          return respond(command, { levels: ['off', 'low', 'medium', 'high'] });
        case 'set_thinking_level':
          thinkingLevel = command.level;
          respond(command);
          return send({ type: 'thinking_level_changed', level: thinkingLevel });
        case 'set_model':
          return respond(command, MODEL);
        case 'get_commands':
          return respond(command, { commands: [{ name: 'fake-confirm', description: 'Ask for confirmation', source: 'extension' }] });
        case 'prompt':
          return handlePrompt(command);
        case 'steer':
        case 'follow_up':
          if (!streaming) return fail(command, 'Agent is not running');
          (command.type === 'steer' ? queue.steering : queue.followUp).push(command.message);
          respond(command, { disposition: 'queued' });
          return queueUpdate();
        case 'clear_queue': {
          const cleared = { steering: [...queue.steering], followUp: [...queue.followUp] };
          queue.steering.length = 0;
          queue.followUp.length = 0;
          respond(command, cleared);
          return queueUpdate();
        }
        case 'abort':
          if (!streaming) return respond(command);
          aborted = true;
          abortCommand = command;
          return;
        default:
          return fail(command, 'Unknown command: ' + command.type);
      }
    }

    // Manual LF framing: readline would also split on U+2028 and U+2029, like the real protocol warns.
    let buffer = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => {
      buffer += chunk;
      let end;
      while ((end = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, end).replace(/\r$/, '');
        buffer = buffer.slice(end + 1);
        if (line) handle(JSON.parse(line));
      }
    });
    process.stdin.on('end', () => process.exit(0));
    """#

    /// The script must live in a file: `node -e` would read the flags after it as Node options.
    static func writeScript(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(scriptFileName)
        try script.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
