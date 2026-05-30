# Email Preferences Integration Guide

This guide explains how to implement email preferences — marketing consent at signup, a settings page toggle panel, and an unsubscribe page for email footer links.

**Base URL:** `https://api.casatamplarului.ro` (or `http://localhost:3000` for local dev)

---

## How it works

Every auth response (`POST /registration`, `POST /session`, `GET /me`, all OAuth sign-ins) now includes an `email_preferences` object inside `user`:

```json
{
  "jwt": "...",
  "user": {
    "id": 42,
    "first_name": "Ion",
    "email_preferences": {
      "marketing_emails": false,
      "payment_reminder_emails": false,
      "payment_receipt_emails": false,
      "event_reminder_emails": false,
      "event_update_emails": false
    }
  }
}
```

All five fields are always present and are booleans. Use this to pre-populate the settings page without an extra API call.

### Email categories

| Key | What it controls | Toggleable |
|---|---|---|
| `marketing_emails` | Promotional emails, upcoming events | ✅ opt-in at signup |
| `payment_reminder_emails` | Payment due reminders | ✅ |
| `payment_receipt_emails` | Payment confirmation / invoices | ✅ |
| `event_reminder_emails` | "Your event is in X days" reminders | ✅ |
| `event_update_emails` | Speaker, schedule, or info updates for booked events | ✅ |

Transactional emails (booking confirmation, password reset, event cancellation) are always sent regardless of preferences and do not appear in this object.

---

## API Endpoints

### 1. Signup — capture marketing consent

Add `marketing_emails: true` to the existing registration request body. The field is optional; it defaults to `false`.

```
POST /api/v1/auth/registration
Content-Type: application/json
```

```json
{
  "first_name": "Ion",
  "email": "ion@example.com",
  "password": "MyPassword1!",
  "marketing_emails": true
}
```

The response `user.email_preferences.marketing_emails` will reflect the value you sent.

---

### 2. Update preferences — settings page

```
PATCH /api/v1/auth/me/email_preferences
Authorization: Bearer <jwt>
Content-Type: application/json
```

Send only the fields you want to change. Unmentioned fields are left as-is.

**Request body (any combination of the five fields):**

```json
{
  "marketing_emails": true,
  "event_reminder_emails": false
}
```

**Success (200):**

```json
{
  "email_preferences": {
    "marketing_emails": true,
    "payment_reminder_emails": false,
    "payment_receipt_emails": false,
    "event_reminder_emails": false,
    "event_update_emails": false
  }
}
```

**Errors:**

| Status | Body | Reason |
|---|---|---|
| 401 | `{ "error": "Unauthorized" }` | Missing or invalid JWT |

---

### 3. Unsubscribe — email footer link

This endpoint is called automatically when a user clicks an unsubscribe link in an email. You don't call it directly — you just need to handle the redirect destination.

```
GET /api/v1/unsubscribe?token=<signed-token>
```

The API processes the token and redirects to your frontend:

| Outcome | Redirect |
|---|---|
| Successfully unsubscribed | `{FRONTEND_URL}/unsubscribed?type=marketing_emails` |
| Invalid or expired token (tokens expire after 90 days) | `{FRONTEND_URL}/unsubscribed?error=invalid_token` |

You need to build a `/unsubscribed` page that reads these query params and shows an appropriate message.

---

## Frontend implementation

### Signup form — marketing consent checkbox

Add a checkbox to your registration form. Only send `marketing_emails: true` if the box is checked.

```tsx
async function register(formData: {
  first_name: string;
  email: string;
  password: string;
  marketing_emails: boolean;
  // ... other optional fields
}) {
  const res = await fetch("https://api.casatamplarului.ro/api/v1/auth/registration", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(formData),
  });

  const data = await res.json();
  if (!res.ok) throw new Error(data.error);

  localStorage.setItem("ct_jwt", data.jwt);
  return data.user; // data.user.email_preferences.marketing_emails reflects what you sent
}
```

