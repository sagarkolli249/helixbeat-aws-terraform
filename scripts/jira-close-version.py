#!/usr/bin/env python3
"""
Mark Jira Fix Version as Released after a tag push.
Called by release-notes.yml after the GitHub Release is created.
"""
import json
import os
import re
import urllib.request
import base64

JIRA_BASE_URL = os.environ["JIRA_BASE_URL"].rstrip("/")
JIRA_TOKEN    = os.environ["JIRA_TOKEN"]
JIRA_USER     = os.environ["JIRA_USER"]
CURRENT_TAG   = os.environ["CURRENT_TAG"]
PROJECT_KEY   = "ENG"   # adjust to your Jira project key

def _auth() -> dict:
    creds = base64.b64encode(f"{JIRA_USER}:{JIRA_TOKEN}".encode()).decode()
    return {"Authorization": f"Basic {creds}", "Content-Type": "application/json"}

def get_or_create_version(name: str) -> str:
    """Return Jira version ID, creating it if needed."""
    url = f"{JIRA_BASE_URL}/rest/api/3/project/{PROJECT_KEY}/versions"
    req = urllib.request.Request(url, headers=_auth())
    with urllib.request.urlopen(req, timeout=10) as resp:
        versions = json.loads(resp.read())
    for v in versions:
        if v["name"] == name:
            return v["id"]
    # Create
    payload = json.dumps({"name": name, "project": PROJECT_KEY, "released": False}).encode()
    req = urllib.request.Request(f"{JIRA_BASE_URL}/rest/api/3/version",
                                 data=payload, headers=_auth(), method="POST")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())["id"]

def release_version(version_id: str):
    payload = json.dumps({"released": True}).encode()
    req = urllib.request.Request(
        f"{JIRA_BASE_URL}/rest/api/3/version/{version_id}",
        data=payload, headers=_auth(), method="PUT"
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        print(f"Version released: {json.loads(resp.read())['name']}")

if __name__ == "__main__":
    vid = get_or_create_version(CURRENT_TAG)
    release_version(vid)
    print(f"Jira version '{CURRENT_TAG}' marked as Released")
