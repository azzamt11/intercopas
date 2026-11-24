# Intercopas

Intercopas syncs plain-text clipboard content between desktops through `https://threads-api.aazzam.my.id`.

## Run

Install Node.js 20 or later, then run:

```sh
npm install
npm start
```

Sign in with your phone number and password. The app requests a bearer token from `/login`, then stores that token in the app's user-data directory. Keep the app running on both desktops. New clipboard text is uploaded as a post with type `clipboard`, and the app checks for newer `clipboard` posts every 15 seconds.

Build an installer for the current OS with `npm run dist`. On Linux Mint, run the included PowerShell installer from the project directory:

```sh
pwsh ./install.ps1
```

The script builds an AppImage, installs it under `~/.local/opt/intercopas`, and adds launchers to the applications menu and (if present) the desktop. It requires Node.js 20+, npm, PowerShell 7, `sudo` access for the AppImage runtime dependency, and network access to download npm dependencies.

## API behavior

- `POST /posts` with `{ "content": "...", "type": "clipboard", "parent_post_id": null }`
- `GET /posts?type=clipboard`

The API example does not expose timestamps in its JSON post model, so the client tracks post IDs and only applies posts with higher IDs than it has already seen. The app only transfers text; files and images are not synced.
# intercopas
