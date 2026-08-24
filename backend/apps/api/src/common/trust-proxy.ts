type ExpressLikeApp = {
  set: (setting: string, value: string) => unknown;
};

export const TRUSTED_PROXY_HOPS = 'loopback';

export function configureTrustProxy(app: ExpressLikeApp) {
  app.set('trust proxy', TRUSTED_PROXY_HOPS);
}
