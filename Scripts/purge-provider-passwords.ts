/**
 * Operator-only cleanup. Default is dry-run; --apply rewrites existing secrets.
 * Required environment: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PROVIDER_SECRET_KEY.
 * Neither plaintext school data nor backend keys are printed.
 */
if (Deno.args.some((arg) => arg !== "--apply")) {
  console.error("Usage: purge-provider-passwords.ts [--apply]");
  Deno.exit(1);
}

const apply = Deno.args.includes("--apply");
const configuration = [
  "SUPABASE_URL",
  "SUPABASE_SERVICE_ROLE_KEY",
  "PROVIDER_SECRET_KEY",
]
  .map((name) => Deno.env.get(name));
if (configuration.some((value) => !value)) {
  console.error(
    "Set SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, and PROVIDER_SECRET_KEY securely in the environment.",
  );
  Deno.exit(1);
}
const [baseURL, serviceKey, encryptionKey] = configuration as [
  string,
  string,
  string,
];
const url = new URL(baseURL);
if (
  url.protocol !== "https:" || url.username || url.password || url.search ||
  url.hash
) {
  console.error("SUPABASE_URL must be a credential-free HTTPS URL.");
  Deno.exit(1);
}

async function cleanup(shouldApply: boolean) {
  const response = await fetch(
    new URL("/rest/v1/rpc/purge_provider_passwords", url),
    {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_key: encryptionKey, p_apply: shouldApply }),
      redirect: "error",
    },
  );
  if (!response.ok) {
    throw new Error(
      `Cleanup request failed (HTTP ${response.status}); inspect configuration without logging secret values.`,
    );
  }
  const data = await response.json();
  for (const field of ["scanned", "needing_cleanup", "updated"]) {
    if (!Number.isInteger(data?.[field]) || data[field] < 0) {
      throw new Error("Unexpected cleanup result");
    }
  }
  return {
    scanned: data.scanned,
    needing_cleanup: data.needing_cleanup,
    updated: data.updated,
  };
}

try {
  console.log(
    JSON.stringify({
      mode: apply ? "apply" : "dry-run",
      ...await cleanup(apply),
    }),
  );
  if (apply) {
    const verification = await cleanup(false);
    console.log(JSON.stringify({ mode: "verification", ...verification }));
    if (verification.needing_cleanup !== 0) Deno.exit(2);
  }
} catch {
  // Do not print server responses, network details, or secrets on failure.
  console.error(
    "Cleanup or verification failed. Check access, the migration, and encryption-key configuration. A successful verification is required before claiming removal.",
  );
  Deno.exit(1);
}
