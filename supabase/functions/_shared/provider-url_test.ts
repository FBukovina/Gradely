import { providerURLsMatch, requireSafeProviderURL } from "./provider-url.ts";

Deno.test("provider URLs allow public HTTPS provider endpoints", () => {
  const values = [
    "https://demo.bakalari.cz/",
    "https://school.edupage.org/",
    "https://wss5.strava.cz/WSStravne5_15/WSStravne5.svc",
    "https://[2606:4700:4700::1111]/",
  ];

  for (const value of values) {
    if (requireSafeProviderURL(value) !== value) {
      throw new Error(`Expected unchanged safe URL: ${value}`);
    }
  }
});

Deno.test("provider URLs reject unsafe schemes and network targets", () => {
  const values = [
    "http://school.example.com/",
    "https://localhost/",
    "https://127.0.0.1/",
    "https://10.0.0.1/",
    "https://169.254.169.254/",
    "https://[::1]/",
    "https://[fd00::1]/",
    "https://user:password@example.com/",
    "https://example.com/?redirect=internal",
  ];

  for (const value of values) {
    let rejected = false;
    try {
      requireSafeProviderURL(value);
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error(`Expected unsafe URL rejection: ${value}`);
  }
});

Deno.test("provider URL matching normalizes only trailing slashes", () => {
  if (
    !providerURLsMatch(
      "https://school.example.com/application",
      "https://school.example.com/application/",
    )
  ) {
    throw new Error("Expected equivalent provider paths to match");
  }

  if (
    providerURLsMatch(
      "https://school.example.com/application-a/",
      "https://school.example.com/application-b/",
    )
  ) {
    throw new Error("Expected different provider paths not to match");
  }
});
