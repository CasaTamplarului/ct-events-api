# Email/Password Authentication Integration Guide

This guide explains how to implement email/password registration and login in your web or mobile app so it works with the CT Events API.

**Base URL:** `https://api.casatamplarului.ro` (or `http://localhost:3000` for local dev)

---

## How it works

1. User fills in a registration or login form
2. Your app sends the credentials to the API
3. The API validates and returns a **JWT** (valid 30 days)
4. Your app stores the JWT and sends it as `Authorization: Bearer <jwt>` on every authenticated request

The JWT format is identical to Google Sign-In — the same `GET /api/v1/auth/me` endpoint works for both.

---

## API Endpoints

### Register a new account

```
POST /api/v1/auth/registration
Content-Type: application/json
```

**Request body:**

| Field | Required | Notes |
|---|---|---|
| `first_name` | ✅ | |
| `email` | ✅ | Stored lowercase; case-insensitive on login |
| `password` | ✅ | Minimum 8 characters |
| `last_name` | optional | |
| `phone_number` | optional | |
| `church_name` | optional | |
| `city` | optional | |

```json
{
  "first_name": "Ion",
  "last_name": "Popescu",
  "email": "ion@example.com",
  "password": "MyPassword1!",
  "phone_number": "+40700000000",
  "church_name": "Biserica Betel",
  "city": "Cluj-Napoca"
}
```

**Success (201):**

```json
{
  "jwt": "eyJhbGciOiJIUzI1NiJ9...",
  "user": {
    "id": 42,
    "first_name": "Ion",
    "last_name": "Popescu",
    "email": "ion@example.com",
    "avatar_url": null,
    "phone_number": "+40700000000",
    "church_name": "Biserica Betel",
    "city": "Cluj-Napoca"
  }
}
```

**Errors:**

| Status | Body | Reason |
|---|---|---|
| 422 | `{ "error": "first_name, email, and password are required" }` | Missing required field |
| 422 | `{ "error": "Password is too short (minimum is 8 characters)" }` | Password too short |
| 422 | `{ "error": "Email is invalid" }` | Malformed email |
| 409 | `{ "error": "Email is already registered" }` | Account already exists |
| 429 | `{ "error": "Too many requests. Please try again later." }` | Rate limit hit (5 req/IP/min) |

---

### Log in

```
POST /api/v1/auth/session
Content-Type: application/json
```

**Request body:**

```json
{
  "email": "ion@example.com",
  "password": "MyPassword1!"
}
```

**Success (200):** Same `jwt` + `user` shape as registration.

**Errors:**

| Status | Body | Reason |
|---|---|---|
| 422 | `{ "error": "email and password are required" }` | Missing field |
| 401 | `{ "error": "Invalid email or password" }` | Wrong credentials (same message for unknown email and wrong password) |
| 429 | `{ "error": "Too many requests. Please try again later." }` | Rate limit hit (5 req/IP/min) |

---

### Get current user

```
GET /api/v1/auth/me
Authorization: Bearer <jwt>
```

**Success (200):** Same `user` shape as above.

**Errors:**

| Status | Body | Reason |
|---|---|---|
| 401 | `{ "error": "Unauthorized" }` | Missing, invalid, or expired JWT |

---

## Web (React / Next.js)

### Registration

```tsx
async function register(formData: {
  first_name: string;
  last_name?: string;
  email: string;
  password: string;
  phone_number?: string;
  church_name?: string;
  city?: string;
}) {
  const res = await fetch("https://api.casatamplarului.ro/api/v1/auth/registration", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(formData),
  });

  const data = await res.json();

  if (!res.ok) {
    // data.error contains a human-readable message
    throw new Error(data.error);
  }

  // Store the JWT
  localStorage.setItem("ct_jwt", data.jwt);
  return data.user;
}
```

**Handle errors in your UI:**

```tsx
try {
  const user = await register({ first_name, email, password });
  // success — redirect or update state
} catch (err) {
  if (err.message === "Email is already registered") {
    setError("An account with this email already exists. Please log in.");
  } else {
    setError(err.message);
  }
}
```

### Login

