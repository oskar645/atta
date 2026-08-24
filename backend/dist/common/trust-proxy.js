"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TRUSTED_PROXY_HOPS = void 0;
exports.configureTrustProxy = configureTrustProxy;
exports.TRUSTED_PROXY_HOPS = 'loopback';
function configureTrustProxy(app) {
    app.set('trust proxy', exports.TRUSTED_PROXY_HOPS);
}
//# sourceMappingURL=trust-proxy.js.map