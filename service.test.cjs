const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { spawn } = require('node:child_process');

// Exercise the service's actual JS functions. The release checklist covers
// Process integration and reactive bindings, which this harness does not emulate.
const source = readFileSync(`${__dirname}/Service.qml`, 'utf8');
function service() {
  const calls = [];
  const context = vm.createContext({
    compatible: true, available: true, ready: true, connection: 'connected', themeAccent: '#509475',
    themeAccentValid: true, mode: 'static', pendingMode: '', currentKind: '',
    queuedAction: null, queuedSync: false, busy: false,
    apiVersion: 1, daemonVersion: '0.1.1',
    activeDynamicColor: '', requestedColor: '#FFFFFF', actionMessage: '',
    executable: '/home/test/.local/bin/edifier-qr65',
    timeoutExecutable: '/usr/bin/timeout', commandTimeoutSeconds: 15,
    streamCharacterLimit: 16384,
    version: 0, configuredStaticColor: '#FFFFFF', configuredBrightness: -1,
    colorMatching: false, requestedSource: '', appliedColor: '', appliedBrightness: -1,
    message: '', updatedAt: 0, error: '', queuedStatus: false,
    commandOut: { text: '', overflowed: false, sawData: false },
    commandErr: { text: '', overflowed: false, sawData: false },
    commandProcess: { running: false, command: [] },
    actionMessageTimer: { restart() {} },
    launch(kind, args) { calls.push({ kind, args: Array.from(args) }); return true; },
  });
  for (const name of ['validColor', 'boundedDiagnostic', 'setUnavailable', 'invalidateApi',
    'lightingAvailable', 'setDynamic', 'setStatic', 'queueThemeColor', 'releaseToApp',
    'resumeDaemon', 'guardStream', 'resetStreams', 'statusIsStale', 'applyStatus']) {
    const match = source.match(new RegExp(`  function ${name}\\([^]*?\\n  }`));
    assert.ok(match, `Missing ${name}`);
    vm.runInContext(match[0], context);
  }
  return { context, calls };
}

test('Follow Theme sends the current accent from static mode', () => {
  const { context: c, calls } = service();
  assert.equal(c.setDynamic(), true);
  assert.deepEqual(calls, [{ kind: 'dynamic', args: ['mode', 'dynamic', '#509475'] }]);
  assert.equal(c.pendingMode, 'dynamic');
});

test('invalid accent produces feedback instead of a silent no-op', () => {
  const { context: c, calls } = service();
  c.themeAccentValid = false;
  assert.equal(c.setDynamic(), false);
  assert.match(c.actionMessage, /accent.*invalid/);
  assert.equal(calls.length, 0);
});

test('unavailable API produces feedback and no command', () => {
  const { context: c, calls } = service();
  c.compatible = false;
  assert.equal(c.setDynamic(), false);
  assert.match(c.actionMessage, /API is not ready/);
  assert.equal(calls.length, 0);
});

test('static mode ignores changing theme colors', () => {
  const { context: c, calls } = service();
  c.queueThemeColor();
  assert.equal(calls.length, 0);
});

test('dynamic queue converges to the latest accent', () => {
  const { context: c } = service();
  c.mode = 'dynamic'; c.busy = true;
  c.queueThemeColor();
  c.themeAccent = '#CBA6F7';
  c.queueThemeColor();
  assert.equal(c.queuedAction.args[2], '#CBA6F7');
  c.themeAccent = c.requestedColor;
  c.queueThemeColor();
  assert.equal(c.queuedAction, null);
});

test('explicit static intent blocks automatic theme updates', () => {
  const { context: c } = service();
  c.mode = 'dynamic'; c.busy = true;
  c.setStatic('#FFB86C');
  c.queueThemeColor();
  assert.equal(c.queuedAction.kind, 'static');
  assert.equal(c.queuedAction.args[2], '#FFB86C');
});

test('release and resume map to lifecycle commands', () => {
  const { context: c, calls } = service();
  assert.equal(c.releaseToApp(), true);
  assert.equal(c.resumeDaemon(), true);
  assert.deepEqual(calls, [
    { kind: 'release', args: ['release'] },
    { kind: 'resume', args: ['resume'] },
  ]);
});

test('latest lifecycle intent replaces a busy queued action', () => {
  const { context: c, calls } = service();
  c.busy = true;
  c.queuedSync = true;
  assert.equal(c.releaseToApp(), true);
  assert.equal(c.queuedAction.kind, 'release');
  assert.equal(c.queuedSync, false);
  assert.equal(c.resumeDaemon(), true);
  assert.equal(c.queuedAction.kind, 'resume');
  assert.equal(calls.length, 0);
});

