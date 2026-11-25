// Shared domain models mirroring Gradey's Swift models (BakalariModels, TimetableModels, HomeworkModels).

export type SchoolProvider = "bakalari" | "eduPage";

export type GradeBand = "excellent" | "good" | "average" | "poor" | "neutral";

export type AbsenceRiskLevel =
  | "unavailable"
  | "safe"
  | "watch"
  | "high"
  | "overLimit";

export type LessonChangeKind =
  | "none"
  | "canceled"
  | "substitution"
  | "roomChanged"
  | "added";

export type DayType =
  | "workDay"
  | "weekend"
  | "celebration"
  | "holiday"
  | "directorDay"
  | "undefined";

export type TimetableKind = "weekly" | "permanent";

export interface ClassInfo {
  id: string;
  abbrev: string;
  name: string | null;
}

export interface UserProfile {
  userUID: string;
  fullName: string;
  userClass: ClassInfo | null;
  schoolName: string | null;
  userType: string;
  userTypeText: string;
  studyYear: number | null;
}

export interface MarkItem {
  id: string;
  markDate: string;
  editDate: string | null;
  caption: string | null;
  theme: string | null;
  markText: string;
  teacherID: string | null;
  type: string;
  typeNote: string | null;
  weight: number | null;
  subjectID: string;
  isNew: boolean;
  isPoints: boolean;
  calculatedMarkText: string | null;
  classRankText: string | null;
  pointsText: string | null;
  maxPoints: number | null;
}

export interface SubjectInfo {
  id: string;
  abbrev: string;
  name: string;
}

export interface SubjectMarks {
  id: string;
  subjectInfo: SubjectInfo;
  marks: MarkItem[];
  averageText: string | null;
  temporaryMark: string | null;
  subjectNote: string | null;
  temporaryMarkNote: string | null;
  pointsOnly: boolean;
  markPredictionEnabled: boolean;
}

export interface MarksSnapshot {
  subjects: SubjectMarks[];
}

export interface AbsenceDay {
  date: string;
  unsolved: number;
  ok: number;
  missed: number;
  late: number;
  soon: number;
  school: number;
  distanceTeaching: number;
}

export interface AbsencePerSubject {
  subjectName: string;
  lessonsCount: number;
  base: number;
  late: number;
  soon: number;
  school: number;
  distanceTeaching: number;
}

export interface AbsenceSnapshot {
  percentageThreshold: number | null;
  absences: AbsenceDay[];
  absencesPerSubject: AbsencePerSubject[];
}

export interface TimetableHour {
  id: number;
  caption: string;
  beginTime: string;
  endTime: string;
}

export interface TimetableChange {
  changeSubject: string | null;
  day: string | null;
  hours: string | null;
  changeType: string | null;
  description: string | null;
  time: string | null;
  typeAbbrev: string | null;
  typeName: string | null;
}

export interface ScheduledLesson {
  id: string;
  hour: TimetableHour;
  subjectID: string | null;
  subjectName: string | null;
  subjectAbbrev: string | null;
  teacherName: string | null;
  teacherAbbrev: string | null;
  roomName: string | null;
  roomAbbrev: string | null;
  groups: string[];
  cycles: string[];
  theme: string | null;
  hasHomework: boolean;
  homeworkIDs: string[];
  change: TimetableChange | null;
  changeKind: LessonChangeKind;
}

export interface ScheduledDay {
  id: string;
  date: string | null;
  dayOfWeek: number;
  dayType: DayType;
  dayDescription: string;
  lessons: ScheduledLesson[];
  isToday: boolean;
}

export interface TimetableWeek {
  weekStart: string;
  kind: TimetableKind;
  hours: TimetableHour[];
  days: ScheduledDay[];
}

export interface SchoolAttachment {
  id: string;
  name: string;
  size: number | null;
}

export interface HomeworkItem {
  id: string;
  subjectID: string | null;
  subjectName: string | null;
  subjectAbbrev: string | null;
  teacherName: string | null;
  title: string;
  content: string;
  notice: string | null;
  assignedOn: string | null;
  dueOn: string | null;
  isDone: boolean;
  isClosed: boolean;
  isElectronic: boolean;
  attachments: SchoolAttachment[];
}

export interface HomeworkSnapshot {
  homeworks: HomeworkItem[];
}

// MARK: - QR Pairing & Linked Web Devices

export type PairingChallengeStatus =
  | "pending"
  | "scanned"
  | "approved"
  | "claimed"
  | "expired"
  | "rejected";

export interface QRChallengeCreateResponse {
  challengeId: string;
  qrPayload: string;
  expiresAt: string;
  ttlSeconds: number;
}

export interface QRChallengeStatusResponse {
  challengeId: string;
  status: PairingChallengeStatus;
  expiresAt: string;
}

export interface MobileChallengePreview {
  challengeId: string;
  browserName: string;
  osName: string;
  deviceLabel: string;
  createdAt: string;
  expiresAt: string;
}

export interface LinkedWebDevice {
  id: string;
  provider: SchoolProvider;
  studentName: string;
  className: string | null;
  schoolName: string | null;
  browserName: string;
  osName: string;
  deviceLabel: string;
  firstLoginAt: string;
  lastActiveAt: string;
  expiresAt: string;
}

export interface WebSessionSummary {
  id: string;
  provider: SchoolProvider;
  studentName: string;
  className: string | null;
  schoolName: string | null;
  baseURL: string;
  browserName: string;
  osName: string;
  deviceLabel: string;
  firstLoginAt: string;
  lastActiveAt: string;
  expiresAt: string;
}

export interface WebAuthStateResponse {
  authenticated: boolean;
  csrfToken?: string;
  session?: WebSessionSummary;
}

export interface SchoolOverviewResponse {
  fetchedAt: string;
  user: UserProfile | null;
  marks: MarksSnapshot;
  absences: AbsenceSnapshot;
  timetable: TimetableWeek | null;
  homeworks: HomeworkSnapshot;
  partialErrors: Partial<Record<"user" | "marks" | "absences" | "timetable" | "homeworks", string>>;
}
