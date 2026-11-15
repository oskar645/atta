"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createJwt = void 0;
const node_crypto_1 = require("node:crypto");
const base64Url = (value) => Buffer.from(value)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
const createJwt = ({ algorithm, header, payload, privateKey, }) => {
    const unsigned = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(payload))}`;
    const signer = (0, node_crypto_1.createSign)(algorithm);
    signer.update(unsigned);
    signer.end();
    const signature = signer.sign({
        key: privateKey,
        ...(algorithm === 'SHA256' ? { dsaEncoding: 'ieee-p1363' } : {}),
    });
    return `${unsigned}.${base64Url(signature)}`;
};
exports.createJwt = createJwt;
//# sourceMappingURL=jwt.util.js.map