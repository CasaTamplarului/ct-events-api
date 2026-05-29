# Google Sign-In Integration Guide

This guide explains how to implement Google Sign-In in your web or mobile app so it works with the CT Events API.

**Base URL:** `https://localhost:3000 || https://api.casatamplarului.ro` (replace with your environment's URL)

---

## How it works

The API uses **stateless JWTs**. The flow is always:

1. Your app initiates Google Sign-In → Google returns an **ID token** (a short-lived signed string)
2. Your app sends that ID token to our API
3. The API verifies it with Google, creates or finds the user, and returns a **JWT** (valid 30 days)
4. Your app stores the JWT and sends it as `Authorization: Bearer <jwt>` on every authenticated request

The API handles everything else: creating the user account, linking past bookings by email, etc.

---

## API Endpoints

### Sign in with Google

```
POST /api/v1/auth/google
Content-Type: application/json

{ "id_token": "<Google ID token>" }
```

**Success (200):**

```json
{
  "jwt": "eyJhbGciOiJIUzI1NiJ9...",
  "user": {
    "id": 42,
    "first_name": "Ion",
    "last_name": "Popescu",
    "email": "ion@example.com",
    "avatar_url": "https://lh3.googleusercontent.com/..."
  }
}
```

**Errors:**
| Status | Body | Reason |
|--------|------|--------|
| 401 | `{ "error": "Invalid Google token" }` | Token failed verification or is expired |
| 422 | `{ "error": "id_token is required" }` | Missing param |

---

### Get current user

```
GET /api/v1/auth/me
Authorization: Bearer <jwt>
```

**Success (200):** Same `user` shape as above.

**Errors:**
| Status | Body | Reason |
|--------|------|--------|
| 401 | `{ "error": "Unauthorized" }` | Missing, invalid, or expired JWT |

---

## What you need before you start

1. A **Google Cloud project** with OAuth 2.0 configured at [console.cloud.google.com](https://console.cloud.google.com)
2. A **Google OAuth Client ID** — you need different client IDs for web, iOS, and Android (they can all live in the same Google Cloud project)
3. The correct **Authorized Origins / Bundle ID / Package Name** set up in the Google Cloud Console for each platform

Give the Google Client IDs to the API team so they can be added to the server-side configuration.

---

## Web (React / Next.js)

Use Google's **Identity Services** library (the modern replacement for the old `gapi`).

### 1. Load the library

In your `index.html` or `_document.tsx`:

```html
<script src="https://accounts.google.com/gsi/client" async></script>
```

Or with `@react-oauth/google` (recommended for React):

```bash
npm install @react-oauth/google
```

### 2. Wrap your app

```tsx
import { GoogleOAuthProvider } from "@react-oauth/google";

export default function App() {
  return (
    <GoogleOAuthProvider clientId="YOUR_GOOGLE_WEB_CLIENT_ID">
      <YourApp />
    </GoogleOAuthProvider>
  );
}
```

### 3. Add the sign-in button

```tsx
import { GoogleLogin } from "@react-oauth/google";

export function SignInButton() {
  const handleSuccess = async (credentialResponse) => {
    const idToken = credentialResponse.credential; // this is the ID token

    const res = await fetch(
      "https://api.casatamplarului.ro/api/v1/auth/google",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id_token: idToken }),
      },
    );

    if (!res.ok) {
      const { error } = await res.json();
      console.error("Sign-in failed:", error);
      return;
    }

    const { jwt, user } = await res.json();

    // Store the JWT — use httpOnly cookie or localStorage depending on your security model
    localStorage.setItem("ct_jwt", jwt);

    console.log("Signed in as", user.first_name);
  };

  return (
    <GoogleLogin
      onSuccess={handleSuccess}
      onError={() => console.error("Google sign-in failed")}
    />
  );
}
```

### 4. Authenticated requests

```ts
function authHeaders() {
  const jwt = localStorage.getItem("ct_jwt");
  return {
    "Content-Type": "application/json",
    ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}),
  };
}

// Example: fetch current user on app load
const res = await fetch("https://api.casatamplarului.ro/api/v1/auth/me", {
  headers: authHeaders(),
});

if (res.status === 401) {
  // JWT is expired or invalid — send the user back to sign-in
  localStorage.removeItem("ct_jwt");
}
```

### 5. Sign out

The JWT is stateless — sign out is purely client-side:

```ts
function signOut() {
  localStorage.removeItem("ct_jwt");
  // Optionally: google.accounts.id.disableAutoSelect()
}
```

---

## iOS (Swift / SwiftUI)

### 1. Add the Google Sign-In SDK

In your `Package.swift` or via CocoaPods:

```ruby
# Podfile
pod 'GoogleSignIn', '~> 7.0'
```

Or via Swift Package Manager:
`https://github.com/google/GoogleSignIn-iOS`

### 2. Configure in `AppDelegate` / `App`

```swift
// In your App entry point or AppDelegate
import GoogleSignIn

@main
struct CTEventsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }

    init() {
        // Your iOS client ID from Google Cloud Console
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "YOUR_IOS_CLIENT_ID"
        )
    }
}
```

### 3. Trigger sign-in and send to API

```swift
import GoogleSignIn

func signInWithGoogle(presenting viewController: UIViewController) async {
    do {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)

        guard let idToken = result.user.idToken?.tokenString else {
            print("No ID token")
            return
        }

        try await sendTokenToAPI(idToken: idToken)
    } catch {
        print("Google sign-in failed: \(error)")
    }
}

func sendTokenToAPI(idToken: String) async throws {
    let url = URL(string: "https://api.casatamplarului.ro/api/v1/auth/google")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["id_token": idToken])

    let (data, response) = try await URLSession.shared.data(for: request)

    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        let error = try JSONDecoder().decode([String: String].self, from: data)
        print("API error:", error["error"] ?? "unknown")
        return
    }

    let result = try JSONDecoder().decode(AuthResponse.self, from: data)

    // Store JWT in Keychain (never UserDefaults for auth tokens)
    KeychainHelper.save(key: "ct_jwt", value: result.jwt)

    print("Signed in as", result.user.firstName)
}

struct AuthResponse: Decodable {
    let jwt: String
    let user: UserProfile
}

struct UserProfile: Decodable {
    let id: Int
    let firstName: String
    let lastName: String
    let email: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case firstName = "first_name"
        case lastName = "last_name"
        case avatarUrl = "avatar_url"
    }
}
```

### 4. Authenticated requests

```swift
func authenticatedRequest(url: URL) async throws -> Data {
    guard let jwt = KeychainHelper.get(key: "ct_jwt") else {
        throw AuthError.notSignedIn
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let (data, response) = try await URLSession.shared.data(for: request)

    if (response as? HTTPURLResponse)?.statusCode == 401 {
        // JWT expired — clear and re-authenticate
        KeychainHelper.delete(key: "ct_jwt")
        throw AuthError.tokenExpired
    }

    return data
}
```

---

## Android (Kotlin)

### 1. Add dependencies

```kotlin
// build.gradle (app)
dependencies {
    implementation("com.google.android.gms:play-services-auth:21.0.0")
    // Or the newer Credential Manager (recommended for API 28+):
    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")
}
```

### 2. Sign in and send to API (Credential Manager)

```kotlin
import androidx.credentials.*
import com.google.android.libraries.identity.googleid.*

class AuthViewModel(application: Application) : AndroidViewModel(application) {
    private val credentialManager = CredentialManager.create(application)

    suspend fun signInWithGoogle(activity: Activity): Result<AuthResponse> {
        val googleIdOption = GetGoogleIdOption.Builder()
            .setFilterByAuthorizedAccounts(false)
            .setServerClientId("YOUR_ANDROID_CLIENT_ID")
            .build()

        val request = GetCredentialRequest.Builder()
            .addCredentialOption(googleIdOption)
            .build()

        return try {
            val result = credentialManager.getCredential(activity, request)
            val credential = result.credential as? CustomCredential
                ?: return Result.failure(Exception("Unexpected credential type"))

            if (credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                return Result.failure(Exception("Not a Google ID token"))
            }

            val googleIdToken = GoogleIdTokenCredential.createFrom(credential.data).idToken
            sendTokenToAPI(googleIdToken)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private suspend fun sendTokenToAPI(idToken: String): Result<AuthResponse> {
        return withContext(Dispatchers.IO) {
            try {
                val url = URL("https://api.casatamplarului.ro/api/v1/auth/google")
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.setRequestProperty("Content-Type", "application/json")
                connection.doOutput = true

                val body = """{"id_token":"$idToken"}"""
                connection.outputStream.write(body.toByteArray())

                if (connection.responseCode != 200) {
                    return@withContext Result.failure(Exception("API error: ${connection.responseCode}"))
                }

                val response = connection.inputStream.bufferedReader().readText()
                val authResponse = Json.decodeFromString<AuthResponse>(response)

                // Store JWT securely in EncryptedSharedPreferences
                securePrefs.edit().putString("ct_jwt", authResponse.jwt).apply()

                Result.success(authResponse)
            } catch (e: Exception) {
                Result.failure(e)
            }
        }
    }
}

@Serializable
data class AuthResponse(val jwt: String, val user: UserProfile)

@Serializable
data class UserProfile(
    val id: Int,
    val first_name: String,
    val last_name: String,
    val email: String,
    val avatar_url: String? = null
)
```

### 3. Authenticated requests

```kotlin
fun authenticatedHeaders(): Map<String, String> {
    val jwt = securePrefs.getString("ct_jwt", null)
    return buildMap {
        put("Content-Type", "application/json")
        if (jwt != null) put("Authorization", "Bearer $jwt")
    }
}
```

---

## React Native

### 1. Install

```bash
npm install @react-native-google-signin/google-signin
```

Follow the platform setup guide at: https://react-native-google-signin.github.io/docs/setting-up/get-config-file

### 2. Configure

```ts
import { GoogleSignin } from "@react-native-google-signin/google-signin";

GoogleSignin.configure({
  // Use your WEB client ID here (not iOS/Android) — this is what generates
  // an ID token that the server can verify
  webClientId: "YOUR_GOOGLE_WEB_CLIENT_ID",
  offlineAccess: false,
});
```

### 3. Sign in and send to API

```ts
import {
  GoogleSignin,
  statusCodes,
} from "@react-native-google-signin/google-signin";
import AsyncStorage from "@react-native-async-storage/async-storage";

async function signInWithGoogle() {
  try {
    await GoogleSignin.hasPlayServices();
    const userInfo = await GoogleSignin.signIn();

    const idToken = userInfo.data?.idToken;
    if (!idToken) throw new Error("No ID token received");

    const res = await fetch(
      "https://api.casatamplarului.ro/api/v1/auth/google",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id_token: idToken }),
      },
    );

    if (!res.ok) {
      const { error } = await res.json();
      throw new Error(error);
    }

    const { jwt, user } = await res.json();

    // Use a secure storage library in production (e.g. react-native-keychain)
    await AsyncStorage.setItem("ct_jwt", jwt);

    return user;
  } catch (error) {
    if (error.code === statusCodes.SIGN_IN_CANCELLED) {
      console.log("User cancelled");
    } else {
      console.error("Sign-in error:", error);
    }
  }
}
```

### 4. Authenticated requests

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
    // Token expired — clear and redirect to sign-in
    await AsyncStorage.removeItem("ct_jwt");
    throw new Error("Session expired");
  }

  return res;
}

