# Add "Other Arguments (Advanced)" entry field
ttk.Label(filters_frame, text="Other Arguments (Advanced):").grid(
    row=4, column=0, columnspan=7, padx=5, pady=(10, 0), sticky="w")

# Create the "Other Arguments" entry widget
other_entry = ttk.Entry(filters_frame, textvariable=self.other_args)
other_entry.grid(row=5, column=0, columnspan=6, padx=5, pady=(0, 5), sticky="ew")

# Add the "?" help button next to the entry box
ttk.Button(filters_frame, text="?", command=self._open_help_popup, width=2).grid(
    row=5, column=6, padx=5, pady=(0, 5), sticky="e")

# Add examples text below the "Other Arguments" entry or keep as is
examples = r'e.g., -perm 644 | ! -name ".*" | -exec "mv {} {}.bak" \;'
ttk.Label(filters_frame, text=examples, font=('Courier', 10)).grid(
    row=6, column=0, columnspan=7, padx=5, pady=(0, 5), sticky="w")