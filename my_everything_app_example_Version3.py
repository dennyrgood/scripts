def _open_help_popup(self):
    """Opens a Help pop-up with examples for 'Other Arguments'."""
    # Create the pop-up window
    help_popup = tk.Toplevel(self.master)
    help_popup.title("Advanced Arguments Examples")
    help_popup.geometry("600x400")
    
    # Add a scrollable text area
    text_frame = ttk.Frame(help_popup)
    text_frame.pack(fill="both", expand=True, padx=10, pady=10)
    
    scrollbar = tk.Scrollbar(text_frame)
    text = tk.Text(text_frame, wrap="word", yscrollcommand=scrollbar.set)
    scrollbar.config(command=text.yview)
    
    # Insert examples
    examples_text = """
    === Examples for 'Other Arguments' ===

    1. Permissions:
    - Find files with specific permissions:
      Example: -perm 755 
    - Exclude files with specific permissions:
      Example: ! -perm 644 

    2. Name and Pattern Matching:
    - Exclude temporary files:
      Example: ! -name "*.tmp"
    - Find multiple file types (e.g., .pyc or .log):
      Example: -name "*.pyc" -o -name "*.log"

    3. Date and Time Filters:
    - Modified after January 1, 2025:
      Example: -newermt "2025-01-01"

    4. Actions:
    - Delete matching files (USE WITH CAUTION):
      Example: -delete
    - Change permissions to 644:
      Example: -exec chmod 644 {} \;

    (More detailed examples can be added here.)
    """
    text.insert("1.0", examples_text)
    text.config(state="disabled")  # Make read-only
    text.pack(side="left", fill="both", expand=True)
    scrollbar.pack(side="right", fill="y")
    
    # Close button
    ttk.Button(help_popup, text="Close", command=help_popup.destroy).pack(pady=5)