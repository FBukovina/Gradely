import { DatabaseSync } from "node:sqlite";
import { randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type {
  LinkedWebDevice,
  MobileChallengePreview,
  PairingChallengeStatus,
  SchoolProvider,
  WebSessionSummary,
} from "../shared/types.ts";
import {
  decryptProviderSecret,
  encryptProviderSecret,
  generateOpaqueToken,
  safeCompareHex,
  safeCompareTokenToHash,
  sanitizeProviderSecret,
  sha256Hex,
} from "./security.ts";

export const QR_CHALLENGE_TTL_MS = 60_000;
export const MAX_QR_FAILED_ATTEMPTS = 5;
export const WEB_SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days max
export const WEB_SESSION_IDLE_TTL_MS = 14 * 24 * 60 * 60 * 1000; // 14 days idle
export const WEB_SESSION_ROTATION_INTERVAL_MS = 15 * 60 * 1000; // Rotate cookie every 15m
export const ROTATED_TOKEN_GRACE_MS = 30_000; // 30s overlap for parallel browser tab fetches

export interface PairingChallengeRecord {
  id: string;
  qrSecretHash: string;
  browserBindingHash: string;
  userAgentFamily: string;
  browserName: string;
  osName: string;
  deviceLabel: string;
  ipHash: string | null;
  status: PairingChallengeStatus;
  scannerUserId: string | null;
  webSessionId: string | null;
  failedAttempts: number;
  createdAt: string;
  scannedAt: string | null;
  approvedAt: string | null;
  claimedAt: string | null;
  expiresAt: string;
}

export interface StoredWebSession {
  id: string;
  userId: string;
  linkedAccountId: string | null;
  provider: SchoolProvider;
  providerUserId: string | null;
  baseURL: string;
  studentName: string;
  className: string | null;
  schoolName: string | null;
  sessionTokenHash: string;
  previousSessionTokenHash: string | null;
  previousTokenGraceUntil: string | null;
  csrfTokenHash: string;
  userAgentFamily: string;
  browserName: string;
  osName: string;
  deviceLabel: string;
  createdAt: string;
  lastActiveAt: string;
  rotatedAt: string;
  expiresAt: string;
  revokedAt: string | null;
  revokeReason: string | null;
}

export interface ClaimedWebSessionResult {
  sessionToken: string;
  csrfToken: string;
  session: WebSessionSummary;
}

export interface AuthenticatedWebSessionResult {
  record: StoredWebSession;
  rotatedSessionToken?: string;
  rotatedCsrfToken?: string;
}

export interface ApproveChallengeInput {
  challengeId: string;
  qrSecret: string;
  userId: string;
  linkedAccountId?: string | null;
  provider: SchoolProvider;
  providerUserId?: string | null;
  baseURL: string;
  studentName: string;
  className?: string | null;
  schoolName?: string | null;
  tokenPayload: Record<string, unknown>;
}

export class PairingStoreError extends Error {
  constructor(
    message: string,
    public readonly statusCode: number,
    public readonly code: string,
  ) {
    super(message);
  }
}

// MARK: - Real-time Event Bus (SSE Push)

export type ChallengeEventPayload = {
  challengeId: string;
  status: PairingChallengeStatus;
  expiresAt: string;
};

export type SessionEventPayload = {
  sessionId: string;
  type: "revoked";
  reason: string;
};

export class PairingEventBus {
  private readonly challengeListeners = new Map<string, Set<(ev: ChallengeEventPayload) => void>>();
  private readonly sessionListeners = new Map<string, Set<(ev: SessionEventPayload) => void>>();

  subscribeChallenge(
    challengeId: string,
    listener: (ev: ChallengeEventPayload) => void,
  ): () => void {
    const set = this.challengeListeners.get(challengeId) ?? new Set();
    set.add(listener);
    this.challengeListeners.set(challengeId, set);
    return () => {
      const current = this.challengeListeners.get(challengeId);
      if (!current) return;
      current.delete(listener);
      if (current.size === 0) this.challengeListeners.delete(challengeId);
    };
  }

  emitChallenge(event: ChallengeEventPayload): void {
    const set = this.challengeListeners.get(event.challengeId);
    if (!set) return;
    for (const listener of set) {
      listener(event);
    }
  }

  subscribeSession(
    sessionId: string,
    listener: (ev: SessionEventPayload) => void,
  ): () => void {
    const set = this.sessionListeners.get(sessionId) ?? new Set();
    set.add(listener);
    this.sessionListeners.set(sessionId, set);
    return () => {
      const current = this.sessionListeners.get(sessionId);
      if (!current) return;
      current.delete(listener);
      if (current.size === 0) this.sessionListeners.delete(sessionId);
    };
  }

  emitSession(event: SessionEventPayload): void {
    const set = this.sessionListeners.get(event.sessionId);
    if (!set) return;
    for (const listener of set) {
      listener(event);
    }
  }
}

export interface WebDeviceStore {
  readonly events: PairingEventBus;
  createChallenge(params: {
    qrSecretHash: string;
    browserBindingHash: string;
    userAgentFamily: string;
    browserName: string;
    osName: string;
    deviceLabel: string;
    ipHash: string | null;
    now?: Date;
  }): Promise<PairingChallengeRecord>;
  getChallengeForBrowser(
    challengeId: string,
    browserSecret: string | undefined,
    now?: Date,
  ): Promise<PairingChallengeRecord>;
  inspectChallengeFromMobile(params: {
    challengeId: string;
    qrSecret: string;
    userId: string;
    now?: Date;
  }): Promise<MobileChallengePreview>;
  rejectChallengeFromMobile(params: {
    challengeId: string;
    qrSecret: string;
    userId: string;
    now?: Date;
  }): Promise<void>;
  approveChallengeFromMobile(
    input: ApproveChallengeInput,
    now?: Date,
  ): Promise<LinkedWebDevice>;
  claimChallengeForBrowser(params: {
    challengeId: string;
    browserSecret: string | undefined;
    userAgentFamily: string;
    now?: Date;
  }): Promise<ClaimedWebSessionResult>;
  authenticateWebSession(params: {
    sessionToken: string | undefined;
    userAgentFamily: string;
    allowRotation?: boolean;
    now?: Date;
  }): Promise<AuthenticatedWebSessionResult | null>;
  readSessionProviderSecret(sessionId: string): Promise<Record<string, unknown> | null>;
  updateSessionProviderSecret(
    sessionId: string,
    userId: string,
    payload: Record<string, unknown>,
  ): Promise<void>;
  touchSessionActivity(sessionId: string, now?: Date): Promise<void>;
  listDevicesForUser(userId: string, now?: Date): Promise<LinkedWebDevice[]>;
  revokeSessionByBrowser(sessionId: string, reason?: string, now?: Date): Promise<void>;
  revokeSessionForUser(userId: string, sessionId: string, reason?: string, now?: Date): Promise<boolean>;
  revokeAllSessionsForUser(userId: string, reason?: string, now?: Date): Promise<number>;
}

export function toWebSessionSummary(s: StoredWebSession): WebSessionSummary {
  return {
    id: s.id,
    provider: s.provider,
    studentName: s.studentName,
    className: s.className,
    schoolName: s.schoolName,
    baseURL: s.baseURL,
    browserName: s.browserName,
    osName: s.osName,
    deviceLabel: s.deviceLabel,
    firstLoginAt: s.createdAt,
    lastActiveAt: s.lastActiveAt,
    expiresAt: s.expiresAt,
  };
}

export function toLinkedWebDevice(s: StoredWebSession): LinkedWebDevice {
  return {
    id: s.id,
    provider: s.provider,
    studentName: s.studentName,
    className: s.className,
    schoolName: s.schoolName,
    browserName: s.browserName,
    osName: s.osName,
    deviceLabel: s.deviceLabel,
    firstLoginAt: s.createdAt,
    lastActiveAt: s.lastActiveAt,
    expiresAt: s.expiresAt,
  };
}

function userAgentOsCompatible(storedFamily: string, currentFamily: string): boolean {
  const storedOs = storedFamily.split(":")[1] ?? "";
  const currentOs = currentFamily.split(":")[1] ?? "";
  if (!storedOs || !currentOs || storedOs === "desktop" || currentOs === "desktop") return true;
  return storedOs === currentOs;
}

// MARK: - SQLite + AES-256-GCM Persistent Store (Self-hosted / Local / Test)

export class SqliteWebDeviceStore implements WebDeviceStore {
  public readonly events = new PairingEventBus();
  private readonly db: DatabaseSync;

  constructor(
    dbPath: string,
    private readonly providerSecretKey: string,
  ) {
    if (!providerSecretKey || providerSecretKey.length < 32) {
      throw new Error("PROVIDER_SECRET_KEY must be at least 32 characters");
    }
    if (dbPath !== ":memory:") {
      mkdirSync(dirname(dbPath), { recursive: true });
    }
    this.db = new DatabaseSync(dbPath);
    this.db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;");
    this.initSchema();
  }

  private initSchema(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS encrypted_secrets (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        ciphertext BLOB NOT NULL,
        created_at TEXT NOT NULL,
        rotated_at TEXT
      );

      CREATE TABLE IF NOT EXISTS web_sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        linked_account_id TEXT,
        provider TEXT NOT NULL,
        provider_user_id TEXT,
        base_url TEXT NOT NULL,
        student_name TEXT NOT NULL,
        class_name TEXT,
        school_name TEXT,
        secret_id TEXT REFERENCES encrypted_secrets(id) ON DELETE SET NULL,
        session_token_hash TEXT NOT NULL UNIQUE,
        previous_session_token_hash TEXT,
        previous_token_grace_until TEXT,
        csrf_token_hash TEXT NOT NULL,
        user_agent_family TEXT NOT NULL,
        browser_name TEXT NOT NULL,
        os_name TEXT NOT NULL,
        device_label TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_active_at TEXT NOT NULL,
        rotated_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        revoked_at TEXT,
        revoke_reason TEXT
      );

      CREATE TABLE IF NOT EXISTS web_pairing_challenges (
        id TEXT PRIMARY KEY,
        qr_secret_hash TEXT NOT NULL UNIQUE,
        browser_binding_hash TEXT NOT NULL,
        user_agent_family TEXT NOT NULL,
        browser_name TEXT NOT NULL,
        os_name TEXT NOT NULL,
        device_label TEXT NOT NULL,
        ip_hash TEXT,
        status TEXT NOT NULL,
        scanner_user_id TEXT,
        web_session_id TEXT REFERENCES web_sessions(id) ON DELETE SET NULL,
        failed_attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        scanned_at TEXT,
        approved_at TEXT,
        claimed_at TEXT,
        expires_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        event_name TEXT NOT NULL,
        metadata_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    `);
  }

  private mapChallenge(row: Record<string, any>): PairingChallengeRecord {
    return {
      id: String(row.id),
      qrSecretHash: String(row.qr_secret_hash),
      browserBindingHash: String(row.browser_binding_hash),
      userAgentFamily: String(row.user_agent_family),
      browserName: String(row.browser_name),
      osName: String(row.os_name),
      deviceLabel: String(row.device_label),
      ipHash: row.ip_hash ? String(row.ip_hash) : null,
      status: row.status as PairingChallengeStatus,
      scannerUserId: row.scanner_user_id ? String(row.scanner_user_id) : null,
      webSessionId: row.web_session_id ? String(row.web_session_id) : null,
      failedAttempts: Number(row.failed_attempts ?? 0),
      createdAt: String(row.created_at),
      scannedAt: row.scanned_at ? String(row.scanned_at) : null,
      approvedAt: row.approved_at ? String(row.approved_at) : null,
      claimedAt: row.claimed_at ? String(row.claimed_at) : null,
      expiresAt: String(row.expires_at),
    };
  }

  private mapSession(row: Record<string, any>): StoredWebSession {
    return {
      id: String(row.id),
      userId: String(row.user_id),
      linkedAccountId: row.linked_account_id ? String(row.linked_account_id) : null,
      provider: row.provider as SchoolProvider,
      providerUserId: row.provider_user_id ? String(row.provider_user_id) : null,
      baseURL: String(row.base_url),
      studentName: String(row.student_name),
      className: row.class_name ? String(row.class_name) : null,
      schoolName: row.school_name ? String(row.school_name) : null,
      sessionTokenHash: String(row.session_token_hash),
      previousSessionTokenHash: row.previous_session_token_hash
        ? String(row.previous_session_token_hash)
        : null,
      previousTokenGraceUntil: row.previous_token_grace_until
        ? String(row.previous_token_grace_until)
        : null,
      csrfTokenHash: String(row.csrf_token_hash),
      userAgentFamily: String(row.user_agent_family),
      browserName: String(row.browser_name),
      osName: String(row.os_name),
      deviceLabel: String(row.device_label),
      createdAt: String(row.created_at),
      lastActiveAt: String(row.last_active_at),
      rotatedAt: String(row.rotated_at),
      expiresAt: String(row.expires_at),
      revokedAt: row.revoked_at ? String(row.revoked_at) : null,
      revokeReason: row.revoke_reason ? String(row.revoke_reason) : null,
    };
  }

  async createChallenge(params: {
    qrSecretHash: string;
    browserBindingHash: string;
    userAgentFamily: string;
    browserName: string;
    osName: string;
    deviceLabel: string;
    ipHash: string | null;
    now?: Date;
  }): Promise<PairingChallengeRecord> {
    const now = params.now ?? new Date();
    const id = randomUUID();
    const createdAt = now.toISOString();
    const expiresAt = new Date(now.getTime() + QR_CHALLENGE_TTL_MS).toISOString();

    this.db
      .prepare(
        `INSERT INTO web_pairing_challenges (
          id, qr_secret_hash, browser_binding_hash, user_agent_family,
          browser_name, os_name, device_label, ip_hash, status,
          failed_attempts, created_at, expires_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, ?, ?)`,
      )
      .run(
        id,
        params.qrSecretHash,
        params.browserBindingHash,
        params.userAgentFamily,
        params.browserName,
        params.osName,
        params.deviceLabel,
        params.ipHash,
        createdAt,
        expiresAt,
      );

    const row = this.db
      .prepare("SELECT * FROM web_pairing_challenges WHERE id = ?")
      .get(id) as Record<string, any>;
    return this.mapChallenge(row);
  }

  async getChallengeForBrowser(
    challengeId: string,
    browserSecret: string | undefined,
    now: Date = new Date(),
  ): Promise<PairingChallengeRecord> {
    const row = this.db
      .prepare("SELECT * FROM web_pairing_challenges WHERE id = ?")
      .get(challengeId) as Record<string, any> | undefined;
    if (!row) {
      throw new PairingStoreError("Challenge not found", 404, "challenge_not_found");
    }
    const challenge = this.mapChallenge(row);
    if (!safeCompareTokenToHash(browserSecret, challenge.browserBindingHash)) {
      throw new PairingStoreError(
        "Pairing challenge is bound to a different browser session",
        403,
        "browser_binding_mismatch",
      );
    }
    if (
      Date.parse(challenge.expiresAt) <= now.getTime() &&
      (challenge.status === "pending" || challenge.status === "scanned")
    ) {
      this.db
        .prepare("UPDATE web_pairing_challenges SET status = 'expired' WHERE id = ?")
        .run(challenge.id);
      challenge.status = "expired";
    }
    return challenge;
  }

  private verifyChallengeSecretFromMobile(
    challengeId: string,
    qrSecret: string,
    now: Date,
  ): PairingChallengeRecord {
    const row = this.db
      .prepare("SELECT * FROM web_pairing_challenges WHERE id = ?")
      .get(challengeId) as Record<string, any> | undefined;
    if (!row) {
      throw new PairingStoreError(
        "QR code is invalid or has expired.",
        404,
        "challenge_not_found",
      );
    }
    const challenge = this.mapChallenge(row);
    if (
      Date.parse(challenge.expiresAt) <= now.getTime() ||
      challenge.status === "expired" ||
      challenge.status === "claimed" ||
      challenge.status === "rejected" ||
      challenge.failedAttempts >= MAX_QR_FAILED_ATTEMPTS
    ) {
      if (challenge.status === "pending" || challenge.status === "scanned") {
        this.db
          .prepare("UPDATE web_pairing_challenges SET status = 'expired' WHERE id = ?")
          .run(challenge.id);
        this.events.emitChallenge({
          challengeId: challenge.id,
          status: "expired",
          expiresAt: challenge.expiresAt,
        });
      }
      throw new PairingStoreError(
        "QR code has expired. Scan the refreshed QR code on your computer.",
        410,
        "challenge_expired",
      );
    }

    if (!safeCompareTokenToHash(qrSecret, challenge.qrSecretHash)) {
      const attempts = challenge.failedAttempts + 1;
      const nextStatus: PairingChallengeStatus =
        attempts >= MAX_QR_FAILED_ATTEMPTS ? "expired" : challenge.status;
      this.db
        .prepare(
          "UPDATE web_pairing_challenges SET failed_attempts = ?, status = ? WHERE id = ?",
        )
        .run(attempts, nextStatus, challenge.id);
      if (nextStatus === "expired") {
        this.events.emitChallenge({
          challengeId: challenge.id,
          status: "expired",
          expiresAt: challenge.expiresAt,
        });
      }
      throw new PairingStoreError("Invalid QR pairing token.", 403, "invalid_qr_secret");
    }

    return challenge;
  }

  async inspectChallengeFromMobile(params: {
    challengeId: string;
    qrSecret: string;
    userId: string;
    now?: Date;
  }): Promise<MobileChallengePreview> {
    const now = params.now ?? new Date();
    const challenge = this.verifyChallengeSecretFromMobile(
      params.challengeId,
      params.qrSecret,
      now,
    );

    if (challenge.scannerUserId && challenge.scannerUserId !== params.userId) {
      throw new PairingStoreError(
        "This QR code was already scanned by another account.",
        409,
        "challenge_already_scanned",
      );
    }
    if (challenge.status !== "pending" && challenge.status !== "scanned") {
      throw new PairingStoreError(
        "This QR code has already been used.",
        409,
        "challenge_already_used",
      );
    }

    const scannedAt = challenge.scannedAt ?? now.toISOString();
    this.db
      .prepare(
        `UPDATE web_pairing_challenges
         SET status = 'scanned', scanner_user_id = ?, scanned_at = ?
         WHERE id = ? AND status IN ('pending', 'scanned')`,
      )
      .run(params.userId, scannedAt, challenge.id);

    this.events.emitChallenge({
      challengeId: challenge.id,
      status: "scanned",
      expiresAt: challenge.expiresAt,
    });

    return {
      challengeId: challenge.id,
      browserName: challenge.browserName,
      osName: challenge.osName,
      deviceLabel: challenge.deviceLabel,
      createdAt: challenge.createdAt,
      expiresAt: challenge.expiresAt,
    };
  }

  async rejectChallengeFromMobile(params: {
    challengeId: string;
    qrSecret: string;
    userId: string;
    now?: Date;
  }): Promise<void> {
    const now = params.now ?? new Date();
    const challenge = this.verifyChallengeSecretFromMobile(
      params.challengeId,
      params.qrSecret,
      now,
    );
    if (challenge.scannerUserId && challenge.scannerUserId !== params.userId) {
      throw new PairingStoreError("Challenge belongs to another scanner", 409, "scanner_mismatch");
    }
    this.db
      .prepare(
        "UPDATE web_pairing_challenges SET status = 'rejected' WHERE id = ? AND status IN ('pending', 'scanned')",
      )
      .run(challenge.id);
    this.events.emitChallenge({
      challengeId: challenge.id,
      status: "rejected",
      expiresAt: challenge.expiresAt,
    });
  }

  async approveChallengeFromMobile(
    input: ApproveChallengeInput,
    now: Date = new Date(),
  ): Promise<LinkedWebDevice> {
    const challenge = this.verifyChallengeSecretFromMobile(
      input.challengeId,
      input.qrSecret,
      now,
    );

    if (challenge.status !== "scanned" || challenge.scannerUserId !== input.userId) {
      throw new PairingStoreError(
        "Scan the QR code again before approving.",
        409,
        "challenge_not_scanned",
      );
    }

    const secretId = randomUUID();
    const sessionId = randomUUID();
    const nowIso = now.toISOString();
    const expiresAt = new Date(now.getTime() + WEB_SESSION_TTL_MS).toISOString();
    const sanitized = sanitizeProviderSecret({
      ...input.tokenPayload,
      provider: input.provider,
      baseURL: input.baseURL,
    });
    const ciphertext = encryptProviderSecret(sanitized, this.providerSecretKey);

    // Unclaimed placeholder token hash until the bound browser redeems the challenge.
    const unclaimedHash = sha256Hex(`unclaimed:${randomUUID()}:${generateOpaqueToken(32)}`);
    const unclaimedCsrf = sha256Hex(`unclaimed-csrf:${randomUUID()}`);

    this.db.exec("BEGIN IMMEDIATE");
    try {
      const currentRow = this.db
        .prepare("SELECT status, scanner_user_id FROM web_pairing_challenges WHERE id = ?")
        .get(challenge.id) as Record<string, any> | undefined;
      if (
        !currentRow ||
        currentRow.status !== "scanned" ||
        currentRow.scanner_user_id !== input.userId
      ) {
        throw new PairingStoreError("QR challenge was already processed.", 409, "challenge_race");
      }

      this.db
        .prepare(
          "INSERT INTO encrypted_secrets (id, user_id, ciphertext, created_at) VALUES (?, ?, ?, ?)",
        )
        .run(secretId, input.userId, ciphertext, nowIso);

      this.db
        .prepare(
          `INSERT INTO web_sessions (
            id, user_id, linked_account_id, provider, provider_user_id, base_url,
            student_name, class_name, school_name, secret_id,
            session_token_hash, csrf_token_hash, user_agent_family,
            browser_name, os_name, device_label,
            created_at, last_active_at, rotated_at, expires_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        )
        .run(
          sessionId,
          input.userId,
          input.linkedAccountId ?? null,
          input.provider,
          input.providerUserId ?? null,
          input.baseURL,
          input.studentName.trim().slice(0, 120) || "Student",
          input.className?.trim().slice(0, 40) ?? null,
          input.schoolName?.trim().slice(0, 160) ?? null,
          secretId,
          unclaimedHash,
          unclaimedCsrf,
          challenge.userAgentFamily,
          challenge.browserName,
          challenge.osName,
          challenge.deviceLabel,
          nowIso,
          nowIso,
          nowIso,
          expiresAt,
        );

      this.db
        .prepare(
          `UPDATE web_pairing_challenges
           SET status = 'approved', web_session_id = ?, approved_at = ?
           WHERE id = ? AND status = 'scanned'`,
        )
        .run(sessionId, nowIso, challenge.id);

      this.db
        .prepare(
          "INSERT INTO audit_logs (id, user_id, event_name, metadata_json, created_at) VALUES (?, ?, ?, ?, ?)",
        )
        .run(
          randomUUID(),
          input.userId,
          "web_session_linked",
          JSON.stringify({
            webSessionId: sessionId,
            browserName: challenge.browserName,
            osName: challenge.osName,
          }),
          nowIso,
        );

      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }

    this.events.emitChallenge({
      challengeId: challenge.id,
      status: "approved",
      expiresAt: challenge.expiresAt,
    });

    const created = this.db
      .prepare("SELECT * FROM web_sessions WHERE id = ?")
      .get(sessionId) as Record<string, any>;
    return toLinkedWebDevice(this.mapSession(created));
  }

  async claimChallengeForBrowser(params: {
    challengeId: string;
    browserSecret: string | undefined;
    userAgentFamily: string;
    now?: Date;
  }): Promise<ClaimedWebSessionResult> {
    const now = params.now ?? new Date();
    const nowIso = now.toISOString();

    let committed = false;
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const row = this.db
        .prepare("SELECT * FROM web_pairing_challenges WHERE id = ?")
        .get(params.challengeId) as Record<string, any> | undefined;
      if (!row) {
        throw new PairingStoreError("Challenge not found", 404, "challenge_not_found");
      }
      const challenge = this.mapChallenge(row);

      if (!safeCompareTokenToHash(params.browserSecret, challenge.browserBindingHash)) {
        throw new PairingStoreError(
          "Pairing challenge is bound to a different browser session",
          403,
          "browser_binding_mismatch",
        );
      }

      if (challenge.status === "claimed" || challenge.claimedAt != null) {
        // Replay defense: commit the session revocation before throwing 409!
        if (challenge.webSessionId) {
          this.revokeSessionInternal(challenge.webSessionId, "challenge_replay_detected", nowIso);
        }
        this.db.exec("COMMIT");
        committed = true;
        throw new PairingStoreError(
          "Pairing challenge has already been claimed.",
          409,
          "challenge_already_claimed",
        );
      }

      if (Date.parse(challenge.expiresAt) + 30_000 <= now.getTime()) {
        throw new PairingStoreError("Pairing challenge expired.", 410, "challenge_expired");
      }

      if (challenge.status !== "approved" || !challenge.webSessionId) {
        throw new PairingStoreError(
          "Pairing challenge has not been approved yet.",
          409,
          "challenge_not_approved",
        );
      }

      if (!userAgentOsCompatible(challenge.userAgentFamily, params.userAgentFamily)) {
        throw new PairingStoreError(
          "Browser environment changed during pairing.",
          403,
          "environment_mismatch",
        );
      }

      const sessionRow = this.db
        .prepare("SELECT * FROM web_sessions WHERE id = ? AND revoked_at IS NULL")
        .get(challenge.webSessionId) as Record<string, any> | undefined;
      if (!sessionRow) {
        throw new PairingStoreError("Web session was revoked.", 410, "session_revoked");
      }

      const sessionToken = generateOpaqueToken(32);
      const csrfToken = generateOpaqueToken(32);

      this.db
        .prepare(
          `UPDATE web_pairing_challenges
           SET status = 'claimed', claimed_at = ?
           WHERE id = ? AND status = 'approved'`,
        )
        .run(nowIso, challenge.id);

      this.db
        .prepare(
          `UPDATE web_sessions
           SET session_token_hash = ?, csrf_token_hash = ?, last_active_at = ?, rotated_at = ?
           WHERE id = ?`,
        )
        .run(
          sha256Hex(sessionToken),
          sha256Hex(csrfToken),
          nowIso,
          nowIso,
          challenge.webSessionId,
        );

      const updatedSession = this.db
        .prepare("SELECT * FROM web_sessions WHERE id = ?")
        .get(challenge.webSessionId) as Record<string, any>;

      this.db.exec("COMMIT");
      committed = true;

      return {
        sessionToken,
        csrfToken,
        session: toWebSessionSummary(this.mapSession(updatedSession)),
      };
    } catch (error) {
      if (!committed) {
        this.db.exec("ROLLBACK");
      }
      throw error;
    }
  }

  async authenticateWebSession(params: {
    sessionToken: string | undefined;
    userAgentFamily: string;
    allowRotation?: boolean;
    now?: Date;
  }): Promise<AuthenticatedWebSessionResult | null> {
    if (!params.sessionToken) return null;
    const now = params.now ?? new Date();
    const nowMs = now.getTime();
    const nowIso = now.toISOString();
    const incomingHash = sha256Hex(params.sessionToken);

    let row = this.db
      .prepare(
        "SELECT * FROM web_sessions WHERE session_token_hash = ? AND revoked_at IS NULL",
      )
      .get(incomingHash) as Record<string, any> | undefined;

    let matchedPreviousGrace = false;
    if (!row) {
      row = this.db
        .prepare(
          "SELECT * FROM web_sessions WHERE previous_session_token_hash = ? AND revoked_at IS NULL",
        )
        .get(incomingHash) as Record<string, any> | undefined;
      if (row) {
        const graceUntil = row.previous_token_grace_until
          ? Date.parse(String(row.previous_token_grace_until))
          : 0;
        if (graceUntil > nowMs) {
          matchedPreviousGrace = true;
        } else {
          // Replaying a rotated-out session token after grace period -> suspected token theft; revoke session!
          this.revokeSessionInternal(String(row.id), "rotated_token_reuse", nowIso);
          return null;
        }
      }
    }

    if (!row) return null;
    const session = this.mapSession(row);

    // Check absolute expiry and idle expiry
    if (
      Date.parse(session.expiresAt) <= nowMs ||
      Date.parse(session.lastActiveAt) + WEB_SESSION_IDLE_TTL_MS <= nowMs
    ) {
      this.revokeSessionInternal(session.id, "session_expired", nowIso);
      return null;
    }

    // Session hijacking mitigation: prevent cross-OS cookie replay
    if (!userAgentOsCompatible(session.userAgentFamily, params.userAgentFamily)) {
      return null;
    }

    // Rotate session cookie token periodically on primary token hits
    const needsRotation =
      params.allowRotation === true &&
      !matchedPreviousGrace &&
      Date.parse(session.rotatedAt) + WEB_SESSION_ROTATION_INTERVAL_MS <= nowMs;

    if (needsRotation) {
      const nextToken = generateOpaqueToken(32);
      const nextCsrf = generateOpaqueToken(32);
      const graceUntil = new Date(nowMs + ROTATED_TOKEN_GRACE_MS).toISOString();
      this.db
        .prepare(
          `UPDATE web_sessions
           SET previous_session_token_hash = session_token_hash,
               previous_token_grace_until = ?,
               session_token_hash = ?,
               csrf_token_hash = ?,
               rotated_at = ?,
               last_active_at = ?
           WHERE id = ? AND revoked_at IS NULL`,
        )
        .run(
          graceUntil,
          sha256Hex(nextToken),
          sha256Hex(nextCsrf),
          nowIso,
          nowIso,
          session.id,
        );

      const refreshed = this.db
        .prepare("SELECT * FROM web_sessions WHERE id = ?")
        .get(session.id) as Record<string, any>;
      return {
        record: this.mapSession(refreshed),
        rotatedSessionToken: nextToken,
        rotatedCsrfToken: nextCsrf,
      };
    }

    return { record: session };
  }

  async readSessionProviderSecret(sessionId: string): Promise<Record<string, unknown> | null> {
    const row = this.db
      .prepare(
        `SELECT s.ciphertext
         FROM web_sessions ws
         JOIN encrypted_secrets s ON s.id = ws.secret_id
         WHERE ws.id = ? AND ws.revoked_at IS NULL`,
      )
      .get(sessionId) as { ciphertext: Uint8Array } | undefined;
    if (!row?.ciphertext) return null;
    return decryptProviderSecret(row.ciphertext, this.providerSecretKey);
  }

  async updateSessionProviderSecret(
    sessionId: string,
    userId: string,
    payload: Record<string, unknown>,
  ): Promise<void> {
    const row = this.db
      .prepare(
        "SELECT secret_id FROM web_sessions WHERE id = ? AND user_id = ? AND revoked_at IS NULL",
      )
      .get(sessionId, userId) as { secret_id: string | null } | undefined;
    if (!row?.secret_id) {
      throw new PairingStoreError("Session is no longer active", 401, "session_revoked");
    }
    const ciphertext = encryptProviderSecret(payload, this.providerSecretKey);
    this.db
      .prepare(
        "UPDATE encrypted_secrets SET ciphertext = ?, rotated_at = ? WHERE id = ? AND user_id = ?",
      )
      .run(ciphertext, new Date().toISOString(), row.secret_id, userId);
  }

  async touchSessionActivity(sessionId: string, now: Date = new Date()): Promise<void> {
    const row = this.db
      .prepare("SELECT last_active_at FROM web_sessions WHERE id = ? AND revoked_at IS NULL")
      .get(sessionId) as { last_active_at: string } | undefined;
    if (!row) return;
    if (now.getTime() - Date.parse(row.last_active_at) < 30_000) return;
    this.db
      .prepare("UPDATE web_sessions SET last_active_at = ? WHERE id = ?")
      .run(now.toISOString(), sessionId);
  }

  async listDevicesForUser(userId: string, now: Date = new Date()): Promise<LinkedWebDevice[]> {
    const rows = this.db
      .prepare(
        `SELECT * FROM web_sessions
         WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?
         ORDER BY last_active_at DESC`,
      )
      .all(userId, now.toISOString()) as Array<Record<string, any>>;
    return rows.map((r) => toLinkedWebDevice(this.mapSession(r)));
  }

  private revokeSessionInternal(sessionId: string, reason: string, nowIso: string): boolean {
    const existing = this.db
      .prepare("SELECT id, user_id, secret_id, revoked_at FROM web_sessions WHERE id = ?")
      .get(sessionId) as Record<string, any> | undefined;
    if (!existing) return false;

    this.db
      .prepare(
        `UPDATE web_sessions
         SET revoked_at = COALESCE(revoked_at, ?),
             revoke_reason = COALESCE(revoke_reason, ?),
             secret_id = NULL,
             previous_session_token_hash = NULL,
             previous_token_grace_until = NULL
         WHERE id = ?`,
      )
      .run(nowIso, reason, sessionId);

    if (existing.secret_id) {
      this.db
        .prepare("DELETE FROM encrypted_secrets WHERE id = ? AND user_id = ?")
        .run(String(existing.secret_id), String(existing.user_id));
    }

    this.events.emitSession({
      sessionId,
      type: "revoked",
      reason,
    });
    return true;
  }

  async revokeSessionByBrowser(
    sessionId: string,
    reason = "browser_logout",
    now: Date = new Date(),
  ): Promise<void> {
    this.revokeSessionInternal(sessionId, reason, now.toISOString());
  }

  async revokeSessionForUser(
    userId: string,
    sessionId: string,
    reason = "mobile_revoked",
    now: Date = new Date(),
  ): Promise<boolean> {
    const row = this.db
      .prepare("SELECT id FROM web_sessions WHERE id = ? AND user_id = ?")
      .get(sessionId, userId) as { id: string } | undefined;
    if (!row) return false;
    return this.revokeSessionInternal(sessionId, reason, now.toISOString());
  }

  async revokeAllSessionsForUser(
    userId: string,
    reason = "mobile_revoked_all",
    now: Date = new Date(),
  ): Promise<number> {
    const nowIso = now.toISOString();
    const active = this.db
      .prepare("SELECT id FROM web_sessions WHERE user_id = ? AND revoked_at IS NULL")
      .all(userId) as Array<{ id: string }>;
    for (const item of active) {
      this.revokeSessionInternal(item.id, reason, nowIso);
    }
    return active.length;
  }
}

