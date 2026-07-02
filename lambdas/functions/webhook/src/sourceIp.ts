import { BlockList, isIP } from 'net';
import { APIGatewayEvent } from 'aws-lambda';

import ValidationError from './ValidationError';

type ApiGatewayRequestContext = {
  http?: {
    sourceIp?: string;
  };
  identity?: {
    sourceIp?: string | null;
  };
};

export function assertSourceIpAllowed(event: APIGatewayEvent, allowedCidrs: string[]): void {
  if (allowedCidrs.length === 0) {
    return;
  }

  const sourceIp = sourceIpFromEvent(event);
  if (!sourceIp) {
    throw new ValidationError(403, 'Source IP address is not allowed.');
  }

  const sourceFamily = isIP(sourceIp);
  if (!sourceFamily) {
    throw new ValidationError(403, 'Source IP address is not allowed.');
  }

  const blockList = buildBlockList(allowedCidrs);
  if (!blockList.check(sourceIp, sourceFamily === 4 ? 'ipv4' : 'ipv6')) {
    throw new ValidationError(403, 'Source IP address is not allowed.');
  }
}

export function sourceIpFromEvent(event: APIGatewayEvent): string | undefined {
  const requestContext = event.requestContext as unknown as ApiGatewayRequestContext;
  return requestContext.http?.sourceIp ?? requestContext.identity?.sourceIp ?? undefined;
}

function buildBlockList(allowedCidrs: string[]): BlockList {
  const blockList = new BlockList();

  for (const cidr of allowedCidrs) {
    const [address, prefix] = cidr.split('/');
    const family = isIP(address);
    const prefixLength = Number(prefix);

    if (
      !family ||
      !Number.isInteger(prefixLength) ||
      prefixLength < 0 ||
      (family === 4 && prefixLength > 32) ||
      (family === 6 && prefixLength > 128)
    ) {
      throw new ValidationError(500, 'Webhook source CIDR allowlist is invalid.');
    }

    blockList.addSubnet(address, prefixLength, family === 4 ? 'ipv4' : 'ipv6');
  }

  return blockList;
}
