// Run with each packaged Node runtime, without NODE_OPTIONS or custom CA variables.
const assert = require('node:assert/strict');
const { X509Certificate } = require('node:crypto');
const https = require('node:https');
const tls = require('node:tls');

const minimum = { 22: [23, 4], 24: [22, 1] };
const [major, minor, patch] = process.versions.node.split('.').map(Number);
assert(minimum[major], `Unexpected Node major: ${major}`);
const [minMinor, minPatch] = minimum[major];
assert(minor > minMinor || (minor === minMinor && patch >= minPatch));

const fingerprint = '86:A1:EC:BA:08:9C:4A:8D:3B:BE:27:34:C6:12:BA:34:1D:81:3E:04:3C:F9:E8:A8:62:CD:5C:57:A3:6B:BE:6B';
assert(tls.rootCertificates.length > 0);
assert(!tls.rootCertificates.some(pem => new X509Certificate(pem).fingerprint256 === fingerprint),
  'Bundled roots still contain emSign ECC Root CA - G3');
for (const dep of ['openssl', 'cares', 'sqlite', 'brotli']) {
  assert.equal(process.config.variables[`node_shared_${dep}`], false,
    `${dep} must use the dependency bundled with the security release`);
}

const req = https.get('https://example.com', res => {
  assert.equal(res.socket.authorized, true);
  res.resume();
  res.on('end', () => console.log(`${process.version}: bundled roots, dependency linkage, and HTTPS passed`));
});
req.setTimeout(10_000, () => req.destroy(new Error('HTTPS probe timed out')));
req.on('error', error => {
  console.error(error);
  process.exitCode = 1;
});
