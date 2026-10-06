import type { NextConfig } from "next";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseHostname = supabaseUrl ? new URL(supabaseUrl).hostname : null;

// Next.js 16 blocks image optimization from private/loopback IPs by default.
// Local Supabase Storage is served from loopback, so allow it only when the
// configured Supabase host is itself a loopback address. A public deployment
// keeps the default SSRF protection.
const isLoopbackSupabase =
  supabaseHostname === "localhost" ||
  supabaseHostname === "127.0.0.1" ||
  supabaseHostname === "::1" ||
  supabaseHostname === "[::1]";

const supabaseStoragePattern = supabaseUrl
  ? {
      protocol: new URL(supabaseUrl).protocol.replace(":", "") as
        | "http"
        | "https",
      hostname: new URL(supabaseUrl).hostname,
      port: new URL(supabaseUrl).port,
      search: "",
    }
  : null;

const nextConfig: NextConfig = {
  images: supabaseStoragePattern
    ? {
        dangerouslyAllowLocalIP: isLoopbackSupabase,
        remotePatterns: [
          {
            ...supabaseStoragePattern,
            pathname: "/storage/v1/object/public/product-images/**",
          },
          {
            ...supabaseStoragePattern,
            pathname: "/storage/v1/object/public/avatars/**",
          },
        ],
      }
    : undefined,
};

export default nextConfig;