test('automatic theme updates preserve queued lifecycle intent', () => {
  const { context: c } = service();
  c.mode = 'dynamic'; c.busy = true;
  c.releaseToApp();
  c.themeAccent = '#CBA6F7';
  c.queueThemeColor();
  assert.equal(c.queuedAction.kind, 'release');
});

test('automatic theme updates preserve queued explicit controls', () => {
  const { context: c } = service();
  c.mode = 'dynamic'; c.busy = true;
  c.queuedAction = { kind: 'matching', args: ['color-matching', 'on'] };
  c.themeAccent = '#CBA6F7';
  c.queueThemeColor();
  assert.equal(c.queuedAction.kind, 'matching');
});

test('API invalidation preserves accepted lifecycle intent', () => {
  const { context: c } = service();
  c.busy = true;
  c.releaseToApp();
  c.invalidateApi('Malformed status.');
  assert.equal(c.queuedAction.kind, 'release');
});

test('lighting changes are blocked while released', () => {
  const { context: c, calls } = service();
  c.connection = 'released';
  assert.equal(c.setDynamic(), false);
  assert.equal(c.setStatic('#FFB86C'), false);
  c.queueThemeColor();
  assert.match(c.actionMessage, /Resume QR65 control/);
  assert.equal(calls.length, 0);
});

test('daemon error status fails closed', () => {
  const { context: c } = service();
  const status = {
    version: 1, mode: 'static', configuredStaticColor: '#FFFFFF',
    configuredBrightness: null, colorMatching: false, requestedColor: '',
    requestedSource: '', appliedColor: '', appliedBrightness: null,
    connection: 'error', message: 'Daemon failed safely.', updatedAt: Date.now() / 1000,
  };
  assert.equal(c.applyStatus(JSON.stringify(status)), true);
  assert.equal(c.available, false);
  assert.equal(c.connection, 'error');
  assert.equal(c.error, 'Daemon failed safely.');
});

test('lighting commands are blocked when status is unavailable', () => {
  const { context: c, calls } = service();
  c.available = false;
  c.ready = false;
  c.connection = 'error';
  assert.equal(c.setStatic('#FFB86C'), false);
  assert.match(c.actionMessage, /status is unavailable/);
  assert.equal(calls.length, 0);
});

test('stream guard stops a child before retaining excessive output', () => {
  const { context: c } = service();
  c.commandProcess.running = true;
  const stream = { text: 'x'.repeat(c.streamCharacterLimit + 1), overflowed: false, sawData: false };
  c.guardStream(stream);
  assert.equal(stream.sawData, true);
  assert.equal(stream.overflowed, true);
  assert.equal(c.commandProcess.running, false);
});

test('stream guard leaves bounded output running', () => {
  const { context: c } = service();
  c.commandProcess.running = true;
  const stream = { text: 'x'.repeat(c.streamCharacterLimit), overflowed: false, sawData: false };
  c.guardStream(stream);
  assert.equal(stream.overflowed, false);
  assert.equal(c.commandProcess.running, true);
});

test('stream freshness resets between helper runs', () => {
  const { context: c } = service();
  c.commandOut.sawData = true;
  c.commandErr.sawData = true;
  c.resetStreams();
  assert.equal(c.commandOut.sawData, false);
  assert.equal(c.commandErr.sawData, false);
  assert.match(source, /exitCode === 0 && commandOut\.sawData/);
});

test('deadline wrapper forwards termination and kills a resistant child', async () => {
  const wrapper = spawn('/usr/bin/timeout', ['-k', '1', '30', '/usr/bin/bash', '-c',
    'trap "" TERM; echo $$; exec /usr/bin/sleep 30']);
  let childPid = 0;
  try {
    childPid = Number(await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('child did not start')), 2000);
      wrapper.stdout.once('data', data => {
        clearTimeout(timer);
        resolve(String(data).trim());
      });
      wrapper.once('error', reject);
    }));
    const closed = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('deadline wrapper did not exit')), 5000);
      wrapper.once('close', () => { clearTimeout(timer); resolve(); });
    });
    wrapper.kill('SIGTERM');
    await closed;
    assert.throws(() => process.kill(childPid, 0), error => error.code === 'ESRCH');
  } finally {
    if (wrapper.exitCode === null) wrapper.kill('SIGKILL');
    if (childPid > 0) {
      try { process.kill(childPid, 'SIGKILL'); } catch {}
    }
  }
});

test('process execution uses a clean environment and external kill deadline', () => {
  assert.match(source, /clearEnvironment:\s*true/);
  assert.match(source, /environment:\s*root\.processEnvironment/);
  assert.match(source, /\[timeoutExecutable, "-k", "2",/);
  assert.match(source, /Component\.onDestruction:[^]*commandProcess\.running = false/);
  assert.match(source, /onDataChanged:\s*root\.guardStream\(commandOut\)/);
  assert.match(source, /onDataChanged:\s*root\.guardStream\(commandErr\)/);
});
