export interface ExistingSchoolAccount {
  id: string;
  provider_user_id?: string | null;
  display_name: string;
  school_name?: string | null;
}

export interface RelinkSchoolAccountInput {
  provider_user_id?: string | null;
  display_name?: string | null;
  school_name?: string | null;
}

export function relinkSchoolAccountPatch(
  account: ExistingSchoolAccount,
  input: RelinkSchoolAccountInput,
  secretID: string,
  baseURL: string,
  now: Date,
) {
  return {
    provider_user_id: input.provider_user_id ?? account.provider_user_id,
    base_url: baseURL,
    display_name: input.display_name || account.display_name,
    school_name: input.school_name ?? account.school_name,
    status: "active",
    secret_id: secretID,
    failure_count: 0,
    action_required_reason: null,
    last_synced_at: now.toISOString(),
    next_poll_at: new Date(now.getTime() + 15 * 60 * 1000).toISOString(),
    updated_at: now.toISOString(),
  };
}
