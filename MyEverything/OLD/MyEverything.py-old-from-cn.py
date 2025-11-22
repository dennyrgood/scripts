 import os
 import datetime
 from tkinter import *
 from tkinter import filedialog, messagebox

 # The popup widget code
 class PopupWidget:
     def __init__(self, master):
         self.master = master
         self.popup_window = None
     
     def create_popup(self, message):
         self.popup_window = Toplevel(self.master)
         self.popup_window.title("Popup")
         
         label = Label(self.popup_window, text=message)
         label.pack(pady=20)
         
         close_button = Button(self.popup_window, text="Close", 
 command=self.close_popup)
         close_button.pack(pady=10)
         
     def close_popup(self):
         if self.popup_window:
             self.popup_window.destroy()
             self.popup_window = None

 # The application code
 class MyEverythingApp(Tk):
     
     FIND_FILTERS = [
         ("min_size", "-size +%dk"),
         ("max_size", "-size -%dk"),
         ("older_than_days", "-mtime +{}d"),
         ("newer_than_days", "-mtime -{}d")
     ]
     
     COLUMN_SETUP = {
         "#0": {"text": "Name", "data_key": None},
         "Folder": {"text": "Folder_Path"},
         "Size": {"text": "Size", "data_key": "Size_Bytes"},
         "Modified": {"text": "Modified", "data_key": "Modified_Timestamp"},
         "Accessed": {"text": "Last Accessed", "data_key": 
 "Accessed_Timestamp"},
         "Changed": {"text": "Last Changed", "data_key": "Changed_Timestamp"}
     }
     
     ERROR_COLOR = 'red'
     
     def __init__(self):
         super().__init__()
         
         self.title("My Everything Search")
         self.geometry("1024x768")

         # Start Path
         self.start_path = StringVar(value=os.getcwd())
         start_label = Label(self, text="Start Directory:")
         start_label.grid(row=0, column=0)
         start_entry = Entry(self, textvariable=self.start_path, width=85)
         start_entry.grid(row=0, column=1, sticky=NSEW)
         browse_button = Button(self, text="Browse", command=self._select_path)
         browse_button.grid(row=0, column=2)

         # Search Name
         self.search_name = StringVar()
         search_label = Label(self, text="File Pattern:")
         search_label.grid(row=1, column=0)
         search_entry = Entry(self, textvariable=self.search_name, width=85)
         search_entry.grid(row=1, column=1, sticky=NSEW)

         # Case Insensitivity
         self.case_insensitive = BooleanVar(value=True)
         case_checkbox = Checkbutton(self, text="Case Insensitive", 
 variable=self.case_insensitive)
         case_checkbox.grid(row=1, column=2)

         # Filters
         filters_frame_label = Label(self, text="Filters:")
         filters_frame_label.grid(row=2, column=0, sticky=W)

         for i, (var_name, flag) in enumerate(self.FIND_FILTERS):
             variable = StringVar()
             label = Label(self, text=f"{flag.replace('%d', '')} (days):" if 
 "%d" in flag else f"{flag.replace('%k', '')}:")
             entry = Entry(self, textvariable=variable)
             
             label.grid(row=i + 3, column=0, sticky=W)
             entry.grid(row=i + 3, column=1, sticky=NSEW)
             
             setattr(self, var_name, variable)

         # Other Arguments
         other_args_label = Label(self, text="Other Arguments:")
         other_args_label.grid(row=len(self.FIND_FILTERS) + 3, column=0, 
 sticky=W)
         self.other_args = StringVar()
         other_args_entry = Entry(self, textvariable=self.other_args, width=85)
         other_args_entry.grid(row=len(self.FIND_FILTERS) + 3, column=1, 
 sticky=NSEW)

         # Run Button
         run_button = Button(self, text="Run Search", command=self._run_search)
         run_button.grid(row=len(self.FIND_FILTERS) + 4, column=0, 
 columnspan=2, pady=10, sticky=NSEW)

         # Results Display
         self.results_tree = Treeview(self, 
 columns=list(self.COLUMN_SETUP.keys())[1:], show="headings")
         for col_id, values in self.COLUMN_SETUP.items():
             self.results_tree.heading(col_id, text=values["text"])
         
         vsb = Scrollbar(orient='vertical', command=self.results_tree.yview)
         self.results_tree.configure(yscrollcommand=vsb.set)

         self.results_tree.grid(row=len(self.FIND_FILTERS) + 5, column=0, 
 columnspan=3, sticky=NSEW)
         vsb.grid(row=len(self.FIND_FILTERS) + 5, column=2, sticky='ns')

         # Status Bar
         self.status_label = Label(self, text="Ready", bd=1, relief=SUNKEN, 
 anchor=W)
         self.status_label.grid(row=len(self.FIND_FILTERS) + 6, column=0, 
 columnspan=3, sticky=NSEW)
         
         # Error Display
         error_frame = LabelFrame(self, text="Command Errors (stderr):", 
 fg="red")
         error_frame.grid(row=len(self.FIND_FILTERS) + 7, column=0, 
 columnspan=3, sticky=NSEW)

         self.error_output = Text(error_frame, height=6, state='disabled')
         self.error_output.grid(row=0, column=0, sticky=NSEW)

         # Bind double-click on treeview to open in Finder if applicable
         self.popup_widget = PopupWidget(self)  # Initialize with the main 
 window

     def _select_path(self):
         folder_selected = 
 filedialog.askdirectory(initialdir=self.start_path.get())
         if folder_selected:
             self.start_path.set(folder_selected)

     def _run_search(self):
         try:
             command = self._build_find_command()
             subprocess.run(command, shell=True, check=True)
             messagebox.showinfo("Success", "Command executed successfully.")
         except Exception as e:
             messagebox.showerror("Execution Error", f"Failed to execute 
 command: {e}")

     def _build_find_command(self):
         command = [
             "find",
             self.start_path.get(),
             "-name", self.search_name.get()
         ]

         for var_name, flag in self.FIND_FILTERS:
             filter_value = getattr(self, var_name).get().strip()
             if filter_value:
                 command.extend([flag.format(filter_value)])

         other_args_val = self.other_args.get().strip()
         if other_args_val:
             command.extend(shlex.split(other_args_val))

         return command

     def _log_error(self, message):
         self.error_output.config(state='normal')
         self.error_output.delete('1.0', tk.END)
         
         if not message:
             self.error_status_label.config(text="Command Errors (stderr):", 
 foreground='red')
             self.error_output.config(state='disabled')
             return

         self.error_output.insert(tk.END, message)
         self.error_output.see('1.0')
         self.error_output.config(state='disabled')
         
         self.master.update_idletasks() 
         

 if __name__ == "__main__":
     root = Tk()
     app = MyEverythingApp(root)
     root.mainloop()