```tsx
async function login(email: string, password: string) {
  const res = await fetch("https://api.casatamplarului.ro/api/v1/auth/session", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });

  const data = await res.json();

  if (!res.ok) {
    throw new Error(data.error);
  }

  localStorage.setItem("ct_jwt", data.jwt);
  return data.user;
}
```

### Authenticated requests

```ts
function authHeaders() {
  const jwt = localStorage.getItem("ct_jwt");
  return {
    "Content-Type": "application/json",
    ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}),
  };
}

const res = await fetch("https://api.casatamplarului.ro/api/v1/auth/me", {
  headers: authHeaders(),
});

if (res.status === 401) {
  localStorage.removeItem("ct_jwt");
  // redirect to login
}
```

### Log out

```ts
function logout() {
  localStorage.removeItem("ct_jwt");
  // redirect to home/login
}
```

---

## iOS (Swift / SwiftUI)

### Registration

```swift
struct RegisterRequest: Encodable {
  let first_name: String
  let last_name: String?
  let email: String
  let password: String
  let phone_number: String?
  let church_name: String?
  let city: String?
}

func register(_ params: RegisterRequest) async throws -> AuthResponse {
  let url = URL(string: "https://api.casatamplarului.ro/api/v1/auth/registration")!
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = try JSONEncoder().encode(params)

  let (data, response) = try await URLSession.shared.data(for: request)

  if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
    let error = try JSONDecoder().decode([String: String].self, from: data)
    throw AuthError.serverError(error["error"] ?? "Unknown error")
  }

  let result = try JSONDecoder().decode(AuthResponse.self, from: data)
  KeychainHelper.save(key: "ct_jwt", value: result.jwt)
  return result
}
```

### Login

```swift
func login(email: String, password: String) async throws -> AuthResponse {
  let url = URL(string: "https://api.casatamplarului.ro/api/v1/auth/session")!
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

  let (data, response) = try await URLSession.shared.data(for: request)

  if (response as? HTTPURLResponse)?.statusCode == 401 {
    throw AuthError.invalidCredentials
  }

  let result = try JSONDecoder().decode(AuthResponse.self, from: data)
  KeychainHelper.save(key: "ct_jwt", value: result.jwt)
  return result
}
```

### Shared models

```swift
struct AuthResponse: Decodable {
  let jwt: String
  let user: UserProfile
}

struct UserProfile: Decodable {
  let id: Int
  let firstName: String
  let lastName: String?
  let email: String
  let avatarUrl: String?
  let phoneNumber: String?
  let churchName: String?
  let city: String?

  enum CodingKeys: String, CodingKey {
    case id, email, city
    case firstName = "first_name"
    case lastName = "last_name"
    case avatarUrl = "avatar_url"
    case phoneNumber = "phone_number"
    case churchName = "church_name"
  }
}

enum AuthError: Error {
  case invalidCredentials
  case serverError(String)
  case tokenExpired
}
```

---

## Android (Kotlin)

### Registration

```kotlin
@Serializable
data class RegisterRequest(
  val first_name: String,
  val last_name: String? = null,
  val email: String,
  val password: String,
  val phone_number: String? = null,
  val church_name: String? = null,
  val city: String? = null
)

suspend fun register(params: RegisterRequest): Result<AuthResponse> {
  return withContext(Dispatchers.IO) {
    try {
      val url = URL("https://api.casatamplarului.ro/api/v1/auth/registration")
      val connection = url.openConnection() as HttpURLConnection
      connection.requestMethod = "POST"
      connection.setRequestProperty("Content-Type", "application/json")
      connection.doOutput = true
      connection.outputStream.write(Json.encodeToString(params).toByteArray())

      val responseCode = connection.responseCode
      val body = if (responseCode in 200..299) {
        connection.inputStream.bufferedReader().readText()
      } else {
        val error = connection.errorStream?.bufferedReader()?.readText()
        val message = error?.let { Json.decodeFromString<Map<String, String>>(it)["error"] }
        return@withContext Result.failure(Exception(message ?: "Error $responseCode"))
      }

      val result = Json.decodeFromString<AuthResponse>(body)
      securePrefs.edit().putString("ct_jwt", result.jwt).apply()
      Result.success(result)
    } catch (e: Exception) {
      Result.failure(e)
    }
  }
}
```