// MARK: - Supabase PostgreSQL Store (Production Cloud Integration)

export class SupabaseWebDeviceStore implements WebDeviceStore {
  public readonly events = new PairingEventBus();
  public readonly supabase: SupabaseClient;

  constructor(
    supabaseUrl: string,
    serviceRoleKey: string,
    private readonly providerSecretKey: string,
  ) {
    if (!providerSecretKey || providerSecretKey.length < 32) {
      throw new Error("PROVIDER_SECRET_KEY must be at least 32 characters");
    }
    this.supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
  }

  private mapChallenge(row: Record<string, any>): PairingChallengeRecord {
    return {
      id: String(row.id),
      qrSecretHash: String(row.qr_secret_hash),
      browserBindingHash: String(row.browser_binding_hash),
      userAgentFamily: String(row.user_agent_family),
      browserName: String(row.browser_name),
      osName: String(row.os_name),
      deviceLabel: String(row.device_label),
      ipHash: row.ip_hash ?? null,
      status: row.status as PairingChallengeStatus,
      scannerUserId: row.scanner_user_id ?? null,
      webSessionId: row.web_session_id ?? null,
      failedAttempts: Number(row.failed_attempts ?? 0),
      createdAt: String(row.created_at),
      scannedAt: row.scanned_at ?? null,
      approvedAt: row.approved_at ?? null,
      claimedAt: row.claimed_at ?? null,
      expiresAt: String(row.expires_at),
    };
  }

