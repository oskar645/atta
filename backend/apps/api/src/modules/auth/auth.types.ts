export interface AuthTokenPayload {
  sub: string;
  sessionId: string;
  type: 'access' | 'refresh';
  email?: string | null;
  role: 'user' | 'admin';
}

export interface AuthenticatedUser {
  userId: string;
  sessionId: string;
  email?: string | null;
  role: 'user' | 'admin';
}
