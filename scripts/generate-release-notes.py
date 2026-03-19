#!/usr/bin/env python3
"""
HelixBeat – Jira-linked release notes generator
Slide 6: Extract ticket IDs → Jira API → Markdown changelog → publish

Usage (called by GitHub Actions release-notes.yml):
  python scripts/generate-release-notes.py

Env vars required:
  JIRA_BASE_URL, JIRA_TOKEN, JIRA_USER
  CURRENT_TAG, GITHUB_TOKEN, GITHUB_REPOSITORY
"""
import json
import os
import re
import subprocess
import sys
from datetime import date
from typing import Optional
import urllib.request
import urllib.parse
import base64

# ── Config ────────────────────────────────────────────────────────────────────
JIRA_BASE_URL = os.environ["JIRA_BASE_URL"].rstrip("/")
JIRA_TOKEN    = os.environ["JIRA_TOKEN"]
JIRA_USER     = os.environ["JIRA_USER"]
CURRENT_TAG   = os.environ["CURRENT_TAG"]
GITHUB_REPO   = os.environ.get("GITHUB_REPOSITORY", "org/helixbeat")

# Ticket pattern: PROJECT-123 (any uppercase project key)
TICKET_RE = re.compile(r"\b([A-Z][A-Z0-9]+-[0-9]+)\b")

# Commit type mapping (conventional commits)
TYPE_MAP = {
    "feat":     ("🚀 New Features",    "feat"),
    "fix":      ("🐛 Bug Fixes",       "fix"),
    "perf":     ("⚡ Performance",     "perf"),
    "security": ("🔐 Security",        "security"),
    "infra":    ("🏗️ Infrastructure", "infra"),
    "docs":     ("📚 Documentation",   "docs"),
    "chore":    ("🔧 Chores",          "chore"),
    "refactor": ("♻️ Refactoring",    "refactor"),
}

def _jira_auth_header() -> dict:
    creds = base64.b64encode(f"{JIRA_USER}:{JIRA_TOKEN}".encode()).decode()
    return {"Authorization": f"Basic {creds}", "Content-Type": "application/json"}

def get_jira_issue(ticket_id: str) -> Optional[dict]:
    """Fetch a single Jira issue summary + type."""
    url = f"{JIRA_BASE_URL}/rest/api/3/issue/{ticket_id}?fields=summary,issuetype,status,epic"
    req = urllib.request.Request(url, headers=_jira_auth_header())
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        print(f"  Warning: could not fetch {ticket_id}: {e}", file=sys.stderr)
        return None

def get_commits_since_last_tag() -> list[dict]:
    """Return list of {hash, message, type, tickets} since the previous tag."""
    try:
        prev_tag = subprocess.check_output(
            ["git", "describe", "--tags", "--abbrev=0", f"{CURRENT_TAG}^"],
            stderr=subprocess.DEVNULL, text=True
        ).strip()
        commit_range = f"{prev_tag}..{CURRENT_TAG}"
    except subprocess.CalledProcessError:
        # First release — all commits
        commit_range = CURRENT_TAG

    raw = subprocess.check_output(
        ["git", "log", commit_range, "--pretty=format:%H|||%s|||%b"],
        text=True
    ).strip()

    commits = []
    for line in raw.splitlines():
        if "|||" not in line:
            continue
        parts = line.split("|||", 2)
        sha, subject, body = parts[0], parts[1], parts[2] if len(parts) > 2 else ""

        # Determine conventional commit type
        type_match = re.match(r"^(\w+)(?:\([^)]+\))?!?:", subject)
        commit_type = type_match.group(1).lower() if type_match else "chore"

        # Extract Jira ticket IDs from subject + body
        tickets = list(dict.fromkeys(TICKET_RE.findall(subject + " " + body)))

        commits.append({
            "sha": sha[:8],
            "message": subject,
            "type": commit_type,
            "tickets": tickets,
        })

    return commits

def build_changelog(commits: list[dict]) -> tuple[str, list]:
    """Group commits by type and enrich with Jira data. Returns (markdown, manifest)."""
    groups: dict[str, list] = {k: [] for k in TYPE_MAP}
    groups["other"] = []
    manifest_issues = []

    for commit in commits:
        ctype = commit["type"] if commit["type"] in TYPE_MAP else "other"
        tickets_info = []

        for ticket_id in commit["tickets"]:
            issue = get_jira_issue(ticket_id)
            if issue:
                summary = issue["fields"]["summary"]
                itype = issue["fields"]["issuetype"]["name"]
                tickets_info.append({"id": ticket_id, "summary": summary, "type": itype})
                manifest_issues.append({"ticket": ticket_id, "summary": summary})
            else:
                tickets_info.append({"id": ticket_id, "summary": "(Jira unavailable)", "type": "Unknown"})

        commit["tickets_info"] = tickets_info
        groups[ctype].append(commit)

    # Build markdown
    lines = [
        f"## Release {CURRENT_TAG} — {date.today().isoformat()}",
        "",
        f"**Full diff:** https://github.com/{GITHUB_REPO}/compare/... {CURRENT_TAG}",
        "",
    ]

    for type_key, (section_title, _) in TYPE_MAP.items():
        if not groups.get(type_key):
            continue
        lines.append(f"### {section_title}")
        for commit in groups[type_key]:
            ticket_parts = ""
            for t in commit["tickets_info"]:
                ticket_parts += f" [{t['id']}]({JIRA_BASE_URL}/browse/{t['id']}) {t['summary']} |"
            if ticket_parts:
                lines.append(f"- {ticket_parts.rstrip('|')} *(commit {commit['sha']})*")
            else:
                lines.append(f"- {commit['message']} *(commit {commit['sha']})*")
        lines.append("")

    if groups.get("other"):
        lines.append("### 🔩 Other Changes")
        for commit in groups["other"]:
            lines.append(f"- {commit['message']} *(commit {commit['sha']})*")
        lines.append("")

    return "\n".join(lines), manifest_issues

def main():
    print(f"Generating release notes for {CURRENT_TAG}...")
    commits = get_commits_since_last_tag()
    print(f"Found {len(commits)} commits")

    markdown, issues = build_changelog(commits)

    # Write markdown for GitHub Release
    with open("/tmp/release-notes.md", "w") as f:
        f.write(markdown)
    print("Written: /tmp/release-notes.md")

    # Write JSON manifest for S3
    manifest = {
        "version": CURRENT_TAG,
        "date": date.today().isoformat(),
        "commit_count": len(commits),
        "jira_issues": issues,
        "github_repo": GITHUB_REPO,
    }
    with open("/tmp/release-manifest.json", "w") as f:
        json.dump(manifest, f, indent=2)
    print("Written: /tmp/release-manifest.json")

    print(f"\n{'='*60}")
    print(markdown)

if __name__ == "__main__":
    main()