  private mapSession(row: Record<string, any>): StoredWebSession {
    return {
      id: String(row.id),
      userId: String(row.user_id),
      linkedAccountId: row.linked_account_id ?? null,
      provider: row.provider as SchoolProvider,
      providerUserId: row.provider_user_id ?? null,
      baseURL: String(row.base_url),
      studentName: String(row.student_name),
      className: row.class_name ?? null,
      schoolName: row.school_name ?? null,
      sessionTokenHash: String(row.session_token_hash),
      previousSessionTokenHash: row.previous_session_token_hash ?? null,
      previousTokenGraceUntil: row.previous_token_grace_until ?? null,
      csrfTokenHash: String(row.csrf_token_hash),
      userAgentFamily: String(row.user_agent_family),
      browserName: String(row.browser_name),
      osName: String(row.os_name),
      deviceLabel: String(row.device_label),
      createdAt: String(row.created_at),
      lastActiveAt: String(row.last_active_at),
      rotatedAt: String(row.rotated_at),
      expiresAt: String(row.expires_at),
      revokedAt: row.revoked_at ?? null,
      revokeReason: row.revoke_reason ?? null,
    };
  }

  async createChallenge(params: {
    qrSecretHash: string;
    browserBindingHash: string;
    userAgentFamily: string;
    browserName: string;
    osName: string;
    deviceLabel: string;
    ipHash: string | null;
    now?: Date;
  }): Promise<PairingChallengeRecord> {
    const now = params.now ?? new Date();
    const expiresAt = new Date(now.getTime() + QR_CHALLENGE_TTL_MS).toISOString();
    const { data, error } = await this.supabase
      .from("web_pairing_challenges")
      .insert({
        qr_secret_hash: params.qrSecretHash,
        browser_binding_hash: params.browserBindingHash,
        user_agent_family: params.userAgentFamily,
        browser_name: params.browserName,
        os_name: params.osName,
        device_label: params.deviceLabel,
        ip_hash: params.ipHash,
        status: "pending",
        expires_at: expiresAt,
      })
      .select("*")
      .single();
    if (error || !data) throw new Error(error?.message ?? "Failed to create QR challenge");
    return this.mapChallenge(data);
  }