```tsx
// In your form component
const [marketingConsent, setMarketingConsent] = useState(false);

<label>
  <input
    type="checkbox"
    checked={marketingConsent}
    onChange={(e) => setMarketingConsent(e.target.checked)}
  />
  I agree to receive news and updates about upcoming events
</label>

// On submit:
await register({ first_name, email, password, marketing_emails: marketingConsent });
```

---

### Settings page — preference toggles

On load, read `user.email_preferences` from your auth state (already returned at login — no extra API call needed).

```tsx
// TypeScript types
interface EmailPreferences {
  marketing_emails: boolean;
  payment_reminder_emails: boolean;
  payment_receipt_emails: boolean;
  event_reminder_emails: boolean;
  event_update_emails: boolean;
}

async function updateEmailPreferences(
  prefs: Partial<EmailPreferences>
): Promise<EmailPreferences> {
  const jwt = localStorage.getItem("ct_jwt");

  const res = await fetch(
    "https://api.casatamplarului.ro/api/v1/auth/me/email_preferences",
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${jwt}`,
      },
      body: JSON.stringify(prefs),
    }
  );

  const data = await res.json();
  if (!res.ok) throw new Error(data.error);

  return data.email_preferences;
}
```

**Example toggle component:**

```tsx
function EmailPreferencesPanel({ initialPrefs }: { initialPrefs: EmailPreferences }) {
  const [prefs, setPrefs] = useState(initialPrefs);
  const [saving, setSaving] = useState<string | null>(null);

  async function toggle(key: keyof EmailPreferences) {
    setSaving(key);
    try {
      const updated = await updateEmailPreferences({ [key]: !prefs[key] });
      setPrefs(updated);
    } finally {
      setSaving(null);
    }
  }

  const labels: Record<keyof EmailPreferences, string> = {
    marketing_emails: "News and upcoming events",
    payment_reminder_emails: "Payment reminders",
    payment_receipt_emails: "Payment receipts",
    event_reminder_emails: "Event reminders",
    event_update_emails: "Event updates for booked events",
  };

  return (
    <div>
      <h3>Email notifications</h3>
      {(Object.keys(labels) as Array<keyof EmailPreferences>).map((key) => (
        <label key={key}>
          <input
            type="checkbox"
            checked={prefs[key]}
            disabled={saving === key}
            onChange={() => toggle(key)}
          />
          {labels[key]}
        </label>
      ))}
    </div>
  );
}

// Usage — prefs come from your auth state, already present after login:
<EmailPreferencesPanel initialPrefs={currentUser.email_preferences} />
```

---

### Unsubscribe page — `/unsubscribed`

Build a page at the path your `FRONTEND_URL` points to (e.g. `https://casatamplarului.ro/unsubscribed`). The API redirects here after processing an unsubscribe link.

```tsx
// app/unsubscribed/page.tsx (Next.js App Router)
// or pages/unsubscribed.tsx (Pages Router)

const preferenceLabels: Record<string, string> = {
  marketing_emails: "promotional emails",
  payment_reminder_emails: "payment reminders",
  payment_receipt_emails: "payment receipts",
  event_reminder_emails: "event reminders",
  event_update_emails: "event update emails",
};

export default function UnsubscribedPage() {
  const searchParams = useSearchParams();
  const type = searchParams.get("type");
  const error = searchParams.get("error");

  if (error === "invalid_token") {
    return (
      <div>
        <h1>Link expired</h1>
        <p>
          This unsubscribe link has expired or is invalid. You can manage your
          email preferences from your{" "}
          <a href="/settings">account settings</a>.
        </p>
      </div>
    );
  }

  const label = type ? preferenceLabels[type] ?? "those emails" : "those emails";

  return (
    <div>
      <h1>Unsubscribed</h1>
      <p>
        You've been unsubscribed from {label}. You can re-enable this at any
        time from your <a href="/settings">account settings</a>.
      </p>
    </div>
  );
}
```

