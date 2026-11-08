import { createSign } from 'node:crypto';

const base64Url = (value: string | Buffer) =>
  Buffer.from(value)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

export const createJwt = ({
  algorithm,
  header,
  payload,
  privateKey,
}: {
  algorithm: 'RSA-SHA256' | 'SHA256';
  header: Record<string, unknown>;
  payload: Record<string, unknown>;
  privateKey: string;
}) => {
  const unsigned = `${base64Url(JSON.stringify(header))}.${base64Url(
    JSON.stringify(payload),
  )}`;
  const signer = createSign(algorithm);
  signer.update(unsigned);
  signer.end();
  const signature = signer.sign({
    key: privateKey,
    ...(algorithm === 'SHA256' ? { dsaEncoding: 'ieee-p1363' as const } : {}),
  });
  return `${unsigned}.${base64Url(signature)}`;
};
