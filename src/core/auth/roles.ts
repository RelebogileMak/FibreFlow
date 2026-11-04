export const UserRole = {
  Admin: 'admin',
  Manager: 'manager',
  Sales: 'sales',
  Dispatcher: 'dispatcher',
  Technician: 'technician',
} as const;

export type UserRole = (typeof UserRole)[keyof typeof UserRole];
