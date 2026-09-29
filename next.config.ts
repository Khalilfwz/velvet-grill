import type { NextConfig } from "next";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;

const nextConfig: NextConfig = {
  images: supabaseUrl
    ? {
        remotePatterns: [
          {
            protocol: new URL(supabaseUrl).protocol.replace(":", "") as
              | "http"
              | "https",
            hostname: new URL(supabaseUrl).hostname,
            port: new URL(supabaseUrl).port,
            pathname: "/storage/v1/object/public/product-images/**",
            search: "",
          },
        ],
      }
    : undefined,
};

export default nextConfig;
