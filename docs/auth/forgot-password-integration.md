# Forgot Password — Frontend Integration Guide

## Overview

Two endpoints handle the forgot/reset password flow. The forgot endpoint never reveals whether an email exists. The reset endpoint returns a JWT on success so the user is automatically logged in after resetting.

---

## Endpoint 1 — Request a Reset Link

```
POST /api/v1/auth/password/forgot
Content-Type: application/json
```

### Request body

```json
{
  "email": "ion@example.com"
}
```

### Response — always 200

```json
{
  "message": "If that email is registered, a reset link has been sent."
}
```

Always show this message regardless of whether the email exists. This prevents user enumeration.

### Error — missing email (422)

```json
{ "error": "email is required" }
```

### Rate limit

3 requests per IP per minute. On the 4th request the server returns `429`:

```json
{ "error": "Too many requests. Please try again later." }
```

---

## Endpoint 2 — Reset the Password

The reset link sent by email points to your frontend (configured via `FRONTEND_URL` on the server). The URL looks like:

```
https://your-app.com/reset-password?token=<token>
```

Extract the `token` query param and submit it with the new password:

```
POST /api/v1/auth/password/reset
Content-Type: application/json
```

### Request body

```json
{
  "token": "<token from URL>",
  "password": "NewPassword1!"
}
```

Password must be at least 8 characters.

### Success — 200

```json
{
  "jwt": "<jwt-token>",
  "user": {
    "id": 1,
    "first_name": "Ion",
    "last_name": "Popescu",
    "email": "ion@example.com",
    "avatar_url": null,
    "phone_number": null,
    "church_name": null,
    "city": null
  }
}
```

Store the JWT and treat the user as logged in — no separate login step needed.

### Errors

| Status | Body | Meaning |
|--------|------|---------|
| `422` | `{ "error": "token and password are required" }` | Missing param |
| `422` | `{ "error": "Invalid or expired reset token" }` | Token not found or expired (tokens expire after 1 hour) |
| `422` | `{ "error": "Password is too short (minimum is 8 characters)" }` | Password too short |

---

## Registration — language param

When registering a new user, pass the user's preferred language so the API sends future emails (e.g. password reset) in the correct language:

```
POST /api/v1/auth/registration
Content-Type: application/json
```

```json
{
  "first_name": "Ion",
  "email": "ion@example.com",
  "password": "SecurePass1!",
  "language": "ro-RO"
}
```

`language` is optional. Any BCP-47 code is accepted (`ro-RO`, `en-US`, etc.). If omitted, the reset email defaults to English.

---

## Full Flow (React example)

### Step 1 — Forgot password form

```tsx
async function requestReset(email: string) {
  const res = await fetch('/api/v1/auth/password/forgot', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email }),
  });
  // Always show the same message — don't branch on response content
  return res.ok;
}
```

### Step 2 — Reset password form (at `/reset-password`)

```tsx
async function resetPassword(token: string, password: string) {
  const res = await fetch('/api/v1/auth/password/reset', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token, password }),
  });

  const data = await res.json();

  if (!res.ok) {
    throw new Error(data.error);
  }

  // Store JWT and user
  localStorage.setItem('jwt', data.jwt);
  return data.user;
}

// On mount — extract token from URL
const token = new URLSearchParams(window.location.search).get('token') ?? '';
```

### Step 3 — Handle the token page

```tsx
export default function ResetPasswordPage() {
  const token = new URLSearchParams(window.location.search).get('token');

  if (!token) {
    return <p>Invalid reset link.</p>;
  }

  async function handleSubmit(password: string) {
    try {
      const user = await resetPassword(token!, password);
      // Redirect to dashboard
    } catch (err: any) {
      setError(err.message); // e.g. "Invalid or expired reset token"
    }
  }

  return <ResetForm onSubmit={handleSubmit} />;
}
```

---

## Notes

- Reset tokens expire after **1 hour**.
- Tokens are single-use — invalidated immediately after a successful reset.
- After a successful reset the JWT is valid for **30 days** (same as login).
- The reset email is sent in Romanian if the user's `language` starts with `ro`; otherwise English.
