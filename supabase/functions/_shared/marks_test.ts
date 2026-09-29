import { markCandidates } from "./marks.ts";

const accountID = "00000000-0000-4000-8000-000000000020";

Deno.test("mark candidates cover every mark in response order", async () => {
  const candidates = await markCandidates("bakalari", accountID, [
    {
      Subject: { Id: "MAT", Abbrev: "M", Name: "Mathematics" },
      Marks: [{ Id: "A1", MarkText: "1" }, { Id: "A2", MarkText: "3" }],
    },
    {
      Subject: { Id: "CJ", Abbrev: "Čj", Name: "Czech" },
      Marks: [{ Id: "B1", MarkText: "2-" }],
    },
  ]);

  const summary = candidates.map((candidate) =>
    [candidate.subjectID, candidate.providerMarkID, candidate.markText, candidate.subjectAbbrev].join("|")
  );
  const expected = ["MAT|A1|1|M", "MAT|A2|3|M", "CJ|B1|2-|Čj"];
  if (JSON.stringify(summary) !== JSON.stringify(expected)) {
    throw new Error(`Unexpected candidates: ${JSON.stringify(summary)}`);
  }
  if (candidates[0].fingerprint !== `bakalari:${accountID}:MAT:provider:A1`) {
    throw new Error(`Unexpected fingerprint: ${candidates[0].fingerprint}`);
  }
});

Deno.test("mark candidates collapse duplicate fingerprints within one response", async () => {
  const duplicate = { MarkDate: "2026-09-29", MarkText: "1", Caption: "Test" };
  const candidates = await markCandidates("eduPage", accountID, [
    { Subject: { Id: "FY" }, Marks: [duplicate, { ...duplicate }, { ...duplicate, MarkText: "2" }] },
  ]);

  if (candidates.length !== 2) {
    throw new Error(`Expected two unique marks, got ${candidates.length}`);
  }
  if (candidates.some((candidate) => candidate.source !== "content_hash" || candidate.providerMarkID !== null)) {
    throw new Error("Marks without provider IDs must use content fingerprints");
  }
});

Deno.test("mark candidates tolerate missing subject metadata", async () => {
  const [candidate] = await markCandidates("bakalari", accountID, [{ Marks: [{ Id: "X" }] }]);

  if (
    candidate.subjectID !== "unknown-subject" || candidate.subjectAbbrev !== null ||
    candidate.subjectName !== null || candidate.markText !== ""
  ) {
    throw new Error(`Unexpected fallback candidate: ${JSON.stringify(candidate)}`);
  }
});
