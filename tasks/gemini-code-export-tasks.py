#!/usr/bin/env python3
# export_tasks_csv.py
# Updated to output to CSV format.

import os
import csv
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CREDENTIALS_FILE = os.path.join(SCRIPT_DIR, "credentials.json")
TOKEN_FILE = os.path.join(SCRIPT_DIR, "token.json")
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "gemini_google_tasks.csv")
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

    # Define the CSV column headers
    fieldnames = ['title', 'status', 'due', 'completed', 'notes', 'updated', 'id']

    with open(OUTPUT_FILE, "w", newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        
        for t in tasks:
            # We filter the dictionary to ensure we only write the keys we want,
            # and use .get() to provide empty strings if the key is missing.
            row = {field: t.get(field, '') for field in fieldnames}
            writer.writerow(row)

    print(f"Wrote {len(tasks)} tasks to {OUTPUT_FILE}")

if __name__ == "__main__":
    main()