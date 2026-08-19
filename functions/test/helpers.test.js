const test = require('node:test');
const assert = require('node:assert/strict');
const { _test } = require('../index.js');
const { generateSecurePassword, replacePlaceholders } = _test;

test('generateSecurePassword generates passwords meeting complexity rules', (t) => {
  // Test default length 12
  const pwd12 = generateSecurePassword();
  assert.equal(pwd12.length, 12);
  assert.match(pwd12, /[A-Z]/, 'Must contain uppercase');
  assert.match(pwd12, /[a-z]/, 'Must contain lowercase');
  assert.match(pwd12, /[0-9]/, 'Must contain digit');
  assert.match(pwd12, /[!@#$%&*+]/, 'Must contain symbol');

  // Test minimum length enforcement (passing 4 should enforce at least 8)
  const pwdMin = generateSecurePassword(4);
  assert.ok(pwdMin.length >= 8, 'Length must be at least 8');

  // Test custom length 20
  const pwd20 = generateSecurePassword(20);
  assert.equal(pwd20.length, 20);

  // Test multiple generations produce distinct outputs
  const set = new Set();
  for (let i = 0; i < 50; i++) {
    const p = generateSecurePassword();
    assert.match(p, /[A-Z]/);
    assert.match(p, /[a-z]/);
    assert.match(p, /[0-9]/);
    assert.match(p, /[!@#$%&*+]/);
    set.add(p);
  }
  assert.equal(set.size, 50, 'All generated passwords should be unique');
});

test('replacePlaceholders replaces placeholder tags case-insensitively', (t) => {
  const template = 'Hello %Name%, your email is %EMAIL%, password is %Password%, address is %ADDRESS%, role is %Role%, app is %appName%.';
  const data = {
    name: 'Jane Doe',
    email: 'jane@example.com',
    password: 'SecretPass123!',
    address: 'Oak St #10',
    role: 'Resident',
    appName: 'Suburban Life',
  };

  const result = replacePlaceholders(template, data);

  assert.equal(
    result,
    'Hello Jane Doe, your email is jane@example.com, password is SecretPass123!, address is Oak St #10, role is Resident, app is Suburban Life.'
  );
});

test('replacePlaceholders handles missing data with safe defaults', (t) => {
  const template = 'Name: %name%, Address: %address%, Role: %role%, App: %appName%';
  const result = replacePlaceholders(template, {});

  assert.equal(result, 'Name: , Address: N/A, Role: Residente, App: Suburban Life');
});

test('replacePlaceholders returns empty string on null or empty template', (t) => {
  assert.equal(replacePlaceholders(null, {}), '');
  assert.equal(replacePlaceholders('', {}), '');
});
