from plexapi.server import PlexServer
from requests.exceptions import ConnectionError

# Configure your Plex server details
PLEX_URL = 'http://surface3-gc:32400'
PLEX_TOKEN = 'xqetuxscJvEVVUdNE6-v'

def check_plex_server_status():
    try:
        # Attempt to connect to the Plex server
        plex = PlexServer(PLEX_URL, PLEX_TOKEN)
        print(f"Successfully connected to Plex server: {plex.friendlyName}")

        # Get and print basic information
        print("\n--- Basic Server Information ---")
        print(f"Platform: {plex.platform} {plex.platformVersion}")
        print(f"Version: {plex.version}")
        print(f"Plex Username: {plex.myPlexUsername}")
        print(f"Total Libraries: {len(plex.library.sections())}")
        # Instead of plex.allowRemoteAccess, use these:
        print(f"Remote Mapping State: {plex.myPlexMappingState}")  # e.g., 'mapped' or 'failed'
        print(f"MyPlex Sign-in State: {plex.myPlexSigninState}")   # e.g., 'ok'

        for client in plex.clients():
            print(f"Connected Client: {client.title} ({client.product})")

        for section in plex.library.sections():
            # Use .totalSize to see total items in that section
           print(f"Library: {section.title} | Type: {section.type} | Total Items: {section.totalSize}")

        sessions = plex.sessions()
        print(f"Active Streams: {len(sessions)}")

        sessions = plex.sessions()
        print(f"Active Streams: {len(sessions)}")

        for session in sessions:
            # Get user and state safely
            user = session.usernames[0] if session.usernames else "Unknown"
            state = session.players[0].state if session.players else "unknown"
    
            # Determine the display title based on media type
            if session.type == 'episode':
               # Show Name - S01E03 - Episode Title
                full_title = f"{session.grandparentTitle} - {session.parentTitle} - {session.title}"
            elif session.type == 'movie':
               # Movie Name (Year)
               full_title = f"{session.title} ({session.year})"
            else:
               full_title = session.title

            print(f"- {user} is watching: {full_title} [{state}]")


        # Basic check to see if remote access is likely working

        if plex.myPlexMappingState == "mapped":
            print("✅ Remote Access appears to be ACTIVE.")
        else:
            print("❌ Remote Access is likely DISABLED or failing.")


        # Check for active streams (sessions)
        sessions = plex.sessions()
        if sessions:
            print(f"\nActive Streams: {len(sessions)}")
            for session in sessions:
                print(f"- {session.title} (User: {session.user.title}, Type: {session.type})")
        else:
            print("\nNo active streams currently.")

        return True

    except ConnectionError:
        print(f"Error: Could not connect to the Plex server at {PLEX_URL}.")
        print("Please check if the server is running and the URL/IP is correct.")
        return False
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        return False

if __name__ == "__main__":
    check_plex_server_status()

