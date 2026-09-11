const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');

// Exercise the service's actual JS functions. Live QML checks separately verify
// reactive bindings and Process completion, which this harness does not emulate.
const source = readFileSync(`${__dirname}/Service.qml`, 'utf8');
function service() {
  const calls = [];
  const context = vm.createContext({
    compatible: true, available: true, connection: 'connected', themeAccent: '#509475',
    themeAccentValid: true, mode: 'static', pendingMode: '', currentKind: '',
    queuedAction: null, queuedSync: false, busy: false,
    apiVersion: 1, daemonVersion: '0.1.0',
    activeDynamicColor: '', requestedColor: '#FFFFFF', actionMessage: '',
    actionMessageTimer: { restart() {} },
    launch(kind, args) { calls.push({ kind, args: Array.from(args) }); return true; },
  });
  for (const name of ['validColor', 'boundedDiagnostic', 'setUnavailable', 'invalidateApi',
    'lightingAvailable', 'setDynamic', 'setStatic', 'queueThemeColor', 'releaseToApp',
    'resumeDaemon']) {
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