  async getChallengeForBrowser(
    challengeId: string,
    browserSecret: string | undefined,
    now: Date = new Date(),
  ): Promise<PairingChallengeRecord> {
    const { data, error } = await this.supabase
      .from("web_pairing_challenges")
      .select("*")
      .eq("id", challengeId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    if (!data) throw new PairingStoreError("Challenge not found", 404, "challenge_not_found");
    const challenge = this.mapChallenge(data);
    if (!safeCompareTokenToHash(browserSecret, challenge.browserBindingHash)) {
      throw new PairingStoreError(
        "Pairing challenge is bound to a different browser session",
        403,
        "browser_binding_mismatch",
      );
    }
    if (
      Date.parse(challenge.expiresAt) <= now.getTime() &&
      (challenge.status === "pending" || challenge.status === "scanned")
    ) {
      await this.supabase
        .from("web_pairing_challenges")
        .update({ status: "expired" })
        .eq("id", challenge.id);
      challenge.status = "expired";
    }
    return challenge;
  }

  private async verifyChallengeSecret(
    challengeId: string,
    qrSecret: string,
    now: Date,
  ): Promise<PairingChallengeRecord> {
    const { data, error } = await this.supabase
      .from("web_pairing_challenges")
      .select("*")
      .eq("id", challengeId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    if (!data) {
      throw new PairingStoreError("QR code is invalid or has expired.", 404, "challenge_not_found");
    }
    const challenge = this.mapChallenge(data);
    if (
      Date.parse(challenge.expiresAt) <= now.getTime() ||
      challenge.status === "expired" ||
      challenge.status === "claimed" ||
      challenge.status === "rejected" ||
      challenge.failedAttempts >= MAX_QR_FAILED_ATTEMPTS
    ) {
      throw new PairingStoreError("QR code has expired.", 410, "challenge_expired");
    }
    if (!safeCompareHex(sha256Hex(qrSecret), challenge.qrSecretHash)) {
      const attempts = challenge.failedAttempts + 1;
      const nextStatus: PairingChallengeStatus =
        attempts >= MAX_QR_FAILED_ATTEMPTS ? "expired" : challenge.status;
      await this.supabase
        .from("web_pairing_challenges")
        .update({ failed_attempts: attempts, status: nextStatus })
        .eq("id", challenge.id);
      throw new PairingStoreError("Invalid QR pairing token.", 403, "invalid_qr_secret");
    }
    return challenge;
  }

  async inspectChallengeFromMobile(params: {
    challengeId: string;
    qrSecret: string;
    userId: string;
    now?: Date;
  }): Promise<MobileChallengePreview> {
    const now = params.now ?? new Date();
    const challenge = await this.verifyChallengeSecret(params.challengeId, params.qrSecret, now);
    if (challenge.scannerUserId && challenge.scannerUserId !== params.userId) {
      throw new PairingStoreError("QR code already scanned", 409, "challenge_already_scanned");
    }
    if (challenge.status !== "pending" && challenge.status !== "scanned") {
      throw new PairingStoreError("QR code already used", 409, "challenge_already_used");
    }
    const { data, error } = await this.supabase
      .from("web_pairing_challenges")
      .update({
        status: "scanned",
        scanner_user_id: params.userId,
        scanned_at: challenge.scannedAt ?? now.toISOString(),
      })
      .eq("id", challenge.id)
      .in("status", ["pending", "scanned"])
      .select("*")
      .maybeSingle();
    if (error || !data) {
      throw new PairingStoreError("QR code is no longer available", 409, "challenge_unavailable");
    }
    const updated = this.mapChallenge(data);
    this.events.emitChallenge({
      challengeId: updated.id,
      status: "scanned",
      expiresAt: updated.expiresAt,
    });
    return {
      challengeId: updated.id,
      browserName: updated.browserName,
      osName: updated.osName,
      deviceLabel: updated.deviceLabel,
      createdAt: updated.createdAt,
      expiresAt: updated.expiresAt,
    };
  }

  async rejectChallengeFromMobile(params: {
    challengeId: string;
    qrSecret: string;
    userId: string;
    now?: Date;
  }): Promise<void> {
    const now = params.now ?? new Date();
    const challenge = await this.verifyChallengeSecret(params.challengeId, params.qrSecret, now);
    if (challenge.scannerUserId && challenge.scannerUserId !== params.userId) {
      throw new PairingStoreError("Challenge belongs to another scanner", 409, "scanner_mismatch");
    }
    await this.supabase
      .from("web_pairing_challenges")
      .update({ status: "rejected" })
      .eq("id", challenge.id)
      .in("status", ["pending", "scanned"]);
    this.events.emitChallenge({
      challengeId: challenge.id,
      status: "rejected",
      expiresAt: challenge.expiresAt,
    });
  }

  async approveChallengeFromMobile(
    input: ApproveChallengeInput,
    now: Date = new Date(),
  ): Promise<LinkedWebDevice> {
    const challenge = await this.verifyChallengeSecret(input.challengeId, input.qrSecret, now);
    if (challenge.status !== "scanned" || challenge.scannerUserId !== input.userId) {
      throw new PairingStoreError("Scan the QR code again before approving.", 409, "challenge_not_scanned");
    }

    const sanitized = sanitizeProviderSecret({
      ...input.tokenPayload,
      provider: input.provider,
      baseURL: input.baseURL,
    });
    const { data: secretId, error: secretError } = await this.supabase.rpc("store_provider_secret", {
      p_user_id: input.userId,
      p_payload: sanitized,
      p_key: this.providerSecretKey,
    });
    if (secretError || !secretId) throw new Error(secretError?.message ?? "Could not store secret");

    const placeholderHash = sha256Hex(`unclaimed:${randomUUID()}:${generateOpaqueToken(32)}`);
    const placeholderCsrf = sha256Hex(`unclaimed-csrf:${randomUUID()}`);

    const { data: sessionRow, error: sessionError } = await this.supabase
      .from("web_sessions")
      .insert({
        user_id: input.userId,
        linked_account_id: input.linkedAccountId ?? null,
        provider: input.provider,
        provider_user_id: input.providerUserId ?? null,
        base_url: input.baseURL,
        student_name: input.studentName.trim().slice(0, 120) || "Student",
        class_name: input.className?.trim().slice(0, 40) ?? null,
        school_name: input.schoolName?.trim().slice(0, 160) ?? null,
        secret_id: secretId,
        session_token_hash: placeholderHash,
        csrf_token_hash: placeholderCsrf,
        user_agent_family: challenge.userAgentFamily,
        browser_name: challenge.browserName,
        os_name: challenge.osName,
        device_label: challenge.deviceLabel,
        expires_at: new Date(now.getTime() + WEB_SESSION_TTL_MS).toISOString(),
      })
      .select("*")
      .single();
    if (sessionError || !sessionRow) {
      throw new Error(sessionError?.message ?? "Failed to create web session");
    }

    const { data: approvedRow, error: approveError } = await this.supabase
      .from("web_pairing_challenges")
      .update({
        status: "approved",
        web_session_id: sessionRow.id,
        approved_at: now.toISOString(),
      })
      .eq("id", challenge.id)
      .eq("status", "scanned")
      .eq("scanner_user_id", input.userId)
      .select("*")
      .maybeSingle();

    if (approveError || !approvedRow) {
      await this.supabase.rpc("revoke_web_session", {
        p_user_id: input.userId,
        p_session_id: sessionRow.id,
        p_reason: "challenge_race_cleanup",
      });
      throw new PairingStoreError("QR challenge could not be approved", 409, "challenge_race");
    }

    await this.supabase.from("account_audit_logs").insert({
      user_id: input.userId,
      linked_account_id: input.linkedAccountId ?? null,
      event_name: "web_session_linked",
      metadata: {
        web_session_id: sessionRow.id,
        browser_name: challenge.browserName,
        os_name: challenge.osName,
      },
    });

    this.events.emitChallenge({
      challengeId: challenge.id,
      status: "approved",
      expiresAt: challenge.expiresAt,
    });

    return toLinkedWebDevice(this.mapSession(sessionRow));
  }

  async claimChallengeForBrowser(params: {
    challengeId: string;
    browserSecret: string | undefined;
    userAgentFamily: string;
    now?: Date;
  }): Promise<ClaimedWebSessionResult> {
    const now = params.now ?? new Date();
    const nowIso = now.toISOString();
    const challenge = await this.getChallengeForBrowser(
      params.challengeId,
      params.browserSecret,
      now,
    );

    if (challenge.status === "claimed" || challenge.claimedAt != null) {
      if (challenge.webSessionId && challenge.scannerUserId) {
        await this.revokeSessionForUser(
          challenge.scannerUserId,
          challenge.webSessionId,
          "challenge_replay_detected",
          now,
        );
      }
      throw new PairingStoreError("Pairing challenge already claimed", 409, "challenge_already_claimed");
    }

    if (Date.parse(challenge.expiresAt) + 30_000 <= now.getTime()) {
      throw new PairingStoreError("Pairing challenge expired", 410, "challenge_expired");
    }
    if (challenge.status !== "approved" || !challenge.webSessionId) {
      throw new PairingStoreError("Challenge not approved yet", 409, "challenge_not_approved");
    }
    if (!userAgentOsCompatible(challenge.userAgentFamily, params.userAgentFamily)) {
      throw new PairingStoreError("Browser environment mismatch", 403, "environment_mismatch");
    }

    const { data: claimed, error: claimErr } = await this.supabase
      .from("web_pairing_challenges")
      .update({ status: "claimed", claimed_at: nowIso })
      .eq("id", challenge.id)
      .eq("status", "approved")
      .is("claimed_at", null)
      .select("*")
      .maybeSingle();

    if (claimErr || !claimed) {
      throw new PairingStoreError("Pairing challenge already claimed", 409, "challenge_already_claimed");
    }

    const sessionToken = generateOpaqueToken(32);
    const csrfToken = generateOpaqueToken(32);
    const { data: updatedSession, error: sessErr } = await this.supabase
      .from("web_sessions")
      .update({
        session_token_hash: sha256Hex(sessionToken),
        csrf_token_hash: sha256Hex(csrfToken),
        last_active_at: nowIso,
        rotated_at: nowIso,
      })
      .eq("id", challenge.webSessionId)
      .is("revoked_at", null)
      .select("*")
      .maybeSingle();

    if (sessErr || !updatedSession) {
      throw new PairingStoreError("Web session is unavailable", 410, "session_revoked");
    }

    return {
      sessionToken,
      csrfToken,
      session: toWebSessionSummary(this.mapSession(updatedSession)),
    };
  }

  async authenticateWebSession(params: {
    sessionToken: string | undefined;
    userAgentFamily: string;
    allowRotation?: boolean;
    now?: Date;
  }): Promise<AuthenticatedWebSessionResult | null> {
    if (!params.sessionToken) return null;
    const now = params.now ?? new Date();
    const nowMs = now.getTime();
    const nowIso = now.toISOString();
    const incomingHash = sha256Hex(params.sessionToken);

    let { data: row } = await this.supabase
      .from("web_sessions")
      .select("*")
      .eq("session_token_hash", incomingHash)
      .is("revoked_at", null)
      .maybeSingle();

    let matchedPreviousGrace = false;
    if (!row) {
      const prev = await this.supabase
        .from("web_sessions")
        .select("*")
        .eq("previous_session_token_hash", incomingHash)
        .is("revoked_at", null)
        .maybeSingle();
      if (prev.data) {
        const graceUntil = prev.data.previous_token_grace_until
          ? Date.parse(String(prev.data.previous_token_grace_until))
          : 0;
        if (graceUntil > nowMs) {
          row = prev.data;
          matchedPreviousGrace = true;
        } else {
          await this.revokeSessionForUser(
            String(prev.data.user_id),
            String(prev.data.id),
            "rotated_token_reuse",
            now,
          );
          return null;
        }
      }
    }

    if (!row) return null;
    const session = this.mapSession(row);

    if (
      Date.parse(session.expiresAt) <= nowMs ||
      Date.parse(session.lastActiveAt) + WEB_SESSION_IDLE_TTL_MS <= nowMs
    ) {
      await this.revokeSessionForUser(session.userId, session.id, "session_expired", now);
      return null;
    }

    if (!userAgentOsCompatible(session.userAgentFamily, params.userAgentFamily)) {
      return null;
    }

    const needsRotation =
      params.allowRotation === true &&
      !matchedPreviousGrace &&
      Date.parse(session.rotatedAt) + WEB_SESSION_ROTATION_INTERVAL_MS <= nowMs;

    if (needsRotation) {
      const nextToken = generateOpaqueToken(32);
      const nextCsrf = generateOpaqueToken(32);
      const graceUntil = new Date(nowMs + ROTATED_TOKEN_GRACE_MS).toISOString();
      const { data: rotated } = await this.supabase
        .from("web_sessions")
        .update({
          previous_session_token_hash: session.sessionTokenHash,
          previous_token_grace_until: graceUntil,
          session_token_hash: sha256Hex(nextToken),
          csrf_token_hash: sha256Hex(nextCsrf),
          rotated_at: nowIso,
          last_active_at: nowIso,
        })
        .eq("id", session.id)
        .is("revoked_at", null)
        .select("*")
        .maybeSingle();
      if (rotated) {
        return {
          record: this.mapSession(rotated),
          rotatedSessionToken: nextToken,
          rotatedCsrfToken: nextCsrf,
        };
      }
    }

    return { record: session };
  }

  async readSessionProviderSecret(sessionId: string): Promise<Record<string, unknown> | null> {
    const { data: session } = await this.supabase
      .from("web_sessions")
      .select("secret_id")
      .eq("id", sessionId)
      .is("revoked_at", null)
      .maybeSingle();
    if (!session?.secret_id) return null;
    const { data: secret, error } = await this.supabase.rpc("read_provider_secret", {
      p_secret_id: session.secret_id,
      p_key: this.providerSecretKey,
    });
    if (error || !secret) return null;
    return secret as Record<string, unknown>;
  }

  async updateSessionProviderSecret(
    sessionId: string,
    userId: string,
    payload: Record<string, unknown>,
  ): Promise<void> {
    const { data: session } = await this.supabase
      .from("web_sessions")
      .select("secret_id")
      .eq("id", sessionId)
      .eq("user_id", userId)
      .is("revoked_at", null)
      .maybeSingle();
    if (!session?.secret_id) {
      throw new PairingStoreError("Session is no longer active", 401, "session_revoked");
    }
    const { error } = await this.supabase.rpc("update_provider_secret", {
      p_secret_id: session.secret_id,
      p_user_id: userId,
      p_payload: sanitizeProviderSecret(payload),
      p_key: this.providerSecretKey,
    });
    if (error) throw new Error(error.message);
  }

  async touchSessionActivity(sessionId: string, now: Date = new Date()): Promise<void> {
    await this.supabase
      .from("web_sessions")
      .update({ last_active_at: now.toISOString() })
      .eq("id", sessionId)
      .is("revoked_at", null);
  }

  async listDevicesForUser(userId: string, now: Date = new Date()): Promise<LinkedWebDevice[]> {
    const { data, error } = await this.supabase
      .from("web_sessions")
      .select("*")
      .eq("user_id", userId)
      .is("revoked_at", null)
      .gt("expires_at", now.toISOString())
      .order("last_active_at", { ascending: false });
    if (error) throw new Error(error.message);
    return (data ?? []).map((r) => toLinkedWebDevice(this.mapSession(r)));
  }

  async revokeSessionByBrowser(
    sessionId: string,
    reason = "browser_logout",
    _now: Date = new Date(),
  ): Promise<void> {
    const { data } = await this.supabase
      .from("web_sessions")
      .select("user_id")
      .eq("id", sessionId)
      .maybeSingle();
    if (!data?.user_id) return;
    await this.revokeSessionForUser(String(data.user_id), sessionId, reason);
  }

  async revokeSessionForUser(
    userId: string,
    sessionId: string,
    reason = "mobile_revoked",
    _now: Date = new Date(),
  ): Promise<boolean> {
    const { data, error } = await this.supabase.rpc("revoke_web_session", {
      p_user_id: userId,
      p_session_id: sessionId,
      p_reason: reason,
    });
    if (error) throw new Error(error.message);
    if (data) {
      this.events.emitSession({ sessionId, type: "revoked", reason });
    }
    return Boolean(data);
  }

  async revokeAllSessionsForUser(
    userId: string,
    reason = "mobile_revoked_all",
    now: Date = new Date(),
  ): Promise<number> {
    const active = await this.listDevicesForUser(userId, now);
    const { data, error } = await this.supabase.rpc("revoke_all_web_sessions", {
      p_user_id: userId,
      p_reason: reason,
    });
    if (error) throw new Error(error.message);
    for (const dev of active) {
      this.events.emitSession({ sessionId: dev.id, type: "revoked", reason });
    }
    return Number(data ?? 0);
  }
}
