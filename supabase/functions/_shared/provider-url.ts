const forbiddenHostSuffixes = [
  ".localhost",
  ".local",
  ".internal",
  ".home",
  ".lan",
  ".test",
  ".invalid",
];

export function requireSafeProviderURL(value: unknown, label = "Provider URL") {
  if (
    typeof value !== "string" || value.trim().length === 0 ||
    value.length > 2048
  ) {
    throw new Error(`${label} is invalid`);
  }

  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    throw new Error(`${label} is invalid`);
  }

  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    (url.port && url.port !== "443") ||
    url.search ||
    url.hash
  ) {
    throw new Error(`${label} must be a credential-free HTTPS URL`);
  }

  const hostname = url.hostname
    .toLowerCase()
    .replace(/^\[/, "")
    .replace(/\]$/, "")
    .replace(/\.$/, "");

  if (
    !hostname ||
    hostname === "localhost" ||
    forbiddenHostSuffixes.some((suffix) => hostname.endsWith(suffix)) ||
    isForbiddenIPv4(hostname) ||
    isForbiddenIPv6(hostname) ||
    (!hostname.includes(".") && !hostname.includes(":"))
  ) {
    throw new Error(`${label} must use a public host`);
  }

  return url.toString();
}

export function providerURLsMatch(first: string, second: string) {
  const firstURL = new URL(first);
  const secondURL = new URL(second);
  return firstURL.origin === secondURL.origin &&
    normalizedPath(firstURL.pathname) === normalizedPath(secondURL.pathname);
}

function normalizedPath(path: string) {
  const normalized = path.replace(/\/{2,}/g, "/").replace(/\/+$/, "");
  return normalized || "/";
}

function isForbiddenIPv4(hostname: string) {
  const parts = hostname.split(".");
  if (parts.length !== 4 || parts.some((part) => !/^\d{1,3}$/.test(part))) {
    return false;
  }

  const octets = parts.map(Number);
  if (octets.some((part) => part < 0 || part > 255)) return true;

  const [first, second, third] = octets;
  return first === 0 ||
    first === 10 ||
    first === 127 ||
    first >= 224 ||
    (first === 100 && second >= 64 && second <= 127) ||
    (first === 169 && second === 254) ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && second === 168) ||
    (first === 192 && second === 0 && (third === 0 || third === 2)) ||
    (first === 198 && (second === 18 || second === 19)) ||
    (first === 198 && second === 51 && third === 100) ||
    (first === 203 && second === 0 && third === 113);
}

function isForbiddenIPv6(hostname: string) {
  if (!hostname.includes(":")) return false;

  const normalized = hostname.toLowerCase();
  return normalized === "::" ||
    normalized === "::1" ||
    normalized.startsWith("::ffff:") ||
    normalized.startsWith("fc") ||
    normalized.startsWith("fd") ||
    /^fe[89ab]/.test(normalized) ||
    normalized.startsWith("fec") ||
    normalized.startsWith("fed") ||
    normalized.startsWith("fee") ||
    normalized.startsWith("fef");
}
