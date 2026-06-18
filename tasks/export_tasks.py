#!/usr/bin/env python3
# export_tasks.py
# Created: 2026-06-17 20:10
# Pulls all tasks from the default Google Tasks list and writes them with full
# details to a text file. Place credentials.json in the same folder. First run
# opens a browser for OAuth consent and saves token.json for reuse.

import os
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CREDENTIALS_FILE = os.path.join(SCRIPT_DIR, "credentials.json")
TOKEN_FILE = os.path.join(SCRIPT_DIR, "token.json")
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "google_tasks.txt")
SCOPES = ["https://www.googleapis.com/auth/tasks.readonly"]


def get_service():
    creds = None
    if os.path.exists(TOKEN_FILE):
        creds = Credentials.from_authorized_user_file(TOKEN_FILE, SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(CREDENTIALS_FILE, SCOPES)
            creds = flow.run_local_server(port=0)
        with open(TOKEN_FILE, "w") as f:
            f.write(creds.to_json())
    return build("tasks", "v1", credentials=creds)


def main():
    service = get_service()

    # Default list is "@default"
    tasklist = service.tasklists().get(tasklist="@default").execute()
    list_title = tasklist.get("title", "Default")

    tasks = []
    page_token = None
    while True:
        resp = service.tasks().list(
            tasklist="@default",
            showCompleted=True,
            showHidden=True,
            maxResults=100,
            pageToken=page_token,
        ).execute()
        tasks.extend(resp.get("items", []))
        page_token = resp.get("nextPageToken")
        if not page_token:
            break

    lines = []
    lines.append(f"Task list: {list_title}")
    lines.append(f"Total tasks: {len(tasks)}")
    lines.append("=" * 60)
    lines.append("")

    for t in tasks:
        lines.append(f"Title:     {t.get('title', '(no title)')}")
        lines.append(f"Status:    {t.get('status', '')}")
        if t.get("due"):
            lines.append(f"Due:       {t['due']}")
        if t.get("completed"):
            lines.append(f"Completed: {t['completed']}")
        if t.get("notes"):
            lines.append(f"Notes:     {t['notes']}")
        lines.append(f"Updated:   {t.get('updated', '')}")
        lines.append(f"ID:        {t.get('id', '')}")
        lines.append("-" * 60)

    with open(OUTPUT_FILE, "w") as f:
        f.write("\n".join(lines))

    print(f"Wrote {len(tasks)} tasks to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
