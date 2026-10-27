---
name: kakao-slice
description: Slice an exported KakaoTalk (카카오톡, 카톡) chat .txt by date, sender or keyword so only the needed part is read. Use whenever the user gives, attaches or mentions a KakaoTalk chat export or 대화 내보내기 file (KakaoTalk_*.txt, Talk_*.txt, "... 님과 카카오톡 대화"), asks what was said in a KakaoTalk chat, or wants part of a chat by date, person or keyword. Use it instead of reading the whole export.
---

# kakao-slice

A KakaoTalk export is often thousands of lines. Never read or paste the raw file; slice it and read only the slice.

1. Overview first, one line per date with message counts:

   ```
   uv run "$HOME/.claude/skills/kakao-slice/kakao_slice.py" CHAT.txt --list
   ```

   For a chat that spans many months, run `--months` first, then `--list --from ... --to ...` for the months that matter.

2. Slice what the question needs (same command, other options):

   ```
   --date 2026-10-27
   --from 2026-10-01 --to 2026-10-27
   --last 3                      the last 3 dates that have messages
   --sender 홍길동               repeatable, matches part of the name
   --grep 회의                   repeatable, ignores case
   --stats                       messages per sender in the selection
   -o slice.txt                  write to a UTF-8 file instead of the screen
   ```

3. Read the printed slice, not CHAT.txt. If it is still large (hundreds of messages), narrow it further, or write it with `-o` and read that file in parts.

Output is one message per line, `YYYY-MM-DD HH:MM Name: text`; the extra lines of a multi-line message follow, indented by two spaces. Join, leave and invite notices are dropped.

- Quote the chat path: export file names contain spaces.
- If the user is about to paste a whole chat, ask for the exported .txt instead (chat room menu, 대화 내용 내보내기). Extract a .zip export first and use the .txt inside.
- Exit code 1 with a list of supported formats means the file is not a KakaoTalk export the script knows (PC Korean/English, Android and iOS Korean, English mobile).
- The user can run the same command in a terminal; `--help` shows every option with examples.
