# /// script
# requires-python = ">=3.13"
# dependencies = []
# ///
"""Slice an exported KakaoTalk chat (.txt) by date, sender or keyword, so only the needed part is read.

Start with --list (messages per date), then pick one day, a range or the last few days, optionally
narrowed to some senders or a keyword.
"""

import argparse
import codecs
import re
import sys
from collections import Counter
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date, datetime, time
from pathlib import Path

MONTHS = {
    key: number
    for number, name in enumerate(
        (
            "january",
            "february",
            "march",
            "april",
            "may",
            "june",
            "july",
            "august",
            "september",
            "october",
            "november",
            "december",
        ),
        start=1,
    )
    for key in (name, name[:3])
}

SPACED_COLON = re.compile(r"(?P<name>.+?) :(?: (?P<text>.*))?")


@dataclass(frozen=True, slots=True)
class Format:
    name: str
    example: str
    line: re.Pattern[str]
    # Mobile exports write "name : text" after the timestamp; a timestamped line without that separator
    # is a notice such as a join or an invite, not a message.
    sender: re.Pattern[str] | None = None


FORMATS = (
    Format(
        "PC (Korean)",
        "[홍길동] [오후 1:19] text, under '--------------- 2026년 10월 27일 화요일 ---------------' lines",
        re.compile(r"\[(?P<name>.+?)\] \[(?P<ampm>오전|오후) (?P<h>\d{1,2}):(?P<mi>\d{2})\] ?(?P<text>.*)"),
    ),
    Format(
        "PC (English)",
        "[Name] [1:19 PM] text, under '--------------- Tuesday, October 27, 2026 ---------------' lines",
        re.compile(r"\[(?P<name>.+?)\] \[(?P<h>\d{1,2}):(?P<mi>\d{2}) (?P<ampm>AM|PM)\] ?(?P<text>.*)"),
    ),
    Format(
        "Android (Korean)",
        "2026년 10월 27일 오후 1:19, 홍길동 : text",
        re.compile(
            r"(?P<y>\d{4})년 (?P<m>\d{1,2})월 (?P<d>\d{1,2})일 "
            r"(?P<ampm>오전|오후) (?P<h>\d{1,2}):(?P<mi>\d{2}), (?P<rest>.*)"
        ),
        SPACED_COLON,
    ),
    Format(
        "iOS (Korean)",
        "2026. 10. 27. 오후 1:19, 홍길동 : text  or  2026. 10. 27. 13:19, 홍길동 : text",
        re.compile(
            r"(?P<y>\d{4})\. (?P<m>\d{1,2})\. (?P<d>\d{1,2})\. (?:(?P<ampm>오전|오후) )?"
            r"(?P<h>\d{1,2}):(?P<mi>\d{2}), (?P<rest>.*)"
        ),
        SPACED_COLON,
    ),
    Format(
        "English mobile",
        "October 27, 2026 at 1:19 PM, Name : text",
        re.compile(
            r"(?P<mon>[A-Za-z]+) (?P<d>\d{1,2}), (?P<y>\d{4}) at "
            r"(?P<h>\d{1,2}):(?P<mi>\d{2}) (?P<ampm>AM|PM), (?P<rest>.*)"
        ),
        SPACED_COLON,
    ),
    Format(
        "English mobile (short)",
        "10/27/26, 1:19 PM - Name: text",
        re.compile(
            r"(?P<m>\d{1,2})/(?P<d>\d{1,2})/(?P<y>\d{4}|\d{2}), "
            r"(?P<h>\d{1,2}):(?P<mi>\d{2}) (?P<ampm>AM|PM) - (?P<rest>.*)"
        ),
        re.compile(r"(?P<name>.+?):(?: (?P<text>.*))?"),
    ),
)

SUPPORTED = "\n".join(f"  {fmt.name}: {fmt.example}" for fmt in FORMATS)

# Only the dashed form sets the day for PC messages: a bare date inside a message must not re-date the rest.
DAY_LINES = (
    re.compile(r"-+\s*(?P<y>\d{4})년 (?P<m>\d{1,2})월 (?P<d>\d{1,2})일 \S요일\s*-+"),
    re.compile(r"-+\s*(?:[A-Za-z]+, )?(?P<mon>[A-Za-z]+) (?P<d>\d{1,2}), (?P<y>\d{4})\s*-+"),
)