### Login

```kotlin
suspend fun login(email: String, password: String): Result<AuthResponse> {
  return withContext(Dispatchers.IO) {
    try {
      val url = URL("https://api.casatamplarului.ro/api/v1/auth/session")
      val connection = url.openConnection() as HttpURLConnection
      connection.requestMethod = "POST"
      connection.setRequestProperty("Content-Type", "application/json")
      connection.doOutput = true

      val body = """{"email":"$email","password":"$password"}"""
      connection.outputStream.write(body.toByteArray())

      if (connection.responseCode == 401) {
        return@withContext Result.failure(Exception("Invalid email or password"))
      }

      val responseBody = connection.inputStream.bufferedReader().readText()
      val result = Json.decodeFromString<AuthResponse>(responseBody)
      securePrefs.edit().putString("ct_jwt", result.jwt).apply()
      Result.success(result)
    } catch (e: Exception) {
      Result.failure(e)
    }
  }
}

@Serializable
data class AuthResponse(val jwt: String, val user: UserProfile)

@Serializable
data class UserProfile(
  val id: Int,
  val first_name: String,
  val last_name: String? = null,
  val email: String,
  val avatar_url: String? = null,
  val phone_number: String? = null,
  val church_name: String? = null,
  val city: String? = null
)
```

---

## React Native

### Install

No additional packages needed beyond what you already have for Google Sign-In (`AsyncStorage`, etc.).

### Registration

```ts
import AsyncStorage from "@react-native-async-storage/async-storage";

async function register(params: {
  first_name: string;
  last_name?: string;
  email: string;
  password: string;
  phone_number?: string;
  church_name?: string;
  city?: string;
}) {
  const res = await fetch(
    "https://api.casatamplarului.ro/api/v1/auth/registration",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(params),
    }
  );

  const data = await res.json();

  if (!res.ok) {
    throw new Error(data.error);
  }

  await AsyncStorage.setItem("ct_jwt", data.jwt);
  return data.user;
}
```

### Login

```ts
async function login(email: string, password: string) {
  const res = await fetch(
    "https://api.casatamplarului.ro/api/v1/auth/session",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    }
  );

  const data = await res.json();

  if (!res.ok) {
    throw new Error(data.error); // "Invalid email or password" on 401
  }

  await AsyncStorage.setItem("ct_jwt", data.jwt);
  return data.user;
}
```

### Authenticated requests (same as Google Sign-In flow)

```ts
async function authFetch(path: string, options: RequestInit = {}) {
  const jwt = await AsyncStorage.getItem("ct_jwt");

  const res = await fetch(`https://api.casatamplarului.ro${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}),
      ...options.headers,
    },
  });

  if (res.status === 401) {
    await AsyncStorage.removeItem("ct_jwt");
    throw new Error("Session expired");
  }

  return res;
}
```

### Log out

```ts
async function logout() {
  await AsyncStorage.removeItem("ct_jwt");
}
```

---

## JWT Lifecycle

| Topic | Detail |
|---|---|
| Expiry | 30 days from registration/login |
| Refresh | No refresh token — user must log in again after expiry |
| Revocation | None server-side — clear the token client-side to "log out" |
| On 401 from API | Clear stored JWT and send user to login screen |
| Shared with Google Sign-In | Yes — the same JWT format and `GET /auth/me` endpoint work for both |

---

## Rate Limiting

Both endpoints are limited to **5 requests per IP per minute**. On the 6th request within a minute you receive:

```
HTTP 429
{ "error": "Too many requests. Please try again later." }
```

Handle this in your UI with a message like "Too many attempts. Please wait a moment and try again."

---

## Error handling checklist

- **422** — show `data.error` directly to the user (it's human-readable)
- **409** — email already registered; offer to log in or reset password instead
- **401** on login — show generic "Invalid email or password" (don't distinguish between wrong password and unknown email)
- **429** — show rate-limit message; optionally disable the submit button for 60 seconds
- **Network error** — catch `fetch` exceptions and show a connectivity message
