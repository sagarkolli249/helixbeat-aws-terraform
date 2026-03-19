#!/usr/bin/env python3
"""
Publish release notes to Confluence under the 'Releases' parent page.
Called by release-notes.yml.
"""
import json
import os
import urllib.request
import base64

CONFLUENCE_BASE_URL = os.environ["CONFLUENCE_BASE_URL"].rstrip("/")
CONFLUENCE_TOKEN    = os.environ["CONFLUENCE_TOKEN"]
CONFLUENCE_USER     = os.getenv("CONFLUENCE_USER", "")
SPACE               = os.environ.get("CONFLUENCE_SPACE", "PLATFORM")
CURRENT_TAG         = os.environ["CURRENT_TAG"]

def _auth() -> dict:
    if CONFLUENCE_USER:
        creds = base64.b64encode(f"{CONFLUENCE_USER}:{CONFLUENCE_TOKEN}".encode()).decode()
        return {"Authorization": f"Basic {creds}", "Content-Type": "application/json"}
    return {"Authorization": f"Bearer {CONFLUENCE_TOKEN}", "Content-Type": "application/json"}

def get_parent_page_id(title: str = "Releases") -> str:
    url = f"{CONFLUENCE_BASE_URL}/rest/api/content?spaceKey={SPACE}&title={title}&type=page"
    req = urllib.request.Request(url, headers=_auth())
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())
    return data["results"][0]["id"]

def create_or_update_page(parent_id: str, title: str, body_md: str):
    # Convert markdown to Confluence storage format (simple HTML wrapping)
    storage = f"<p><ac:structured-macro ac:name='markdown'><ac:plain-text-body><![CDATA[{body_md}]]></ac:plain-text-body></ac:structured-macro></p>"

    # Check if page exists
    url = f"{CONFLUENCE_BASE_URL}/rest/api/content?spaceKey={SPACE}&title={title}&type=page"
    req = urllib.request.Request(url, headers=_auth())
    with urllib.request.urlopen(req, timeout=10) as resp:
        existing = json.loads(resp.read())

    with open("/tmp/release-notes.md") as f:
        body_md = f.read()

    page_body = {
        "type": "page",
        "title": title,
        "space": {"key": SPACE},
        "ancestors": [{"id": parent_id}],
        "body": {
            "storage": {
                "value": storage,
                "representation": "storage"
            }
        }
    }

    if existing["results"]:
        page_id = existing["results"][0]["id"]
        version = existing["results"][0]["version"]["number"] + 1
        page_body["version"] = {"number": version}
        payload = json.dumps(page_body).encode()
        req = urllib.request.Request(
            f"{CONFLUENCE_BASE_URL}/rest/api/content/{page_id}",
            data=payload, headers=_auth(), method="PUT"
        )
        action = "Updated"
    else:
        payload = json.dumps(page_body).encode()
        req = urllib.request.Request(
            f"{CONFLUENCE_BASE_URL}/rest/api/content",
            data=payload, headers=_auth(), method="POST"
        )
        action = "Created"

    with urllib.request.urlopen(req, timeout=10) as resp:
        result = json.loads(resp.read())
        print(f"{action} Confluence page: {result.get('_links', {}).get('webui', '')}")

if __name__ == "__main__":
    parent_id = get_parent_page_id("Releases")
    create_or_update_page(parent_id, f"Release {CURRENT_TAG}", "")
    print("Confluence publish complete")