# PC exports give notices no timestamp, so only their wording tells them apart from a message's next line.
SYSTEM = re.compile(
    r"(?:저장한 날짜|Date Saved|Saved on) ?:.*"
    r"|\d{4}년 \d{1,2}월 \d{1,2}일 \S요일"
    r"|[A-Za-z]+day, [A-Za-z]+ \d{1,2}, \d{4}"
    r"|.+님이 (?:들어왔습니다|나갔습니다)\.?"
    r"|.+님을 (?:초대했습니다|초대하였습니다|내보냈습니다)\.?"
    r"|채팅방 관리자가 메시지를 가렸습니다\.?"
    r"|.+ (?:joined|left) (?:this|the) chatroom\.?"
)

EXAMPLES = f"""examples:
  kakao_slice.py chat.txt --list
  kakao_slice.py chat.txt --date 2026-10-27
  kakao_slice.py chat.txt --from 2026-10-01 --to 2026-10-27 --sender 홍길동
  kakao_slice.py chat.txt --last 3 --grep 회의 -o slice.txt

supported export formats:
{SUPPORTED}
"""


@dataclass(slots=True)
class Message:
    when: datetime
    sender: str
    lines: list[str]

    @property
    def text(self) -> str:
        return "\n".join(self.lines)

    def render(self) -> str:
        first, *rest = self.lines
        head = f"{self.when:%Y-%m-%d %H:%M} {self.sender}: {first}".rstrip()
        return "\n".join([head, *(f"  {line}" if line else "" for line in rest)])


def hour24(hour: int, ampm: str | None) -> int:
    if ampm in ("오후", "PM"):
        return hour % 12 + 12
    if ampm in ("오전", "AM"):
        return hour % 12
    return hour


def to_date(groups: dict[str, str | None]) -> date:
    year = int(groups["y"])
    month = MONTHS[groups["mon"].lower()] if groups.get("mon") else int(groups["m"])
    return date(year + 2000 if year < 100 else year, month, int(groups["d"]))


def day_line(line: str) -> date | None:
    for pattern in DAY_LINES:
        if match := pattern.fullmatch(line):
            try:
                return to_date(match.groupdict())
            except (KeyError, ValueError):
                return None
    return None


def match_message(line: str, locked: Format | None) -> tuple[Format, dict[str, str | None]] | None:
    for fmt in (locked,) if locked else FORMATS:
        if match := fmt.line.fullmatch(line):
            groups = match.groupdict()
            if fmt.sender and (who := fmt.sender.fullmatch(groups["rest"])):
                groups |= who.groupdict()
            return fmt, groups
    return None


def to_datetime(groups: dict[str, str | None], day: date | None) -> datetime | None:
    try:
        if groups.get("y"):
            day = to_date(groups)
        if day is None:
            return None
        return datetime.combine(day, time(hour24(int(groups["h"]), groups.get("ampm")), int(groups["mi"])))
    except (KeyError, ValueError):
        return None


def parse(lines: Iterable[str]) -> list[Message]:
    messages: list[Message] = []
    # The first message line fixes the format, so a later line that only looks like another format stays text.
    locked: Format | None = None
    day: date | None = None
    for raw in lines:
        line = raw.rstrip()
        if hit := match_message(line, locked):
            locked, groups = hit
            if groups.get("name") and (when := to_datetime(groups, day)):
                messages.append(Message(when, groups["name"], [groups["text"] or ""]))
            continue
        if found := day_line(line):
            day = found
        elif messages and not SYSTEM.fullmatch(line):
            messages[-1].lines.append(line)
    for message in messages:
        while len(message.lines) > 1 and not message.lines[-1]:
            message.lines.pop()
    return messages


def read_chat(path: Path) -> str:
    data = path.read_bytes()
    # KakaoTalk writes UTF-8, but Notepad on Korean Windows re-saves as UTF-16 ("Unicode") or CP949 ("ANSI").
    if data.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        return data.decode("utf-16")
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("cp949", errors="replace")


