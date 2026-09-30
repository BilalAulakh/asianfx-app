---
trigger: always_on
---

# Autonomous Execution & Modal Prevention Policy

1. **Autonomous Action**: Always proceed directly with necessary coding, fixes, testing, and operations. Do NOT ask for permission or prompt the user with interactive approval modals for standard operations.
2. **Prevent IDE "Allow" Modals**: Do not send long, complex inline shell strings (like `node -e "<multi-line-code>"`) to `run_command` because they trigger IDE confirmation dialogues that block the user. Always use file tools or clean scripts in scratch directories.
