import {
  defaultNotificationPreferences,
  type NotificationPreferencesRow,
} from "./notification-delivery.ts";

export function toLinkedAccount(row: Record<string, unknown>) {
  return {
    id: row.id,
    provider: row.provider,
    providerUserID: row.provider_user_id,
    displayName: row.display_name,
    schoolName: row.school_name,
    canteenName: row.canteen_name,
    status: row.status,
    notificationsEnabled: row.notifications_enabled,
    lastPolledAt: row.last_polled_at,
    lastSyncedAt: row.last_synced_at,
    actionRequiredReason: row.action_required_reason,
  };
}

export function toNotificationPreferences(
  row?:
    | Partial<
      NotificationPreferencesRow & { user_id: string; updated_at: string }
    >
    | null,
) {
  return {
    new_marks_enabled: row?.new_marks_enabled ??
      defaultNotificationPreferences.new_marks_enabled,
    lock_screen_detail: row?.lock_screen_detail ??
      defaultNotificationPreferences.lock_screen_detail,
    quiet_hours_enabled: row?.quiet_hours_enabled ??
      defaultNotificationPreferences.quiet_hours_enabled,
    quiet_hours_start_minute: row?.quiet_hours_start_minute ??
      defaultNotificationPreferences.quiet_hours_start_minute,
    quiet_hours_end_minute: row?.quiet_hours_end_minute ??
      defaultNotificationPreferences.quiet_hours_end_minute,
    quiet_hours_time_zone: row?.quiet_hours_time_zone ??
      defaultNotificationPreferences.quiet_hours_time_zone,
    updated_at: row?.updated_at ?? null,
  };
}
