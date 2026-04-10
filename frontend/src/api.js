// Direct ALB URL to the backend route prefix
export const API_URL =
  globalThis.env?.API_URL ||
  import.meta.env.VITE_API_URL ||
  "http://leave-system-alb-1763611467.ap-southeast-7.elb.amazonaws.com/api";

// EKS Ingress / Gateway URL
// Use a relative path so the browser sends API requests through the same host ingress:
// export const API_URL = globalThis.env?.API_URL || import.meta.env.VITE_API_URL || "/api";