// Usage
const res = await authFetch("/api/v1/auth/me");
const user = await res.json();
```

### 5. Sign out

```ts
async function signOut() {
  await GoogleSignin.signOut();
  await AsyncStorage.removeItem("ct_jwt");
}
```

---

## JWT Lifecycle

| Topic           | Detail                                                              |
| --------------- | ------------------------------------------------------------------- |
| Expiry          | 30 days from sign-in                                                |
| Refresh         | No refresh token — user must sign in with Google again after expiry |
| Revocation      | None server-side — discard the token client-side to "log out"       |
| On 401 from API | Clear stored JWT and send user to sign-in screen                    |

---

## Security notes

- **Never store the JWT in an insecure location.** Use `Keychain` (iOS), `EncryptedSharedPreferences` (Android), or `react-native-keychain` (React Native). For web, an httpOnly cookie is more secure than `localStorage` if you control the server.
- **The `id_token` from Google is short-lived** (typically 1 hour) — only use it to call our sign-in endpoint. Do not store it.
- **Use the Web Client ID** when configuring React Native — not the Android or iOS client ID. The Web Client ID is what generates an `id_token` verifiable by the backend.

---

## Google Cloud Console checklist

- [ ] Create an OAuth 2.0 Client ID for **Web** → used by the API server and React Native
- [ ] Create an OAuth 2.0 Client ID for **iOS** → add your iOS Bundle ID
- [ ] Create an OAuth 2.0 Client ID for **Android** → add your SHA-1 fingerprint + package name
- [ ] Share all three Client IDs with the API team
- [ ] Add your web app domain to **Authorized JavaScript Origins** (for the Web client)
- [ ] Add your app scheme to **Authorized redirect URIs** if needed
