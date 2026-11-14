# Milestone 1 setup (Mac)

Goal: run Arkborn on your Mac and push it to GitHub. About an hour, most of it downloads.
Keep KNOX plugged in whenever Godot has the project open.

## 1. Install Godot

1. Go to https://godotengine.org/download/macos/ and download the standard
   **Godot Engine** build (not the ".NET" one).
2. Unzip it and drag **Godot.app** into Applications.
3. Open it. If macOS says it can't verify the app, open
   System Settings > Privacy & Security, scroll down, and click **Open Anyway**.

The project targets Godot 4.4. Any newer 4.x release works; if Godot offers to
upgrade the project to its version, say yes.

## 2. Open and run the project

1. In Godot's Project Manager, click **Import**.
2. Browse to `/Volumes/KNOX/claude/projects/arkborn/project.godot` and choose **Import & Edit**.
   The first open takes a minute while Godot builds its cache (the `.godot` folder).
3. Press the **Play** button (triangle, top right) or Cmd+B.

You should see a green-and-blue isometric map with a readout in the top-left.
Try scrolling with WASD, the screen edges, or a two-finger swipe, and zoom with
the wheel or a pinch. Close the game window to return to the editor.

## 3. Check Git

Open Terminal and run:

    git --version

If macOS offers to install the Command Line Developer Tools, accept and run it again.
Then tell Git who you are (use the email you'll use for GitHub):

    git config --global user.name "John Agnew"
    git config --global user.email "you@example.com"
    git config --global init.defaultBranch main

## 4. First commit

    cd /Volumes/KNOX/claude/projects/arkborn
    git init
    git add .
    git commit -m "Initial Arkborn project skeleton"

If Git complains about "dubious ownership" (common on external drives), run this once and retry:

    git config --global --add safe.directory /Volumes/KNOX/claude/projects/arkborn

## 5. Push to GitHub

Easiest path is the GitHub CLI (needs Homebrew; https://brew.sh if you don't have it):

    brew install gh
    gh auth login                 # choose GitHub.com, HTTPS, log in with browser
    gh repo create arkborn --private --source . --push

Without the CLI: create an empty **private** repo named `arkborn` on github.com
(no README, no .gitignore), then:

    git remote add origin https://github.com/<your-username>/arkborn.git
    git push -u origin main

## Done when

- The map runs from Godot on your Mac.
- `git status` says "nothing to commit, working tree clean".
- Your `arkborn` repo shows the files on github.com.

Then tell Claude, and Milestone 2 (villagers, gathering, buildings) starts.
