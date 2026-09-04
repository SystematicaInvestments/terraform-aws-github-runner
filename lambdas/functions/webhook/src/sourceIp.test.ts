import { APIGatewayEvent } from 'aws-lambda';
import { describe, expect, it } from 'vitest';

import { assertSourceIpAllowed, sourceIpFromEvent } from './sourceIp';

function eventWithRequestContext(requestContext: unknown): APIGatewayEvent {
  return { requestContext } as APIGatewayEvent;
}

describe('webhook source IP filtering', () => {
  it('allows any source when the allowlist is empty', () => {
    expect(() => assertSourceIpAllowed(eventWithRequestContext({}), [])).not.toThrow();
  });

  it('accepts an IPv4 source from a REST API Gateway event', () => {
    const event = eventWithRequestContext({ identity: { sourceIp: '192.30.252.45' } });

    expect(() => assertSourceIpAllowed(event, ['192.30.252.0/22'])).not.toThrow();
  });

  it('accepts an IPv6 source from an HTTP API Gateway event', () => {
    const event = eventWithRequestContext({ http: { sourceIp: '2a0a:a440::1234' } });

    expect(() => assertSourceIpAllowed(event, ['2a0a:a440::/29'])).not.toThrow();
  });

  it('rejects missing and disallowed sources', () => {
    const allowedCidrs = ['192.30.252.0/22'];

    expect(() => assertSourceIpAllowed(eventWithRequestContext({}), allowedCidrs)).toThrow(
      'Source IP address is not allowed.',
    );
    expect(() =>
      assertSourceIpAllowed(eventWithRequestContext({ identity: { sourceIp: '203.0.113.4' } }), allowedCidrs),
    ).toThrow('Source IP address is not allowed.');
  });

  it('fails closed when the configured allowlist is invalid', () => {
    const event = eventWithRequestContext({ identity: { sourceIp: '192.30.252.45' } });

    expect(() => assertSourceIpAllowed(event, ['192.30.252.0/33'])).toThrow(
      'Webhook source CIDR allowlist is invalid.',
    );
    expect(() => assertSourceIpAllowed(event, ['192.30.252.0'])).toThrow('Webhook source CIDR allowlist is invalid.');
  });

  it('prefers HTTP API source IP when both request-context shapes are present', () => {
    const event = eventWithRequestContext({
      http: { sourceIp: '2a0a:a440::1234' },
      identity: { sourceIp: '192.30.252.45' },
    });

    expect(sourceIpFromEvent(event)).toBe('2a0a:a440::1234');
  });
});