def select(messages: list[Message], args: argparse.Namespace) -> list[Message]:
    start, end = args.start, args.end
    if args.date:
        start = end = args.date
    if args.last:
        dates = sorted({message.when.date() for message in messages})
        start = dates[-min(args.last, len(dates))]
    senders = [name.casefold() for name in args.sender]
    words = [word.casefold() for word in args.grep]
    return [
        message
        for message in messages
        if (start is None or message.when.date() >= start)
        and (end is None or message.when.date() <= end)
        and (not senders or any(name in message.sender.casefold() for name in senders))
        and (not words or any(word in message.text.casefold() for word in words))
    ]


def plural(count: int, word: str) -> str:
    return f"{count} {word}" if count == 1 else f"{count} {word}s"


def counts_by(keys: list[str], unit: str) -> list[str]:
    counts = Counter(keys)
    width = len(str(max(counts.values())))
    rows = [f"{key}  {count:>{width}}" for key, count in sorted(counts.items())]
    return [*rows, f"total {plural(len(keys), 'message')} on {plural(len(counts), unit)}"]


def per_sender(messages: list[Message]) -> list[str]:
    counts = Counter(message.sender for message in messages)
    width = len(str(max(counts.values())))
    rows = [f"{count:>{width}}  {name}" for name, count in counts.most_common()]
    return [*rows, f"total {plural(len(messages), 'message')} from {plural(len(counts), 'sender')}"]


def iso_date(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a date in YYYY-MM-DD form: {value!r}") from None


def positive(value: str) -> int:
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError(f"must be 1 or more: {value!r}")
    return number


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="kakao_slice.py",
        description="Slice an exported KakaoTalk chat (.txt) by date, sender or keyword. Run --list first.",
        epilog=EXAMPLES,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("chat", type=Path, help="the exported chat .txt")
    parser.add_argument("--list", action="store_true", help="messages per date and the total: the cheap overview")
    parser.add_argument("--months", action="store_true", help="messages per month, for chats that span a long time")
    parser.add_argument("--stats", action="store_true", help="messages per sender in the selection")
    when = parser.add_argument_group("dates (use one way)")
    when.add_argument("--date", type=iso_date, metavar="YYYY-MM-DD", help="one day")
    when.add_argument("--from", dest="start", type=iso_date, metavar="YYYY-MM-DD", help="first day, inclusive")
    when.add_argument("--to", dest="end", type=iso_date, metavar="YYYY-MM-DD", help="last day, inclusive")
    when.add_argument("--last", type=positive, metavar="N", help="the last N dates that have messages")
    narrow = parser.add_argument_group("narrowing")
    narrow.add_argument(
        "--sender",
        action="append",
        default=[],
        metavar="NAME",
        help="only senders whose name contains NAME (repeatable)",
    )
    narrow.add_argument(
        "--grep",
        action="append",
        default=[],
        metavar="TEXT",
        help="only messages containing TEXT, ignoring case (repeatable)",
    )
    parser.add_argument("-o", "--output", type=Path, metavar="OUT.txt", help="write the result to a UTF-8 file")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if sum(choice is not None for choice in (args.date, args.start or args.end, args.last)) > 1:
        parser.error("use only one of --date, --from/--to, --last")
    if args.start and args.end and args.start > args.end:
        parser.error("--from is after --to")
    try:
        text = read_chat(args.chat)
    except OSError as error:
        parser.error(f"cannot read {args.chat}: {error.strerror or error}")

    messages = parse(text.split("\n"))
    if not messages:
        print(
            f"error: no KakaoTalk messages found in {args.chat}\nsupported export formats:\n{SUPPORTED}",
            file=sys.stderr,
        )
        return 1
    selected = select(messages, args)
    if not selected:
        print("no messages match", file=sys.stderr)
        return 0

    sections = []
    if args.months:
        sections.append(counts_by([f"{m.when:%Y-%m}" for m in selected], "month"))
    if args.list:
        sections.append(counts_by([f"{m.when:%Y-%m-%d}" for m in selected], "date"))
    if args.stats:
        sections.append(per_sender(selected))
    if not sections:
        sections.append([message.render() for message in selected])
    result = "\n\n".join("\n".join(section) for section in sections) + "\n"

    if args.output:
        try:
            args.output.write_text(result, encoding="utf-8")
        except OSError as error:
            parser.error(f"cannot write {args.output}: {error.strerror or error}")
        print(f"wrote {len(selected)} messages to {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(result)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    sys.exit(main())
