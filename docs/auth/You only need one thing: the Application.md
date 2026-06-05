You only need one thing: the Application (client) ID from Azure. No client secret — validation uses Microsoft's public keys (same idea as Google's JWKS, no secret involved).

Steps:

1. Go to https://portal.azure.com → Azure Active Directory → App registrations → New registration
2. Name: anything (e.g. "Casa Tâmplarului")
3. Supported account types: "Personal Microsoft accounts only" (the consumers option — critical, don't pick the others)
4. Redirect URI: add your web app's origin (e.g. https://casatamplarului.ro) — also add http://localhost:3000 for dev
5. Click Register
6. Copy the Application (client) ID from the overview page — that's the only value you need

Then add it to Rails credentials:

bin/rails credentials:edit

auth:
microsoft_client_id: <paste the Application (client) ID here>

That's it. No secret, no tenant ID, nothing else.
