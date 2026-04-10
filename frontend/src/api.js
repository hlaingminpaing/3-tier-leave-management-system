const host = globalThis.location?.hostname || "";
const isLocalhost = host === "localhost" || host === "127.0.0.1";
const isAlbHost = host.includes("elb.amazonaws.com");

// Single source of truth for API routing:
// - Local frontend -> local backend on :3000/api
// - AWS ALB hostname -> direct ALB /api
// - EKS ingress / gateway / nginx proxy -> same-origin /api
export const API_URL = isLocalhost
  ? "http://localhost:3000/api"
  : isAlbHost
    ? `${globalThis.location.protocol}//${globalThis.location.host}/api`
    : "/api";
