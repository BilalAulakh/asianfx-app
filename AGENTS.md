# Agent Guidelines & Automation Rules

## 1. Autonomous Execution (No Unnecessary Permission Prompts)
- **Do NOT ask for confirmations or permissions**: Always proceed directly with necessary implementations, fixes, file updates, and standard tasks.
- **Do not use interactive modal prompts (`ask_question`)** for routine actions.
- Automatically execute and verify changes without interrupting the user.

## 2. Terminal & Command Safety (Prevent IDE "Allow" Modals)
- **Avoid giant inline script strings**: Never execute huge inline scripts (e.g. multi-line `node -e "..."` or giant PowerShell strings) directly in CLI commands, as these trigger IDE security confirmation dialogs that can freeze or block the user.
- **Use File Operations or Clean Scripts**: Use native file tools (`replace_file_content`, `write_to_file`, `multi_replace_file_content`) to create and update files, or write temporary scripts into scratch directories and execute them cleanly.

## 3. Communication
- Respond concisely.
- Support Urdu / Roman Urdu / English naturally according to user communication.
- Always provide clickable markdown links (`file:///...`) for modified or referenced files.