---

## iOS (Swift / SwiftUI)

### Types

```swift
struct EmailPreferences: Codable {
  var marketingEmails: Bool
  var paymentReminderEmails: Bool
  var paymentReceiptEmails: Bool
  var eventReminderEmails: Bool
  var eventUpdateEmails: Bool

  enum CodingKeys: String, CodingKey {
    case marketingEmails         = "marketing_emails"
    case paymentReminderEmails   = "payment_reminder_emails"
    case paymentReceiptEmails    = "payment_receipt_emails"
    case eventReminderEmails     = "event_reminder_emails"
    case eventUpdateEmails       = "event_update_emails"
  }
}
```

### Signup with marketing consent

Add `marketing_emails` to your `RegisterRequest`:

```swift
struct RegisterRequest: Encodable {
  let first_name: String
  let email: String
  let password: String
  let marketing_emails: Bool
  // ... other optional fields
}
```

### Update preferences

```swift
func updateEmailPreferences(_ prefs: [String: Bool]) async throws -> EmailPreferences {
  let url = URL(string: "https://api.casatamplarului.ro/api/v1/auth/me/email_preferences")!
  var request = URLRequest(url: url)
  request.httpMethod = "PATCH"
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.setValue("Bearer \(KeychainHelper.get("ct_jwt") ?? "")", forHTTPHeaderField: "Authorization")
  request.httpBody = try JSONEncoder().encode(prefs)

  let (data, response) = try await URLSession.shared.data(for: request)

  guard (response as? HTTPURLResponse)?.statusCode == 200 else {
    let error = try? JSONDecoder().decode([String: String].self, from: data)
    throw AppError.serverError(error?["error"] ?? "Unknown error")
  }

  struct Response: Decodable { let email_preferences: EmailPreferences }
  return try JSONDecoder().decode(Response.self, from: data).email_preferences
}
```

---

## React Native

```ts
import AsyncStorage from "@react-native-async-storage/async-storage";

interface EmailPreferences {
  marketing_emails: boolean;
  payment_reminder_emails: boolean;
  payment_receipt_emails: boolean;
  event_reminder_emails: boolean;
  event_update_emails: boolean;
}

async function updateEmailPreferences(
  prefs: Partial<EmailPreferences>
): Promise<EmailPreferences> {
  const jwt = await AsyncStorage.getItem("ct_jwt");

  const res = await fetch(
    "https://api.casatamplarului.ro/api/v1/auth/me/email_preferences",
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${jwt}`,
      },
      body: JSON.stringify(prefs),
    }
  );

  const data = await res.json();
  if (!res.ok) throw new Error(data.error);

  return data.email_preferences;
}
```

For the unsubscribe deep link, register a handler for `casatamplarului://unsubscribed` (or your universal link equivalent) and read the `type` / `error` query params the same way as the web page above.

---

## OAuth signup — post-onboarding consent

OAuth users (Google, Apple, Facebook, Microsoft) are created with all preferences `false`. After the OAuth flow completes, show a one-time onboarding screen asking for marketing consent:

```tsx
// After OAuth login, if this is a new user (you can track this with a `isNewUser` flag):
if (isNewUser) {
  const consented = await showMarketingConsentModal();
  if (consented) {
    await updateEmailPreferences({ marketing_emails: true });
  }
  // Either way, proceed to the app
}
```

---

## Summary

| What | Where |
|---|---|
| Marketing consent at signup | `marketing_emails: true` in `POST /api/v1/auth/registration` body |
| OAuth marketing consent | `PATCH /api/v1/auth/me/email_preferences` after onboarding |
| Current preferences | `user.email_preferences` in any auth response — no extra call needed |
| Update preferences | `PATCH /api/v1/auth/me/email_preferences` with only changed fields |
| Unsubscribe page destination | `/unsubscribed?type=<key>` or `/unsubscribed?error=invalid_token` |
