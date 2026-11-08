type RequestSample = {
  at: number;
  durationMs: number;
  failed: boolean;
};

const requestSamples: RequestSample[] = [];
const REQUEST_WINDOW_MS = 5 * 60 * 1000;

const trim = (now: number) => {
  while (requestSamples.length > 0 && now - requestSamples[0].at > REQUEST_WINDOW_MS) {
    requestSamples.shift();
  }
};

export const recordHttpRequest = (statusCode: number, durationMs: number) => {
  const now = Date.now();
  requestSamples.push({
    at: now,
    durationMs: Math.max(0, durationMs),
    failed: statusCode >= 500,
  });
  trim(now);
};

export const currentHttpMetrics = () => {
  const now = Date.now();
  trim(now);
  const lastMinute = requestSamples.filter((item) => now - item.at <= 60_000);
  const failed = lastMinute.filter((item) => item.failed).length;
  const averageMs = lastMinute.length === 0
    ? 0
    : lastMinute.reduce((sum, item) => sum + item.durationMs, 0) / lastMinute.length;
  return {
    requestsPerMinute: lastMinute.length,
    errorsPerMinute: failed,
    errorPercent: lastMinute.length === 0 ? 0 : (failed / lastMinute.length) * 100,
    averageResponseMs: Math.round(averageMs),
  };
};
