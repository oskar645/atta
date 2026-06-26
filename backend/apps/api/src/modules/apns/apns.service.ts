import { Injectable } from '@nestjs/common';

import { env } from '../../config/env';

@Injectable()
export class ApnsService {
  sendPlaceholder() {
    return {
      message: 'APNs placeholder created',
      bundleId: env.APNS_BUNDLE_ID,
      sandbox: env.APNS_USE_SANDBOX,
      sent: false,
    };
  }
}
